"""The roster table is a transcription, and every way it can rot is silent.

These are the lints `tests/unit/test_commander_portraits.gd` carried while the
face table lived in GDScript: a general seated with no row, a row for a general
since retired, two generals sharing a skull, an expression the whole sheet
wears, a dial outside its range, a key no module can draw. They move here with
the table, and the set-equality one against `data/commanders/` is what proves
the port lost nobody.

A key outside a vocabulary is a raise in the painter now rather than a silent
fallback, so these tests read as a second opinion in only one direction: they
name the row, ahead of a stack trace 22 busts deep.
"""

from __future__ import annotations

import re
import unittest
from collections import Counter
from pathlib import Path

from portraitgen import backdrop, bust, features, hair, head, props, roster, uniform
from portraitgen.canvas import Canvas

GAME = Path(__file__).resolve().parents[3]
COMMANDERS = GAME / "data/commanders"
VISUALS = GAME / "scenes/common/commander_visuals.gd"

_ID = re.compile(r'^id = &"(\w+)"', re.M)
_POWER_COST = re.compile(r"^power_cost = (\d+)", re.M)
_FACTION = re.compile(r'^faction = "([^"]*)"', re.M)
_FACTION_KEYS = re.compile(r"const _FACTION_KEYS := \{(.*?)\}", re.S)
_FACTION_ENTRY = re.compile(r'"([^"]+)"\s*:\s*&"(\w+)"')

# The four costliest Command Powers are the four busts that wear the rank stud.
PIPPED = 4


def _commander_ids() -> list[str]:
    return sorted(_ID.search(p.read_text()).group(1) for p in COMMANDERS.glob("*.tres"))


def _army_of_each_general() -> dict[str, str]:
    """Which theme key the game seats each general under.

    The faction string lives on the `.tres` and the string-to-key adapter in
    `CommanderVisuals`, so both are read rather than restated — the same mirror
    idiom `test_palette_mirror.py` uses on the colours themselves.
    """
    body = _FACTION_KEYS.search(VISUALS.read_text())
    assert body, f"no _FACTION_KEYS dictionary in {VISUALS}"
    keys = dict(_FACTION_ENTRY.findall(body.group(1)))
    armies = {}
    for path in COMMANDERS.glob("*.tres"):
        src = path.read_text()
        armies[_ID.search(src).group(1)] = keys[_FACTION.search(src).group(1)]
    return armies


def _power_costs() -> dict[str, int]:
    costs = {}
    for path in COMMANDERS.glob("*.tres"):
        src = path.read_text()
        costs[_ID.search(src).group(1)] = int(_POWER_COST.search(src).group(1))
    return costs


class TheTableAndTheRosterAreTheSameSet(unittest.TestCase):
    """Set equality rather than one-way coverage, so a failure names the side
    that drifted: a general with no face, or a face for a general since retired.
    """

    def test_the_resources_are_where_the_regex_looks(self):
        ids = _commander_ids()
        self.assertEqual(len(ids), len(list(COMMANDERS.glob("*.tres"))))
        self.assertEqual(len(set(ids)), len(ids))

    def test_every_general_has_a_row_and_every_row_a_general(self):
        self.assertEqual(sorted(roster.FACES), _commander_ids())

    def test_a_row_knows_its_own_id(self):
        for key, face in roster.FACES.items():
            with self.subTest(commander=key):
                self.assertEqual(key, face.id)


class EveryGeneralIsDrawnOnASkullOfTheirOwn(unittest.TestCase):
    """The head column is the only thing separating one bust from another before
    the hair goes on, and a row copied off a neighbour hands two generals one
    face.
    """

    def test_the_dials_are_in_range(self):
        for key, face in roster.FACES.items():
            with self.subTest(commander=key):
                self.assertIn(face.head.jaw, head.JAWS)
                self.assertGreaterEqual(face.head.width, 0.86)
                self.assertLessEqual(face.head.width, 1.14)
                self.assertGreaterEqual(face.head.crown, -3.0)
                self.assertLessEqual(face.head.crown, 3.0)
                self.assertGreaterEqual(face.head.spread, 0.9)
                self.assertLessEqual(face.head.spread, 1.1)

    def test_no_two_generals_share_a_skull(self):
        skulls = Counter(face.head for face in roster.FACES.values())
        self.assertEqual(
            [], [str(s) for s, n in skulls.items() if n > 1], "a skull is worn twice"
        )

    def test_the_empty_seat_stands_on_the_default_head(self):
        self.assertEqual(roster.NEUTRAL.head, head.Skull(*head.HEAD_DEFAULT))

    def test_the_empty_seat_is_named_for_the_file_the_game_falls_back_to(self):
        # CommanderVisuals.NEUTRAL_PORTRAIT_PATH is .../commanders/none.png.
        self.assertEqual(roster.NEUTRAL_ID, "none")
        self.assertNotIn(roster.NEUTRAL_ID, roster.FACES)


