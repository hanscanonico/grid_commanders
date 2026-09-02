"""Contract tests for the fire clip: units_atlas_figures_fire.png / _b.png.

The fire sheets are AUTHORED art — a barrel at full recoil, a rack at launch
elevation, bay doors open — never a second subtraction of the ambient pair's
cast shadow, the same departure `test_ko_pose.py` states for the KO sheet:
`FigureSheet`'s subtract-only rule is the idle pair's alone and does not bind
either authored sheet. Unlike KO, these units are LIVE — dead-by-value rules
(`voxel.wreck_tone`, the interior value floor) do not apply here; a fired gun
is not a casualty and the fire cells keep every faction's ordinary ramp.

Two sheets rather than KO's one, because the two SUSTAINED weapon families
(`units.pose.FIRE_PAIRS` — small_arms, pintle and autocannon) need a second
key for the stream to read as a blaze. Everything else armed draws the same
model into both — the chosen idiom for "one frame in a two-sheet clip" is
per-frame: `build_model`'s existing fallback (`_FALLBACK`) only ever
redirects a WHOLE clip for a uid outside it (`units.FIRES`, the unarmed
carve-out `apc`/`t_copter`/`lander` share with KO's air carve-out); a unit
inside `FIRES` but outside `FIRE_PAIRS` instead has no `Pose.FIRE_B`-specific
branch in its own builder, so `Pose.FIRE_A` and `Pose.FIRE_B` render
byte-identical voxels by construction — never a manifest or schema change.
"""

from __future__ import annotations

import unittest

from spritegen import anim, atlas, pipeline
from spritegen.palette import FACTIONS
from spritegen.units import (
    ATLAS_ORDER,
    CLIP_POSES,
    FIRE_PAIRS,
    FIRES,
    UNITS,
    Pose,
    build_model,
)

from pixel_helpers import pose_cell, units_sheet


def _shipped_fire_sheets():
    """The two fire sheets a full run writes, built through the rows that
    declare them — the same reading `test_ko_pose`'s `_shipped_ko_sheet`
    takes of its own one."""
    a = next(o for o in pipeline.SHEETS if o.rel == anim.FIRE_SHEETS[0])
    b = next(o for o in pipeline.SHEETS if o.rel == anim.FIRE_SHEETS[1])
    return a.build(), b.build()


def _opaque(img):
    px = img.convert("RGBA").load()
    return [
        px[x, y][:3]
        for y in range(img.height)
        for x in range(img.width)
        if px[x, y][3] == 255
    ]


class FireSheets(unittest.TestCase):
    """The grid: same size as every other units sheet, two frames, shadowless."""

    def test_they_are_the_same_grid_as_the_other_units_sheets(self):
        for sheet in _shipped_fire_sheets():
            self.assertEqual(
                sheet.size, (len(ATLAS_ORDER) * atlas.CELL_W, 6 * atlas.CELL_H)
            )
            self.assertEqual(sheet.mode, "RGBA")

    def test_the_shipped_sheets_leave_the_tile_shadow_off(self):
        """Asked of the row `pipeline.SHEETS` actually writes, not of a
        composition this test picked — see `test_ko_pose.KoSheet`'s sibling
        for why: flip either row to `shadow=True` and this fails."""
        for shipped, shadowed_pose in zip(
            _shipped_fire_sheets(), (Pose.FIRE_A, Pose.FIRE_B)
        ):
            shipped_px = shipped.convert("RGBA").load()
            shadowed_px = units_sheet(shadowed_pose).convert("RGBA").load()
            removed = 0
            for y in range(shipped.height):
                for x in range(shipped.width):
                    if shipped_px[x, y] == shadowed_px[x, y]:
                        continue
                    self.assertEqual(
                        shipped_px[x, y][3], 0, f"repainted pixel at {x},{y}"
                    )
                    self.assertEqual(
                        shadowed_px[x, y][3], 255, f"half-shadow at {x},{y}"
                    )
                    removed += 1
            self.assertGreater(removed, 0)

    def test_they_are_reproducible(self):
        for pose in (Pose.FIRE_A, Pose.FIRE_B):
            self.assertEqual(
                atlas.build_units_atlas(pose, shadow=False).tobytes(),
                atlas.build_units_atlas(pose, shadow=False).tobytes(),
            )


