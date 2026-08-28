"""The faction ramps are the game's own FactionTheme, read back out of its code.

`palette.FACTIONS` restates every faction's colour as 0-255 triples so a sprite
can be painted without the engine. That was a comment; it is a test now. The
game owns the values (`scenes/common/commander_visuals.gd`) and the row order
(`scenes/common/side_identity.gd`), and a failure here means the sheets and the
UI chrome have started disagreeing about what colour an army is.

Parsing GDScript with a regex is narrow on purpose: it reads the `FactionTheme.new`
literals and the `_ROW_FOR_KEY` dictionary and nothing else, so a rename in either
file fails loudly rather than silently matching nothing.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from spritegen import palette

GAME = Path(__file__).resolve().parents[3]
VISUALS = GAME / "scenes/common/commander_visuals.gd"
IDENTITY = GAME / "scenes/common/side_identity.gd"

# FactionTheme.new(<key>, "<display>", Color(r, g, b), Color(...), Color(...), ...)
# The key is a StringName literal or the NEUTRAL_KEY constant beside it.
_THEME = re.compile(
    r"FactionTheme\.new\(\s*"
    r'(?:&"(?P<key>\w+)"|(?P<const>NEUTRAL_KEY))\s*,\s*'
    r'"[^"]*"\s*,\s*'
    r"Color\((?P<body>[^)]*)\)\s*,\s*"
    r"Color\((?P<dark>[^)]*)\)\s*,\s*"
    r"Color\((?P<light>[^)]*)\)"
)
_NEUTRAL_KEY = re.compile(r'const NEUTRAL_KEY := &"(\w+)"')
_ROW_FOR_KEY = re.compile(r"const _ROW_FOR_KEY := \{(.*?)\}", re.S)
_ROW_ENTRY = re.compile(r'&"(\w+)"\s*:\s*(\d+)')


def _rgb(literal: str) -> tuple[int, int, int]:
    parts = [float(v) for v in literal.split(",")]
    return tuple(round(v * 255) for v in parts[:3])


def game_themes() -> dict[str, dict[str, tuple[int, int, int]]]:
    src = VISUALS.read_text()
    neutral = _NEUTRAL_KEY.search(src)
    assert neutral, f"no NEUTRAL_KEY constant in {VISUALS}"
    themes = {}
    for m in _THEME.finditer(src):
        key = m.group("key") or neutral.group(1)
        themes[key] = {
            "body": _rgb(m.group("body")),
            "body_dk": _rgb(m.group("dark")),
            "body_lt": _rgb(m.group("light")),
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


class FactionRampsMirrorTheGame(unittest.TestCase):
    """Every row's three body colours are FactionTheme's, x255."""

    def test_every_row_matches_its_theme(self):
        themes = game_themes()
        for faction in palette.FACTIONS:
            with self.subTest(faction=faction.key):
                theme = themes.get(faction.key)
                self.assertIsNotNone(
                    theme,
                    f"{faction.key}: palette.FACTIONS names a faction "
                    f"{VISUALS.name} has no theme for",
                )
                for field in ("body", "body_dk", "body_lt"):
                    self.assertEqual(
                        getattr(faction, field),
                        theme[field],
                        f"{faction.key}.{field} has drifted from "
                        f"{VISUALS.name}'s FactionTheme",
                    )


class RowOrderMirrorsSideIdentity(unittest.TestCase):
    """The atlas row a faction is baked into is the row the game reads it from."""

    def test_row_order(self):
        self.assertEqual(
            [f.key for f in palette.FACTIONS],
            game_rows(),
            "atlas row order has drifted from SideIdentity._ROW_FOR_KEY",
        )


if __name__ == "__main__":
    unittest.main()