class NoExpressionIsWornByTheWholeRoster(unittest.TestCase):
    """Five brows over twenty-two generals cannot go below five apiece, which is
    why the mouth is the column held to three.
    """

    MOUTH_CAP = 3
    BROW_CAP = 5

    def test_every_expression_is_one_the_painter_draws(self):
        for key, face in roster.FACES.items():
            with self.subTest(commander=key):
                self.assertIn(face.eyes, features.EYE_KINDS)
                self.assertIn(face.brow, features.BROW_KINDS)
                self.assertIn(face.mouth, features.MOUTH_KINDS)
                self.assertGreaterEqual(face.eye, 0.82)
                self.assertLessEqual(face.eye, 1.06)

    def test_no_mouth_is_worn_by_more_than_three(self):
        worn = Counter(face.mouth for face in roster.FACES.values())
        self.assertEqual([], [m for m, n in worn.items() if n > self.MOUTH_CAP])

    def test_no_brow_is_worn_by_more_than_five(self):
        worn = Counter(face.brow for face in roster.FACES.values())
        self.assertEqual([], [b for b, n in worn.items() if n > self.BROW_CAP])


class EveryColumnNamesSomethingDrawable(unittest.TestCase):
    """Each vocabulary is owned by the module that draws it; the table only
    names into them.
    """

    def test_skin_and_hair_name_a_ramp(self):
        for key, face in roster.FACES.items():
            with self.subTest(commander=key):
                self.assertIn(face.skin, roster.SKIN_TONES)
                self.assertIn(face.hair, hair.HAIR_COLOURS)
                self.assertIn(face.style, hair.STYLES)

    def test_facial_hair_and_accessories_are_in_the_vocabulary(self):
        for key, face in roster.FACES.items():
            with self.subTest(commander=key):
                self.assertIn(face.facial, features.FACIAL_KINDS)
                self.assertIn(face.acc, features.ACCESSORY_KINDS)
                self.assertIn(face.acc2, features.ACCESSORY_KINDS)

    def test_only_the_first_slot_may_cover_a_socket(self):
        for key, face in roster.FACES.items():
            with self.subTest(commander=key):
                self.assertIsNone(features.covered_eye(face.acc2))

    def test_every_collar_is_one_the_uniform_can_cut(self):
        for key, face in roster.FACES.items():
            with self.subTest(commander=key):
                self.assertIn(face.collar, uniform.COLLAR_CUTS)

    def test_every_backdrop_is_one_the_window_can_field(self):
        for key, face in roster.FACES.items():
            with self.subTest(commander=key):
                self.assertIn(face.bg, backdrop.KINDS)

    def test_the_empty_seat_stands_against_the_bars(self):
        self.assertEqual(roster.NEUTRAL.bg, "bars")
        self.assertIn(roster.NEUTRAL.bg, backdrop.KINDS)

    def test_all_seven_backdrops_are_used_and_none_carries_the_sheet(self):
        worn = Counter(face.bg for face in roster.FACES.values())
        self.assertEqual(sorted(worn), sorted(backdrop.KINDS))
        self.assertEqual([], [b for b, n in worn.items() if n > 4])

    def test_all_three_noses_are_used(self):
        worn = Counter(face.nose for face in roster.FACES.values())
        self.assertEqual(sorted(worn), sorted(features.NOSE_KINDS))


class EveryGeneralCarriesTheirOwnProp(unittest.TestCase):
    def test_the_props_are_twenty_two_distinct_drawable_ones(self):
        worn = [face.prop for face in roster.FACES.values()]
        self.assertEqual(sorted(worn), sorted(props.PROPS))
        self.assertEqual(len(set(worn)), len(roster.FACES))


class EveryGeneralWearsTheirOwnArmy(unittest.TestCase):
    """`bust.FACTION_OF` decides which cloth a general is painted in, and the
    game decides which army they command. Nothing else compares the two, so a
    general reseated in their `.tres` would keep the old army's colour and only
    a human looking at the sheet would catch it."""

    def test_the_adapter_is_where_the_regex_looks(self):
        armies = _army_of_each_general()
        self.assertEqual(sorted(armies), _commander_ids())
        self.assertEqual(len(set(armies.values())), 5)

    def test_the_painter_dresses_every_general_in_the_army_they_command(self):
        self.assertEqual(bust.FACTION_OF, _army_of_each_general())


class TheRareMarksAreRare(unittest.TestCase):
    """The pip, the earring and the freckles are the columns only a few rows
    set, so a copied row shows up as a second wearer rather than as a picture.
    """

    def test_the_rank_stud_is_worn_by_the_four_costliest_powers(self):
        costs = _power_costs()
        pipped = sorted(f.id for f in roster.FACES.values() if f.pip)
        costliest = sorted(sorted(costs, key=lambda i: -costs[i])[:PIPPED])
        self.assertEqual(pipped, costliest)

    def test_one_general_wears_the_earring_and_one_the_freckles(self):
        self.assertEqual(
            ["alina_ward"], [f.id for f in roster.FACES.values() if f.earring]
        )
        self.assertEqual(
            ["nia_rowan"], [f.id for f in roster.FACES.values() if f.freckles]
        )


