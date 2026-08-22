"""The depth and normal planes, and the two pure passes over them.

The models here are synthetic — one voxel, two voxels — because the passes are
about geometry the eye can check by hand: a single cube is three faces, one
depth, and a silhouette exactly one pixel thick. The last test holds the whole
point of the change: adding the planes moved no colour.

Run with `.venv/bin/python -m unittest discover tests`.
"""

from __future__ import annotations

import unittest

from spritegen.gbuffer import (
    DEPTH_EMPTY,
    N_LEFT,
    N_NONE,
    N_RIGHT,
    N_TOP,
    convex_edges,
    edge_mask,
    voxel_depth,
)
from spritegen.palette import FACTIONS
from spritegen.units import build_model
from spritegen.voxel import (
    Model,
    render,
    render_gbuffer,
    render_indexed,
    render_indexed_gbuffer,
)

FACTION = FACTIONS[1]


def cube() -> Model:
    m = Model()
    m.set(0, 0, 0, "body")
    return m


class VoxelDepth(unittest.TestCase):
    """Depth runs along the camera ray, the one direction the projection hides."""

    def test_the_view_axis_is_the_only_offset_that_moves_depth_alone(self):
        # (1, 1, 1) lands on the same screen pixel, and is one step nearer.
        self.assertEqual(voxel_depth(1, 1, 1) - voxel_depth(0, 0, 0), 3)
        for step in ((1, 0, 0), (0, 1, 0), (0, 0, 1)):
            self.assertEqual(voxel_depth(*step) - voxel_depth(0, 0, 0), 1)


class SingleCube(unittest.TestCase):
    """One voxel: three faces, one depth, a 1px ring.

    `_bounds` reserves a 1px margin, so the 4x4 cube stamp sits at (1, 1) in a
    7x7 buffer — every coordinate below is read off that stamp.
    """

    def setUp(self):
        self.g = render_indexed_gbuffer(cube(), FACTION, outline=False)
        self.drawn = {
            (x, y)
            for y in range(self.g.height)
            for x in range(self.g.width)
            if self.g.normal.at(x, y) != N_NONE
        }

    def test_the_three_faces_carry_three_normals(self):
        self.assertEqual(
            {self.g.normal.at(x, y) for x, y in self.drawn}, {N_TOP, N_LEFT, N_RIGHT}
        )
        # The rhombus tip is top, the bottom row is the two side faces.
        self.assertEqual(self.g.normal.at(2, 1), N_TOP)
        self.assertEqual(self.g.normal.at(1, 4), N_LEFT)
        self.assertEqual(self.g.normal.at(4, 4), N_RIGHT)

    def test_every_written_pixel_shares_the_one_voxel_depth(self):
        depths = {self.g.depth.at(x, y) for x, y in self.drawn}
        self.assertEqual(depths, {voxel_depth(0, 0, 0)})

    def test_unwritten_pixels_are_depth_empty(self):
        for y in range(self.g.height):
            for x in range(self.g.width):
                if (x, y) not in self.drawn:
                    self.assertEqual(self.g.depth.at(x, y), DEPTH_EMPTY)

    def test_the_depth_edge_ring_is_one_pixel_thick(self):
        mask = edge_mask(self.g.depth)
        marked = {
            (x, y)
            for y in range(mask.height)
            for x in range(mask.width)
            if mask.at(x, y)
        }
        # Nothing outside the shape, and exactly the ring inside it: the only
        # pixels a 4x4 stamp keeps are the 2x2 that touch no transparency.
        self.assertEqual(marked, self.drawn - {(2, 2), (3, 2), (2, 3), (3, 3)})

    def test_the_ridges_between_the_three_faces_are_convex(self):
        mask = convex_edges(self.g.normal)
        # Top over left, top over right: the cube's upper creases, both sides.
        self.assertTrue(mask.at(1, 2) and mask.at(1, 3))
        self.assertTrue(mask.at(4, 2) and mask.at(4, 3))
        # The near vertical corner where the two side faces meet.
        self.assertTrue(mask.at(2, 4) and mask.at(3, 4))
        # The rhombus tip sees only top pixels, so it is on no crease.
        self.assertFalse(mask.at(2, 1))


