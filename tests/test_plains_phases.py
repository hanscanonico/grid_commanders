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

from PIL import Image

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
    # `terrain._CLUMP_SHARE` is a fixed 30% of the tile's blocks; the tufts
    # and decals drawn over the field eat a little of it, which measures
    # 29.0-29.5% of the tile — so the floor is close under that rather than a
    # token one a half-coverage field would still clear.
    MIN_CLUMP_SHARE = 0.25
    MAX_CLUMP_SHARE = 0.30
    # Two phases sharing this much of their clump layout would be the same
    # picture again. Measured 0.23-0.30 over the ten pairs; the border ring
    # every phase shares (`terrain._SEAM_SALT`) is a fifth of a tile's clumps
    # laid identically, so ~0.15 of that is structural and the bar stays where
    # it was rather than being moved to suit the ring.
    MAX_LAYOUT_OVERLAP = 0.40
    # A tile of open field is an INDEXED tile. The ±3% grain used to be a
    # continuous mix per 4px block, which spent 29-33 colours a tile — 28 of
    # them green, 17 inside one 0.03 slice of luma — against 16.5 for a unit
    # sprite. The grain is a three-step ramp now: the field is six authored
    # greens (the three grain steps, the two clumps, the tuft) and whatever
    # the phase's two decals add, measured 7-11.
    MAX_TILE_COLOURS = 14
    # A find is drawn in the field's own hue: gravel-grey and wildflower-tan
    # at 1-3px are dead pixels on a hue-100 ground, not a stone and a flower.
    DECAL_HUE_ARC = 30.0
    DECAL_MAX_SAT = 0.45
    # Seamlessness, measured the way a board tiles: the mean luma step across
    # a 64px boundary against the mean step inside a tile, on a field of
    # phases laid by coordinate hash. The clump field wrapped at the cell,
    # which is seamless only for ONE phase repeated — measured 9.6 against
    # 1.9 inside, a five-fold discontinuity that quilts an open field.
    MAX_SEAM_RATIO = 1.5
    FIELD_TILES = 8

    def _phases(self):
        return [terrain.plains(phase) for phase in range(len(terrain.PLAINS_PHASES))]

    def _hashed_field(self):
        """The board's own arrangement: a phase per cell, by coordinate hash —
        which is the only arrangement seamlessness can be measured on. One
        phase repeated is a different, easier question."""
        tiles = self._phases()
        n = self.FIELD_TILES
        field = Image.new("RGB", (n * CELL, n * CELL))
        for gy in range(n):
            for gx in range(n):
                i = int(palette.h01(gx, gy, 7) * len(tiles)) % len(tiles)
                field.paste(tiles[i].convert("RGB"), (gx * CELL, gy * CELL))
        return field

    def _steps(self, field, axis: int) -> tuple[float, float]:
        """Mean |luma step| between adjacent pixels across a cell boundary and
        inside a cell, along one axis."""
        w, h = field.size
        px = field.load()
        lum = [[terrain.luminance(px[x, y]) for x in range(w)] for y in range(h)]
        seam, inside = [], []
        for y in range(h - axis):
            for x in range(w - (1 - axis)):
                nxt = lum[y + axis][x + 1 - axis]
                step = abs(nxt - lum[y][x])
                at = (y if axis else x) + 1
                (seam if at % CELL == 0 else inside).append(step)
        return statistics.mean(seam), statistics.mean(inside)

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
        """A phase moves the field's texture, never its density: every tuft is
        drawn whole, inside the cell, so no phase is a thinner field."""
        counts = [
            sum(1 for c in opaque_pixels(tile) if c == terrain.GRASS_DARK)
            for tile in self._phases()
        ]
        self.assertEqual(len(set(counts)), 1)
        self.assertEqual(counts[0], len(terrain._TUFTS) * 3 * 2)

    def test_a_field_of_mixed_phases_has_no_seam(self):
        """The gate this pass exists for.

        Every phase wraps against every OTHER phase, on all four sides, because
        that is what the game lays: a phase per cell by coordinate hash. A field
        of them is measured the way an eye reads a quilt — the luma step across
        the 64px boundaries against the step inside the cells. Before the shared
        border ring the boundaries stepped 9.6/9.7 against 1.9/2.0 inside; the
        ring makes the two blocks that meet at a seam one block, so the step is
        0.0 and the ratio cannot creep back up without this failing.
        """
        field = self._hashed_field()
        for axis, name in ((0, "horizontal"), (1, "vertical")):
            with self.subTest(axis=name):
                seam, inside = self._steps(field, axis)
                self.assertGreater(inside, 0.0)
                self.assertLessEqual(seam / inside, self.MAX_SEAM_RATIO)

    def test_a_tile_of_field_stays_indexed(self):
        """A ratchet on the field's colour count, the way `IndexedPalette`
        ratchets a unit's. Terrain averaged 27.8 colours a cell against 16.5
        for a sprite, and plains — the tile 78% of a board is — spent 29 of
        them on 28 near-duplicate greens the grain mixed per block."""
        for phase, tile in enumerate(self._phases()):
            with self.subTest(phase=phase):
                self.assertLessEqual(
                    len(set(opaque_pixels(tile))), self.MAX_TILE_COLOURS
                )

    def test_every_decal_is_drawn_in_the_fields_own_hue(self):
        """A find is 1-3px on a hue-100 ground. At that size a tone carries no
        material, only a hue: gravel (H41 S0.09), its shadow (H225) and the
        wildflower (H40 S0.73) read as dead pixels, not as a stone and a
        flower. Every tone a decal spends is grass's hue, held under S0.45."""
        grass_hue = palette._rgb_to_hsv(GRASS)[0] * 360.0
        for kind, paint in terrain._DECALS.items():
            swatch = Image.new("RGBA", (CELL, CELL), (*GRASS, 255))
            paint(swatch, 8, 8)
            for tone in set(opaque_pixels(swatch)) - {GRASS}:
                with self.subTest(decal=kind, tone=tone):
                    hue, sat, _ = palette._rgb_to_hsv(tone)
                    arc = abs(hue * 360.0 - grass_hue)
                    self.assertLessEqual(min(arc, 360.0 - arc), self.DECAL_HUE_ARC)
                    self.assertLessEqual(sat, self.DECAL_MAX_SAT)
        # and the table really spends them: a decal every phase but the atlas
        # column, drawn from this set and no other
        for entry in terrain.PLAINS_PHASES:
            for kind, _, _ in entry[3]:
                self.assertIn(kind, terrain._DECALS)

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
