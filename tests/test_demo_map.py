"""The demo board — the review artefact, held to the game it stands in for.

`preview_map.png` is what a human looks at to decide the sheet works, so it may
not be a nicer board than the game draws. Two things it has to keep: the mix of
the shipped maps (grid_commanders/maps is about 56% plains, 12% sea, 11% road),
because a demo that is half open sea proves the sea tile and little else; and
the coordinate-hashed phases, because a board that paints phase 0 everywhere
hides the very lattice the phase sheets exist to break.

Run with `.venv/bin/python -m unittest discover tests`.
"""

from __future__ import annotations

import collections
import unittest

from spritegen import atlas, terrain


# TerrainAutotiles.phase(Vector2i(x, y), 8) and (…, 3) for x in 0..14, printed
# by Godot 4.7 from scenes/battle/terrain_autotiles.gd. The hash is the whole
# contract — a preview whose phases are merely plausible is not the game's
# board — so it is pinned against the engine's own arithmetic rather than
# against ours. The plains row was re-derived when the field went from five
# phases to eight; the count is an argument to the hash, so every cell moves.
_GODOT_PLAINS_PHASES_ROW0 = (0, 1, 3, 4, 0, 7, 1, 1, 0, 2, 7, 4, 4, 3, 3)
_GODOT_SEA_PHASES_ROW0 = (0, 1, 0, 0, 1, 2, 2, 2, 2, 2, 0, 2, 2, 0, 2)


class DemoPhaseHash(unittest.TestCase):
    def test_matches_the_games_hash(self):
        self.assertEqual(len(terrain.PLAINS_PHASES), 8, "re-derive the pinned row")
        for x, want in enumerate(_GODOT_PLAINS_PHASES_ROW0):
            self.assertEqual(atlas.phase(x, 0, 8), want, f"plains phase at x={x}")
        for x, want in enumerate(_GODOT_SEA_PHASES_ROW0):
            self.assertEqual(atlas.phase(x, 0, 3), want, f"sea phase at x={x}")

    def test_stays_inside_the_phase_count(self):
        for count in (3, 8):
            for y in range(40):
                for x in range(40):
                    self.assertIn(atlas.phase(x, y, count), range(count))


class DemoMap(unittest.TestCase):
    def _cells(self) -> list[tuple[int, int, str]]:
        return [
            (x, y, atlas._DEMO_LEGEND[char])
            for y, row in enumerate(atlas._DEMO_MAP)
            for x, char in enumerate(row)
        ]

    def test_rows_are_rectangular(self):
        widths = {len(row) for row in atlas._DEMO_MAP}
        self.assertEqual(len(widths), 1, f"ragged board: {sorted(widths)}")

    def test_plains_share_matches_the_shipped_maps(self):
        cells = self._cells()
        plains = sum(1 for _, _, tid in cells if tid == "plains")
        share = plains / len(cells)
        self.assertGreaterEqual(share, 0.45, f"{share:.0%} plains, too little ground")
        self.assertLessEqual(share, 0.65, f"{share:.0%} plains, too little else")

    def test_plains_cells_wear_at_least_three_phases(self):
        phases = {
            atlas.phase(x, y, len(terrain.PLAINS_PHASES))
            for x, y, tid in self._cells()
            if tid == "plains"
        }
        self.assertGreaterEqual(len(phases), 3, f"phases drawn: {sorted(phases)}")

    def test_every_terrain_column_appears(self):
        drawn = collections.Counter(tid for _, _, tid in self._cells())
        self.assertEqual(set(drawn) - set(terrain.TERRAIN_ORDER), set())
        self.assertEqual(set(terrain.TERRAIN_ORDER) - set(drawn), set())

    def test_units_stand_on_the_board(self):
        w, h = len(atlas._DEMO_MAP[0]), len(atlas._DEMO_MAP)
        seen: set[tuple[int, int]] = set()
        for uid, _, x, y in atlas._DEMO_UNITS:
            with self.subTest(unit=uid):
                self.assertTrue(0 <= x < w and 0 <= y < h, "off the board")
                # a cell is taller than a tile, so a unit hangs over the tile
                # above it: two units a row apart in one column overlap
                self.assertNotIn((x, y), seen)
                self.assertNotIn((x, y + 1), seen)
                seen.add((x, y))


class DemoRender(unittest.TestCase):
    """The board as drawn, not merely as declared: a legend that hashes into
    five phases proves nothing if `build_demo` still paints phase 0."""

    @classmethod
    def setUpClass(cls):
        cls.img = atlas.build_demo()

    def _quiet_plains(self):
        """Plains cells with nothing drawn over them — no property overlay, and
        no unit, which stands in its own cell and hangs into the one above."""
        busy = set()
        for _, _, x, y in atlas._DEMO_UNITS:
            busy |= {(x, y), (x, y - 1)}
        for y, row in enumerate(atlas._DEMO_MAP):
            for x, char in enumerate(row):
                if atlas._DEMO_LEGEND[char] == "plains" and (x, y) not in busy:
                    yield x, y

    def test_plains_cells_are_drawn_at_their_hashed_phase(self):
        drawn = set()
        for x, y in self._quiet_plains():
            cell = terrain.CELL
            got = self.img.crop((x * cell, y * cell, (x + 1) * cell, (y + 1) * cell))
            want = atlas.phase(x, y, len(terrain.PLAINS_PHASES))
            with self.subTest(cell=(x, y)):
                self.assertEqual(
                    got.tobytes(),
                    terrain.plains(want).convert("RGBA").tobytes(),
                    f"cell {(x, y)} is not plains phase {want}",
                )
            drawn.add(want)
        self.assertGreaterEqual(len(drawn), 3, f"phases drawn: {sorted(drawn)}")


if __name__ == "__main__":
    unittest.main()