class ConvexAgainstConcave(unittest.TestCase):
    """The heuristic has to tell a ridge from a gutter, not just find creases."""

    def setUp(self):
        # A wall three voxels tall with a deck spread in front of it along +y:
        # the wall's screen-left face meets that deck in a concave gutter, and
        # the deck is wide enough that a gutter pixel is interior to it.
        m = Model()
        m.box(0, 2, 0, 0, 0, 2, "body")
        m.box(0, 3, 1, 3, 0, 0, "body")
        self.g = render_indexed_gbuffer(m, FACTION, outline=False)
        self.gutter = [
            (x, y)
            for y in range(1, self.g.height)
            for x in range(self.g.width)
            if self.g.normal.at(x, y) == N_TOP and self.g.normal.at(x, y - 1) == N_LEFT
        ]

    def test_a_wall_standing_on_a_deck_leaves_that_crease_unmarked(self):
        mask = convex_edges(self.g.normal)
        self.assertTrue(self.gutter, "expected a wall standing on a lower top")
        # The deck side of the gutter is checked, not the wall side: a wall
        # pixel can sit on the wall's OWN convex corner as well as in the
        # gutter, and the mask is per pixel, not per crease.
        for x, y in self.gutter:
            self.assertFalse(mask.at(x, y), f"concave crease marked at {(x, y)}")

    def test_the_wall_top_still_reads_as_a_convex_ridge(self):
        mask = convex_edges(self.g.normal)
        ridges = [
            (x, y)
            for y in range(self.g.height - 1)
            for x in range(self.g.width)
            if self.g.normal.at(x, y) == N_TOP and self.g.normal.at(x, y + 1) == N_LEFT
        ]
        self.assertTrue(ridges)
        for x, y in ridges:
            self.assertTrue(mask.at(x, y) and mask.at(x, y + 1))


class FlatDeck(unittest.TestCase):
    """The default depth threshold has to survive a plane seen at an angle."""

    def test_a_level_slab_is_marked_only_on_its_silhouette(self):
        m = Model()
        m.box(0, 3, 0, 3, 0, 0, "body")
        g = render_indexed_gbuffer(m, FACTION, outline=False)
        mask = edge_mask(g.depth)

        def drawn(x, y):
            return (
                0 <= x < g.width and 0 <= y < g.height and g.normal.at(x, y) != N_NONE
            )

        for y in range(g.height):
            for x in range(g.width):
                if not mask.at(x, y):
                    continue
                # Every mark has to be justified by transparency next door or
                # by the slab's own side faces, never by a seam in its top.
                touches_air = any(
                    not drawn(x + dx, y + dy)
                    for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1))
                )
                self.assertTrue(
                    touches_air or g.normal.at(x, y) != N_TOP,
                    f"flat deck seam marked at {(x, y)}",
                )


def slab() -> Model:
    """A model the SHADED path can draw too: it resolves "body" directly."""
    m = Model()
    m.box(0, 3, 0, 2, 0, 1, "body")
    return m


class Determinism(unittest.TestCase):
    """The planes are as reproducible as the picture."""

    def test_both_renderers_repeat_every_plane(self):
        for call, model in (
            (render_indexed_gbuffer, build_model("md_tank", 0)),
            (render_gbuffer, slab()),
        ):
            a, b = call(model, FACTION), call(model, FACTION)
            self.assertEqual(a.rgba.tobytes(), b.rgba.tobytes())
            self.assertEqual(list(a.depth.values), list(b.depth.values))
            self.assertEqual(list(a.normal.values), list(b.normal.values))
            self.assertEqual(list(a.material.values), list(b.material.values))


class PurelyAdditive(unittest.TestCase):
    """The wrappers hand back exactly what they always did."""

    def test_the_indexed_wrapper_matches_its_gbuffer(self):
        model = build_model("md_tank", 0)
        sprite = render_indexed(model, FACTION)
        g = render_indexed_gbuffer(model, FACTION)
        self.assertEqual(sprite.image.tobytes(), g.rgba.tobytes())
        self.assertEqual(bytes(sprite.materials), bytes(g.material.values))

    def test_the_shaded_wrapper_matches_its_gbuffer(self):
        model = slab()
        self.assertEqual(
            render(model, FACTION).tobytes(),
            render_gbuffer(model, FACTION).rgba.tobytes(),
        )

    def test_an_empty_model_still_renders_a_1x1_hole(self):
        empty = Model()
        self.assertEqual(render(empty, FACTION).size, (1, 1))
        sprite = render_indexed(empty, FACTION)
        self.assertEqual(sprite.image.size, (1, 1))
        self.assertEqual(len(sprite.materials), 1)


if __name__ == "__main__":
    unittest.main()
