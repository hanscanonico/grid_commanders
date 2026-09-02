"""Contract tests for the fire clip: units_atlas_figures_fire.png / _b.png.

The fire sheets are AUTHORED art — a barrel at full recoil, a rack at launch
elevation, bay doors open — never a second subtraction of the ambient pair's
cast shadow, the same departure `test_ko_pose.py` states for the KO sheet:
`FigureSheet`'s subtract-only rule is the idle pair's alone and does not bind
either authored sheet. Unlike KO, these units are LIVE — dead-by-value rules
(`voxel.wreck_tone`, the interior value floor) do not apply here; a fired gun
is not a casualty and the fire cells keep every faction's ordinary ramp.

Two sheets rather than KO's one, because the three SUSTAINED weapon families
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
from collections import deque

from spritegen import aa, anim, atlas, pipeline
from spritegen.palette import FACTIONS
from spritegen.voxel import render_indexed
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


class OnePiece(unittest.TestCase):
    """A unit's own art is ONE piece, and a fire pose may not break it.

    A key pose moves a sub-assembly, and an assembly carried past the face it
    shared with the machine leaves the machine — a nose tip, a round on its
    rail — floating clear at 1:1 in the cut-in. The silhouette floor counts
    pixels and the contour ratchet a ratio, so both pass a sprite that has
    come apart; `parts._rotor`'s own thickening records the same defect from
    the other side.

    Asked of the SPRITE the renderer draws rather than of the composed cell,
    because a cell also carries water: a hull's waterline foam is a deliberate
    dither and the sub's wake sits on the water plane the bobbed hull rises
    off, so both are their own components in every clip and neither is the
    machine. Asked without the MUZZLE FLAME too — a detached spark is a
    reading a fire pose is allowed to have; a detached radome is not. All
    eighteen units answer 1 in all four poses, so the bar is the whole roster's
    and not this clip's alone.

    The two poses NOT in that tuple are a choice, not an oversight. MOVE_A and
    MOVE_B pass today and are one edit from joining it — until they do, a gait
    that shook a part loose would still slip through. KO cannot join without a
    decision first: `battleship` and `cruiser` wrecks render 872 + 14 and
    766 + 14 pixels in every livery, a detached 14-px piece this clip neither
    introduced nor touched, so adding the pose means either authoring those two
    wrecks whole or writing the carve-out down.
    """

    @staticmethod
    def _components(img) -> list[int]:
        px = img.convert("RGBA").load()
        w, h = img.size
        lit = {(x, y) for y in range(h) for x in range(w) if px[x, y][3] == 255}
        seen: set[tuple[int, int]] = set()
        sizes = []
        for start in lit:
            if start in seen:
                continue
            queue, size = deque([start]), 0
            seen.add(start)
            while queue:
                x, y = queue.popleft()
                size += 1
                for step in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    near = (x + step[0], y + step[1])
                    if near in lit and near not in seen:
                        seen.add(near)
                        queue.append(near)
            sizes.append(size)
        return sorted(sizes, reverse=True)

    @staticmethod
    def _unlit_sprite(uid, fac, pose):
        model = build_model(uid, pose)
        for cell in [c for c, material in model.vox.items() if material == "flame"]:
            del model.vox[cell]
        return aa.soften_sprite(render_indexed(model, fac).image, model, fac)

    def test_every_pose_of_every_unit_draws_one_connected_sprite(self):
        for uid in ATLAS_ORDER:
            for fac in FACTIONS:
                for pose in (Pose.A, Pose.B, Pose.FIRE_A, Pose.FIRE_B):
                    with self.subTest(unit=uid, faction=fac.key, pose=pose.name):
                        sizes = self._components(self._unlit_sprite(uid, fac, pose))
                        self.assertEqual(len(sizes), 1, f"detached: {sizes}")


class ReconSweep(unittest.TestCase):
    """recon is the one pair whose second key sweeps a weapon that is
    standing INSIDE the body.

    Depressed on target its pintle sits in the cabin band, so a traverse
    taken there carries the roof, the team stripe and the windshield with it
    and leaves a texel-deep trench along the roofline. Neither the silhouette
    floor above nor the contour ratchet can see that: the outline is
    identical and the hole is interior. So the two questions are asked of the
    models here — the sweep may empty a cell only where the GUN was, and the
    cabin's own roof stands in both frames.
    """

    GUN = frozenset({"gunmetal", "gunmetal_dk", "bore", "flame"})
    CABIN_X = range(2, 8)
    CABIN_Y = range(3, 10)
    ROOF_Z = 4

    def test_the_sweep_empties_no_cell_the_machine_was_standing_in(self):
        a = build_model("recon", Pose.FIRE_A).vox
        b = build_model("recon", Pose.FIRE_B).vox
        for cell, material in sorted(a.items()):
            if cell in b:
                continue
            with self.subTest(cell=cell):
                self.assertIn(material, self.GUN)

    def test_the_cabin_roof_stands_in_both_fire_frames(self):
        for pose in (Pose.FIRE_A, Pose.FIRE_B):
            vox = build_model("recon", pose).vox
            for x in self.CABIN_X:
                for y in self.CABIN_Y:
                    column = [z for (vx, vy, z) in vox if (vx, vy) == (x, y)]
                    with self.subTest(pose=pose.name, column=(x, y)):
                        self.assertGreaterEqual(max(column), self.ROOF_Z)


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


class ReadDelta(unittest.TestCase):
    """An authored fire frame has to be VISIBLE, which is a different question
    from being authored.

    `AuthoredMembership` asks only that the voxels differ and `Silhouette` is a
    floor rather than a delta, so a frame built where this projection cannot
    show it passes both. That is measured history, not a worry: the bomber's
    first bay was 40 voxels hung under the wing root, and the wing occludes the
    fuselage's whole lower-right flank at every depth — it moved 17 pixels of a
    thousand, changed no silhouette texel, and shipped green through the suite,
    the snapshot gate and `make verify`.

    So the bar is CHANGED PIXELS against pose A's own cell, taken as the worst
    livery, and it is deliberately not a silhouette-delta bar: `cruiser`'s
    barrels recoil inside the hull's own outline and its read is the lit
    muzzle, so a silhouette rule would fail correct art. Measured 2026-09-02,
    the roster's floors are bomber 49, fighter 67, cruiser 89, recon 115,
    anti_air 162, battleship 209, infantry 309, b_copter 344, sub 369, then
    523 and up to md_tank's 1557. `MIN_CHANGED` sits under the smallest of
    those and far over the occluded bay's 17, so a frame nobody can see fails
    by name rather than by a hand measurement in review.
    """

    MIN_CHANGED = 40

    def test_every_authored_fire_frame_changes_enough_to_be_seen(self):
        for uid in ATLAS_ORDER:
            if uid not in FIRES:
                continue
            for fac in FACTIONS:
                rest = pose_cell(uid, fac, Pose.A, shadow=False).convert("RGBA")
                fired = pose_cell(uid, fac, Pose.FIRE_A, shadow=False).convert("RGBA")
                rest_px, fired_px = rest.load(), fired.load()
                changed = sum(
                    1
                    for y in range(rest.height)
                    for x in range(rest.width)
                    if rest_px[x, y] != fired_px[x, y]
                )
                with self.subTest(unit=uid, faction=fac.key):
                    self.assertGreaterEqual(changed, self.MIN_CHANGED)


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
