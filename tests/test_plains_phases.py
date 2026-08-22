"""The field's phase variants — the sea's rule on the ground a board is mostly
made of.

One plains tile repeated is a lattice however its tufts are spread inside it,
because what lines up is the repeat. The generator emits the phases; placing
them is the game's, by coordinate hash. Phase 0 stays the atlas column exactly,
so a board that has not adopted the sheet is unchanged and adoption is additive.

Plains is also the reference ground most contrast pairs are read against, so a
phase may not move the field's value band: every phase is held to the same
ceilings and the same colour count as the tile it varies.

Run with `.venv/bin/python -m unittest discover tests`.
"""

from __future__ import annotations

import statistics
import unittest
from unittest import mock

from spritegen import atlas, autotile, palette, terrain
from spritegen.terrain import (
    CELL,
    GRASS,
    GRASS_DARK,
    TERRAIN_MEDIAN_CEILING,
    TERRAIN_VALUE_CEILING,
)

from test_generated_output import (
    TerrainPalette,
    ValueCeiling,
    opaque_pixels,
    share_above,
)


# The widest decal the table may place, as a square: the box a decal's pixels
# have to stay inside for it to be ground detail rather than a prop.
DECAL_SPAN = 8


class PlainsPhases(unittest.TestCase):
    # The field's texture, bounded from below. Measured 9.70-9.95 sd and
    # 55-75% of pixels within 8L of the mean, against 4.5 and 97.9% before
    # the clump field.
    MIN_FIELD_SD = 8.0
    MAX_FLAT_SHARE = 0.80
    # `terrain._CLUMP_SHARE` is a fixed 30% of the tile's blocks; the tufts,
    # wildflowers and decals drawn over the field eat a little of it, which
    # measures 29.2-29.5% of the tile — so the floor is close under that
    # rather than a token one a half-coverage field would still clear.
    MIN_CLUMP_SHARE = 0.25
    MAX_CLUMP_SHARE = 0.30
    # Two phases sharing this much of their clump layout would be the same
    # picture again. Measured 0.08-0.33 over the ten pairs, against 0.18 for
    # two layouts of this coverage drawn independently.
    MAX_LAYOUT_OVERLAP = 0.40

    def _phases(self):
        return [terrain.plains(phase) for phase in range(len(terrain.PLAINS_PHASES))]

    def test_phase_zero_is_the_atlas_plains_column(self):
        col = terrain.TERRAIN_ORDER.index("plains")
        column = atlas.build_terrain_atlas().crop(
            (col * CELL, 0, col * CELL + CELL, CELL)
        )
        self.assertEqual(
            column.convert("RGB").tobytes(), terrain.plains(0).convert("RGB").tobytes()
        )

    def test_every_phase_moves_the_field(self):
        frames = [tile.convert("RGB").tobytes() for tile in self._phases()]
        self.assertGreaterEqual(len(frames), 2)
        self.assertEqual(len(set(frames)), len(frames))

    def test_a_phase_is_the_same_tile_twice(self):
        for phase, tile in enumerate(self._phases()):
            with self.subTest(phase=phase):
                self.assertEqual(
                    tile.convert("RGB").tobytes(),
                    terrain.plains(phase).convert("RGB").tobytes(),
                )

    def test_no_phase_leaves_the_terrain_band_or_the_colour_ceiling(self):
        for phase, tile in enumerate(self._phases()):
            with self.subTest(phase=phase):
                px = opaque_pixels(tile)
                self.assertLessEqual(
                    share_above(px, TERRAIN_VALUE_CEILING),
                    ValueCeiling.TERRAIN_HIGHLIGHT_SHARE,
                )
                median = statistics.median(terrain.luminance(c) for c in px)
                self.assertLess(median, TERRAIN_MEDIAN_CEILING)
                self.assertLessEqual(len(set(px)), TerrainPalette.NATURE_CEILING)

    def test_every_phase_carries_the_same_tufts(self):
        """A phase moves the field's texture, never its density: the tufts wrap
        around the tile rather than off it, so no phase is a thinner field."""
        counts = [
            sum(1 for c in opaque_pixels(tile) if c == terrain.GRASS_DARK)
            for tile in self._phases()
        ]
        self.assertEqual(len(set(counts)), 1)

    def test_the_field_is_clumped_rather_than_grained(self):
        """The 2026-08-22 measurement, kept as a floor.

        The ±3% grain alone put 97.9% of a plains tile within 8L of its mean
        (sd 4.5): a texture no eye reads and one the game's 4:1 nearest
        downsample averages away, which is why a board that is ~78% plains
        read as one flat rectangle per cell. The clump field is the answer, so
        it is bounded from BELOW here — a change that quietly flattens the
        field again fails this rather than passing everything else.
        """
        for phase, tile in enumerate(self._phases()):
            with self.subTest(phase=phase):
                lums = [terrain.luminance(c) for c in opaque_pixels(tile)]
                mean = statistics.mean(lums)
                flat = sum(1 for v in lums if abs(v - mean) <= 8) / len(lums)
                self.assertGreaterEqual(statistics.pstdev(lums), self.MIN_FIELD_SD)
                self.assertLessEqual(flat, self.MAX_FLAT_SHARE)

    def test_the_clump_tones_are_darker_grass_and_nothing_else(self):
        """DARKEN ONLY, and inside the band the outline grade is chosen out of.

        A clump lighter than GRASS would push the tile's median at the ceiling
        it is authored under; a clump darker than the tuft tone would put
        ground under `palette.GROUND_BAND`, which is the band `voxel.render`
        decides a silhouette's lit line against before any tile exists.
        """
        for tone in (terrain.CLUMP, terrain.CLUMP_DK):
            with self.subTest(tone=tone):
                self.assertLess(terrain.luminance(tone), terrain.luminance(GRASS))
                self.assertGreater(
                    terrain.luminance(tone), terrain.luminance(GRASS_DARK)
                )
                lo, hi = palette.GROUND_BAND
                self.assertGreaterEqual(palette.luminance(tone), lo)
                self.assertLessEqual(palette.luminance(tone), hi)
                # still saturated green: the colour break the light rows are
                # held to over plains is the hue's, not the value's
                self.assertGreater(tone[1], max(tone[0], tone[2]) + 40)

    def test_every_phase_covers_the_same_share_of_field_in_clumps(self):
        for phase, tile in enumerate(self._phases()):
            with self.subTest(phase=phase):
                px = opaque_pixels(tile)
                clumped = sum(1 for c in px if c in (terrain.CLUMP, terrain.CLUMP_DK))
                self.assertGreaterEqual(clumped / len(px), self.MIN_CLUMP_SHARE)
                self.assertLessEqual(clumped / len(px), self.MAX_CLUMP_SHARE)

    def test_no_two_phases_lay_their_clumps_the_same_way(self):
        """Content, not translation. The old table was five copies of one tuft
        grid slid around a torus — tile means within 0.31L of each other — so
        a stretch of field repeated whatever the game hashed. The clump field
        is keyed to the phase's salt, so the phases differ in SHAPE."""
        layouts = [
            frozenset(
                (x, y)
                for y in range(CELL)
                for x in range(CELL)
                if tile.convert("RGB").getpixel((x, y))
                in (terrain.CLUMP, terrain.CLUMP_DK)
            )
            for tile in self._phases()
        ]
        self.assertEqual(len(set(layouts)), len(layouts))
        for i, a in enumerate(layouts):
            for j, b in enumerate(layouts):
                if i < j:
                    with self.subTest(phases=(i, j)):
                        self.assertLess(
                            len(a & b) / len(a | b), self.MAX_LAYOUT_OVERLAP
                        )

    def test_most_of_the_table_carries_a_find(self):
        """The doctrine this table shipped with was the reverse — three of the
        five phases bare, so a decal was the only thing a phase varied by. With
        the clump field carrying the variation, a decal is scattered detail on
        a field that already differs, and the field can afford them: four of
        the five carry one. Phase 0 stays bare because it is the atlas column,
        the tile a board that has not adopted the sheet draws everywhere."""
        carried = [bool(entry[3]) for entry in terrain.PLAINS_PHASES]
        self.assertFalse(carried[0])
        self.assertEqual(sum(carried), len(carried) - 1)

    def test_a_decal_changes_only_its_own_corner_of_the_tile(self):
        """A decal is drawn inside the cell — no overhang into the neighbour and
        no second pass over the field, so a decal phase is the bare phase
        everywhere its decals are not."""
        for phase, entry in enumerate(terrain.PLAINS_PHASES):
            decals = entry[3]
            if not decals:
                continue
            with self.subTest(phase=phase):
                bare_table = tuple(
                    e[:3] + ((),) if i == phase else e
                    for i, e in enumerate(terrain.PLAINS_PHASES)
                )
                with mock.patch.object(terrain, "PLAINS_PHASES", bare_table):
                    bare = terrain.plains(phase).convert("RGB")
                tile = terrain.plains(phase).convert("RGB")
                boxes = [(x, y, x + DECAL_SPAN, y + DECAL_SPAN) for _, x, y in decals]
                for x0, y0, x1, y1 in boxes:
                    self.assertLessEqual(x1, CELL)
                    self.assertLessEqual(y1, CELL)
                    self.assertGreaterEqual(min(x0, y0), 0)
                moved = [
                    (x, y)
                    for y in range(CELL)
                    for x in range(CELL)
                    if tile.getpixel((x, y)) != bare.getpixel((x, y))
                ]
                self.assertTrue(moved)
                for x, y in moved:
                    self.assertTrue(
                        any(x0 <= x < x1 and y0 <= y < y1 for x0, y0, x1, y1 in boxes),
                        f"pixel {(x, y)} changed outside every decal",
                    )

    def test_the_sheet_lays_the_phases_out_in_order(self):
        sheet = autotile.plains_sheet()
        phases = self._phases()
        self.assertEqual(sheet.size, (len(phases) * (CELL + 2) + 2, CELL + 4))
        for i, tile in enumerate(phases):
            with self.subTest(phase=i):
                x = i * (CELL + 2) + 2
                cut = sheet.crop((x, 2, x + CELL, 2 + CELL))
                self.assertEqual(cut.tobytes(), tile.convert("RGB").tobytes())


if __name__ == "__main__":
    unittest.main()
