"""Contract tests for the board's one sun.

One light so one shadow direction, the cast shadow's read at every rung, and
the tile features outlined by that same sun.
"""

from __future__ import annotations

import contextlib
import unittest
from unittest import mock

from spritegen import atlas, autotile, terrain
from spritegen.autotile import E, N, S, W
from spritegen.palette import FACTIONS
from spritegen.terrain import (
    CELL,
    PLAINS_SALT,
    ROAD,
    ROAD_DARK,
    WATER,
    WATER_DARK,
)
from spritegen.units import AMBIENT_POSES, ATLAS_ORDER, MOVE_POSES, UNITS, Pose, foot
from spritegen import cell as cell_mod
from spritegen import voxel

from pixel_helpers import opaque_pixels, pose_cell


class OneSun(unittest.TestCase):
    """One light, so one shadow direction — over the whole sheet.

    The board used to run four cast-shadow rules at once: a building dropped
    its silhouette down-right, a land or sea unit sat on an ellipse straight
    under itself, and a wood or a mountain laid a 1px line straight down its
    fringe. Nothing on a tile is lit from underneath, so three of those four
    read as ambient dirt rather than as shade, and a city and the wood beside
    it disagreed about where the sun was.

    `voxel.SHADOW_OFFSET` is now that one statement, and terrain re-exports
    it rather than keeping a second copy. Airborne units keep their larger
    drop — the gap between unit and shadow is the altitude cue — but on the
    same diagonal.

    The move clip is the one thing on the board the consumer MIRRORS, and a
    mirrored offset is a second sun. Its land and air poses therefore hold
    the drop and drop the throw; that is the only place the sheet does not
    read down-right, and it has a test of its own
    (`test_a_mirrored_move_frame_owes_the_sun_nothing_lateral`).
    """

    OFFSET = voxel.SHADOW_OFFSET
    # The measured floor on the units, whose shadow is an ellipse under the
    # hull rather than the hull's own silhouette: rockets, whose long barrel
    # sits left of its own cell centre, comes in at +0.37px lateral.
    MIN_UNIT_LATERAL = 0.2
    # Half a pixel: how far a centred move shadow's centre of mass may sit
    # off the cell's mirror axis. The ELLIPSE is symmetric by construction
    # (`voxel._shadow_ellipse`'s `mirrored`); what moves the centroid at all
    # is the asymmetric hull standing on part of it, and the tracked family's
    # roll is the worst of those at 0.04px.
    MAX_MOVE_LATERAL = 0.5

    def _sheet_poses(self, uid: str) -> tuple[Pose, ...]:
        """The poses that carry the sheet's own sun for this unit.

        Everything but the move poses of a unit whose shadow is CENTRED for
        the consumer's mirror — land and air; a ship's ellipse is
        displacement and keeps the offset in every pose. See
        `test_a_mirrored_move_frame_owes_the_sun_nothing_lateral`.
        """
        if UNITS[uid][1] == "sea":
            return tuple(Pose)
        return AMBIENT_POSES

    def _centroid(self, pts) -> tuple[float, float]:
        return (
            sum(x for x, _ in pts) / len(pts),
            sum(y for _, y in pts) / len(pts),
        )

    def _split(self, cell, shadow_tone):
        """(shadow pixels, everything else opaque) of a composed cell."""
        img = cell.convert("RGBA")
        px = img.load()
        shade, caster = [], []
        for y in range(img.height):
            for x in range(img.width):
                if px[x, y][3] == 0:
                    continue
                (shade if px[x, y][:3] == shadow_tone else caster).append((x, y))
        return shade, caster

    def test_the_tile_drawer_and_the_cell_read_one_offset(self):
        sx, sy = self.OFFSET
        self.assertIs(terrain.SHADOW_OFFSET, voxel.SHADOW_OFFSET)
        self.assertGreater(sx, 0)  # down-RIGHT: the sun is up-left
        self.assertGreater(sy, 0)

    def test_every_unit_drops_its_shadow_down_right_of_itself(self):
        fac = FACTIONS[1]
        for uid in ATLAS_ORDER:
            for pose in self._sheet_poses(uid):
                cast, hull = self._split(pose_cell(uid, fac, pose), voxel.SHADOW)
                with self.subTest(unit=uid, pose=pose.name):
                    self.assertTrue(cast)
                    (sx, sy), (hx, hy) = self._centroid(cast), self._centroid(hull)
                    self.assertGreater(sx - hx, self.MIN_UNIT_LATERAL)
                    self.assertGreater(sy - hy, 0.0)

    def test_a_unit_cell_lays_its_ellipse_by_the_sheet_offset(self):
        """The hull-relative reading above only fixes the SIGN — a unit whose
        own mass sits left of centre would pass it on a half-pixel. This one
        moves the sheet's offset to zero and measures how far each shadow
        travels: a land or sea ellipse follows the full diagonal (short of
        2px only where the cell edge or the wake clips it), and an airborne
        one keeps its own larger lateral drop."""
        fac = FACTIONS[1]
        # Every render under a patched offset is `atlas`'s own: a shared cell
        # would answer the patched question with the unpatched cell.
        for uid in ATLAS_ORDER:
            for pose in self._sheet_poses(uid):
                with self.subTest(unit=uid, pose=pose.name):
                    lit, _ = self._split(pose_cell(uid, fac, pose), voxel.SHADOW)
                    with mock.patch.object(cell_mod, "SHADOW_OFFSET", (0, 0)):
                        bare, _ = self._split(
                            atlas.unit_cell(uid, fac, pose), voxel.SHADOW
                        )
                    (lx, ly), (bx, by) = self._centroid(lit), self._centroid(bare)
                    self.assertGreaterEqual(lx - bx, 1.0)
                    self.assertGreaterEqual(
                        ly - by, 1.5 if UNITS[uid][1] != "air" else 0.0
                    )

    def test_a_mirrored_move_frame_owes_the_sun_nothing_lateral(self):
        """The sheet's one exception, and it is the mirror that buys it.

        The consumer plays the move clip through `Sprite2D.flip_h` for
        rightward travel (docs/move_clip.md section 3), which negates x: a
        shadow thrown down-right on the sheet is thrown down-LEFT on screen
        for every unit travelling right, next to terrain that never mirrors.
        A sun that changes sides with a unit's heading is worse than one that
        stops throwing, so the land and air move poses keep the whole drop
        and give up the throw, on an ellipse drawn symmetric about the cell's
        mirror axis — the same shadow either way round.

        Three readings say that: it is still under its caster, its centre of
        mass is on the mirror axis, and zeroing the sheet's offset in x alone
        changes not one byte of the cell — it owes the sheet's sun nothing
        lateral — while zeroing it in y still costs a land unit its 2px drop.

        Ships are not centred and are asked the sheet's own question in all
        four poses by the two tests above.
        """
        fac = FACTIONS[1]
        axis = (atlas.CELL_W - 1) / 2
        for uid in ATLAS_ORDER:
            if UNITS[uid][1] == "sea":
                continue
            for pose in MOVE_POSES:
                with self.subTest(unit=uid, pose=pose.name):
                    cell = pose_cell(uid, fac, pose)
                    lit, hull = self._split(cell, voxel.SHADOW)
                    self.assertTrue(lit)
                    with mock.patch.object(
                        cell_mod, "SHADOW_OFFSET", (0, self.OFFSET[1])
                    ):
                        no_throw = atlas.unit_cell(uid, fac, pose)
                    with mock.patch.object(cell_mod, "SHADOW_OFFSET", (0, 0)):
                        bare, _ = self._split(
                            atlas.unit_cell(uid, fac, pose), voxel.SHADOW
                        )
                    (lx, ly), (_, by) = self._centroid(lit), self._centroid(bare)
                    self.assertGreater(ly - self._centroid(hull)[1], 0.0)
                    self.assertLessEqual(abs(lx - axis), self.MAX_MOVE_LATERAL)
                    self.assertEqual(cell.tobytes(), no_throw.tobytes())
                    self.assertGreaterEqual(
                        ly - by, 1.5 if UNITS[uid][1] != "air" else 0.0
                    )

    def test_every_building_drops_its_shadow_down_right_of_itself(self):
        for bid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                cast, walls = self._split(
                    terrain.property_overlay(bid, fac), terrain.SHADOW
                )
                with self.subTest(building=bid, faction=fac.key):
                    self.assertTrue(cast)
                    (sx, sy), (bx, by) = self._centroid(cast), self._centroid(walls)
                    self.assertGreater(sx - bx, 0.0)
                    self.assertGreater(sy - by, 0.0)

    @contextlib.contextmanager
    def _sun(self, offset):
        """Both tile drawers under one sun. The offset is `voxel.SHADOW_OFFSET`,
        which each drawer's module binds for itself, so it is patched where each
        reads it rather than once on the package."""
        with (
            mock.patch("spritegen.terrain.mountain.SHADOW_OFFSET", offset),
            mock.patch("spritegen.terrain.woods.SHADOW_OFFSET", offset),
        ):
            yield

    def _stamped(self, draw, offset):
        """The shadow a tile drawer stamps, read by DIFFERENCE against the
        same tile drawn with no offset at all — which is the only way to tell
        a wood's contact shadow from the tufts standing in its clearings,
        both being GRASS_DARK, without the test copying their coordinates.

        The plate the ground pixels are recognised by is the CLUMPED grass
        plate every scenery tile stands on: read against the plain `_ground`
        the clumps count as casters, and a clump four pixels up-left of a
        shadow pixel vouches for it, which makes both readings vacuous."""
        with self._sun(offset):
            lit = draw().convert("RGB")
        with self._sun((0, 0)):
            bare = draw().convert("RGB")
        a, b = lit.load(), bare.load()
        shade, caster = set(), set()
        plate = set(opaque_pixels(terrain._grass_ground(PLAINS_SALT)))
        for y in range(CELL):
            for x in range(CELL):
                if a[x, y] != b[x, y]:
                    shade.add((x, y))
                elif b[x, y] not in plate:
                    caster.add((x, y))
        return shade, caster

    def _airborne(self, draw, drawn_with) -> int:
        """Shadow pixels with nothing up-left of them to cast them, the tile
        having been drawn with `drawn_with` — always read against the sheet's
        own offset, so a tile stamped on another sun comes back non-zero."""
        sx, sy = self.OFFSET
        shade, caster = self._stamped(draw, drawn_with)
        return sum(
            1
            for x, y in shade
            if not any((x - sx, y - d) in caster for d in range(1, sy + 1))
        )

    def _drawers(self):
        yield "woods", terrain.woods
        for mask in range(16):
            yield f"woods {mask}", lambda m=mask: autotile.woods_tile(m)
        for phase in range(len(terrain.MOUNTAIN_PHASES)):
            yield f"mountain {phase}", lambda p=phase: terrain.mountain(p)

    def test_every_contact_shadow_is_its_own_caster_displaced_down_right(self):
        """Scenery stamps its shadow rather than casting an ellipse, so it is
        held to the offset pixel by pixel: every shadow pixel has the thing
        that cast it exactly SHADOW_OFFSET[0] to its left and one to two rows
        above."""
        for name, draw in self._drawers():
            with self.subTest(tile=name):
                shade, _ = self._stamped(draw, self.OFFSET)
                self.assertTrue(shade)
                self.assertEqual(self._airborne(draw, self.OFFSET), 0)

    def test_the_reading_refuses_a_shadow_thrown_the_other_way(self):
        # worth asserting only if it catches a shadow on another sun: the
        # same tiles drawn with the offset mirrored leave most of their
        # shadow with nothing up-left of it
        mirrored = (-self.OFFSET[0], self.OFFSET[1])
        for name, draw in self._drawers():
            with self.subTest(tile=name):
                self.assertGreater(self._airborne(draw, mirrored), 0)