class UnarmedFallback(unittest.TestCase):
    """Unarmed carries no fire frame: `apc`, `t_copter` and `lander` draw
    their own idle key instead, the manifest's existing fallback contract —
    same idiom as KO's air carve-out, a different domain gate."""

    UNARMED = frozenset({"apc", "t_copter", "lander"})

    def test_every_unarmed_unit_is_outside_fires(self):
        for uid in self.UNARMED:
            self.assertNotIn(uid, FIRES)

    def test_every_unarmed_column_falls_back_to_the_idle_pair(self):
        for uid in self.UNARMED:
            for fac in FACTIONS:
                with self.subTest(unit=uid, faction=fac.key):
                    self.assertEqual(
                        pose_cell(uid, fac, Pose.FIRE_A, shadow=False).tobytes(),
                        pose_cell(uid, fac, Pose.A, shadow=False).tobytes(),
                    )
                    self.assertEqual(
                        pose_cell(uid, fac, Pose.FIRE_B, shadow=False).tobytes(),
                        pose_cell(uid, fac, Pose.B, shadow=False).tobytes(),
                    )

    def test_every_armed_unit_is_in_fires(self):
        for uid, (_, kind) in UNITS.items():
            if uid in self.UNARMED:
                continue
            with self.subTest(unit=uid):
                self.assertIn(uid, FIRES)


class AuthoredMembership(unittest.TestCase):
    """`FIRES` is the claim that a unit has a fire pose; the builder is where
    the claim is kept, and they are independent the same way `test_ko_pose`'s
    `AirFallback.test_a_membership_without_a_wreck_is_not_a_ko_frame` reads
    KOS against the models rather than against the burn, which never reaches
    a live cell here in the first place."""

    def test_every_fires_member_authors_a_fire_a_pose(self):
        for uid in sorted(FIRES):
            with self.subTest(unit=uid):
                self.assertNotEqual(
                    build_model(uid, Pose.FIRE_A).vox, build_model(uid, Pose.A).vox
                )


class PairVsSingle(unittest.TestCase):
    """`FIRE_PAIRS` is the whole of the schema's answer to "does this unit's
    second key differ": a sustained weapon's stream needs to alternate, a
    single shot's does not — and both are asked of the model, never of a
    pixel count, so a livery that happens to render two keys the same by
    coincidence cannot pass for the wrong reason."""

    def test_every_pair_member_differs_between_fire_a_and_fire_b(self):
        for uid in sorted(FIRE_PAIRS):
            with self.subTest(unit=uid):
                self.assertIn(uid, FIRES, f"{uid} is in FIRE_PAIRS but not FIRES")
                self.assertNotEqual(
                    build_model(uid, Pose.FIRE_A).vox, build_model(uid, Pose.FIRE_B).vox
                )

    def test_every_single_key_member_draws_the_same_model_into_both(self):
        for uid in sorted(FIRES - FIRE_PAIRS):
            with self.subTest(unit=uid):
                self.assertEqual(
                    build_model(uid, Pose.FIRE_A).vox, build_model(uid, Pose.FIRE_B).vox
                )


class Bob(unittest.TestCase):
    """The air/sea bob ticks with the FRAME, not with the clip.

    Asked of EVERY two-frame clip rather than of the fire pair alone, since
    what breaks is silent: the cut-in swaps the fire pair in and out
    mid-window on the same 500 ms director's clock the idle pair runs on
    (`CutsceneSide._figure_now`), so a clip whose second frame sat at the
    first's altitude would step the figure `BOB_PX` the moment the window
    opened or closed — a pop no still frame of a posed capture can show.
    A land unit's origin is pose-invariant instead: its own beat is authored
    in the model (`parts._roll`), never in the placement.
    """

    def test_every_two_frame_clip_lifts_its_off_beat_for_air_and_sea(self):
        for uid, (_, kind) in UNITS.items():
            lift = atlas.BOB_PX if kind in ("air", "sea") else 0
            for clip, poses in CLIP_POSES.items():
                if len(poses) < 2:
                    continue
                with self.subTest(unit=uid, clip=clip):
                    rest, off_beat = (atlas.cell_placement(uid, p) for p in poses)
                    self.assertEqual(rest.origin[0], off_beat.origin[0])
                    self.assertEqual(rest.origin[1] - off_beat.origin[1], lift)


class Silhouette(unittest.TestCase):
    """Per-column silhouette floor, measured off the shipped models the way
    `test_ko_pose.Silhouette` measures the wreck's: a fire pose may lose or
    gain mass (a retracted barrel, a raised rack) but never enough to read as
    a blob or a speck."""

    MIN_RATIO = 0.6
    MIN_PIXELS = 400

    def test_every_fire_cell_clears_its_own_silhouette_floor(self):
        for uid in ATLAS_ORDER:
            if uid not in FIRES:
                continue
            for fac in FACTIONS:
                for pose in (Pose.FIRE_A, Pose.FIRE_B):
                    with self.subTest(unit=uid, faction=fac.key, pose=pose.name):
                        live = len(_opaque(pose_cell(uid, fac, Pose.A, shadow=False)))
                        fired = len(_opaque(pose_cell(uid, fac, pose, shadow=False)))
                        self.assertGreaterEqual(fired, self.MIN_PIXELS)
                        self.assertGreaterEqual(fired, live * self.MIN_RATIO)


if __name__ == "__main__":
    unittest.main()
