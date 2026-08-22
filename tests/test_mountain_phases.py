"""The mountain's phase variants — the sea's rule on the board's most
silhouette-dominant tile.

A range drawn from one mountain tile is a wall of identical peaks, which is what
the phases break. What a phase may move is where the summits stand and how the
snow line zigzags; what it may not move is the horizon — the ground line and the
contact shadow are the same row in every phase, or a ridge of them would read as
peaks at different altitudes rather than as a range. Phase 0 stays the atlas
column exactly, so a board that has not adopted the sheet is unchanged.

Run with `.venv/bin/python -m unittest discover tests`.
"""

from __future__ import annotations

import statistics
import unittest

from spritegen import atlas, autotile, buildings, terrain
from spritegen.gbuffer import N_LEFT, N_RIGHT, N_TOP
from spritegen.palette import FACTIONS, ROCK_RAMP, SNOW_RAMP
from spritegen.terrain import CELL, TERRAIN_MEDIAN_CEILING, TERRAIN_VALUE_CEILING
from spritegen.voxel import SHADOW_OFFSET, render_indexed_gbuffer

from test_generated_output import (
    TerrainPalette,
    ValueCeiling,
    opaque_pixels,
    share_above,
)

# The row the massif's lowest rock pixel lands on: `terrain.MOUNTAIN_GROUND`
# less the 2px margin `voxel._bounds` leaves under a sprite, and less the one
# row the bottom voxel's own faces do not reach. It is a constant of the
# placement, not of the phase — which is the horizon rule below.
_FOOT_ROW = 54


_MASSIF_TONES = frozenset(ROCK_RAMP) | frozenset(SNOW_RAMP)