class FootprintContact(unittest.TestCase):
    """A land unit's ellipse is CONTACT, and it never outgrew the shadow the
    board was already measured against.

    Two halves of one statement. The shadow is fitted to the footprint the
    unit plants on the ground (`voxel.footprint_width`) rather than to its
    whole crop, so it must TOUCH the unit: a foot unit's 4px stance used to
    carry a 23px lozenge two rows clear of its boots, which reads as a unit
    hovering. And fitting it may only ever take width away — a land ellipse
    the board had already been measured against is a shape the legibility
    ratchet and the mirrored move frame's occlusion floor both hold, so the
    pre-S3 radius is the ceiling.

    The sheet cannot catch either on its own: a change that reopened the gap
    or lifted the ceiling regenerates matching art and passes the snapshot
    gate, both sides of it coming from this same code.

    Read on the composed cells rather than on the formula: the shadow by
    DIFFERENCE against the same cell composed with `shadow=False`, which is
    the only reading that tells a cast pixel from a dark pixel of the unit
    itself.
    """

    # The pre-S3 radius: 0.34 of the whole pose-A crop, the coefficient this
    # file shipped before the shadow was fitted to the footprint.
    SILHOUETTE_COEFFICIENT = 0.34
    # The roster's own answer to which units walk rather than roll.
    FOOT = frozenset(
        uid for uid, (build, _) in UNITS.items() if build.__module__ == foot.__name__
    )

    def _cast_and_body(self, uid: str):
        """(shadow pixels, the unit's own pixels) of one composed cell."""
        fac = FACTIONS[1]
        lit = pose_cell(uid, fac).convert("RGBA").load()
        bare = pose_cell(uid, fac, shadow=False).convert("RGBA").load()
        cast, body = set(), set()
        for y in range(atlas.CELL_H):
            for x in range(atlas.CELL_W):
                if lit[x, y] != bare[x, y]:
                    cast.add((x, y))
                elif bare[x, y][3] > 200:
                    body.add((x, y))
        return cast, body

    def _kind(self, kind: str):
        return [uid for uid in ATLAS_ORDER if UNITS[uid][1] == kind]

    def _gap(self, uid: str) -> int:
        """Blank rows between the unit's lowest pixel and its shadow's
        highest. Zero or less is contact; the shapes overlap."""
        cast, body = self._cast_and_body(uid)
        self.assertTrue(cast, f"{uid} casts no shadow at all")
        self.assertTrue(body, f"{uid} composed no sprite")
        return min(y for _, y in cast) - max(y for _, y in body) - 1

    def test_every_foot_unit_stands_on_its_own_shadow(self):
        for uid in sorted(self.FOOT):
            with self.subTest(unit=uid):
                self.assertLessEqual(self._gap(uid), 0)

    def test_the_reading_sees_the_gap_an_aircraft_keeps(self):
        # worth asserting only if it catches a detached shadow, and the sheet
        # holds one on purpose: an aircraft's drop IS the altitude cue, so
        # the same reading has to come back with rows of daylight in it.
        for uid in self._kind("air"):
            with self.subTest(unit=uid):
                self.assertGreater(self._gap(uid), 1)

    def _ceiling(self, uid: str) -> int:
        silhouette_w = atlas.cell_placement(uid, Pose.A).silhouette_w
        return max(4, int(silhouette_w * self.SILHOUETTE_COEFFICIENT))

    def _half_width(self, uid: str) -> int:
        cast, _ = self._cast_and_body(uid)
        self.assertTrue(cast, f"{uid} casts no shadow at all")
        cx = atlas.CELL_W // 2 + cell_mod.SHADOW_OFFSET[0]
        return max(abs(x - cx) for x, _ in cast)

    def test_no_land_ellipse_is_wider_than_the_shadow_it_replaced(self):
        for uid in self._kind("land"):
            with self.subTest(unit=uid):
                self.assertLessEqual(self._half_width(uid), self._ceiling(uid))

    def test_a_foot_unit_is_narrower_than_that_ceiling_rather_than_at_it(self):
        # the cap is only half the fit: if every unit simply converged on the
        # ceiling, the footprint would be measuring nothing. The two units
        # whose stance is nothing like their crop have to come in under it.
        for uid in sorted(self.FOOT):
            with self.subTest(unit=uid):
                self.assertLess(self._half_width(uid), self._ceiling(uid))


