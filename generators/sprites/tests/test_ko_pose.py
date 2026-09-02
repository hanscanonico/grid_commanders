"""Contract tests for the KO clip: units_atlas_figures_ko.png.

The casualty sheet is AUTHORED art — a hand-placed crumpled figure for
infantry and mech, a burnt-out hull for a tracked or wheeled vehicle, a hull
settled by the stern for a ship — never a second subtraction of the ambient
pair's cast shadow. `test_atlas_contract.py`'s `FigureSheet` pins the ambient
pair's two figures to differ from the board sheet in NOTHING but an erased
shadow; that subtract-only rule is the idle pair's alone and does not bind
this sheet, so a KO cell is free to differ from its own faction's pose-A
cell in silhouette, pose and tone all at once, on purpose.

Air ships no authored frame in v1 (the plan's own fallback): every column
still renders, off the unit's own rest key (`units.build_model`'s fallback),
because `pipeline.SHEETS` composes a full 18-column grid whatever a family
has authored — but nothing reads that column at runtime
(`CutsceneSide.bind` never asks for one on a flying unit).
"""

from __future__ import annotations

import unittest

from spritegen import anim, atlas, pipeline
from spritegen.palette import FACTIONS, RAMPS, S_TOP, luminance
from spritegen.units import ATLAS_ORDER, KOS, UNITS, Pose, build_model
from spritegen.voxel import ramp_floor

from pixel_helpers import pose_cell, units_sheet

# The cell's own composed decoration — the cast-shadow-adjacent wake and the
# waterline foam `compose_cell` paints in AFTER the unit renders — excluded
# the same way `test_value_bands.UnitBandCoverage.COMPOSED` excludes it: a
# unit's own burn-down never reaches either, and testing them as if it did
# would fail every hull on its own sea state rather than its own paint.
COMPOSED = {(16, 18, 24), (226, 240, 250)}


def _shipped_ko_sheet():
    """The KO sheet a full run writes, built through the row that declares it
    so the pins read the composition the game installs."""
    ko = next(o for o in pipeline.SHEETS if o.rel == anim.KO_SHEET)
    return ko.build()


def _opaque(img):
    px = img.convert("RGBA").load()
    return [
        px[x, y][:3]
        for y in range(img.height)
        for x in range(img.width)
        if px[x, y][3] == 255
    ]


def _paint(img):
    return [c for c in _opaque(img) if c not in COMPOSED]


class KoSheet(unittest.TestCase):
    """The grid: same size as every other units sheet, one frame, shadowless."""

    def test_it_is_the_same_grid_as_the_other_units_sheets(self):
        ko = _shipped_ko_sheet()
        self.assertEqual(
            ko.size, (len(ATLAS_ORDER) * atlas.CELL_W, len(FACTIONS) * atlas.CELL_H)
        )
        self.assertEqual(ko.mode, "RGBA")

    def test_the_shipped_sheet_leaves_the_tile_shadow_off(self):
        """Asked of the row `pipeline.SHEETS` actually writes, not of a
        composition this test picked: the cut-in draws its own contact shadow
        under the figure, so a tile shadow baked into this sheet would be a
        second one. Flip that row to `shadow=True` and the two sheets become
        the same picture — `removed` falls to zero and this fails."""
        shipped = _shipped_ko_sheet().convert("RGBA").load()
        shadowed = units_sheet(Pose.KO).convert("RGBA").load()
        removed = 0
        for y in range(len(FACTIONS) * atlas.CELL_H):
            for x in range(len(ATLAS_ORDER) * atlas.CELL_W):
                if shipped[x, y] == shadowed[x, y]:
                    continue
                # The only legal difference: an opaque shadow pixel is gone.
                self.assertEqual(shipped[x, y][3], 0, f"repainted pixel at {x},{y}")
                self.assertEqual(shadowed[x, y][3], 255, f"half-shadow at {x},{y}")
                removed += 1
        self.assertGreater(removed, 0)

    def test_it_is_reproducible(self):
        self.assertEqual(
            atlas.build_units_atlas(Pose.KO, shadow=False).tobytes(),
            atlas.build_units_atlas(Pose.KO, shadow=False).tobytes(),
        )


class AirFallback(unittest.TestCase):
    """Air carries no KO frame in v1: its column is its own rest key."""

    def test_every_air_column_is_pose_a(self):
        for uid, (_, kind) in UNITS.items():
            if kind != "air":
                continue
            with self.subTest(unit=uid):
                self.assertNotIn(uid, KOS)
                for fac in FACTIONS:
                    self.assertEqual(
                        pose_cell(uid, fac, Pose.KO, shadow=False).tobytes(),
                        pose_cell(uid, fac, Pose.A, shadow=False).tobytes(),
                    )

    def test_every_land_and_sea_unit_authors_one(self):
        for uid, (_, kind) in UNITS.items():
            if kind == "air":
                continue
            with self.subTest(unit=uid):
                self.assertIn(uid, KOS)

    def test_a_membership_without_a_wreck_is_not_a_ko_frame(self):
        """`KOS` is the claim that this unit has a wreck; the builder is where
        the claim is kept, and they are independent — `atlas.unit_cell` burns
        the tone on membership alone, so a uid added to `KOS` whose builder
        grew no `Pose.KO` branch would ship its REST pose, standing, dead by
        value and nothing else. Every pin above still passes that sheet: the
        silhouette is the live one, and the tone band is `wreck_tone`'s. So
        ask the models, which the burn does not reach — the same reading
        `test_clips` takes of a move pair that is the ambient pair."""
        for uid in sorted(KOS):
            with self.subTest(unit=uid):
                self.assertNotEqual(
                    build_model(uid, Pose.KO).vox, build_model(uid, Pose.A).vox
                )


