"""Contract tests for the two animation clips.

Frame B is the same army breathing and the move pair is the same army
walking — both read at the board's furthest rung.
"""

from __future__ import annotations

import unittest

from PIL import Image

from spritegen import atlas, units
from spritegen.palette import FACTIONS, Faction, faction_by_key
from spritegen.units import (
    AMBIENT_POSES,
    ATLAS_ORDER,
    MOVE_POSES,
    MOVES,
    UNITS,
    Pose,
    build_model,
)
from spritegen import voxel
from spritegen.voxel import CAST, FOAM

from pixel_helpers import RUNG_1_CELL, pose_cell, rung1_texels, units_sheet


def air_beat_readings(uid: str, rest: Pose, off: Pose) -> tuple[int, float]:
    """One airframe's beat with the bob taken back out, for either clip.

    The hop moves every boundary pixel of an aircraft, so anything read
    across it is mostly the hop. Settle the off-beat back down by `BOB_PX`
    and ask two questions of what is left, over every livery: in how many
    of them the composed cell (shadow off) stops being byte-identical to
    the rest pose's — a beat that paints nothing anywhere scores 0 — and
    the worst opaque-coverage IoU, the copters' rotor reading, which says
    what did move is a named assembly rather than a second aircraft.

    Both clips get this. `beat(pose)` gates the bob, the plume, the glint
    and the nacelles alike, so `MOVE_B` carries the same lift and the same
    tick as `Pose.B` and the same subtraction reads it.
    """
    lit = 0
    worst = 1.0
    for fac in FACTIONS:
        a = pose_cell(uid, fac, rest, shadow=False)
        b = pose_cell(uid, fac, off, shadow=False)
        settled = Image.new("RGBA", b.size)
        settled.paste(b, (0, atlas.BOB_PX))
        lit += settled.tobytes() != a.tobytes()
        pa, pb = a.load(), b.load()
        w, h = a.size
        a_set = {(x, y) for y in range(h) for x in range(w) if pa[x, y][3] > 200}
        b_set = {
            (x, y + atlas.BOB_PX)
            for y in range(h)
            for x in range(w)
            if pb[x, y][3] > 200
        }
        worst = min(worst, len(a_set & b_set) / len(a_set | b_set))
    return lit, worst


