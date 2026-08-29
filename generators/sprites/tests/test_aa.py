"""Inner-corner softening: what it may touch, and what it may never touch.

`spritegen.aa` is the sheet's only post-hoc edit of a rendered sprite, so it
is held to the narrowest contract on the pipeline: one pixel per staircase
step, inside the silhouette, out of a colour the sprite already uses. These
tests are written against SYNTHETIC staircases rather than against a unit,
because a unit's edges are the 2:1 runs of two the rule deliberately leaves
alone, and a test that measured those would be measuring today's models.

Run with `.venv/bin/python -m unittest discover tests`.
"""

from __future__ import annotations

import unittest
from unittest import mock

from PIL import Image

from spritegen import aa, atlas, buildings, terrain
from spritegen.palette import FACTIONS, SLOTS
from spritegen.units import ATLAS_ORDER, Pose, build_model
from spritegen.voxel import render, render_indexed


# A stand-in six-step ramp: evenly spaced greys, so a slot is readable off the
# pixel and a mid slot is unambiguous.
RAMP = tuple((v, v, v) for v in range(0, 251, 50))
EDGE = RAMP[0]
FILL = RAMP[3]


def staircase(run: int, rise: int, steps: int = 5) -> Image.Image:
    """A filled staircase descending to the right: `run` pixels across per
    `rise` pixels down, outlined one pixel thick in the ramp's S0."""
    w, h = run * steps + 2, rise * steps + 2
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(min(run * (y // rise) + run, w)):
            px[x, y] = (*FILL, 255)
    solid = [[px[x, y][3] == 255 for x in range(w)] for y in range(h)]

    def at(x: int, y: int) -> bool:
        return 0 <= x < w and 0 <= y < h and solid[y][x]

    for y in range(h):
        for x in range(w):
            if solid[y][x] and not all(
                at(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
            ):
                px[x, y] = (*EDGE, 255)
    return img


def thick_edge_staircase(run: int, rise: int, thickness: int) -> Image.Image:
    """`staircase`, but with an edge `thickness` pixels deep instead of one —
    a lit FACE along the step rather than a one-pixel line."""
    img = staircase(run, rise)
    px = img.load()
    w, h = img.size
    for _ in range(thickness - 1):
        edge = [
            (x, y)
            for y in range(h)
            for x in range(w)
            if px[x, y][3] and px[x, y][:3] == EDGE
        ]
        for x, y in edge:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                cx, cy = x + dx, y + dy
                if 0 <= cx < w and 0 <= cy < h and px[cx, cy][3]:
                    px[cx, cy] = (*EDGE, 255)
    return img


def changed(before: Image.Image, after: Image.Image) -> list[tuple[int, int]]:
    return [
        (x, y)
        for y in range(before.height)
        for x in range(before.width)
        if before.getpixel((x, y)) != after.getpixel((x, y))
    ]


class InnerCorners(unittest.TestCase):
    """Exactly the corners in the crook of a long step, and nothing else."""

    def test_a_long_shallow_staircase_softens_one_pixel_per_step(self):
        # Steps of four across and two down: the corner is the first pixel of
        # each lower run, the one the outline turns through.
        img = staircase(4, 2)
        out = aa.soften_staircase(img, (RAMP,))
        self.assertEqual(changed(img, out), [(4, 2), (8, 4), (12, 6), (16, 8)])

    def test_a_one_pixel_rise_softens_one_pixel_per_step(self):
        img = staircase(4, 1)
        out = aa.soften_staircase(img, (RAMP,))
        self.assertEqual(changed(img, out), [(4, 1), (8, 2), (12, 3), (16, 4)])

    def test_the_softened_pixel_is_the_mid_slot_of_the_sprites_own_ramp(self):
        out = aa.soften_staircase(staircase(4, 2), (RAMP,))
        corner = out.getpixel((4, 2))[:3]
        self.assertIn(corner, RAMP, "softening invented a colour off the ramp")
        self.assertEqual(corner, RAMP[(0 + 3) // 2])

    def test_it_adds_no_colour_to_the_sprite(self):
        img = staircase(4, 2)
        out = aa.soften_staircase(img, (RAMP,))
        self.assertLessEqual(len(set(out.getdata())), len(RAMP) + 1)


class ShortRuns(unittest.TestCase):
    """A clean diagonal is not a staircase to be fixed."""

    def test_a_45_degree_edge_is_untouched(self):
        img = staircase(1, 1)
        self.assertEqual(changed(img, aa.soften_staircase(img, (RAMP,))), [])

    def test_the_2_to_1_runs_the_projection_draws_are_untouched(self):
        img = staircase(2, 1)
        self.assertEqual(changed(img, aa.soften_staircase(img, (RAMP,))), [])

    def test_min_run_is_the_knob_that_decides_it(self):
        img = staircase(2, 1)
        self.assertTrue(changed(img, aa.soften_staircase(img, (RAMP,), min_run=2)))

    def test_a_riser_taller_than_a_step_is_the_shapes_own_corner(self):
        img = staircase(4, aa._MAX_RISE + 1)
        self.assertEqual(changed(img, aa.soften_staircase(img, (RAMP,))), [])


class ReachesOnlyThroughTheLine(unittest.TestCase):
    """The colour a corner is softened toward is the body under the OUTLINE,
    which is one pixel wide (docs/outlines.md) — never a plane several pixels
    in. Reaching further is how a bright corner on a wide lit face used to be
    softened toward a dark tone that was nowhere near it."""

    def test_a_corner_on_a_face_deeper_than_the_reach_is_left_alone(self):
        img = thick_edge_staircase(4, 2, aa._INTERIOR_REACH + 1)
        self.assertEqual(changed(img, aa.soften_staircase(img, (RAMP,))), [])

    def test_a_line_doubled_at_the_corner_still_softens(self):
        # A stair corner puts two line pixels in a column; the body is then at
        # step two, and that is the whole allowance the reach exists for.
        img = thick_edge_staircase(4, 2, 2)
        self.assertTrue(changed(img, aa.soften_staircase(img, (RAMP,))))

    def test_no_unit_corner_is_softened_away_from_its_own_edge(self):
        # Every write lands strictly between the corner's colour and the body,
        # so a lit corner may only darken toward the body and a shaded one may
        # only lighten toward it — never past either end.
        def value(c):
            return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

        for uid in ATLAS_ORDER:
            model = build_model(uid, Pose.A)
            for fac in (FACTIONS[0], FACTIONS[1]):
                sprite = render_indexed(model, fac).image
                out = aa.soften_sprite(sprite, model, fac)
                for x, y in changed(sprite, out):
                    edge = sprite.getpixel((x, y))[:3]
                    # Every colour within the pass's own reach, in each of the
                    # four inward directions: one of them is the body it read.
                    bodies = []
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        for step in range(1, aa._INTERIOR_REACH + 1):
                            near = sprite.getpixel((x + dx * step, y + dy * step))
                            if not near[3]:
                                break
                            if near[:3] != edge:
                                bodies.append(near[:3])
                                break
                    mid = value(out.getpixel((x, y))[:3])
                    self.assertTrue(
                        any(
                            min(value(edge), value(b))
                            <= mid
                            <= max(value(edge), value(b))
                            for b in bodies
                        ),
                        f"{uid} {fac.key} {(x, y)}: softened past {edge} and {bodies}",
                    )


class NeverOutside(unittest.TestCase):
    """Softening may not grow the silhouette, and may not shrink it."""

    def test_alpha_is_untouched_on_a_synthetic_staircase(self):
        img = staircase(4, 2)
        out = aa.soften_staircase(img, (RAMP,))
        self.assertEqual(img.getchannel("A").tobytes(), out.getchannel("A").tobytes())

    def test_alpha_is_untouched_on_every_unit(self):
        for uid in ATLAS_ORDER:
            for pose in (Pose.A, Pose.B):
                model = build_model(uid, pose)
                for fac in (FACTIONS[0], FACTIONS[3]):
                    sprite = render_indexed(model, fac).image
                    out = aa.soften_sprite(sprite, model, fac)
                    self.assertEqual(
                        sprite.getchannel("A").tobytes(),
                        out.getchannel("A").tobytes(),
                        f"{uid} {pose.name} {fac.key} changed its silhouette",
                    )

    def test_the_input_image_is_never_mutated(self):
        img = staircase(4, 2)
        before = img.tobytes()
        aa.soften_staircase(img, (RAMP,))
        self.assertEqual(img.tobytes(), before)


class Palette(unittest.TestCase):
    """The result stays inside the ramps the sprite was painted from."""

    def test_no_unit_lands_off_its_own_ramps(self):
        # A softened corner may be a slot the sprite was not using — that is
        # what a mid-tone IS — but never a colour outside the ramps the model
        # is painted from, which is what keeps a faction a ramp swap.
        for uid in ATLAS_ORDER:
            model = build_model(uid, Pose.A)
            for fac in FACTIONS:
                sprite = render_indexed(model, fac).image
                out = aa.soften_sprite(sprite, model, fac)
                allowed = {c for ramp in aa.ramps_for_model(model, fac) for c in ramp}
                allowed |= {p[:3] for p in sprite.getdata() if p[3]}
                stray = {p[:3] for p in out.getdata() if p[3]} - allowed
                self.assertEqual(stray, set(), f"{uid} {fac.key} gained {stray}")

    def test_a_colour_pair_that_shares_no_ramp_is_left_alone(self):
        img = staircase(4, 2)
        other = tuple((0, v, 0) for v in range(0, 251, 50))
        self.assertEqual(changed(img, aa.soften_staircase(img, (other,))), [])

    def test_neighbouring_slots_have_no_mid_and_are_left_alone(self):
        img = staircase(4, 2)
        px = img.load()
        # Repaint the fill one slot off the edge colour: nothing sits between.
        for y in range(img.height):
            for x in range(img.width):
                if px[x, y][:3] == FILL:
                    px[x, y] = (*RAMP[1], 255)
        self.assertEqual(changed(img, aa.soften_staircase(img, (RAMP,))), [])


class Determinism(unittest.TestCase):
    """Same input, same bytes — the pass carries no state and no randomness."""

    def test_repeated_runs_agree(self):
        img = staircase(4, 2)
        first = aa.soften_staircase(img, (RAMP,))
        for _ in range(3):
            self.assertEqual(
                aa.soften_staircase(img, (RAMP,)).tobytes(), first.tobytes()
            )

    def test_the_gate_turns_the_pass_off_completely(self):
        model = build_model("mech", Pose.A)
        sprite = render_indexed(model, FACTIONS[1]).image
        aa.ENABLED = False
        try:
            self.assertIs(aa.soften_sprite(sprite, model, FACTIONS[1]), sprite)
        finally:
            aa.ENABLED = True

    def test_a_short_sprite_is_skipped(self):
        model = build_model("mech", Pose.A)
        sprite = render_indexed(model, FACTIONS[1]).image
        short = sprite.crop((0, 0, sprite.width, aa.MIN_SPRITE_HEIGHT - 1))
        self.assertIs(aa.soften_sprite(short, model, FACTIONS[1]), short)


class Wiring(unittest.TestCase):
    """The pass is actually the last word on a cell, not just a module."""

    CELLS = ("infantry", "mech", "recon", "bomber", "cruiser")

    def _cells(self):
        # Rendered rather than asked of `pose_cell`: these tests render the
        # same cells twice with `aa.ENABLED` flipped between, and a shared
        # cell would hand the second call the first one's answer.
        return [atlas.unit_cell(uid, FACTIONS[0]) for uid in self.CELLS]

    def test_the_composed_cell_carries_the_softening(self):
        # Same cells with the pass gated off: at least one has to move, or
        # nothing in the pipeline is calling it.
        after = self._cells()
        aa.ENABLED = False
        try:
            before = self._cells()
        finally:
            aa.ENABLED = True
        moved = [
            uid
            for uid, a, b in zip(self.CELLS, before, after)
            if a.tobytes() != b.tobytes()
        ]
        self.assertTrue(moved, "unit_cell composes an unsoftened sprite")

    def test_the_cell_silhouette_is_the_same_either_way(self):
        after = self._cells()
        aa.ENABLED = False
        try:
            before = self._cells()
        finally:
            aa.ENABLED = True
        for uid, a, b in zip(self.CELLS, before, after):
            self.assertEqual(
                a.getchannel("A").tobytes(),
                b.getchannel("A").tobytes(),
                f"{uid} changed its cell silhouette",
            )


class Buildings(unittest.TestCase):
    """The property buildings run through the pass, and it finds nothing.

    Both halves are the claim `aa`'s docstring records: the seam is wired, and
    at the shipped `MIN_RUN` a building — a base-plate diamond and axis-aligned
    walls, runs of two end to end — has no corner that qualifies. If a model is
    redrawn with a shallower line, the first test here is what says so.
    """

    BUILDINGS = ("city", "base", "hq", "airport", "port")

    def test_no_building_has_a_qualifying_corner(self):
        for bid in self.BUILDINGS:
            for fac in FACTIONS:
                model = buildings.model_for(bid, fac)
                sprite = render(model, fac)
                # Not the height gate answering for the run rule.
                self.assertGreaterEqual(sprite.height, aa.MIN_SPRITE_HEIGHT)
                out = aa.soften_sprite(sprite, model, fac)
                self.assertEqual(changed(sprite, out), [], f"{bid} {fac.key}")

    def _softened_at_two(self, bid: str, fac) -> Image.Image:
        """`property_sprite` with the run bar lowered to the runs of two a
        building is actually drawn out of — the only way to see the seam
        carry anything at all."""
        real = aa.soften_staircase

        def softer(sprite, model, faction):
            return real(sprite, aa.ramps_for_model(model, faction), 2)

        with mock.patch.object(aa, "soften_sprite", softer):
            return terrain.property_sprite(bid, fac)

    def test_the_property_sprite_is_the_softened_one(self):
        for bid in self.BUILDINGS:
            fac = FACTIONS[0]
            plain = render(buildings.model_for(bid, fac), fac)
            self.assertNotEqual(
                plain.tobytes(),
                self._softened_at_two(bid, fac).tobytes(),
                f"{bid} is drawn unsoftened",
            )

    def test_a_softened_building_keeps_its_silhouette_and_its_palette(self):
        for bid in self.BUILDINGS:
            for fac in FACTIONS:
                model = buildings.model_for(bid, fac)
                plain = render(model, fac)
                soft = self._softened_at_two(bid, fac)
                self.assertEqual(
                    plain.getchannel("A").tobytes(),
                    soft.getchannel("A").tobytes(),
                    f"{bid} {fac.key} changed its silhouette",
                )
                allowed = {c for ramp in aa.ramps_for_model(model, fac) for c in ramp}
                allowed |= {p[:3] for p in plain.getdata() if p[3]}
                stray = {p[:3] for p in soft.getdata() if p[3]} - allowed
                self.assertFalse(
                    stray, f"{bid} {fac.key} landed off its ramps: {stray}"
                )


class RampShape(unittest.TestCase):
    """The stand-in ramp used here has the shape the real ones do."""

    def test_it_is_six_slots(self):
        self.assertEqual(len(RAMP), SLOTS)


if __name__ == "__main__":
    unittest.main()