class Silhouette(unittest.TestCase):
    """Per-column silhouette floor, measured off the shipped models rather
    than argued: a KO cell may lose mass — a prone figure renders about half
    the height of a standing one, 20 rows against 37 for the rifleman — but
    never enough to read as a blob or a speck. `MIN_RATIO` is a floor under
    every measured ratio, and mass is not height; the foot
    family's own crouch (0.685-0.703 of its own pose-A count) is the
    tightest reading on the roster and sets it, everything else clearing it
    by a wide margin (0.87-1.03, `apc` and `missiles` even gaining mass from
    their sprung ramp/toppled rounds).
    """

    MIN_RATIO = 0.6
    # An absolute floor besides the ratio one, so a unit whose pose-A count
    # somehow shrank could not silently drag its own KO floor down with it.
    MIN_PIXELS = 400

    def test_every_ko_cell_clears_its_own_silhouette_floor(self):
        for uid in ATLAS_ORDER:
            if uid not in KOS:
                continue
            for fac in FACTIONS:
                with self.subTest(unit=uid, faction=fac.key):
                    live = len(_opaque(pose_cell(uid, fac, Pose.A, shadow=False)))
                    dead = len(_opaque(pose_cell(uid, fac, Pose.KO, shadow=False)))
                    self.assertGreaterEqual(dead, self.MIN_PIXELS)
                    self.assertGreaterEqual(dead, live * self.MIN_RATIO)


class InteriorFloor(unittest.TestCase):
    """Interior value floor: dead by value, never by hue.

    `voxel.wreck_tone` re-keys every opaque pixel of an authored KO cell
    into `[ramp_floor(ramp), luminance(ramp[S_TOP])]` — the ramp being the
    unit's own faction row — so no interior pixel may fall under that floor,
    none may reach past the ordinary lit plane the rim used to own, and the
    tone band a unit is rendered into is narrower dead than it was alive.
    Measured against the actual render rather than trusted from the
    generator's own arithmetic, the way `Cell.test_ground_px_is_the_
    composer_s_own_arithmetic` holds a generated number to a second reading.
    """

    # A rounding pixel either side of the exact float floor/ceiling.
    SLACK = 1.0

    def test_every_interior_pixel_clears_the_ramp_floor(self):
        for uid in ATLAS_ORDER:
            if uid not in KOS:
                continue
            for fac in FACTIONS:
                floor = ramp_floor(RAMPS[fac.key])
                with self.subTest(unit=uid, faction=fac.key):
                    for c in _paint(pose_cell(uid, fac, Pose.KO, shadow=False)):
                        self.assertGreaterEqual(luminance(c), floor - self.SLACK)

    def test_no_interior_pixel_reaches_past_the_lit_plane(self):
        """The rim — the flash a unit's own S5 owns while it is parked — is
        gone: nothing on a wreck may read louder than an ordinary lit face."""
        for uid in ATLAS_ORDER:
            if uid not in KOS:
                continue
            for fac in FACTIONS:
                ceiling = luminance(RAMPS[fac.key][S_TOP])
                with self.subTest(unit=uid, faction=fac.key):
                    for c in _paint(pose_cell(uid, fac, Pose.KO, shadow=False)):
                        self.assertLessEqual(luminance(c), ceiling + self.SLACK)

    def test_the_burn_down_narrows_the_value_range(self):
        """Floored above and ceilinged under, a wreck's own tone band is
        strictly narrower than the unit it was — flatter, the way a burnt
        surface reads against a shaded one, never darker by construction
        alone (the floor a dark faction's own S0 already sits close to
        forbids that reading, and is the locked bar this sheet is authored
        against instead)."""
        for uid in ATLAS_ORDER:
            if uid not in KOS:
                continue
            for fac in FACTIONS:
                with self.subTest(unit=uid, faction=fac.key):
                    live = [
                        luminance(c)
                        for c in _paint(pose_cell(uid, fac, Pose.A, shadow=False))
                    ]
                    dead = [
                        luminance(c)
                        for c in _paint(pose_cell(uid, fac, Pose.KO, shadow=False))
                    ]
                    self.assertLess(max(dead) - min(dead), max(live) - min(live))


if __name__ == "__main__":
    unittest.main()
