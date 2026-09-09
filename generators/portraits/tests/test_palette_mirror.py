"""The faction themes are the game's own, read back out of its code.

`palette.FACTIONS` restates every faction's colour so a portrait can be painted
without the engine. That was a comment; it is a test now. The game owns the
values (`scenes/common/commander_visuals.gd`) and the row order
(`scenes/common/side_identity.gd`), and a failure here means the busts and the
UI chrome that frames them have started disagreeing about what colour an army
is.

Parsing GDScript with a regex is narrow on purpose: it reads the
`FactionTheme.new` literals and the `_ROW_FOR_KEY` dictionary and nothing else,
so a rename in either file fails loudly rather than silently matching nothing.
The floats are compared as floats — the byte conversion is `palette.rgb8`'s
business, and it is checked where it matters, against the committed emblems.

The suite's second job is where each of a bust's sixteen tones actually comes
from, because that is easy to say loosely and easy to drift: the army's six
rungs and the gunmetal's two are the board's ramps themselves, skin's four and
hair's three are the board's SHAPER over bases and a value ladder that are this
sheet's own, and the ink is off no ladder at all.
"""

from __future__ import annotations

import re
import unittest

from game import GAME, VISUALS, scrape
from portraitgen import hair, head, light, palette

IDENTITY = GAME / "scenes/common/side_identity.gd"

# FactionTheme.new(<key>, "<display>", Color(r, g, b), Color(...), Color(...), ...)
# The key is a StringName literal or the NEUTRAL_KEY constant beside it.
_THEME = re.compile(
    r"FactionTheme\.new\(\s*"
    r'(?:&"(?P<key>\w+)"|(?P<const>NEUTRAL_KEY))\s*,\s*'
    r'"(?P<display>[^"]*)"\s*,\s*'
    r"Color\((?P<color>[^)]*)\)\s*,\s*"
    r"Color\((?P<dark>[^)]*)\)\s*,\s*"
    r"Color\((?P<light>[^)]*)\)"
)
_NEUTRAL_KEY = re.compile(r'const NEUTRAL_KEY := &"(\w+)"')
_ROW_FOR_KEY = re.compile(r"const _ROW_FOR_KEY := \{(.*?)\}", re.S)
_ROW_ENTRY = re.compile(r'&"(\w+)"\s*:\s*(\d+)')

_COLOURS = ("color", "color_dark", "color_light")

# The only rungs a bust may not share with the board, one at a time: the three
# the Gilded coat is lit in, off the funds gold, and the one Iron's window field
# sits on. `palette.BUST_RUNGS` says why each is spent.
BUST_OVERRIDES = {
    ("gold", palette.S_BODY),
    ("gold", palette.S_TOP),
    ("gold", palette.S_RIM),
    ("iron", palette.S_SHADOW),
}

# The materials this sheet authors bases for, rather than taking a whole ramp
# off the board: the five skins and the eight hair colours.
SHEET_BASES: dict[str, palette.RGB] = {
    **{f"skin {name}": base for name, base in head.SKIN_BASES.items()},
    **{f"hair {name}": base for name, base in hair.HAIR_BASES.items()},
}


def board_shaped(base: palette.RGB) -> palette.Ramp6:
    """`light.Ramp.of_material`'s six rungs, recomputed off `palette.BOARD`.

    Written out here rather than called, so the bar is that the shaper the
    portraits paint a face with IS the board's `build_ramp` — a shaper of this
    package's own could not be slipped under `light` without failing.
    """
    lum = palette.BOARD.luminance(base)
    rungs = tuple(min(lum * step, light._LIT_CEILING) for step in light._LADDER)
    six = palette.BOARD.build_ramp(base, (*rungs, rungs[-1]))
    return (*six[: palette.S_RIM], six[palette.S_TOP])


def _floats(literal: str) -> tuple[float, ...]:
    return tuple(float(v) for v in literal.split(",")[:3])


def game_themes() -> dict[str, dict[str, object]]:
    src = VISUALS.read_text()
    neutral = scrape(VISUALS, _NEUTRAL_KEY)
    themes: dict[str, dict[str, object]] = {}
    for m in _THEME.finditer(src):
        key = m.group("key") or neutral.group(1)
        themes[key] = {
            "display": m.group("display"),
            "color": _floats(m.group("color")),
            "color_dark": _floats(m.group("dark")),
            "color_light": _floats(m.group("light")),
        }
    return themes