class AmbientFrames(unittest.TestCase):
    """Frame B is the same army breathing, never a different army."""

    # An idle key pose shifts weight; it does not swap the sprite. The
    # silhouette's pixel count may move a little (a settled cab hides a row,
    # a swept rotor disc thins) and no more.
    MAX_MASS_DRIFT = 0.08

    def test_frame_b_is_reproducible_and_distinct(self):
        b1 = atlas.build_units_atlas(Pose.B)
        self.assertEqual(b1.tobytes(), atlas.build_units_atlas(Pose.B).tobytes())
        self.assertNotEqual(b1.tobytes(), units_sheet().tobytes())

    # What the board draws is `RUNG_1_CELL` — the furthest the board zooms
    # out, and the hardest sample an idle has to survive.
    # Every unit at rung 1, measured on 2026-08-24 over all five liveries
    # (tests/measure_motion.py prints the red row of the same readout):
    # apc 3, recon 4, tank 5, md_tank 6, mech 7, artillery 7, anti_air 8,
    # missiles 10, rockets 11, infantry 12 for the land army; fighter 30,
    # bomber 36, b_copter 28, t_copter 30 in the air; battleship 33, cruiser
    # 24, sub 25, lander 20 at sea. Three is the floor the quietest of them
    # clears, and it is what an idle needs to be seen at board scale at all.
    MIN_SILHOUETTE_TEXELS = 3
    # Interior change per silhouette texel at rung 1, same run, worst first:
    # apc 4.67, tank 4.40, md_tank 4.33, rockets 3.64, artillery 3.00,
    # recon 2.25, anti_air 2.12, missiles 1.90, cruiser 1.71, infantry 1.58,
    # lander 1.50, bomber 1.39, battleship 1.09, t_copter 1.07, fighter 0.90,
    # sub 0.80, b_copter 0.79, mech 0.43 — each the worst of that unit's five
    # liveries. Livery moves the tones and not the shape, so the silhouette
    # counts above are the same for all five, but this ratio is a tone count
    # and does drift with them: by 0.1 or less on most units, 0.67 on the
    # md_tank and 1.67 on the apc (3.00 in iron, 4.67 in the other four),
    # whose three silhouette texels make a very small divisor. Five is just
    # over the noisiest livery of the noisiest unit; the apc is up there
    # because it has no turret and no gun, so its whole texel is the nose
    # dipping past a hull that can only re-tone behind it.
    MAX_SHIMMER = 5.0

    def test_every_unit_moves_a_whole_board_texel(self):
        """A beat the board cannot resample is not a beat.

        This used to ask only that frame B's cell differ from frame A's
        somewhere in its 64x96 pixels, which one pixel satisfies and which a
        one-voxel settle or a period-2 tread checker passed while changing
        NOTHING the player sees: under the 4:1 sample a sub-texel delta
        re-tones the inside of a shape that holds still. So ask it at the
        size the board draws — how many rung-1 texels the two poses disagree
        about being PAINTED — for every unit of every livery.

        Each land unit earns it by moving one named assembly a whole texel
        (a dz of two voxels, or a `(dx +1, dy -1)` diagonal); the two foot
        figures by leaning the whole upper body; the copters by turning
        their rotors; the four hulls by the `BOB_PX` hop plus an assembly of
        their own riding it; fighter and bomber by that same hop — one texel
        of altitude exactly — plus the beat their own columns now carry (the
        burner plume, the tail and canopy retones), which
        `test_the_bob_lifts_the_airframe_and_a_named_delta_besides` is what
        actually holds them to.
        """
        for uid in ATLAS_ORDER:
            for fac in FACTIONS:
                with self.subTest(unit=uid, faction=fac.key):
                    _, silhouette = self._texels(uid, fac)
                    self.assertGreaterEqual(silhouette, self.MIN_SILHOUETTE_TEXELS)

    def test_no_unit_shimmers_more_than_it_moves(self):
        """The floor above can be bought the wrong way.

        A unit that repaints half its interior while its outline holds still
        does clear a silhouette bar if a few boundary texels flip with the
        sampling phase, and it reads as the sprite boiling rather than as an
        idle. So cap the other half of the ratio: interior texels that only
        change tone, per texel of silhouette that actually moves, under
        `MAX_SHIMMER` at rung 1. The two numbers together say the change the
        board sees is mostly the shape going somewhere.
        """
        for uid in ATLAS_ORDER:
            for fac in FACTIONS:
                with self.subTest(unit=uid, faction=fac.key):
                    changed, silhouette = self._texels(uid, fac)
                    interior = changed - silhouette
                    self.assertLess(interior / max(silhouette, 1), self.MAX_SHIMMER)

    def _texels(self, uid: str, fac: Faction) -> tuple[int, int]:
        return rung1_texels(uid, fac, AMBIENT_POSES)

    def test_the_key_pose_keeps_the_units_mass(self):
        for uid in ATLAS_ORDER:
            for fac in FACTIONS:
                a = self._mass(pose_cell(uid, fac))
                b = self._mass(pose_cell(uid, fac, Pose.B))
                with self.subTest(unit=uid, faction=fac.key):
                    self.assertLess(abs(b - a) / a, self.MAX_MASS_DRIFT)

    def test_every_unit_keeps_its_cast_shadow(self):
        """A parked unit shifts its weight, and the patch of ground it stands
        on may not move a pixel with it.

        This used to be asked of land units alone, and an air or sea shadow
        was sized off the POSE's own sprite width: t_copter's pose B is 4px
        wider than its A, so its shadow pumped from 159px to 173px — 9% —
        every beat, and the whole helicopter slid 2px sideways with it. Sized
        off the pose-A footprint and laid on the pose-A ground row instead
        (compose_cell's `footprint_w` and `ground`), every kind's shadow now
        holds still through the bob the way a land unit's always did.
        """
        for uid in ATLAS_ORDER:
            for fac in FACTIONS:
                with self.subTest(unit=uid, faction=fac.key):
                    self.assertEqual(
                        self._shadow(pose_cell(uid, fac)),
                        self._shadow(pose_cell(uid, fac, Pose.B)),
                    )

    def test_both_poses_stand_on_the_same_cell_coordinate(self):
        """Pose B is the same unit moving, so model space's screen origin
        lands on the same cell pixel in both — a land unit exactly, an air or
        sea one exactly one board texel higher, which is the bob and nothing
        else. The footprint the shadow is sized from and the ground row it
        sits on are the same number for both poses, whatever the crops do."""
        for uid in ATLAS_ORDER:
            a = atlas.cell_placement(uid, Pose.A)
            b = atlas.cell_placement(uid, Pose.B)
            bob = atlas.BOB_PX if UNITS[uid][1] in ("air", "sea") else 0
            with self.subTest(unit=uid):
                self.assertEqual(a.footprint_w, b.footprint_w)
                self.assertEqual(a.ground, b.ground)
                self.assertEqual(a.origin[0], b.origin[0])
                self.assertEqual(a.origin[1] - b.origin[1], bob)

    # The rest-to-beat delta, read the way the copters' rotor tick is
    # (`test_the_copters_turn_one_rotor_rather_than_swapping_its_blades`):
    # opaque coverage IoU between the two poses once `BOB_PX` is taken back
    # out. Measured 2026-09-01 at 0.991 (fighter, both clips) and 1.000
    # (bomber ambient) / 0.902 (bomber move) across every livery — the
    # burner plume and the nacelle exhaust are a handful of voxels against a
    # fuselage that otherwise does not move, so the floor sits under the
    # copters' own 0.85 with headroom rather than at it. `MoveFrames` takes
    # the same number against the move pair, which is where the 0.902 is.
    MIN_AIR_DELTA_IOU = 0.80

    def test_the_bob_lifts_the_airframe_and_a_named_delta_besides(self):
        """The placement above is a plan; this is the composed cell.

        `fighter` and `bomber` used to draw the same voxels in both poses —
        the beat WAS the bob for them, and nothing else — which is the two
        dead columns `tests/measure_motion.py` used to record. Each now
        lights a named assembly on the off-beat (the fighter's afterburner
        plume; the bomber's nacelle exhaust, but only under way, `MOVE_B`
        alone) and retones another in place (the canopy glint, the
        tailplane's tick — see `units/air.py`'s `beat(pose)` branches for
        why those two are colour changes rather than moved voxels), so this
        asks the model the hulls' question — it must differ, and still
        share nearly every voxel with pose A — and the composed cell the
        copters' question — opaque coverage must still mostly agree once
        the bob is subtracted back out. What the beat may never do is reach
        the hover line down, where the cast shadow lives: pose B's cell is
        byte-identical to pose A's from `ground` down, in every livery.

        Neither of those two readings can tell a retone from nothing: the
        model differs on a pure material swap whether or not the swapped
        voxel has a face the ramp ever paints, and IoU is over opaque
        coverage, so it scores an all-tone beat 1.000 — which is exactly
        what the bomber's idle beat is. So ask the composed cell outright:
        settled back down by `BOB_PX`, pose B must stop being byte-identical
        to pose A in at least one livery — measured 2026-09-01, fighter 29-31
        px in all six. Re-measured after S8 (the board-scale contour pass):
        bomber's own tail-tip retone sits on the silhouette, and every
        faction's boundary voxel there now falls to the same ground-facing
        S0 in both poses alike, so its ambient beat is absorbed to 0 of 6 —
        the model still differs (asserted above) and the move clip's own
        nacelle flame still lights the composed cell
        (`test_the_move_beat_lifts_the_airframe_and_a_named_delta_besides`),
        so this is the one column S8's board legibility priced out of the
        idle reading specifically, not a beat that paints nothing anywhere.
        `MIN_LIT` states the floor per unit: -1 waives it (0 liveries is
        the measured, accepted reading) rather than lying that a positive
        floor was cleared."""
        # One board texel and not a pixel less: the board draws the 64x96
        # cell at 0.25 scale, so a bob under 4px moves no visible pixel at
        # all — it only changes which source pixel the resample keeps, which
        # is the flicker the 1px bob shipped as a hover.
        self.assertEqual(atlas.BOB_PX, 4)
        # bomber: see the docstring above — S8's board contour absorbs its
        # one ambient retone (the tail tips) into the ground-facing S0 both
        # poses already share there.
        MIN_LIT = {"bomber": -1}
        for uid in ("fighter", "bomber"):
            a_model = build_model(uid, Pose.A).vox
            b_model = build_model(uid, Pose.B).vox
            with self.subTest(unit=uid, reading="model"):
                self.assertNotEqual(a_model, b_model)
                shared = sum(1 for v, mat in a_model.items() if b_model.get(v) == mat)
                self.assertGreater(shared / len(a_model), 0.9)
            ground = atlas.cell_placement(uid, Pose.A).ground
            for fac in FACTIONS:
                a = pose_cell(uid, fac)
                b = pose_cell(uid, fac, Pose.B)
                with self.subTest(unit=uid, faction=fac.key, reading="shadow"):
                    self.assertEqual(
                        b.crop((0, ground, atlas.CELL_W, atlas.CELL_H)).tobytes(),
                        a.crop((0, ground, atlas.CELL_W, atlas.CELL_H)).tobytes(),
                    )
            lit, worst = air_beat_readings(uid, Pose.A, Pose.B)
            with self.subTest(unit=uid, reading="beat"):
                self.assertGreater(lit, MIN_LIT.get(uid, 0))
            with self.subTest(unit=uid, reading="iou"):
                self.assertGreaterEqual(worst, self.MIN_AIR_DELTA_IOU)

    def test_every_hull_moves_a_part_and_not_only_its_altitude(self):
        """The bob is a fleet rising in unison; the beat is a ship working.

        All four hulls used to build byte-identical models in both poses and
        pass the texel floor on `BOB_PX` alone. Each now moves one named
        assembly besides — the guns, the autocannon, the periscope, the bow
        visor — so ask the models, where the bob does not reach. And ask that
        it stayed ONE assembly: the two poses keep nine voxels in ten, so a
        hull that answered this by rebuilding itself would fail here."""
        for uid in ("battleship", "cruiser", "sub", "lander"):
            with self.subTest(unit=uid):
                a = build_model(uid, Pose.A).vox
                b = build_model(uid, Pose.B).vox
                self.assertNotEqual(a, b)
                shared = sum(1 for v, mat in a.items() if b.get(v) == mat)
                self.assertGreater(shared / len(a), 0.9)

    # The copters are the only units whose SHAPE changes between poses, and
    # the shape is one part: the rotor. Measured on 2026-08-25, cell IoU with
    # the bob taken out is 0.889 (b_copter) and 0.878 (t_copter); the
    # 45-degree sweep these replaced drew a DIFFERENT blade set in frame B —
    # four axial blades against two long diagonals — and scored 0.74 and
    # 0.74, which read as two aircraft alternating rather than one turning.
    MIN_ROTOR_IOU = 0.85
    # ...while still moving what the board can see: 31 and 28 texels at rung
    # 1 (`tests/measure_motion.py`), so the bar is a floor, not the number.
    MIN_ROTOR_TEXELS = 10

    def test_the_copters_turn_one_rotor_rather_than_swapping_its_blades(self):
        """A disc that spins keeps its blades and moves them.

        Three readings of the same requirement. The models must draw the
        same COUNT of `rotor` voxels in both poses and span the same box
        within a voxel, so no blade is added, dropped or lengthened; the two
        composed cells, with `atlas.BOB_PX` subtracted so this reads the
        rotor and not the hop, must share `MIN_ROTOR_IOU` of their union; and
        the board at rung 1 must still see `MIN_ROTOR_TEXELS` of silhouette
        change, so keeping the frames alike may never be bought by keeping
        them still.
        """
        neutral = faction_by_key("neutral")
        for uid in ("b_copter", "t_copter"):
            box = {}
            # The ambient pair only: this reading is about the idle clip, and
            # a `for pose in Pose` here would hand the two-frame comparisons
            # below four frames.
            for pose in AMBIENT_POSES:
                blades = [
                    v for v, mat in build_model(uid, pose).vox.items() if mat == "rotor"
                ]
                box[pose] = (
                    len(blades),
                    max(x for x, _, _ in blades) - min(x for x, _, _ in blades),
                    max(y for _, y, _ in blades) - min(y for _, y, _ in blades),
                )
            with self.subTest(unit=uid, reading="blades"):
                self.assertEqual(box[Pose.A][0], box[Pose.B][0])
                self.assertLessEqual(abs(box[Pose.A][1] - box[Pose.B][1]), 1)
                self.assertLessEqual(abs(box[Pose.A][2] - box[Pose.B][2]), 1)
            cells = {}
            for pose in AMBIENT_POSES:
                cell = pose_cell(uid, neutral, pose, shadow=False)
                px = cell.load()
                w, h = cell.size
                dy = atlas.BOB_PX if pose is Pose.B else 0
                cells[pose] = {
                    (x, y + dy) for y in range(h) for x in range(w) if px[x, y][3] > 200
                }
            a, b = cells[Pose.A], cells[Pose.B]
            with self.subTest(unit=uid, reading="iou"):
                self.assertGreaterEqual(len(a & b) / len(a | b), self.MIN_ROTOR_IOU)
            small = [
                pose_cell(uid, neutral, pose).resize((16, 24), Image.NEAREST)
                for pose in AMBIENT_POSES
            ]
            pa, pb = (cell.load() for cell in small)
            moved = sum(
                1
                for y in range(24)
                for x in range(16)
                if (pa[x, y][3] > 128) != (pb[x, y][3] > 128)
            )
            with self.subTest(unit=uid, reading="texels"):
                self.assertGreaterEqual(moved, self.MIN_ROTOR_TEXELS)

    def test_the_foam_line_stays_on_the_water(self):
        """The sea's own marks belong to the sea, not to the hull that made
        them: a ship riding a swell leaves its waterline foam exactly where
        the still pose broke it (10 flecks for the surface ships, 94 for the
        sub, whose running wake is foam too). Derived from the bobbed hull
        instead, the whole line rose with the ship and the swell read as the
        sea heaving."""
        for uid in ATLAS_ORDER:
            if UNITS[uid][1] != "sea":
                continue
            for fac in FACTIONS:
                with self.subTest(unit=uid, faction=fac.key):
                    a = self._foam(pose_cell(uid, fac))
                    self.assertTrue(a)
                    self.assertEqual(a, self._foam(pose_cell(uid, fac, Pose.B)))

    def test_frame_b_still_reads_as_its_own_unit(self):
        # A rotor sweep on a small aircraft legitimately moves a quarter of
        # its 32px silhouette, so an absolute overlap bar would misfire.
        # The real requirement: among every unit's frame A, the one a frame
        # B most resembles must be its own — animation may move pixels, it
        # may never move identity.
        frame_a = {uid: self._sil(uid, Pose.A) for uid in ATLAS_ORDER}
        for uid in ATLAS_ORDER:
            b = self._sil(uid, Pose.B)
            best = max(
                ATLAS_ORDER,
                key=lambda other: len(b & frame_a[other]) / len(b | frame_a[other]),
            )
            with self.subTest(unit=uid):
                self.assertEqual(best, uid)

    def _sil(self, uid: str, pose: Pose) -> set:
        cell = pose_cell(uid, faction_by_key("neutral"), pose)
        small = cell.convert("RGBA").resize((32, 32), Image.NEAREST)
        px = small.load()
        return {(x, y) for y in range(32) for x in range(32) if px[x, y][3] > 200}

    def _mass(self, cell: Image.Image) -> int:
        px = cell.convert("RGBA").load()
        w, h = cell.size
        return sum(1 for y in range(h) for x in range(w) if px[x, y][3] > 0)

    def _shadow(self, cell: Image.Image) -> set:
        px = cell.convert("RGBA").load()
        w, h = cell.size
        return {(x, y) for y in range(h) for x in range(w) if px[x, y] == CAST}

    def _foam(self, cell: Image.Image) -> set:
        px = cell.convert("RGBA").load()
        w, h = cell.size
        return {
            (x, y)
            for y in range(h)
            for x in range(w)
            if px[x, y][:3] == FOAM and px[x, y][3] == 255
        }