class CastShadow(unittest.TestCase):
    """The cast shadow reads as shade at every rung the board offers.

    `BattleZoom` steps whole rungs 1 to 5, and the 64px cell is drawn onto a
    16px grid with nearest filtering, so the board keeps one source pixel in
    4/z: 4:1 at rung 1, 2:1 at rung 2, 1:1 at rung 4. The shadow used to be a
    1px checkerboard, and a 1px parity is a different picture at every one of
    those — measured over this same army it came out anywhere from 0% to 285%
    of its own density depending on the rung and on where the sampling grid
    happened to fall, which on the board is solid at rung 1, all but gone at
    rung 2 and loose black dots at rung 4. Two players reported the dots.

    Solid is the shape with no sub-pixel structure to lose, which is what
    these two readings pin: the shadow uses both parities (so it cannot go
    back to a checkerboard unnoticed), and every rung at every phase draws
    the same share of it.
    """

    SHADOW = (16, 18, 24)
    # Source pixels per screen pixel at the rungs a match is played at.
    RATIOS = (4, 2, 1)
    # How far a phase's share of the shadow may sit from the shadow's own
    # density. The checkerboard it replaced misses this by 0.85 at its best
    # rung; solid comes in at 0.07.
    TOLERANCE = 0.15

    def _shadows(self) -> list[list[tuple[int, int]]]:
        """Every unit's cast-shadow pixels. One faction: the shadow belongs to
        the cell rather than to the army and is identical on every row."""
        fac = FACTIONS[1]
        found = []
        for uid in ATLAS_ORDER:
            px = pose_cell(uid, fac).convert("RGBA").load()
            found.append(
                [
                    (x, y)
                    for y in range(atlas.CELL_H)
                    for x in range(atlas.CELL_W)
                    if px[x, y][3] == 255 and px[x, y][:3] == self.SHADOW
                ]
            )
        return found

    def test_every_unit_casts_a_shadow_on_both_parities(self):
        for uid, cast in zip(ATLAS_ORDER, self._shadows()):
            with self.subTest(unit=uid):
                self.assertTrue(cast, "no cast shadow at all")
                self.assertEqual({(x + y) % 2 for x, y in cast}, {0, 1})
                self.assertEqual({x % 2 for x, y in cast}, {0, 1})

    def test_every_rung_draws_the_same_share_of_it(self):
        casts = self._shadows()
        total = sum(len(c) for c in casts)
        for ratio in self.RATIOS:
            for phase_y in range(ratio):
                for phase_x in range(ratio):
                    drawn = sum(
                        1
                        for cast in casts
                        for x, y in cast
                        if x % ratio == phase_x and y % ratio == phase_y
                    )
                    share = drawn * ratio * ratio / total
                    with self.subTest(ratio=ratio, phase=(phase_x, phase_y)):
                        self.assertAlmostEqual(share, 1.0, delta=self.TOLERANCE)