def game_rows() -> list[str]:
    body = scrape(IDENTITY, _ROW_FOR_KEY)
    entries = _ROW_ENTRY.findall(body.group(1))
    return [key for key, _ in sorted(entries, key=lambda e: int(e[1]))]


class TheGameFilesAreReadable(unittest.TestCase):
    def test_both_authorities_are_where_the_regexes_look(self):
        self.assertTrue(VISUALS.is_file(), VISUALS)
        self.assertTrue(IDENTITY.is_file(), IDENTITY)
        self.assertEqual(len(game_themes()), len(palette.FACTIONS))
        self.assertEqual(len(game_rows()), len(palette.FACTIONS))


class FactionThemesMirrorTheGame(unittest.TestCase):
    def test_every_faction_matches_its_theme(self):
        themes = game_themes()
        for faction in palette.FACTIONS:
            with self.subTest(faction=faction.key):
                theme = themes.get(faction.key)
                self.assertIsNotNone(
                    theme,
                    f"{faction.key}: palette.FACTIONS names a faction "
                    f"{VISUALS.name} has no theme for",
                )
                self.assertEqual(faction.display, theme["display"])
                for field in _COLOURS:
                    self.assertEqual(
                        getattr(faction, field),
                        theme[field],
                        f"{faction.key}.{field} has drifted from "
                        f"{VISUALS.name}'s FactionTheme",
                    )


class RowOrderMirrorsSideIdentity(unittest.TestCase):
    """The order the factions are listed in is the order the game rows them."""

    def test_row_order(self):
        self.assertEqual(
            [f.key for f in palette.FACTIONS],
            game_rows(),
            "faction order has drifted from SideIdentity._ROW_FOR_KEY",
        )


class TheThemesAreTruncatedWhereTheBoardRoundsThem(unittest.TestCase):
    """Why this package keeps its own copy of the six themes.

    `generators/sprites` carries the same six, from the same `FactionTheme`
    literals, already converted to bytes — and converted by ROUNDING, where
    this module truncates the way Godot writes a `Color` into `FORMAT_RGBA8`.
    The two therefore land a unit apart on some channels. The committed
    emblems are drawn straight off `Faction.body` at 1x with nothing to
    quantise them, so all five move if this block is swapped for the board's,
    which is why the copy stays and the disagreement is pinned here instead.
    """

    def test_the_same_six_themes_in_the_same_order(self):
        board = palette.BOARD
        self.assertEqual(
            [f.key for f in palette.FACTIONS], [f.key for f in board.FACTIONS]
        )

    def test_no_channel_is_more_than_a_rounding_apart(self):
        board = palette.BOARD
        for faction in palette.FACTIONS:
            theirs = board.faction_by_key(faction.key)
            with self.subTest(faction=faction.key):
                for field in ("body", "body_dk", "body_lt"):
                    mine, other = getattr(faction, field), getattr(theirs, field)
                    self.assertEqual(
                        [],
                        [
                            (index, a, b)
                            for index, (a, b) in enumerate(zip(mine, other))
                            if abs(a - b) > 1
                        ],
                        f"{faction.key}.{field} is further from the board than "
                        "a truncation can explain",
                    )

    def test_this_module_truncates_where_the_board_rounds(self):
        """The disagreement itself, so neither converter can change alone."""
        board = palette.BOARD
        truncated = {
            faction.key: faction.body
            for faction in palette.FACTIONS
            if faction.body != board.faction_by_key(faction.key).body
        }
        self.assertEqual(
            truncated,
            {
                "neutral": (95, 106, 112),
                "meridian": (219, 73, 58),
                "aurora": (56, 100, 215),
                "iron": (73, 82, 87),
                "verdant": (44, 133, 54),
                "gold": (233, 200, 40),
            },
        )


class TheBustRungsAreTheOnlyRungsNotTheBoardsOwn(unittest.TestCase):
    """The four rungs a bust does not share with the board, and nothing else.

    `palette` no longer restates the board's ramps — it loads
    `generators/sprites`' own palette module off its file and paints out of its
    shaper and its ladders, so a rung cannot drift between a commander and the
    tank beside them. What can still drift is the small set of rungs a bust
    deliberately takes off another ladder: a fifth could be added, or one of
    them widened to a whole row, and no bar would notice. This is that bar.
    """

    def test_the_boards_palette_is_where_the_package_looks_for_it(self):
        self.assertEqual(
            palette.BOARD_PALETTE,
            GAME / "generators/sprites/spritegen/palette.py",
        )
        self.assertTrue(palette.BOARD_PALETTE.is_file(), palette.BOARD_PALETTE)

    def test_every_bust_ramp_is_the_boards_but_for_the_four_named_rungs(self):
        drifted = {
            (key, slot)
            for key in sorted(palette.RAMPS)
            for slot, (mine, theirs) in enumerate(
                zip(palette.faction_ramp(key), palette.RAMPS[key], strict=True)
            )
            if mine != theirs
        }
        self.assertEqual(drifted, BUST_OVERRIDES)

    def test_the_overrides_are_the_ones_bust_rungs_declares(self):
        """The enumeration above against the table it is meant to describe, so
        neither can be edited alone."""
        self.assertEqual(
            {
                (key, slot)
                for key, rungs in palette.BUST_RUNGS.items()
                for slot in rungs
            },
            BUST_OVERRIDES,
        )


