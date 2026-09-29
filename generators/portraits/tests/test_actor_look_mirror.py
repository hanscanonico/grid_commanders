"""The 3D board's commander figures wear the portraits' own looks.

`scenes/board3d/commander_looks_3d.gd` carries a copy of the FACES columns a
figure can show — skin, hair, style, both worn glyphs, facial hair, collar,
chest and prop — and of the skin and hair bases, so the figure standing on the
board and the bust in the dialogue agree. This suite reads that copy back and
holds it to FACES and the two base tables, column for column.

The regexes read the `LOOKS` rows, the `COLUMNS` order and the two
`Vector3i` tables and nothing else, so a rename fails loudly.
"""

from __future__ import annotations

import re
import unittest

from game import GAME, scrape
from portraitgen import hair, head
from portraitgen.roster import FACES

LOOKS_FILE = GAME / "scenes/board3d/commander_looks_3d.gd"

_COLUMNS = re.compile(r"const COLUMNS: Array\[StringName\] = \[(.*?)\]", re.S)
_LOOKS = re.compile(r"const LOOKS: Dictionary\[StringName, String\] = \{(.*?)\}", re.S)
_ROW = re.compile(r'&"(\w+)"\s*:\s*"([^"]*)"')
_NAME = re.compile(r'&"(\w+)"')
_RGB = re.compile(r'&"(\w+)"\s*:\s*Vector3i\((\d+),\s*(\d+),\s*(\d+)\)')


def _table(name: str) -> dict[str, tuple[int, int, int]]:
    pattern = re.compile(
        rf"const {name}: Dictionary\[StringName, Vector3i\] = \{{(.*?)\}}", re.S
    )
    body = scrape(LOOKS_FILE, pattern).group(1)
    return {key: (int(r), int(g), int(b)) for key, r, g, b in _RGB.findall(body)}


def game_columns() -> list[str]:
    return _NAME.findall(scrape(LOOKS_FILE, _COLUMNS).group(1))


def game_looks() -> dict[str, dict[str, str]]:
    columns = game_columns()
    rows = _ROW.findall(scrape(LOOKS_FILE, _LOOKS).group(1))
    return {gid: dict(zip(columns, row.split(), strict=True)) for gid, row in rows}


class TheLooksMirrorFaces(unittest.TestCase):
    def test_the_columns_are_the_ones_a_figure_draws(self):
        self.assertEqual(
            game_columns(),
            "skin hair style acc acc2 facial collar chest prop".split(),
        )

    def test_one_row_per_general_in_the_same_order(self):
        self.assertEqual(list(game_looks()), list(FACES))

    def test_every_column_matches_faces(self):
        looks = game_looks()
        for gid, face in FACES.items():
            for column, value in looks[gid].items():
                with self.subTest(general=gid, column=column):
                    self.assertEqual(
                        value,
                        getattr(face, column),
                        f"{gid}.{column} has drifted from roster.FACES",
                    )


class TheBasesMirrorThePainters(unittest.TestCase):
    def test_skin_bases(self):
        self.assertEqual(_table("SKIN_BASES"), dict(head.SKIN_BASES))

    def test_hair_bases(self):
        self.assertEqual(_table("HAIR_BASES"), dict(hair.HAIR_BASES))


if __name__ == "__main__":
    unittest.main()