class MountainPhases(unittest.TestCase):
    def _phases(self):
        return [
            terrain.mountain(phase) for phase in range(len(terrain.MOUNTAIN_PHASES))
        ]

    def test_phase_zero_is_the_atlas_mountain_column(self):
        col = terrain.TERRAIN_ORDER.index("mountain")
        column = atlas.build_terrain_atlas().crop(
            (col * CELL, 0, col * CELL + CELL, CELL)
        )
        self.assertEqual(
            column.convert("RGB").tobytes(),
            terrain.mountain(0).convert("RGB").tobytes(),
        )

    def test_every_phase_moves_the_massif(self):
        frames = [tile.convert("RGB").tobytes() for tile in self._phases()]
        self.assertGreaterEqual(len(frames), 2)
        self.assertEqual(len(set(frames)), len(frames))

    def test_a_phase_is_the_same_tile_twice(self):
        for phase, tile in enumerate(self._phases()):
            with self.subTest(phase=phase):
                self.assertEqual(
                    tile.convert("RGB").tobytes(),
                    terrain.mountain(phase).convert("RGB").tobytes(),
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

    def test_every_phase_stands_on_the_same_horizon(self):
        """The rock stops at the same row in every phase and nothing of the
        massif is drawn below it, so a range sits on one ground line."""
        for phase, tile in enumerate(self._phases()):
            with self.subTest(phase=phase):
                rows = _rock_rows(tile)
                self.assertTrue(rows, "phase draws no rock at all")
                self.assertEqual(max(rows), _FOOT_ROW)

    def test_every_phase_casts_its_contact_shadow_onto_the_same_row(self):
        """The massif's foot is a dimetric footprint now — a diamond meeting
        the grass at a front CORNER, not a painted base line across the tile —
        so the shadow it drops is read where that corner puts it: the foot row
        plus the sheet's own down-right offset, the same row in every phase.

        The row count the old tile was held to (half the tile's width of
        shadow, level with a flat base) was a measurement of the front
        elevation, and the elevation is what this pass deleted."""
        want = _FOOT_ROW + SHADOW_OFFSET[1]
        for phase, tile in enumerate(self._phases()):
            with self.subTest(phase=phase):
                cast = _contact_shadow(tile)
                self.assertTrue(cast)
                self.assertEqual(max(y for _, y in cast), want)

    def test_every_phase_keeps_a_summit_worth_a_silhouette(self):
        """A phase that flattened the massif would cost the range its read, so
        each one is held to the shipped tile's own headroom."""
        tops = [min(_rock_rows(tile)) for tile in self._phases()]
        self.assertTrue(all(top <= tops[0] + 4 for top in tops), tops)

    def test_the_sheet_lays_the_phases_out_in_order(self):
        sheet = autotile.mountain_sheet()
        phases = self._phases()
        self.assertEqual(sheet.size, (len(phases) * (CELL + 2) + 2, CELL + 4))
        for i, tile in enumerate(phases):
            with self.subTest(phase=i):
                x = i * (CELL + 2) + 2
                cut = sheet.crop((x, 2, x + CELL, 2 + CELL))
                self.assertEqual(cut.tobytes(), tile.convert("RGB").tobytes())


def _rock_rows(tile) -> list[int]:
    """The rows the massif is drawn on.

    The massif is a voxel mass off two shared ramps now (`palette.ROCK_RAMP`
    and `SNOW_RAMP`), so its pixels are exactly those twelve rungs — which is
    a stronger probe than the four literals this used to look for, and the
    same one `MountainProjection` reads the picture with."""
    rgb = tile.convert("RGB")
    return [
        y
        for y in range(CELL)
        if any(rgb.getpixel((x, y)) in _MASSIF_TONES for x in range(CELL))
    ]


def _contact_shadow(tile) -> list[tuple[int, int]]:
    """The massif's own cast shadow: dark grass with the rock that cast it
    exactly `SHADOW_OFFSET` up-left, which is what tells it from the boulders
    shed on the apron (`OneSun` reads the whole sheet this way)."""
    rgb = tile.convert("RGB")
    dx, dy = SHADOW_OFFSET
    return [
        (x, y)
        for y in range(dy, CELL)
        for x in range(dx, CELL)
        if rgb.getpixel((x, y)) == terrain.GRASS_DARK
        and rgb.getpixel((x - dx, y - dy)) in _MASSIF_TONES
    ]


def _fit(points) -> float:
    """Least-squares slope of a screen contour, in pixels of y per pixel of
    x — the number the projection makes a claim about."""
    n = len(points)
    mx = sum(x for x, _ in points) / n
    my = sum(y for _, y in points) / n
    num = sum((x - mx) * (y - my) for x, y in points)
    return num / sum((x - mx) ** 2 for x, _ in points)


def _contours(sprite):
    """(topmost, bottommost) opaque pixel per column of a rendered massif."""
    px = sprite.load()
    tops: dict[int, int] = {}
    bottoms: dict[int, int] = {}
    for x in range(sprite.width):
        column = [y for y in range(sprite.height) if px[x, y][3]]
        if column:
            tops[x], bottoms[x] = min(column), max(column)
    return tops, bottoms


class MountainProjection(unittest.TestCase):
    """The mountain is drawn in the sheet's projection, like everything else.

    It was not: `terrain.mountain` painted a FRONT ELEVATION — a silhouette
    fitted at slope -1.20/+0.92, the light split by an `x <= apex` comparison,
    no top plane on it anywhere and no y axis at all — while every unit,
    every building and the reef rock beside it are voxel masses in the
    dimetric `voxel` defines. A range of them was a row of cardboard cut-outs
    standing on a three-dimensional board.

    Two readings hold the replacement to the projection rather than to a
    picture: where the mass meets the ground, and what planes it is made of.
    """

    # The ground plane's own slope: +x is (2, 1) on screen, so anything lying
    # IN that plane runs at 2:1. The massif's footprint is such a thing, and
    # it is the one contour a projection claim can be exact about — hence the
    # tight tolerance. A painted elevation's base line comes in at 0.00.
    GROUND_SLOPE = 0.5
    GROUND_TOL = 0.1
    # The summit flank is not: it climbs out of the plane. A flank authored at
    # `buildings.MASSIF_SLOPE` voxels of z per voxel of ground meets the
    # camera along the crest — the 45° diagonal of the ground plane, sqrt(2)
    # of ground per voxel step — so the projection puts it on screen at
    # MASSIF_SLOPE / sqrt(2). The tolerance is wide because the crag relief
    # moves a summit column by up to a voxel, which is 2px of screen y over
    # the 12px the fit is taken across.
    FLANK_TOL = 0.3
    FLANK_SPAN = 12
    # Three oriented planes, and none of them a sliver: the elevation had two
    # (lit and unlit), split by an x comparison rather than by a normal.
    MIN_PLANE_SHARE = 0.15

    def _sprites(self):
        for phase, (peaks, seed) in enumerate(terrain.MOUNTAIN_PHASES):
            yield (
                phase,
                render_indexed_gbuffer(buildings.massif(peaks, seed), FACTIONS[0]),
            )

    def test_the_massifs_foot_lies_in_the_ground_plane(self):
        for phase, g in self._sprites():
            with self.subTest(phase=phase):
                _, bottoms = _contours(g.rgba)
                xs = sorted(bottoms)
                half = len(xs) // 2
                left = [(x, bottoms[x]) for x in xs[:half]]
                right = [(x, bottoms[x]) for x in xs[half:]]
                self.assertAlmostEqual(
                    _fit(left), self.GROUND_SLOPE, delta=self.GROUND_TOL
                )
                self.assertAlmostEqual(
                    _fit(right), -self.GROUND_SLOPE, delta=self.GROUND_TOL
                )

    def test_the_summit_flanks_stand_at_the_slope_they_are_authored_at(self):
        want = buildings.MASSIF_SLOPE / 2**0.5
        for phase, g in self._sprites():
            with self.subTest(phase=phase):
                tops, _ = _contours(g.rgba)
                apex = min(tops, key=lambda x: (tops[x], x))
                left = [
                    (x, y)
                    for x, y in tops.items()
                    if apex - self.FLANK_SPAN <= x < apex
                ]
                right = [
                    (x, y)
                    for x, y in tops.items()
                    if apex < x <= apex + self.FLANK_SPAN
                ]
                self.assertAlmostEqual(-_fit(left), want, delta=self.FLANK_TOL)
                self.assertAlmostEqual(_fit(right), want, delta=self.FLANK_TOL)

    def test_the_massif_is_three_oriented_planes(self):
        for phase, g in self._sprites():
            with self.subTest(phase=phase):
                px = g.rgba.load()
                normals = [
                    g.normal.values[y * g.rgba.width + x]
                    for y in range(g.rgba.height)
                    for x in range(g.rgba.width)
                    if px[x, y][3]
                ]
                self.assertEqual(set(normals), {N_TOP, N_LEFT, N_RIGHT})
                for plane in (N_TOP, N_LEFT, N_RIGHT):
                    share = normals.count(plane) / len(normals)
                    self.assertGreater(share, self.MIN_PLANE_SHARE)

    def test_every_massif_pixel_is_a_ramp_rung(self):
        """The other half of the rewrite: the faces are SLOTS, not arithmetic.
        The elevation computed a tone per band and per dither parity."""
        for phase, tones in enumerate(self._phases_with_rock()):
            with self.subTest(phase=phase):
                self.assertTrue(tones)
                self.assertLessEqual(tones, _MASSIF_TONES)

    def _phases_with_rock(self):
        for phase in range(len(terrain.MOUNTAIN_PHASES)):
            sprite = render_indexed_gbuffer(
                buildings.massif(*terrain.MOUNTAIN_PHASES[phase]), FACTIONS[0]
            ).rgba
            px = sprite.load()
            yield {
                px[x, y][:3]
                for y in range(sprite.height)
                for x in range(sprite.width)
                if px[x, y][3]
            }


if __name__ == "__main__":
    unittest.main()