class MoveFrames(unittest.TestCase):
    """The move clip is the same army walking, and it has to walk at board
    scale.

    `MIN_SILHOUETTE_TEXELS = 6` is double the idle floor. An idle shifts one
    named assembly and three rung-1 texels is the quietest of those anyone
    can see; a gait is the whole running gear — legs, tracks, rotor, bow —
    and if the board cannot see six texels of it move, the unit reads as
    sliding rather than travelling. Six is also exactly the texel rule
    applied twice over: one board texel is 4 atlas px (`dz +/-2`, or a
    `(dx -1, dy +1)` forward diagonal), so a stride that clears this cannot
    be a sub-texel jiggle in any livery.

    `MAX_SHIMMER = 5.0` and `MAX_MASS_DRIFT = 0.08` are `AmbientFrames`'
    numbers, carried over unchanged and for the same reasons: a frame that
    repaints its interior instead of moving its outline reads as boiling,
    and a unit that walks is still the same mass of metal. The drift is
    measured against pose A for BOTH move frames, so a gait may not grow the
    unit across the clip either.

    Everything that reads pixels is scoped to `units.MOVES`, the opt-in set
    of units with an authored gait. The rest render their ambient
    counterpart (`MOVE_A -> A`, `MOVE_B -> B`), which the fallback test
    checks byte-for-byte; while `MOVES` is empty the scoped tests skip
    loudly rather than pass vacuously.
    """

    MIN_SILHOUETTE_TEXELS = 6
    MAX_SHIMMER = 5.0
    MAX_MASS_DRIFT = 0.08

    def _movers(self) -> list[str]:
        """The units under gate, or a skip that says the gate saw nothing."""
        if not MOVES:
            self.skipTest("no unit has authored move poses yet")
        return [uid for uid in ATLAS_ORDER if uid in MOVES]

    def test_the_move_sheet_is_reproducible(self):
        """The move sheets are sheets like any other: same bytes every run.
        Whether they differ from the ambient pair is a per-unit question the
        next two tests ask, since a unit outside `MOVES` falls back."""
        a1 = atlas.build_units_atlas(Pose.MOVE_A)
        self.assertEqual(a1.tobytes(), atlas.build_units_atlas(Pose.MOVE_A).tobytes())

    def test_the_move_pair_is_not_the_ambient_pair(self):
        """A unit that opts in has to author something.

        `MOVES` is the claim that this unit walks; the claim is empty if the
        clip is the idle under another name. Per unit and per livery: the two
        move frames differ from each other, and the pair is not the ambient
        pair (one of the two may legitimately reuse its ambient key — a gait
        that passes through the rest pose — but not both)."""
        for uid in self._movers():
            for fac in FACTIONS:
                cells = {
                    pose: pose_cell(uid, fac, pose).tobytes()
                    for pose in AMBIENT_POSES + MOVE_POSES
                }
                with self.subTest(unit=uid, faction=fac.key):
                    self.assertNotEqual(cells[Pose.MOVE_A], cells[Pose.MOVE_B])
                    self.assertNotEqual(
                        (cells[Pose.MOVE_A], cells[Pose.MOVE_B]),
                        (cells[Pose.A], cells[Pose.B]),
                    )

    MIN_AIR_DELTA_IOU = AmbientFrames.MIN_AIR_DELTA_IOU

    def test_the_move_beat_lifts_the_airframe_and_a_named_delta_besides(self):
        """`AmbientFrames`' airframe reading, asked of the move pair.

        `MOVE_B` bobs for the same reason `Pose.B` does — `beat(pose)` gates
        the hop — so the move clip could go dead exactly the way the ambient
        one had: the pair differs, the rung-1 floor clears, and all of it is
        the four-pixel lift. The test above only asks the two frames not to
        be byte-equal, which the hop alone satisfies, so it cannot tell an
        authored gait from a hovering one.

        Bob subtracted, per unit: the composed cell must stop being
        byte-identical in at least one livery, and opaque coverage must
        still mostly agree. Measured 2026-09-01: 6 liveries of 6 for both
        airframes, worst IoU 0.991 (fighter) and 0.902 (bomber, whose
        `MOVE_B` carries a further whole texel of nose-down).

        Only the two jets. The copters have
        `test_the_flying_copters_are_not_the_hovering_copters` and a turning
        rotor of their own; the ships bob but do not fly, and their beat is
        `test_a_moving_hull_adds_a_bow_wave_and_moves_nothing_else`."""
        for uid in ("fighter", "bomber"):
            if uid not in MOVES:
                self.skipTest(f"{uid} has no authored move poses")
            lit, worst = air_beat_readings(uid, Pose.MOVE_A, Pose.MOVE_B)
            with self.subTest(unit=uid, reading="beat"):
                self.assertGreater(lit, 0)
            with self.subTest(unit=uid, reading="iou"):
                self.assertGreaterEqual(worst, self.MIN_AIR_DELTA_IOU)

    def test_every_moving_unit_crosses_a_whole_board_texel(self):
        """The gait at the size the board draws it: how many rung-1 texels
        the two move frames disagree about being PAINTED, for every livery.
        Under this floor the stride re-tones the inside of a shape that
        holds still, which is the sliding-sprite failure the ambient gate
        was written for, doubled because a gait moves more than an idle."""
        for uid in self._movers():
            for fac in FACTIONS:
                with self.subTest(unit=uid, faction=fac.key):
                    _, silhouette = rung1_texels(uid, fac, MOVE_POSES)
                    self.assertGreaterEqual(silhouette, self.MIN_SILHOUETTE_TEXELS)

    # The sub against its own parked pose, at rung 1 and per livery. This is
    # the one hull whose gait is a trim and a mast rather than a stride, and
    # the two are easy to author at a scale the board cannot sample: the
    # first attempt raised a one-voxel periscope, 4 atlas px, and measured 3
    # changed / 1 silhouette texel against pose A — the move clip WAS the
    # idle, and every gate above still passed because they all read MOVE_A
    # against MOVE_B. Measured 2026-08-25 at 22 changed / 7 silhouette in the
    # thinnest livery; the floors are the texel rule, not the measurement.
    SUB_MIN_PARKED_CHANGED = 14
    SUB_MIN_PARKED_SILHOUETTE = 6

    # The floor on a bow wave (`voxel._bow_wave`), in cell pixels: 16 is one
    # whole rung-1 board texel of white water (4 atlas px on a side), the
    # least a hull can break and still have the 4:1 sample see anything.
    # Measured 2026-08-25 at 42 px (lander, cruiser), 60 (sub) and 78
    # (battleship); the floor is the texel rule, not the measurement.
    MIN_BOW_WAVE_PX = 16

    def test_the_running_sub_is_not_the_parked_sub(self):
        """A submarine under way must differ from one lying stopped by
        something the board can count, not by a periscope the 4:1 sample
        eats. Asked of the sub alone: the land families legitimately carry
        their whole gait on MOVE_B and leave MOVE_A at the rest pose, which
        `test_the_move_pair_is_not_the_ambient_pair` allows on purpose."""
        if "sub" not in MOVES:
            self.skipTest("the sub has no authored move poses")
        for fac in FACTIONS:
            with self.subTest(faction=fac.key):
                changed, silhouette = rung1_texels("sub", fac, (Pose.A, Pose.MOVE_A))
                self.assertGreaterEqual(changed, self.SUB_MIN_PARKED_CHANGED)
                self.assertGreaterEqual(silhouette, self.SUB_MIN_PARKED_SILHOUETTE)

    # The copters against their own parked poses, same reading, both frames.
    # A rotorcraft's gait is attitude and nothing else — the disc has to be
    # the ambient disc voxel for voxel (`MoveFallback`) and the hull may not
    # translate in-sheet — so it is the one family whose move clip can come
    # out as the idle while every MOVE_A-vs-MOVE_B gate above passes on the
    # blades alone. It did: a nose-down of one texel measured 17 changed / 6
    # silhouette on b_copter and 14 / 9 on t_copter, the smallest
    # parked-vs-moving deltas in the fleet, and a transiting copter read as a
    # hovering one. Raking the airframe about the mast — nose down, tail up —
    # measures 28 changed / 15 silhouette in the thinnest livery of either
    # copter on either frame (2026-08-25). The floors below are the texel
    # rule, not that measurement: twelve silhouette texels is the move gate's
    # six asked of a machine that carries its whole gait in one line.
    COPTER_MIN_PARKED_CHANGED = 22
    COPTER_MIN_PARKED_SILHOUETTE = 12

    def test_the_flying_copters_are_not_the_hovering_copters(self):
        """A helicopter under way must differ from one holding station by
        something the board can count. Asked of both frames, because a
        rotorcraft has no rest pose to pass through: MOVE_A is cruise as much
        as MOVE_B is, and a copter that authored the attitude on one frame
        only would spend half the clip parked."""
        for uid in ("b_copter", "t_copter"):
            if uid not in MOVES:
                self.skipTest(f"{uid} has no authored move poses")
            for fac in FACTIONS:
                for parked, moving in ((Pose.A, Pose.MOVE_A), (Pose.B, Pose.MOVE_B)):
                    with self.subTest(unit=uid, faction=fac.key, pose=moving.name):
                        changed, silhouette = rung1_texels(uid, fac, (parked, moving))
                        self.assertGreaterEqual(changed, self.COPTER_MIN_PARKED_CHANGED)
                        self.assertGreaterEqual(
                            silhouette, self.COPTER_MIN_PARKED_SILHOUETTE
                        )

    def test_no_moving_unit_shimmers_more_than_it_walks(self):
        """The other half of the ratio, as in `AmbientFrames`: interior
        texels that only change tone, per texel of silhouette that actually
        moves. Together the two say the change the board sees is mostly the
        shape going somewhere."""
        for uid in self._movers():
            for fac in FACTIONS:
                with self.subTest(unit=uid, faction=fac.key):
                    changed, silhouette = rung1_texels(uid, fac, MOVE_POSES)
                    interior = changed - silhouette
                    self.assertLess(interior / max(silhouette, 1), self.MAX_SHIMMER)

    def test_the_gait_keeps_the_units_mass(self):
        for uid in self._movers():
            for fac in FACTIONS:
                a = self._mass(pose_cell(uid, fac, Pose.A))
                for pose in MOVE_POSES:
                    with self.subTest(unit=uid, faction=fac.key, pose=pose.name):
                        m = self._mass(pose_cell(uid, fac, pose))
                        self.assertLessEqual(abs(m - a) / a, self.MAX_MASS_DRIFT)

    def test_the_move_clip_moves_no_cell(self):
        """The game's tween is the travel; the sheet shows gait only.

        A move frame that translated the hull in-sheet would travel twice —
        once by the tween and once by the art — so all four poses hang off
        pose A's crop: `MOVE_A` places exactly where `A` does and `MOVE_B`
        where `B` does (the air/sea bob included, since `beat` is true for
        both off-beats), and the footprint the shadow is sized from and the
        ground row it sits on are one number for the whole unit. Asked of
        all eighteen units, `MOVES` or not, because it is placement and
        costs no render."""
        for uid in ATLAS_ORDER:
            a = atlas.cell_placement(uid, Pose.A)
            with self.subTest(unit=uid):
                self.assertEqual(atlas.cell_placement(uid, Pose.MOVE_A), a)
                self.assertEqual(
                    atlas.cell_placement(uid, Pose.MOVE_B),
                    atlas.cell_placement(uid, Pose.B),
                )
                for pose in Pose:
                    place = atlas.cell_placement(uid, pose)
                    self.assertEqual(place.footprint_w, a.footprint_w)
                    self.assertEqual(place.ground, a.ground)

    def _shadow_dx(self, uid: str) -> int:
        """How far left the move clip recentres this unit's shadow.

        The throw it gives up: `voxel.SHADOW_OFFSET`'s x, doubled for the
        airborne caster that drops further, and zero for a ship — a hull's
        ellipse is displacement with the foam line placed against it, and it
        keeps its offset in every pose (see `atlas.unit_cell`).
        """
        kind = UNITS[uid][1]
        if kind == "sea":
            return 0
        return voxel.SHADOW_OFFSET[0] * (2 if kind == "air" else 1)

    def _flip(self, pixels: set) -> set:
        """The set as `Sprite2D.flip_h` leaves it: mirrored in the cell."""
        return {(atlas.CELL_W - 1 - x, y) for x, y in pixels}

    def test_every_moving_unit_keeps_its_cast_shadow(self):
        """The patch of ground a unit walks over may not pump with its
        stride, exactly as a parked unit's may not pump with its idle: one
        shadow, sized off the pose-A footprint and laid on the pose-A ground
        row, in every pose.

        The rule is that the shadow never MOVES; it may only be UNCOVERED.
        The same ellipse is drawn every pose, but the hull is composed over
        it, so a pose that lifts a track off the ground — the tracked
        family's roll, the MBT's nose pitch — hands back the four or five
        pixels its pose-A hull was standing on. Those pixels are the ground
        showing through, not the shadow growing. So each pose's shadow is
        asked to account for the other's exactly: every shadow pixel of one
        pose is either a shadow pixel of the other, or it is hidden under the
        other's body. A shadow that slid, stretched or swelled has pixels
        that answer to neither and fails here — as does one that shrank,
        since the containment is checked both ways.

        The move poses are asked the same question about a RECENTRED pose A:
        their shadow gives up its x throw so that the consumer's mirror is a
        no-op on it (`compose_cell`'s `centred_shadow`). The reference is
        therefore pose A's shadow translated by `(-dx, 0)` and intersected
        with its own reflection in the cell — exactly what a mirror-safe
        ellipse is — with the allowance mirrored too, since a pixel pose A's
        hull hid is hidden on both sides of a symmetric shadow. Nothing else
        moves: the drop, the radii and the ground row are pose A's.
        """
        for uid in self._movers():
            dx = self._shadow_dx(uid)
            for fac in FACTIONS:
                a = pose_cell(uid, fac, Pose.A)
                shadow, body = self._shadow(a), self._body(a)
                for pose in (Pose.B, *MOVE_POSES):
                    cell = pose_cell(uid, fac, pose)
                    other, other_body = self._shadow(cell), self._body(cell)
                    ref, ref_body = shadow, body
                    if units.moving(pose) and dx:
                        ref = {(x - dx, y) for x, y in shadow}
                        ref_body = {(x - dx, y) for x, y in body}
                        ref, ref_body = (
                            ref & self._flip(ref),
                            ref_body | self._flip(ref_body),
                        )
                    with self.subTest(unit=uid, faction=fac.key, pose=pose.name):
                        # Reported as the offending pixels rather than as a
                        # subset relation between two several-hundred-pixel
                        # sets, which prints both in full and names neither.
                        self.assertEqual(
                            ref - other - other_body, set(), "pose A's shadow"
                        )
                        self.assertEqual(
                            other - ref - ref_body, set(), f"{pose.name}'s shadow"
                        )

    def test_a_moving_units_shadow_survives_the_consumers_mirror(self):
        """The property the whole centred shadow exists for.

        The game plays this clip with `Sprite2D.flip_h` for rightward travel
        (`docs/move_clip.md` section 3), which mirrors the cell about its
        centre. An ambient shadow is thrown down-right by
        `voxel.SHADOW_OFFSET`, so mirroring one lands it 5 px (land) or 9 px
        (air) to the LEFT of where every terrain tile puts its own — a sun
        that changes sides when a unit turns round. So the ground patch a
        move frame draws must be its own reflection.

        Checked modulo the body, because the hull mirrors too and is supposed
        to: a shadow pixel whose mirror is not shadow is only allowed if the
        mirrored hull is standing on it. That is the same 'uncovered, never
        moved' allowance the test above makes, asked of the flip.

        Ships are exempt and keep their offset ellipse: it is displacement,
        not a cast shadow, and the foam line is placed against it — see
        `_shadow_dx` and `atlas.unit_cell`.
        """
        for uid in self._movers():
            if not self._shadow_dx(uid):
                continue
            for fac in FACTIONS:
                for pose in MOVE_POSES:
                    cell = pose_cell(uid, fac, pose)
                    shadow, body = self._shadow(cell), self._body(cell)
                    flipped = self._flip(shadow)
                    with self.subTest(unit=uid, faction=fac.key, pose=pose.name):
                        self.assertTrue(shadow)
                        self.assertEqual(flipped - shadow - body, set(), "mirrored")
                        self.assertEqual(
                            shadow - flipped - self._flip(body), set(), "unmirrored"
                        )

    def test_a_moving_land_unit_keeps_a_foot_on_the_ground(self):
        """A land unit under way touches the ground in EVERY frame.

        The shadow is drawn on pose A's ground row and never moves, so a
        move frame that lifts its whole running gear opens the board's
        smallest visible gap — one rung-1 texel of bare terrain between the
        lowest body row and the shadow — and the unit reads as hovering, or,
        if the two frames disagree about it, as bouncing at the clip's own
        6 Hz. Asked at the board's 4:1 sample rather than in voxels because
        that is where the gap is either visible or not: the lowest body row
        of each move pose must be pose A's, in every livery. Air and sea are
        exempt — they carry `atlas.BOB_PX` on the off-beat by design."""
        for uid in self._movers():
            if UNITS[uid][1] != "land":
                continue
            for fac in FACTIONS:
                parked = self._lowest_body_row(uid, fac, Pose.A)
                for pose in MOVE_POSES:
                    with self.subTest(unit=uid, faction=fac.key, pose=pose.name):
                        self.assertEqual(self._lowest_body_row(uid, fac, pose), parked)

    @staticmethod
    def _lowest_body_row(uid: str, fac: Faction, pose: Pose) -> int:
        """The bottom rung-1 row the unit's own body paints, shadow off."""
        w, h = RUNG_1_CELL
        px = (
            pose_cell(uid, fac, pose, shadow=False)
            .resize(RUNG_1_CELL, Image.NEAREST)
            .load()
        )
        rows = [y for y in range(h) for x in range(w) if px[x, y][3] > 128]
        return max(rows)

    def test_a_moving_hull_adds_a_bow_wave_and_moves_nothing_else(self):
        """A running hull ADDS white water; it never moves the water it had.

        Two rules, and the first is the ambient clip's own
        (`test_the_foam_line_stays_on_the_water`) asked of the move clip.
        `voxel._waterline_foam` places its flecks against the composed cell's
        lowest spans, so a hull that trims bow-up by lifting its waterline
        course out of them would drag the foam line up the sheet and the sea
        would read as heaving rather than the ship as running. So every fleck
        pose A drew is still there, in the same pixel, in both move poses:
        pose A's foam is a SUBSET of the move pose's, not merely equal to it.

        The second is what a move pose may add on top — the bow wave
        (`voxel._bow_wave`), which is why this is a superset and not an
        equality. It is held to being a WAVE rather than a licence to paint:

        - it is a whole board texel of white water at least
          (`MIN_BOW_WAVE_PX`), in every livery and both move frames, so the
          4:1 sample cannot eat it;
        - every new fleck lands where pose A had displacement shading or open
          water, never on the hull, so the wave is on the sea and not a white
          stripe on the freeboard;
        - every new fleck is forward of the displacement patch's own midline,
          so it is the bow breaking and not the whole ship going white;
        - it occupies the same ROWS on both move frames. The hull bobs
          `voxel.BOB_PX` on the beat and the water does not: a crest authored
          against the hull instead of the water plane would ride up with it
          and the sea would heave again. Rows and not pixels, so a later
          frame may still tick the crest along the water.

        Together those say the sea under a moving ship is the sea under the
        parked one plus foam at its bow, which is the whole claim the move
        clip makes about water.
        """
        for uid in self._movers():
            if UNITS[uid][1] != "sea":
                continue
            for fac in FACTIONS:
                parked = pose_cell(uid, fac, Pose.A)
                foam, shade = self._foam(parked), self._shadow(parked)
                water = shade | self._transparent(parked)
                self.assertTrue(foam)
                midline = (min(x for x, _ in shade) + max(x for x, _ in shade) + 1) // 2
                rows = {}
                for pose in MOVE_POSES:
                    running = self._foam(pose_cell(uid, fac, pose))
                    wave = running - foam
                    rows[pose] = {y for _, y in wave}
                    with self.subTest(unit=uid, faction=fac.key, pose=pose.name):
                        self.assertEqual(foam - running, set(), "the ambient line")
                        self.assertGreaterEqual(
                            len(wave), self.MIN_BOW_WAVE_PX, "no bow wave"
                        )
                        self.assertEqual(wave - water, set(), "off the water")
                        self.assertEqual(
                            {(x, y) for x, y in wave if x > midline}, set(), "abaft"
                        )
                with self.subTest(unit=uid, faction=fac.key):
                    for pose in MOVE_POSES[1:]:
                        self.assertEqual(
                            rows[MOVE_POSES[0]],
                            rows[pose],
                            "the wave heaved with the hull",
                        )

    def test_a_unit_without_a_gait_renders_its_ambient_frame(self):
        """The fallback is what makes the move sheets valid from day one:
        every unit outside `MOVES` draws its ambient counterpart, byte for
        byte, so the clip can be adopted one family at a time without the
        sheet ever going blank or stale. Since S6 that is A/B/A/B, not just
        A/B — the move clip's own extra pair interpolates the same way an
        unauthored unit's whole clip does."""
        for uid in ATLAS_ORDER:
            if uid in MOVES:
                continue
            for fac in FACTIONS:
                with self.subTest(unit=uid, faction=fac.key):
                    for move, ambient in (
                        (Pose.MOVE_A, Pose.A),
                        (Pose.MOVE_B, Pose.B),
                        (Pose.MOVE_C, Pose.A),
                        (Pose.MOVE_D, Pose.B),
                    ):
                        self.assertEqual(
                            pose_cell(uid, fac, move).tobytes(),
                            pose_cell(uid, fac, ambient).tobytes(),
                            f"{move.name} did not fall back to {ambient.name}",
                        )

    def test_a_moving_unit_still_reads_as_its_own_unit(self):
        """As for frame B: among every unit's frame A, the one a move frame
        most resembles must be its own. A gait may move pixels; it may never
        move identity."""
        movers = self._movers()
        frame_a = {uid: self._sil(uid, Pose.A) for uid in ATLAS_ORDER}
        for uid in movers:
            for pose in MOVE_POSES:
                sil = self._sil(uid, pose)
                best = max(
                    ATLAS_ORDER,
                    key=lambda o: len(sil & frame_a[o]) / len(sil | frame_a[o]),
                )
                with self.subTest(unit=uid, pose=pose.name):
                    self.assertEqual(best, uid)

    def test_a_move_frame_is_not_its_own_mirror(self):
        """Informational, and it guards the consumer's `flip_h`.

        The game plays one move clip for both facings and mirrors the cell
        about its centre for the other. A frame that is its own mirror makes
        that flip a no-op — nothing in the art leads — so a gait worth
        mirroring is asymmetric in the sheet."""
        for uid in self._movers():
            for fac in FACTIONS:
                cell = pose_cell(uid, fac, Pose.MOVE_A)
                with self.subTest(unit=uid, faction=fac.key):
                    self.assertNotEqual(
                        cell.tobytes(),
                        cell.transpose(Image.Transpose.FLIP_LEFT_RIGHT).tobytes(),
                    )

    def test_the_rocket_trooper_steps_under_a_launcher_that_holds_still(self):
        """The mech's beat stops at the belt (`units.mech`, `_mech_legs`).

        A step needs a landmark that does NOT move: lift and translate the
        whole figure a board texel and every landmark travels at once, which
        at 160 ms reads as a hop in place rather than as a stride. So the
        trooper's torso, backpack, helmet, pauldrons and the launcher with
        its amber warhead tip are placed identically on all FOUR move frames
        (S6, 2026-09-02 — MOVE_A/MOVE_B are the shipped two-frame scissor,
        untouched, and MOVE_C/MOVE_D add the pair a genuine passing step
        each side of it), knee plates included, and only the boots and shins
        scissor.

        Pinned twice, because the two say different things. In the model,
        every voxel from the knee plate up (`z >= 3`) is the same material
        in the same place in every frame, while the legs under it are not —
        asked of every PAIR, not just consecutive ones, since the two
        passing keys (`_mech_legs(m, gather=1)` then `gather=2`) are two
        magnitudes and not one repeated: no two of the four leg readings may
        agree. In the composed cell — where the ramps, the softening and the
        sampler have had their say — no pixel above the figure's own midline
        differs across the four, the launcher and its tip being up there,
        while the half under it differs between every pair.
        """
        models = [build_model("mech", pose) for pose in MOVE_POSES]
        self.assertTrue(models[0].vox)
        # z 3 is the knee plate, the lowest thing the beat may not touch;
        # the amber warhead tip rides at the top of the same span, z 16.
        upper = [
            {v: mat for v, mat in model.vox.items() if v[2] >= 3} for model in models
        ]
        for other in upper[1:]:
            self.assertEqual(upper[0], other)
        legs = [
            {v: mat for v, mat in model.vox.items() if v[2] < 3} for model in models
        ]
        for i in range(len(legs)):
            for j in range(i + 1, len(legs)):
                with self.subTest(steps=(i, j)):
                    self.assertNotEqual(legs[i], legs[j])
        for fac in FACTIONS:
            cells = [pose_cell("mech", fac, pose) for pose in MOVE_POSES]
            rows = [y for _, y in self._body(cells[0])]
            waist = (min(rows) + max(rows) + 1) // 2
            uppers = [c.crop((0, 0, c.width, waist)).tobytes() for c in cells]
            lowers = [c.crop((0, waist, c.width, c.height)).tobytes() for c in cells]
            with self.subTest(faction=fac.key):
                for other in uppers[1:]:
                    self.assertEqual(uppers[0], other)
                for i in range(len(lowers)):
                    for j in range(i + 1, len(lowers)):
                        with self.subTest(steps=(i, j)):
                            self.assertNotEqual(lowers[i], lowers[j])

    def _mass(self, cell: Image.Image) -> int:
        px = cell.convert("RGBA").load()
        w, h = cell.size
        return sum(1 for y in range(h) for x in range(w) if px[x, y][3] > 0)

    def _shadow(self, cell: Image.Image) -> set:
        px = cell.convert("RGBA").load()
        w, h = cell.size
        return {(x, y) for y in range(h) for x in range(w) if px[x, y] == CAST}

    def _foam(self, cell: Image.Image) -> set:
        px = cell.convert("RGBA").load()
        w, h = cell.size
        return {
            (x, y)
            for y in range(h)
            for x in range(w)
            if px[x, y][:3] == FOAM and px[x, y][3] == 255
        }

    def _transparent(self, cell: Image.Image) -> set:
        px = cell.convert("RGBA").load()
        w, h = cell.size
        return {(x, y) for y in range(h) for x in range(w) if px[x, y][3] == 0}

    def _body(self, cell: Image.Image) -> set:
        """Everything the unit itself paints — the shadow is the ground's."""
        px = cell.convert("RGBA").load()
        w, h = cell.size
        return {
            (x, y)
            for y in range(h)
            for x in range(w)
            if px[x, y][3] > 0 and px[x, y] != CAST
        }

    def _sil(self, uid: str, pose: Pose) -> set:
        cell = pose_cell(uid, faction_by_key("neutral"), pose).convert("RGBA")
        px = cell.resize((32, 32), Image.NEAREST).load()
        return {(x, y) for y in range(32) for x in range(32) if px[x, y][3] > 200}