class TheIdentitiesTheReviewPinned(unittest.TestCase):
    """Three rows the design review named, held by the columns that carry them.

    Rowan's prop drifted to an unsanctioned one once already, and the two busts
    the review read as empty above the collar were empty because their `acc`
    column said `none` — both are one word in this table and neither shows up
    in any other lint here.
    """

    EMPTY_ABOVE_THE_COLLAR = ("dane_ferrow", "iona_vance")

    def test_rowan_carries_the_monocle(self):
        self.assertEqual(roster.FACES["nia_rowan"].prop, "monocle")

    def test_the_two_bare_heads_wear_headwear(self):
        for key in self.EMPTY_ABOVE_THE_COLLAR:
            with self.subTest(commander=key):
                face = roster.FACES[key]
                worn = features.accessory(Canvas(), face.head, face.acc)
                self.assertGreater(len(worn), 2, "an accessory that is not headwear")

    def test_the_two_bare_heads_do_not_wear_the_same_hat(self):
        first, second = (roster.FACES[key].acc for key in self.EMPTY_ABOVE_THE_COLLAR)
        self.assertNotEqual(first, second)

    def test_ferrow_kept_his_scar_when_he_took_the_cap(self):
        face = roster.FACES["dane_ferrow"]
        self.assertIn("scar", (face.acc, face.acc2))

    def test_calder_wears_the_shade_that_parted_her_from_voss(self):
        calder, voss = roster.FACES["ines_calder"], roster.FACES["mara_voss"]
        self.assertIn("visor", (calder.acc, calder.acc2))
        self.assertNotIn("visor", (voss.acc, voss.acc2))

    def test_rowan_and_reed_carry_different_things_on_the_chest(self):
        self.assertNotEqual(
            roster.FACES["nia_rowan"].chest, roster.FACES["tomas_reed"].chest
        )

    def test_the_steel_ramp_is_worn_by_the_one_general_it_was_cut_for(self):
        wearing = [f.id for f in roster.FACES.values() if f.hair == "steel"]
        self.assertEqual(["konrad_vale"], wearing)


class TheGreyArmyWearsTheVillainsFace(unittest.TestCase):
    """The Iron Dominion is the antagonist the sheet has to sell, and the only
    place that is said is its six grey rows. A soft mouth or a wide, bright eye
    on one of them puts the face back where it started, and nothing else here
    reads the expression against the army wearing it.
    """

    SOFT_MOUTHS = ("grin", "laugh", "neutral", "open", "smile", "wry")
    HARD_EYES = ("lidded", "narrow")
    # The widest Iron eye on the sheet. It was 0.94, and at that dial a
    # narrowed lid still leaves a round, bright sclera that reads friendly at
    # bust size, which is the QA finding this cap was tightened for.
    WIDEST_EYE = 0.90

    def iron_faces(self) -> list[roster.Face]:
        return [f for k, f in roster.FACES.items() if bust.FACTION_OF[k] == "iron"]

    def test_the_grey_army_is_six_generals(self):
        self.assertEqual(6, len(self.iron_faces()))

    def test_no_iron_general_wears_a_soft_mouth(self):
        for face in self.iron_faces():
            with self.subTest(commander=face.id):
                self.assertNotIn(face.mouth, self.SOFT_MOUTHS)

    def test_every_iron_eye_is_narrowed_or_lidded(self):
        for face in self.iron_faces():
            with self.subTest(commander=face.id):
                self.assertIn(face.eyes, self.HARD_EYES)
                self.assertLessEqual(face.eye, self.WIDEST_EYE)


class ThePosesAreTiltedAndFiveAreMirrored(unittest.TestCase):
    """The mirror is a pose, never a light: the cast shadow keeps its one offset
    sheet-wide, so the mirrored rows are counted here rather than assumed.
    """

    MIRRORED = 5

    def test_every_pose_is_a_tilt_a_zoom_and_a_mirror(self):
        for key, face in roster.FACES.items():
            with self.subTest(commander=key):
                tilt, zoom, mirrored = face.pose
                self.assertGreaterEqual(tilt, -9.0)
                self.assertLessEqual(tilt, 9.0)
                self.assertGreaterEqual(zoom, 1.1)
                self.assertLessEqual(zoom, 1.3)
                self.assertIsInstance(mirrored, bool)

    def test_five_generals_face_the_other_way(self):
        mirrored = [f.id for f in roster.FACES.values() if f.pose[2]]
        self.assertEqual(len(mirrored), self.MIRRORED, mirrored)

    def test_the_empty_seat_is_not_tilted(self):
        self.assertEqual(roster.NEUTRAL.pose, (0.0, 1.18, False))


if __name__ == "__main__":
    unittest.main()