class SkinAndHairAreTheBoardsShapeOfThisSheetsOwnBases(unittest.TestCase):
    """Where the other seven of a bust's sixteen tones come from.

    Not off a board ramp — `head.SKIN_BASES` and `hair.HAIR_BASES` are authored
    here and `light`'s value ladder is this sheet's, because a face is not a
    chassis and the board has no skin. What IS shared is the shaper: the same
    chroma curve, the same hue rotation and the same cool sky, so a general and
    the tank outside their window are lit by one sun. That is the whole of the
    claim, so it is the whole of what is pinned.
    """

    def test_the_shaper_and_the_sky_are_the_boards_by_reference(self):
        self.assertIs(palette.build_ramp, palette.BOARD.build_ramp)
        self.assertIs(palette.luminance, palette.BOARD.luminance)
        self.assertEqual(palette.AMBIENT, palette.BOARD.AMBIENT)

    def test_every_skin_and_hair_rung_is_the_boards_shape_of_its_base(self):
        for name, base in sorted(SHEET_BASES.items()):
            with self.subTest(material=name):
                self.assertEqual(light.Ramp.of_material(base).six, board_shaped(base))

    def test_no_base_here_is_a_rung_of_a_board_ramp(self):
        """The other half: these bases are authored, not lifted off a ladder."""
        rungs = {rung for ramp in palette.RAMPS.values() for rung in ramp}
        rungs |= set(palette.GUNMETAL_RAMP)
        self.assertEqual(
            [], sorted(name for name, base in SHEET_BASES.items() if base in rungs)
        )


class TheSixteenAreSourcedMaterialByMaterial(unittest.TestCase):
    """Which of the sixteen comes off which ladder, in one statement.

    `bust_palette` is the only place a bust's tones are gathered, so the
    sourcing the README and `.claude/rules/presentation.md` describe is read
    back off it here rather than trusted to prose.
    """

    def test_the_gunmetal_two_are_the_boards_own_ramp(self):
        self.assertEqual(palette.GUNMETAL_RAMP, palette.BOARD.GUNMETAL_RAMP)

    def test_the_ink_is_off_no_ladder_at_all(self):
        """The design system's outline, as bytes — not a rung of anything."""
        rungs = {rung for ramp in palette.RAMPS.values() for rung in ramp}
        rungs |= set(palette.GUNMETAL_RAMP)
        self.assertNotIn(palette.INK, rungs)
        self.assertEqual(palette.INK, (19, 23, 27))

    def test_each_slice_of_the_sixteen_comes_from_where_it_is_said_to(self):
        skin = light.Ramp.of_material(head.SKIN_BASES["tan"]).six
        mane = light.Ramp.of_material(hair.HAIR_BASES["black"]).six
        tones = palette.bust_palette("aurora", skin, mane)
        self.assertEqual(tones[0], palette.INK)
        self.assertEqual(tones[1:7], palette.faction_ramp("aurora"))
        self.assertEqual(tones[7:11], tuple(skin[slot] for slot in palette.SKIN_SLOTS))
        self.assertEqual(tones[11:14], tuple(mane[slot] for slot in palette.HAIR_SLOTS))
        self.assertEqual(
            tones[14:],
            tuple(palette.BOARD.GUNMETAL_RAMP[slot] for slot in palette.METAL_SLOTS),
        )


class EveryArmyWearsAnEmblem(unittest.TestCase):
    """Five emblems, one per army — the seat nobody holds has none."""

    def test_emblem_keys_are_the_factions_less_the_neutral_one(self):
        neutral = scrape(VISUALS, _NEUTRAL_KEY)
        self.assertEqual(
            sorted(palette.EMBLEM_KEYS),
            sorted(f.key for f in palette.FACTIONS if f.key != neutral.group(1)),
        )


if __name__ == "__main__":
    unittest.main()
