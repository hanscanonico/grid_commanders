"""Contract tests for the sheets the game reads whole.

The atlas sizes the game drops in unchanged, byte-for-byte determinism, and
the figure sheet the cut-ins cut from.
"""

from __future__ import annotations

import unittest

from spritegen import atlas, autotile, terrain
from spritegen.palette import FACTIONS
from spritegen.units import ATLAS_ORDER, Pose


class AtlasContract(unittest.TestCase):
    """The two sheets the game drops in unchanged."""

    def test_units_atlas_is_18_by_5_rgba_cells(self):
        img = atlas.build_units_atlas()
        self.assertEqual(
            img.size, (len(ATLAS_ORDER) * atlas.CELL_W, len(FACTIONS) * atlas.CELL_H)
        )
        self.assertEqual(img.size, (1152, 480))
        self.assertEqual(img.mode, "RGBA")

    def test_terrain_atlas_is_14_by_5_rgba_cells(self):
        img = atlas.build_terrain_atlas()
        self.assertEqual(
            img.size, (len(terrain.TERRAIN_ORDER) * 64, len(FACTIONS) * 64)
        )
        self.assertEqual(img.size, (896, 320))
        # RGBA, not RGB: the property columns carry alpha — see PropertyOverlays.
        self.assertEqual(img.mode, "RGBA")

    def test_every_atlas_row_renders_its_own_faction(self):
        img = atlas.build_units_atlas()
        rows = [
            img.crop((0, r * atlas.CELL_H, img.width, (r + 1) * atlas.CELL_H)).tobytes()
            for r in range(len(FACTIONS))
        ]
        self.assertEqual(len(set(rows)), len(FACTIONS))


class Determinism(unittest.TestCase):
    """No seeds, no RNG: identical bytes on every render."""

    def test_units_atlas_is_reproducible(self):
        self.assertEqual(
            atlas.build_units_atlas().tobytes(), atlas.build_units_atlas().tobytes()
        )

    def test_terrain_atlas_is_reproducible(self):
        self.assertEqual(
            atlas.build_terrain_atlas().tobytes(), atlas.build_terrain_atlas().tobytes()
        )

    def test_demo_map_is_reproducible(self):
        self.assertEqual(atlas.build_demo().tobytes(), atlas.build_demo().tobytes())

    def test_autotile_sheets_are_reproducible(self):
        for builder in (
            autotile.road_tile,
            autotile.river_tile,
            autotile.coast_tile,
            autotile.shoal_tile,
            autotile.woods_tile,
        ):
            with self.subTest(builder=builder.__name__):
                self.assertEqual(
                    autotile.variant_sheet(builder).tobytes(),
                    autotile.variant_sheet(builder).tobytes(),
                )


class FigureSheet(unittest.TestCase):
    """units_atlas_figures[_b].png: the board's army, minus the tile's shadow.

    The cut-ins draw the art at 1:1 over a ground plane of their own, with a
    contact shadow of their own under it, so the tile's would be a second
    shadow rather than the same one. What the sheets must never be is a second
    opinion on the ART: the figure a cut-in blows up has to be the figure the
    board shows, in either key pose — the pair is the ambient pair with the
    shadow erased, which is what lets a cut-in idle on the same beat.
    """

    def test_it_removes_shadow_pixels_and_changes_nothing_else(self):
        for pose in (Pose.A, Pose.B):
            with self.subTest(pose=pose):
                board = atlas.build_units_atlas(pose).load()
                figures = atlas.build_units_atlas(pose, shadow=False).load()
                removed = 0
                for y in range(len(FACTIONS) * atlas.CELL_H):
                    for x in range(len(ATLAS_ORDER) * atlas.CELL_W):
                        if board[x, y] == figures[x, y]:
                            continue
                        # The only legal difference: an opaque shadow pixel is
                        # gone.
                        self.assertEqual(
                            figures[x, y][3], 0, f"repainted pixel at {x},{y}"
                        )
                        self.assertEqual(board[x, y][3], 255, f"half-shadow at {x},{y}")
                        removed += 1
                self.assertGreater(removed, 0)

    def test_every_unit_of_every_faction_loses_its_shadow(self):
        for pose in (Pose.A, Pose.B):
            with self.subTest(pose=pose):
                board = atlas.build_units_atlas(pose)
                figures = atlas.build_units_atlas(pose, shadow=False)
                for row, fac in enumerate(FACTIONS):
                    for col, uid in enumerate(ATLAS_ORDER):
                        box = (
                            col * atlas.CELL_W,
                            row * atlas.CELL_H,
                            (col + 1) * atlas.CELL_W,
                            (row + 1) * atlas.CELL_H,
                        )
                        self.assertNotEqual(
                            board.crop(box).tobytes(),
                            figures.crop(box).tobytes(),
                            f"{uid} ({fac.key}) has no shadow to leave off in {pose}",
                        )

    def test_the_figure_sheets_are_reproducible(self):
        for pose in (Pose.A, Pose.B):
            self.assertEqual(
                atlas.build_units_atlas(pose, shadow=False).tobytes(),
                atlas.build_units_atlas(pose, shadow=False).tobytes(),
            )

    def test_the_two_figure_frames_differ(self):
        """A clip needs two frames: the shadow erase must not flatten the
        pose difference the ambient pair carries."""
        self.assertNotEqual(
            atlas.build_units_atlas(Pose.A, shadow=False).tobytes(),
            atlas.build_units_atlas(Pose.B, shadow=False).tobytes(),
        )


if __name__ == "__main__":
    unittest.main()