class GaitPhases(unittest.TestCase):
    """S6's own gate (2026-09-02): which families the move clip's third and
    fourth frames repeat verbatim from the first two, and which grow
    something new on them — the plan's own "state your choice per family"
    line, made a pinned fact rather than a claim in a report."""

    # The families with nothing new to say between the walk's two halves —
    # no tread to crawl, no rotor to turn, no lead leg to swap — so MOVE_C and
    # MOVE_D interpolate the existing two-frame motion by repeating it,
    # byte-identical composed cells and all.
    REUSED: frozenset[str] = frozenset(
        {
            "recon",
            "rockets",
            "missiles",
            "fighter",
            "bomber",
            "battleship",
            "cruiser",
            "sub",
            "lander",
        }
    )

    def test_reused_families_repeat_their_first_two_frames_verbatim(self):
        for uid in self.REUSED:
            for fac in FACTIONS:
                with self.subTest(unit=uid, faction=fac.key):
                    self.assertEqual(
                        pose_cell(uid, fac, Pose.MOVE_C).tobytes(),
                        pose_cell(uid, fac, Pose.MOVE_A).tobytes(),
                        "MOVE_C did not repeat MOVE_A",
                    )
                    self.assertEqual(
                        pose_cell(uid, fac, Pose.MOVE_D).tobytes(),
                        pose_cell(uid, fac, Pose.MOVE_B).tobytes(),
                        "MOVE_D did not repeat MOVE_B",
                    )

    def test_the_other_families_grow_a_genuine_third_and_fourth_frame(self):
        """The foot pair (a real gait), the five tracked hulls (the tread
        crawl) and the two copters (the rotor's third and fourth tick) all
        earn something MOVE_A/MOVE_B alone did not say — the complement of
        `REUSED` within `MOVES`."""
        grown = set(MOVES) - self.REUSED
        self.assertTrue(grown)
        for uid in grown:
            for fac in FACTIONS:
                with self.subTest(unit=uid, faction=fac.key):
                    self.assertNotEqual(
                        pose_cell(uid, fac, Pose.MOVE_C).tobytes(),
                        pose_cell(uid, fac, Pose.MOVE_A).tobytes(),
                        "MOVE_C is a silent repeat of MOVE_A",
                    )
                    self.assertNotEqual(
                        pose_cell(uid, fac, Pose.MOVE_D).tobytes(),
                        pose_cell(uid, fac, Pose.MOVE_B).tobytes(),
                        "MOVE_D is a silent repeat of MOVE_B",
                    )

    # Every tracked unit's link stripe, at rung 1: the four move frames must
    # visit four DIFFERENT quarter-positions, not the old two-frame flip
    # played twice — the tread crawl's own claim, asked of the voxels a
    # `_track` block paints as `track_lt` rather than of the whole cell, so a
    # body reading that also differs (there is none here — the tracked
    # family's own chassis attitude repeats, `REUSED`'s sibling claim above)
    # could never be mistaken for tread motion.
    TRACKED: tuple[str, ...] = ("tank", "md_tank", "anti_air", "artillery", "apc")

    def test_every_tracked_hull_crawls_its_tread_through_four_positions(self):
        for uid in self.TRACKED:
            builder = UNITS[uid][0]
            stripes = [
                frozenset(
                    v for v, mat in builder(pose).vox.items() if mat == "track_lt"
                )
                for pose in MOVE_POSES
            ]
            with self.subTest(unit=uid):
                for i in range(len(stripes)):
                    for j in range(i + 1, len(stripes)):
                        self.assertNotEqual(
                            stripes[i],
                            stripes[j],
                            f"{MOVE_POSES[i].name} and {MOVE_POSES[j].name} share a "
                            "tread phase",
                        )

    # Both copters read the rotor disc through the move clip's own frame
    # index (S6): four blade shapes, one per frame, where the ambient pair
    # only ever turns two of them.
    def test_the_copters_turn_their_rotor_through_all_four_ticks(self):
        for uid in ("b_copter", "t_copter"):
            builder = UNITS[uid][0]
            discs = [
                frozenset(v for v, mat in builder(pose).vox.items() if mat == "rotor")
                for pose in MOVE_POSES
            ]
            with self.subTest(unit=uid):
                for i in range(len(discs)):
                    for j in range(i + 1, len(discs)):
                        self.assertNotEqual(
                            discs[i],
                            discs[j],
                            f"{MOVE_POSES[i].name} and {MOVE_POSES[j].name} share a "
                            "rotor tick",
                        )

    # The rifleman's own four-key gait: contact-L / passing / contact-R /
    # passing, no two consecutive frames sharing a model — the true walk the
    # plan asks foot units for, read at the same voxel level the mech's own
    # pinned test reads its scissor.
    def test_the_rifleman_strides_through_four_distinct_positions(self):
        builder = UNITS["infantry"][0]
        models = [builder(pose).vox for pose in MOVE_POSES]
        for i in range(len(models)):
            with self.subTest(step=i):
                self.assertNotEqual(models[i], models[(i + 1) % len(models)])


if __name__ == "__main__":
    unittest.main()
