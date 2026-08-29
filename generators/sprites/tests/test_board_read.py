"""Contract tests for what survives the board.

Figure against ground, the edge at a quarter of the pixels, and the masses a
player tells apart at board zoom.
"""

from __future__ import annotations

import statistics
import unittest

from PIL import Image

from spritegen import atlas, palette, terrain
from spritegen.gbuffer import project as voxel_project
from spritegen.palette import (
    FACTIONS,
    GROUND_BAND,
    GROUND_BREAK,
    OUTLINE_HEAVY,
    OUTLINE_RIM,
    RAMPS,
    S_BODY,
    faction_by_key,
)
from spritegen.terrain import (
    GRASS,
    GRASS_DARK,
    SAND,
    SAND_DARK,
    WATER,
    WATER_DARK,
    WATER_LIGHT,
)
from spritegen.units import ATLAS_ORDER, Pose, build_model
from spritegen.voxel import render_indexed

from pixel_helpers import RUNG_1_CELL, pose_cell


class GroundContrast(unittest.TestCase):
    """Figure and ground: a unit standing on plains or shoal has to cut out of it.

    The 4px band answered this by construction — every boundary pixel was S0,
    so 0% of any silhouette tied with the tile under it. The 1px selective
    outline lights the two sunward sides instead, and that trade is only paid
    for where the lit line reads against the ground. It does not on two rows:
    neutral is the sand's own khaki, and Iron's lit planes are capped at S3
    (L129) — the middle of the band GRASS_DARK, GRASS, SAND_DARK and SAND
    occupy. The 2026-08-21 sheet review measured the result: neutral and Iron
    boundaries within 25L of the tile beneath them, 10.3% and 12.7% on shoal
    and 19.0% and 19.1% on plains, worst sprite 30% (apc).

    `OUTLINE_HEAVY` is those two rows' answer: their sunward silhouette keeps
    its light only where the lift clears the ground's own band, and takes the
    ground-facing contour where it cannot. Measured the same way afterwards:
    0.46% and 0.61% on shoal, 0.56% on plains for both, worst sprite 2.24%.
    Re-measured after the 2026-08-22 ground regrade (docs/terrain_tones.md),
    which moved the grass a little further into the two rows' band: 0.46% and
    0.61% on shoal unchanged, 0.79% on plains for both, worst sprite 2.24%.

    Meridian is unmoved, and deliberately: its body is a design-system token
    no ground shares, so a lit edge that ties with the grass or the sand in
    VALUE still breaks with it in COLOUR — which is what
    `test_a_light_row_that_ties_in_value_still_breaks_in_colour` holds it to
    instead.

    Two rows had neither half of that argument, and were carried as named
    debt for three rounds: verdant IS the grass's hue (10.30% of its boundary
    tying with the plains in value AND colour) and aurora IS the water's
    (6.48% on shoal). `OUTLINE_RIM` is their answer, and it is the heavy
    grade's question with the opposite answer — where the lift cannot clear
    the ground's band, the line climbs to the rim rather than falling to the
    contour, because the band above the terrain ceiling is the units' by
    contract and a green army on grass has nothing to spend below. Measured
    the same way afterwards: 0.39% and 0.55%, worst sprite 1.56% and 3.75%,
    so both pairs are now inside the bound the light rows answer to and
    nothing is carried as open.
    """

    WEAK = GROUND_BREAK  # under this much luma, boundary and tile read as one
    # The two grounds an army spends its game on.
    GROUNDS = ("plains", "shoal")
    MAX_WEAK_ROW = 0.02  # per row x ground; measured 0.0046-0.0079
    MAX_WEAK_UNIT = 0.04  # per sprite; measured 0.0224 (tank, shoal)
    # A row that keeps its lit line gives up value and must still break in
    # colour. As a distance in RGB, over the same boundary: measured 0.29% at
    # worst on shoal (meridian, verdant) and 0.00-0.39% on plains, with no
    # pair set aside — the two that used to be are the rim grade's now.
    COLOUR_BREAK = 40.0
    MAX_WEAK_LIGHT = 0.02
    SHADOW = (16, 18, 24)

    def _ground(self, name: str):
        tile = terrain._PLAIN_TILES[name]().convert("RGB")
        px = tile.load()
        return [
            [px[x, y] for x in range(tile.width)] for y in range(tile.height)
        ], tile.width

    def _boundary(self, uid, fac, pose, ground, n):
        """(value ties, colour-and-value ties, boundary pixels) of one sprite
        standing on `ground`, the tile repeating under the cell as on a map."""
        cell = pose_cell(uid, fac, pose, False).convert("RGBA")
        px = cell.load()
        w, h = cell.size
        weak = both = total = 0
        for y in range(h):
            for x in range(w):
                c = px[x, y]
                if c[3] != 255 or c[:3] == self.SHADOW:
                    continue
                lum = palette.luminance(c[:3])
                dv = dc = None
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] == 255:
                        continue
                    # Where the sprite ends the tile shows, and the tile is
                    # laid on a 64px grid the 64x96 cell hangs off the top of.
                    g = ground[ny % n][nx % n]
                    v = abs(lum - palette.luminance(g))
                    d = sum((a - b) ** 2 for a, b in zip(c[:3], g)) ** 0.5
                    dv = v if dv is None else min(dv, v)
                    dc = d if dc is None else min(dc, d)
                if dv is None:
                    continue
                total += 1
                weak += dv < self.WEAK
                both += dv < self.WEAK and dc < self.COLOUR_BREAK
        return weak, both, total

    def test_the_band_the_outline_grade_is_stated_on_is_the_ground_it_names(self):
        """`palette.GROUND_BAND` cannot import `terrain`, so it is pinned here.

        The renderer decides whether a lit line clears the ground before any
        tile exists, out of a band written in `palette.py`; these are the four
        authored tones that band claims to span, and the ceiling over them.
        """
        lo, hi = GROUND_BAND
        for tone in (GRASS_DARK, GRASS, SAND_DARK, SAND):
            with self.subTest(tone=tone):
                self.assertGreaterEqual(palette.luminance(tone), lo)
                self.assertLessEqual(palette.luminance(tone), hi)

    def test_the_hues_the_rim_grade_is_stated_on_are_the_grounds_it_names(self):
        """`palette.GROUND_HUES` is the other half of the same pinning.

        The grade is per FACTION and the question it asks is per pixel, so
        both ends have to be checked: the two chromatic grounds are inside the
        arc, the sand is not (it is neutral's khaki, and neutral answers with
        the heavy grade), and exactly the rows whose body token sits inside a
        ground wear the rim grade.
        """
        for tone in (GRASS, GRASS_DARK, WATER, WATER_DARK, WATER_LIGHT):
            with self.subTest(tone=tone):
                self.assertTrue(palette.shares_a_ground_hue(tone))
        for tone in (SAND, SAND_DARK):
            with self.subTest(tone=tone):
                self.assertFalse(palette.shares_a_ground_hue(tone))
        for fac in FACTIONS:
            with self.subTest(faction=fac.key):
                shares = palette.shares_a_ground_hue(RAMPS[fac.key][S_BODY])
                self.assertEqual(shares, fac.outline == OUTLINE_RIM)

    def test_the_value_only_rows_cut_out_of_the_ground_they_stand_on(self):
        for name in self.GROUNDS:
            ground, n = self._ground(name)
            for fac in FACTIONS:
                if fac.outline != OUTLINE_HEAVY:
                    continue
                weak = total = 0
                for uid in ATLAS_ORDER:
                    for pose in Pose:
                        w_, _, t_ = self._boundary(uid, fac, pose, ground, n)
                        weak += w_
                        total += t_
                        with self.subTest(
                            ground=name, faction=fac.key, unit=uid, pose=pose.name
                        ):
                            self.assertLessEqual(w_ / t_, self.MAX_WEAK_UNIT)
                with self.subTest(ground=name, faction=fac.key):
                    self.assertLessEqual(weak / total, self.MAX_WEAK_ROW)

    def test_a_light_row_that_ties_in_value_still_breaks_in_colour(self):
        for name in self.GROUNDS:
            ground, n = self._ground(name)
            for fac in FACTIONS:
                if fac.outline == OUTLINE_HEAVY:
                    continue
                both = total = 0
                for uid in ATLAS_ORDER:
                    for pose in Pose:
                        _, b_, t_ = self._boundary(uid, fac, pose, ground, n)
                        both += b_
                        total += t_
                with self.subTest(ground=name, faction=fac.key):
                    self.assertLessEqual(both / total, self.MAX_WEAK_LIGHT)

    def test_the_b_copters_blades_stay_off_the_body_under_them(self):
        """The rotor is the unit's tell and it is drawn one pixel wide.

        A blade pixel whose four neighbours all sit within `WEAK` of it has
        dissolved into whatever it crosses — the fuselage, the collar, the
        sky. Measured over both frames of all five rows: 2 to 8 of the 35
        blade pixels that touch another drawn pixel. The heavy grade raises
        that on its own two rows (neutral and Iron go 3/6 to 7/8) because a
        blade tip and the body edge under it can both be S0 now, which this
        reading cannot tell from a merge — the blades' separation from the
        GROUND is held by the row test above. So this is a floor under the
        1px lattice rather than a reading of the livery.
        """
        for fac in FACTIONS:
            for pose in Pose:
                model = build_model("b_copter", pose)
                sprite = render_indexed(model, fac)
                px = sprite.image.load()
                w, h = sprite.image.size
                blades = self._blade_pixels(model)
                dissolved = touching = 0
                for x, y in sorted(blades):
                    if not (0 <= x < w and 0 <= y < h) or px[x, y][3] != 255:
                        continue
                    steps = []
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        q = (x + dx, y + dy)
                        if q in blades or not (0 <= q[0] < w and 0 <= q[1] < h):
                            continue
                        if px[q][3] != 255:
                            continue
                        steps.append(
                            abs(
                                palette.luminance(px[q][:3])
                                - palette.luminance(px[x, y][:3])
                            )
                        )
                    if not steps:
                        continue
                    touching += 1
                    dissolved += max(steps) < self.WEAK
                with self.subTest(faction=fac.key, pose=pose.name):
                    self.assertLessEqual(dissolved / touching, 0.25)

    def _blade_pixels(self, model) -> set:
        """The screen pixels of the main rotor's blades — the `rotor` voxels
        at the model's top layer, through the renderer's own projection."""
        anchors = {v: voxel_project(v) for v in model.vox}
        minx = min(a[0] for a in anchors.values()) - 1
        miny = min(a[1] for a in anchors.values()) - 1
        top = max(v[2] for v in model.vox)
        out = set()
        for v, mat in model.vox.items():
            if mat != "rotor" or v[2] != top:
                continue
            sx, sy = anchors[v][0] - minx, anchors[v][1] - miny
            for j in range(2):
                for i in range(1 - j, 3 + j):
                    out.add((sx + i, sy + j))
        return out


