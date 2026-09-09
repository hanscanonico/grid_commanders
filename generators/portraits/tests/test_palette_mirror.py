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
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from portraitgen import palette

GAME = Path(__file__).resolve().parents[3]
VISUALS = GAME / "scenes/common/commander_visuals.gd"
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


def _floats(literal: str) -> tuple[float, ...]:
    return tuple(float(v) for v in literal.split(",")[:3])


def game_themes() -> dict[str, dict[str, object]]:
    src = VISUALS.read_text()
    neutral = _NEUTRAL_KEY.search(src)
    assert neutral, f"no NEUTRAL_KEY constant in {VISUALS}"
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
    body = _ROW_FOR_KEY.search(IDENTITY.read_text())
    assert body, f"no _ROW_FOR_KEY dictionary in {IDENTITY}"
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


class EveryArmyWearsAnEmblem(unittest.TestCase):
    """Five emblems, one per army — the seat nobody holds has none."""

    def test_emblem_keys_are_the_factions_less_the_neutral_one(self):
        neutral = _NEUTRAL_KEY.search(VISUALS.read_text())
        assert neutral
        self.assertEqual(
            sorted(palette.EMBLEM_KEYS),
            sorted(f.key for f in palette.FACTIONS if f.key != neutral.group(1)),
        )


if __name__ == "__main__":
    unittest.main()
