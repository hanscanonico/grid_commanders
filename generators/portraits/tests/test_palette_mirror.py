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

import importlib.util
import re
import sys
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


class TheBoardSRampsAreTheSpriteGeneratorSOwn(unittest.TestCase):
    """The six-slot ramps a bust is painted out of, against the module that
    paints the board.

    `palette` restates them so this package keeps its own dependencies, and a
    restatement nobody checks is a copy that drifts — a commander whose coat is
    a rung off the tank beside them is exactly the clash this bake exists to
    end. The sprite generator's palette module is stdlib-only, so it is loaded
    from its own file rather than installed.
    """

    def setUp(self):
        source = GAME / "generators/sprites/spritegen/palette.py"
        spec = importlib.util.spec_from_file_location("spritegen_palette", source)
        assert spec and spec.loader, f"no module at {source}"
        self.board = importlib.util.module_from_spec(spec)
        # Registered before it runs: a frozen dataclass inside it looks its own
        # module up in `sys.modules` while the class body is being built.
        sys.modules[spec.name] = self.board
        self.addCleanup(sys.modules.pop, spec.name, None)
        spec.loader.exec_module(self.board)

    def test_the_sky_is_the_board_s_sky(self):
        self.assertEqual(palette.AMBIENT, self.board.AMBIENT)

    def test_every_faction_ramp_matches_rung_for_rung(self):
        self.assertEqual(sorted(palette.RAMPS), sorted(self.board.RAMPS))
        for key in sorted(palette.RAMPS):
            with self.subTest(ramp=key):
                self.assertEqual(palette.RAMPS[key], self.board.RAMPS[key])

    def test_every_bust_ramp_is_the_board_s_but_for_the_four_named_rungs(self):
        """`faction_ramp` is what a bust is actually painted in, and it is the
        board's `RAMPS` with four rungs taken off two other ladders. Mirroring
        `RAMPS` alone left those four unpinned: a fifth could be added, or one
        of them widened to a whole row, without a bar noticing."""
        drifted = {
            (key, slot)
            for key in sorted(palette.RAMPS)
            for slot, (mine, theirs) in enumerate(
                zip(palette.faction_ramp(key), self.board.RAMPS[key], strict=True)
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

    def test_the_metal_is_the_board_s_gunmetal(self):
        self.assertEqual(palette.GUNMETAL_RAMP, self.board.GUNMETAL_RAMP)

    def test_the_shaper_itself_agrees_off_the_authored_ramps(self):
        """Equal ramps could still be two shapers that agree on six anchors, so
        the shaper is asked for a colour and a ladder neither module ships."""
        ladder = (18.0, 44.0, 71.0, 108.0, 149.0, 212.0)
        for base in ((201, 84, 137), (37, 176, 189), (128, 128, 128)):
            with self.subTest(base=base):
                self.assertEqual(
                    palette.build_ramp(base, ladder),
                    self.board.build_ramp(base, ladder),
                )

    def test_the_slot_names_line_up(self):
        self.assertEqual(palette.SLOTS, self.board.SLOTS)
        for name in ("S_CONTOUR", "S_UNDER", "S_SHADOW", "S_BODY", "S_TOP", "S_RIM"):
            with self.subTest(slot=name):
                self.assertEqual(getattr(palette, name), getattr(self.board, name))


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