class BoardScaleEdge(unittest.TestCase):
    """The unit's edge has to survive the board, which keeps one pixel in four.

    The game draws the 64px cell onto a 16px grid with nearest filtering, so
    three of every four source pixels are never sampled. Round 10 answered
    that by making the contour ONE LOGICAL PIXEL — a 4px band on the lit edges
    — and the answer worked: 74-76% of what the board drew on a boundary was
    S0. It also cost 34.5% of every unit's pixels, which is the interior the
    sel-out rewrite got back (see docs/outlines.md).

    A 1px outline cannot win that same reading and does not try: 19-27% of the
    board's boundary lands on S0 now. What the reading becomes is the claim
    selective outlining actually makes — the edge is a VALUE BREAK, dark away
    from the sun and light into it, and the board sees the break either way.
    Measured as the share of board-sampled boundary pixels whose value is
    outside the sprite's own interquartile band: 75.1-78.9% at the four
    phases, against 81.4-87.0% for the band it replaces. That is the
    legibility round 10 bought, carried by two tones instead of one, and the
    terrain ceiling is what makes the light half of it safe: no tile may reach
    the band this sheet's lit planes live in.
    """

    MIN_BOARD_BREAK = 0.70
    SCALE = 4

    def _board_boundary(self, sprite, phase: int) -> tuple[int, int]:
        """(pixels that read as an edge, boundary pixels) of the sprite as the
        board samples it: every SCALE-th pixel, offset by `phase`."""
        img = sprite.image
        px = img.load()
        values = [
            terrain.luminance(px[x, y][:3])
            for y in range(img.height)
            for x in range(img.width)
            if px[x, y][3] == 255
        ]
        lo, _, hi = statistics.quantiles(values, n=4)
        cells = {}
        for y in range(phase, img.height, self.SCALE):
            for x in range(phase, img.width, self.SCALE):
                cells[(x // self.SCALE, y // self.SCALE)] = (
                    px[x, y][3] == 255,
                    terrain.luminance(px[x, y][:3]),
                )
        breaks = boundary = 0
        for (bx, by), (solid, value) in cells.items():
            if not solid:
                continue
            beside = ((bx - 1, by), (bx + 1, by), (bx, by - 1), (bx, by + 1))
            if all(cells.get(n, (False, 0.0))[0] for n in beside):
                continue
            boundary += 1
            breaks += value <= lo or value >= hi
        return breaks, boundary

    # The copters' rotor is the one part of the sheet that is drawn as a
    # skeleton rather than as a solid, so it is the one that can strand a
    # texel: a blade tip one voxel across is exactly 4 atlas px, one rung-1
    # texel, and the sample either drops it or leaves it floating clear of
    # the aircraft — the disc read as speckle instead of an arc (b_copter
    # pose B and MOVE_B texel (9, 10) before the tips were widened). The
    # whole roster is clean of lone texels as of 2026-08-25; this is scoped
    # to the two units whose thin geometry makes it a live risk.
    LONE_TEXEL_UNITS = ("b_copter", "t_copter")

    def test_no_pose_strands_a_lone_texel_at_rung_1(self):
        """Every texel the board paints for a copter, in every pose and
        livery, touches another one of that copter's texels. Read without
        the cast shadow, so a tip is never rescued by the ground."""
        for uid in self.LONE_TEXEL_UNITS:
            for fac in FACTIONS:
                for pose in Pose:
                    px = (
                        pose_cell(uid, fac, pose, shadow=False)
                        .resize(RUNG_1_CELL, Image.NEAREST)
                        .load()
                    )
                    w, h = RUNG_1_CELL
                    on = {
                        (x, y) for y in range(h) for x in range(w) if px[x, y][3] > 128
                    }
                    lone = {
                        (x, y)
                        for x, y in on
                        if not any(
                            (x + dx, y + dy) in on
                            for dx in (-1, 0, 1)
                            for dy in (-1, 0, 1)
                            if (dx, dy) != (0, 0)
                        )
                    }
                    with self.subTest(unit=uid, faction=fac.key, pose=pose.name):
                        self.assertEqual(lone, set())

    def test_the_board_lands_on_the_edge_at_every_phase(self):
        for phase in range(self.SCALE):
            breaks = boundary = 0
            for fac in FACTIONS:
                for uid in ATLAS_ORDER:
                    found, total = self._board_boundary(
                        render_indexed(build_model(uid), fac), phase
                    )
                    breaks += found
                    boundary += total
            with self.subTest(phase=phase):
                self.assertGreaterEqual(breaks / boundary, self.MIN_BOARD_BREAK)


class Silhouette(unittest.TestCase):
    """Units must be tellable apart by mass at board zoom (32px), where
    colour and greebling are averaged away. Pairwise IoU of the 1-bit
    silhouettes is the review's gate: any pair above 0.85 is one shape
    wearing two labels.

    Rung 2 is not the zoomed-out board, though, and the rung it is not is
    where a player picks a unit off a full map: rung 1 draws the same cell at
    16x24, one source pixel in four, and a pair that separates on 32x48 can
    still be one blob there. Read at rung 1 on 2026-08-24 the armour cluster
    was a clone family the rung-2 gate could not see — tank/apc 0.810,
    tank/artillery 0.800, artillery/apc 0.782, all of them comfortably under
    the 0.85 bar above. The second reading below holds that rung at 0.78,
    which is where the roster's next-closest pairs already sat (tank/md_tank
    0.750, recon/cruiser 0.747): the bar is the field, not a target.
    """

    # Named debt, not tolerance: a pair listed here fails the gate and is
    # asserted to keep failing, so fixing one is a visible diff. The mass-table
    # milestone (2026-08-14) emptied the original five clone pairs; adding a
    # pair back is a regression.
    KNOWN_CLONES: frozenset[frozenset[str]] = frozenset()

    # Source pixels per screen pixel at the two rungs a match is played at,
    # and the bar each one holds.
    RUNG_2, RUNG_2_BAR = 2, 0.85
    RUNG_1, RUNG_1_BAR = 4, 0.78

    def _silhouette(self, uid: str, ratio: int = 2) -> set[tuple[int, int]]:
        cell = pose_cell(uid, faction_by_key("neutral")).convert("RGBA")
        w, h = atlas.CELL_W // ratio, atlas.CELL_H // ratio
        small = cell.resize((w, h), Image.NEAREST)
        px = small.load()
        return {(x, y) for y in range(h) for x in range(w) if px[x, y][3] > 200}

    def _pairs(self, ratio: int):
        shapes = {uid: self._silhouette(uid, ratio) for uid in ATLAS_ORDER}
        for i, a in enumerate(ATLAS_ORDER):
            for b in ATLAS_ORDER[i + 1 :]:
                inter = len(shapes[a] & shapes[b])
                union = len(shapes[a] | shapes[b])
                yield a, b, (inter / union if union else 1.0)

    def test_no_two_units_share_a_silhouette(self):
        for a, b, iou in self._pairs(self.RUNG_2):
            pair = frozenset((a, b))
            with self.subTest(pair=(a, b)):
                if pair in self.KNOWN_CLONES:
                    self.assertGreater(iou, self.RUNG_2_BAR)  # debt still real
                else:
                    self.assertLessEqual(iou, self.RUNG_2_BAR)

    def test_no_two_units_share_a_silhouette_zoomed_out(self):
        for a, b, iou in self._pairs(self.RUNG_1):
            pair = frozenset((a, b))
            with self.subTest(pair=(a, b)):
                if pair in self.KNOWN_CLONES:
                    self.assertGreater(iou, self.RUNG_1_BAR)  # debt still real
                else:
                    self.assertLessEqual(iou, self.RUNG_1_BAR)


if __name__ == "__main__":
    unittest.main()
