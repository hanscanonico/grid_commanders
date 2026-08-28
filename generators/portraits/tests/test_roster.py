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

from portraitgen import backdrop, features, hair, head, props, roster, uniform

GAME = Path(__file__).resolve().parents[3]
COMMANDERS = GAME / "data/commanders"

_ID = re.compile(r'^id = &"(\w+)"', re.M)
_POWER_COST = re.compile(r"^power_cost = (\d+)", re.M)

# The four costliest Command Powers are the four busts that wear the rank stud.
PIPPED = 4


def _commander_ids() -> list[str]:
    return sorted(_ID.search(p.read_text()).group(1) for p in COMMANDERS.glob("*.tres"))


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

    def test_every_collar_is_one_the_uniform_can_cut(self):
        for key, face in roster.FACES.items():
            with self.subTest(commander=key):
                self.assertIn(face.collar, uniform.COLLAR_CUTS)

    def test_every_backdrop_is_one_the_window_can_field(self):
        for key, face in roster.FACES.items():
            with self.subTest(commander=key):
                self.assertIn(face.bg, backdrop.KINDS)
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