class TileSunwardEdges(unittest.TestCase):
    """The tile features are outlined by the same sun the units are.

    `voxel._selective_outline` lights the two sunward sides of a unit rather
    than blacking them (`test_the_sunward_edge_is_lit_rather_than_outlined`).
    `autotile._edge_pass` used to ring a road, a bank or a channel in one
    dark tone on all four sides, which is a sticker stamped into the tile: no
    lit side means no direction, and a feature with no direction cannot lie
    on the ground the units stand on.

    Read over all sixteen masks of both autotiles: the sunward edge of a
    region is never the dark tone, and the two sides turned away from the
    light keep it.
    """

    # Where a later pass legitimately takes an away-facing edge pixel back:
    # the pond's lip is 1px wide in the reed notches, so the waterline mud of
    # the water pass lands on the very pixel the shore pass had just darkened.
    # Measured worst case is the pond's own shore, at 0.93.
    MIN_AWAY_DARK = 0.9

    def _regions(self, mask: int):
        """(region pixels, finished tile, lit tone, dark tone) per feature,
        the region read off the shape BEFORE any edge pass touched it."""
        base = terrain.plains()
        road = base.copy()
        autotile._fill_arms(road, mask or (E | W), autotile._RLO, autotile._RHI, ROAD)
        river = base.copy()
        autotile._shape_river(river, base, mask)
        shore_tones = {
            autotile.BANK,
            autotile.POND_BANK,
            autotile.POND_BANK_DK,
            WATER,
        }
        road_tile = autotile.road_tile(mask)
        river_tile = autotile.river_tile(mask)
        return (
            ("road", self._mask(road, {ROAD}), road_tile, autotile.ROAD_LIT, ROAD_DARK),
            (
                "shore",
                self._mask(river, shore_tones),
                river_tile,
                autotile.BANK_LIT,
                autotile.BANK_DARK,
            ),
            (
                "water",
                self._mask(river, {WATER}),
                river_tile,
                autotile.WATER_LIT,
                WATER_DARK,
            ),
        )

    def _mask(self, img, tones) -> set[tuple[int, int]]:
        px = img.convert("RGB").load()
        return {(x, y) for y in range(CELL) for x in range(CELL) if px[x, y] in tones}

    def _edges(self, region, tile, dark):
        """(sunward pixels drawn dark, sunward pixels, away pixels drawn
        dark, away pixels). A break at the tile border is not an edge: a
        feature running off the cell continues into its neighbour."""
        px = tile.convert("RGB").load()
        sun_dark = sun = away_dark = away = 0
        for x, y in region:
            out = [
                (nx, ny)
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1))
                if 0 <= nx < CELL and 0 <= ny < CELL and (nx, ny) not in region
            ]
            if not out:
                continue
            if any(n in ((x - 1, y), (x, y - 1)) for n in out):
                sun += 1
                sun_dark += px[x, y] == dark
            else:
                away += 1
                away_dark += px[x, y] == dark
        return sun_dark, sun, away_dark, away

    def test_no_sunward_tile_edge_is_drawn_dark(self):
        for mask in range(16):
            for name, region, tile, _lit, dark in self._regions(mask):
                with self.subTest(mask=mask, feature=name):
                    sun_dark, sun, _, _ = self._edges(region, tile, dark)
                    self.assertGreater(sun, 0)
                    self.assertEqual(sun_dark, 0)

    def test_the_side_turned_away_from_the_light_keeps_its_contour(self):
        for mask in range(16):
            for name, region, tile, _lit, dark in self._regions(mask):
                with self.subTest(mask=mask, feature=name):
                    _, _, away_dark, away = self._edges(region, tile, dark)
                    self.assertGreater(away, 0)
                    self.assertGreaterEqual(away_dark / away, self.MIN_AWAY_DARK)

    def test_the_reading_refuses_the_outline_it_replaced(self):
        # the control: the same road drawn with the old one-tone outline, which
        # blacks every sunward pixel it touches
        for mask in (E | W, N | E | S | W):
            with self.subTest(mask=mask):
                tile = terrain.plains()
                autotile._fill_arms(tile, mask, autotile._RLO, autotile._RHI, ROAD)
                region = self._mask(tile.copy(), {ROAD})
                autotile._edge_pass(tile, lambda c: c == ROAD, ROAD_DARK)
                sun_dark, sun, _, _ = self._edges(region, tile, ROAD_DARK)
                self.assertEqual(sun_dark, sun)


if __name__ == "__main__":
    unittest.main()
