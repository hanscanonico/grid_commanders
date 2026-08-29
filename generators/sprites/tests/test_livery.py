"""Contract tests for the indexed unit palette and the team colour in it.

Ramp membership, the colour ceiling, no isolated pixel, no partial alpha —
and the faction rows telling each other apart as armies.
"""

from __future__ import annotations

import statistics
import unittest

from spritegen import atlas, palette, terrain
from spritegen.palette import (
    FACTIONS,
    GUNMETAL_RAMP,
    MID_CONTOUR,
    MID_FACTION,
    OUTLINE_HEAVY,
    OUTLINE_RIM,
    RAMPS,
    S_BODY,
    faction_by_key,
)
from spritegen.units import ATLAS_ORDER, Pose, build_model
from spritegen.voxel import render_indexed

from pixel_helpers import (
    faction_pixels,
    hue,
    hue_gap,
    pose_cell,
    saturation,
    units_sheet,
)


class Livery(unittest.TestCase):
    """Team colour as a palette slot, not a paint dip.

    The livery used to be a blend — the faction hue pulled toward a chassis
    grey — which is what left every faction body at half its token's
    luminance (sprite fix spec round 4, section 3). It is a ramp slot now,
    and S3 IS the token, so these pin membership rather than a blend ratio.
    """

    def test_team_pixels_come_out_of_the_factions_own_ramp(self):
        red = faction_by_key("red")
        ramp = set(RAMPS[red.key])
        for uid in ("tank", "md_tank", "apc", "fighter", "battleship"):
            with self.subTest(unit=uid):
                sprite = render_indexed(build_model(uid), red)
                px = sprite.image.load()
                worn = [
                    px[x, y][:3]
                    for y in range(sprite.image.height)
                    for x in range(sprite.image.width)
                    if sprite.mid(x, y) == MID_FACTION
                ]
                self.assertGreater(len(worn), 100)
                self.assertEqual(set(worn) - ramp, set())

    def test_the_body_slot_is_the_design_system_token(self):
        # Iron and neutral are authored off-token on purpose — Iron's token
        # is its shadow plane, neutral's khaki is a separation choice.
        for key in ("meridian", "aurora", "verdant"):
            with self.subTest(faction=key):
                slot, theme = RAMPS[key][S_BODY], faction_by_key(key).body
                # the spec's hex and the game's FactionTheme are the same
                # colour written twice; a rounding step apart is not drift
                self.assertLessEqual(max(abs(a - b) for a, b in zip(slot, theme)), 4)

    def test_every_ramp_climbs_in_readable_steps(self):
        for key, ramp in RAMPS.items():
            with self.subTest(ramp=key):
                lums = [palette.luminance(c) for c in ramp]
                self.assertEqual(lums, sorted(lums))
                gaps = [b - a for a, b in zip(lums, lums[1:])]
                self.assertGreater(min(gaps), 12.0)

    def test_property_buildings_are_mostly_neutral_masonry(self):
        red, blue = faction_by_key("red"), faction_by_key("blue")
        for bid in sorted(terrain.PROPERTY):
            with self.subTest(building=bid):
                cell = atlas.building_cell(bid, red).convert("RGBA")
                alpha = cell.getchannel("A").load()
                opaque = sum(
                    1
                    for y in range(cell.height)
                    for x in range(cell.width)
                    if alpha[x, y] > 200
                )
                tinted = len(faction_pixels(cell, atlas.building_cell(bid, blue)))
                self.assertGreater(tinted, 0)  # roofs/caps are owned
                self.assertLess(tinted, opaque * 0.5)  # the rest is concrete


class RampShape(unittest.TestCase):
    """The ramps are lit, not dimmed (`docs/ramps.md`).

    A ramp typed out as six literal hexes drifts into one hue at six
    brightnesses; these pin the three things `palette.build_ramp` adds on
    top of the authored value ladder — a mid-ramp chroma peak, shadow steps
    sitting in the coloured `AMBIENT` sky, a hue that turns across the ramp
    — so that a slide back to a value-only ramp is a failure rather than a
    diff nobody reads. Every shipped ramp before this shaping violated at
    least one of them.
    """

    ALL_RAMPS = dict(RAMPS, gunmetal=GUNMETAL_RAMP)
    # How far a shadow step has to rotate toward AMBIENT before the rotation
    # is doing any work: the value-only ramps managed 0-6 degrees, which is
    # rounding. Capped by how far the base sits from the sky in the first
    # place — aurora is already on that hue and has nowhere to go.
    MIN_SKY_PULL = 8.0
    # The same, at the light end, toward the sun. Small: neutral's khaki is
    # nearly the sun hue already, so it has the least room to turn.
    MIN_SUN_TURN = 4.0
    # Under this luminance a rung is two or three quantisation steps wide
    # and cannot carry a hue at all (iron's S0 is L7).
    HUE_FLOOR = 12.0

    def test_chroma_peaks_mid_ramp_and_collapses_at_the_rim(self):
        for key, ramp in self.ALL_RAMPS.items():
            with self.subTest(ramp=key):
                sats = [saturation(c) for c in ramp]
                body = sats[S_BODY]
                self.assertIn(sats.index(max(sats)), (1, 2), "peak is mid-ramp")
                # a real lift over the body slot, not a rounding one
                self.assertGreater(max(sats[1], sats[2]), body * 1.05)
                # the rim is light rather than paint
                self.assertLess(sats[5], body * 0.6)
                # and the dark end keeps more chroma than the light end
                self.assertGreater(sats[0], sats[5])

    def test_the_shadow_steps_sit_in_the_ambient_sky(self):
        sky = hue(palette.AMBIENT)
        for key, ramp in self.ALL_RAMPS.items():
            with self.subTest(ramp=key):
                want = max(0.0, hue_gap(ramp[S_BODY], sky) - self.MIN_SKY_PULL)
                for slot in (0, 1):
                    if palette.luminance(ramp[slot]) < self.HUE_FLOOR:
                        continue
                    self.assertLessEqual(hue_gap(ramp[slot], sky), want + 0.5)

    def test_the_rim_step_turns_away_toward_the_sun(self):
        for key, ramp in self.ALL_RAMPS.items():
            with self.subTest(ramp=key):
                turn = hue_gap(ramp[5], hue(ramp[S_BODY]))
                self.assertGreaterEqual(turn, self.MIN_SUN_TURN)
                # toward the sun means away from the sky it came from
                sky = hue(palette.AMBIENT)
                self.assertGreater(
                    hue_gap(ramp[5], sky), hue_gap(ramp[S_BODY], sky) - 0.5
                )

    def test_the_builder_hits_the_authored_value_ladder(self):
        # `_at_luminance` is what lets the chroma move without moving the
        # value structure every livery gate measures.
        ladder = (18.0, 55.0, 90.0, 120.0, 160.0, 210.0)
        for base in ((216, 74, 60), (60, 100, 216), (121, 131, 141), (255, 8, 0)):
            with self.subTest(base=base):
                built = palette.build_ramp(base, ladder)
                self.assertEqual(len(built), 6)
                for want, got in zip(ladder, built):
                    self.assertAlmostEqual(palette.luminance(got), want, delta=0.6)

    def test_the_builder_is_a_pure_function_of_the_base(self):
        ladder = (18.0, 55.0, 90.0, 120.0, 160.0, 210.0)
        base = (44, 134, 54)
        self.assertEqual(
            palette.build_ramp(base, ladder), palette.build_ramp(base, ladder)
        )
        self.assertNotEqual(palette.build_ramp((134, 44, 54), ladder), (0,) * 6)


class RowSeparation(unittest.TestCase):
    """Faction rows must be tellable apart as *armies*, not just per-pixel.

    The 2026-08-13 sprite review's blocker: iron's theme hue is a step off
    the chassis grey, so a straight tint left the iron row ~10 RGB units
    from the neutral row — and from any faction's acted grey-out. Iron's
    inverted scheme (light-steel hull, dark slate accents) is what these
    numbers pin.

    Measured over the pixels the material map calls the faction's — the
    gunmetal, the accents and the shadow are identical on every row, so an
    all-pixel mean drags every army toward every other one. That dilution is
    what the old shadow exclusion was patching around; the material id says
    it exactly.
    """

    def _row_mean(self, key: str) -> tuple[float, float, float]:
        fac = faction_by_key(key)
        tot = [0, 0, 0]
        n = 0
        for uid in ATLAS_ORDER:
            sprite = render_indexed(build_model(uid), fac)
            px = sprite.image.load()
            for y in range(sprite.image.height):
                for x in range(sprite.image.width):
                    if sprite.mid(x, y) != MID_FACTION:
                        continue
                    c = px[x, y]
                    tot[0] += c[0]
                    tot[1] += c[1]
                    tot[2] += c[2]
                    n += 1
        return (tot[0] / n, tot[1] / n, tot[2] / n)

    def _dist(self, a, b) -> float:
        return sum((ai - bi) ** 2 for ai, bi in zip(a, b)) ** 0.5

    def test_iron_row_is_far_from_neutral_row(self):
        # The shipped PixVoxel art held ~100; the pre-review generator sat
        # at ~10, which is indistinguishable. Require a wide margin.
        self.assertGreater(
            self._dist(self._row_mean("neutral"), self._row_mean("iron")), 60.0
        )

    def test_every_faction_pair_separates(self):
        means = [self._row_mean(f.key) for f in FACTIONS]
        for i in range(len(FACTIONS)):
            for j in range(i + 1, len(FACTIONS)):
                with self.subTest(pair=(FACTIONS[i].key, FACTIONS[j].key)):
                    self.assertGreater(self._dist(means[i], means[j]), 30.0)

    def _cell_mean(self, key: str) -> tuple[float, float, float]:
        """The whole army as composed — gunmetal, accents and all — which is
        what the board actually shows."""
        fac = faction_by_key(key)
        tot = [0, 0, 0]
        n = 0
        for uid in ATLAS_ORDER:
            cell = pose_cell(uid, fac).convert("RGBA")
            px = cell.load()
            for y in range(cell.height):
                for x in range(cell.width):
                    r, g, b, a = px[x, y]
                    if a != 255 or (r, g, b) == (16, 18, 24):  # the dither
                        continue
                    tot[0] += r
                    tot[1] += g
                    tot[2] += b
                    n += 1
        return (tot[0] / n, tot[1] / n, tot[2] / n)

    def test_composed_rows_separate_too(self):
        """The faction-pixel measurement above is the honest one, but it can
        only be honest about the pixels it counts: the shared gunmetal grew
        with the indexed ramps, so a row's composed mean sits closer to its
        neighbours' than it did (neutral-iron 61.6 before this palette, 43.1
        after; iron-verdant 87.2 -> 40.3). That is the dilution, not the
        armies converging — but it is what a player sees, so it is gated
        rather than left to the faction-pixel figure alone.

        Round 10 diluted it again, and the bar moved with the measurement
        rather than the art moving to the bar: a contour one LOGICAL pixel
        thick spent four times the sprite area on S0, and every row's S0 is
        near-black, so every composed mean walked toward black together —
        closest pair 37.6 -> 32.2, and every pair fell by 13-14%. Nothing
        about the rows changed; the outline got thicker on all five.

        Round 11 gave it back by spending a pixel instead of a band (see
        docs/outlines.md): the closest pair is 45.2 now, against 34.6 under
        the band. The bar is still the faction-pixel bar above, which is the
        floor this diluted figure may never sink below.
        """
        means = {f.key: self._cell_mean(f.key) for f in FACTIONS}
        keys = list(means)
        for i in range(len(keys)):
            for j in range(i + 1, len(keys)):
                with self.subTest(pair=(keys[i], keys[j])):
                    self.assertGreater(self._dist(means[keys[i]], means[keys[j]]), 30.0)

    def test_faction_pixels_keep_their_chroma(self):
        # Review measurement: the red row's saturation p90 was 0.53 against
        # the shipped art's 0.93 — "averaged down to 32px a red tank is a
        # muddy brown-grey". The livery may desaturate the hull, but the
        # team-coloured area as a whole has to stay loud.
        red, blue = faction_by_key("red"), faction_by_key("blue")
        for uid in ("tank", "md_tank", "apc", "battleship"):
            with self.subTest(unit=uid):
                px = faction_pixels(pose_cell(uid, red), pose_cell(uid, blue))
                sats = sorted(saturation(c) for c in px)
                self.assertGreater(statistics.median(sats), 0.45)


class IndexedPalette(unittest.TestCase):
    """The build gates from the sprite fix spec, section 9.

    They fail the atlas rather than the review: the palette defect the spec
    measured (1,076-1,314 colours per row, 129-294 per sprite, four greys
    within 3/channel of each other) is invisible in a contact sheet and
    obvious in a histogram.
    """

    SHADOW = (16, 18, 24)  # the deliberate contact/altitude shadow
    FOAM = (226, 240, 250)

    def _pixels(self, img) -> list[tuple[int, int, int, int]]:
        raw = img.convert("RGBA").tobytes()
        return [tuple(raw[i : i + 4]) for i in range(0, len(raw), 4)]

    def _opaque(self, cell) -> list[tuple[int, int, int]]:
        return [p[:3] for p in self._pixels(cell) if p[3] == 255]

    def test_no_sprite_spends_more_than_24_colours(self):
        for fac in FACTIONS:
            for uid in ATLAS_ORDER:
                with self.subTest(faction=fac.key, unit=uid):
                    self.assertLessEqual(
                        len(set(self._opaque(pose_cell(uid, fac)))), 24
                    )

    def test_the_atlas_carries_no_semi_transparent_pixel(self):
        # 9.8% of the shipped atlas was partial alpha — halos at cut-in.
        for pose in Pose:
            with self.subTest(pose=pose.name):
                alpha = {p[3] for p in self._pixels(units_sheet(pose))}
                self.assertEqual(alpha - {0, 255}, set())

    def test_no_plane_touches_the_ground_on_the_shaded_side(self):
        """The ground-facing silhouette is S0's, absolutely — round-9
        precedence, kept through the switch to 1px outlines.

        What changed is the SIDES it is claimed on. The band claimed all four
        and ate four pixels of plane doing it; the G-buffer outline claims the
        two that face away from the sun (down and right), one pixel wide, and
        answers for the other two with light instead
        (`test_the_sunward_edge_is_lit_rather_than_outlined`). So the rule the
        apc's dotted roof line needed is still absolute where a plane meets
        the ground: 0 violations over both poses of all 18 units in all five
        rows, the same reading the band produced.

        Orthogonal, not diagonal: a 1px line is connected through its sides,
        and a stair's inner corner touching the tile at a point is already
        fenced by the two line pixels beside it.
        """
        for fac in FACTIONS:
            for uid in ATLAS_ORDER:
                for pose in Pose:
                    sprite = render_indexed(build_model(uid, pose), fac)
                    img = sprite.image
                    px = img.load()
                    w, h = img.size

                    def opaque(x, y, px=px, w=w, h=h):
                        return 0 <= x < w and 0 <= y < h and px[x, y][3] == 255

                    naked = [
                        (x, y)
                        for y in range(h)
                        for x in range(w)
                        if opaque(x, y)
                        and sprite.mid(x, y) != MID_CONTOUR
                        and (not opaque(x, y + 1) or not opaque(x + 1, y))
                    ]
                    with self.subTest(faction=fac.key, unit=uid, pose=pose.name):
                        self.assertEqual(naked, [])

    # How much of the sunward silhouette may still be drawn dark, per outline
    # grade. The light grade is the number the sel-out rewrite bought and is
    # unmoved (7.07%); the heavy grade is neutral's and Iron's, where a lit
    # line that lands in the ground's own value band gives way to the contour
    # — 63.2% of it does, and the 37% that stays light is the rim flash those
    # two rows key off (`GroundContrast`, docs/outlines.md). The rim grade
    # spends the band UPWARD instead, so it is held to the light grade's
    # figure: 6.72% of aurora's and verdant's sunward silhouette is dark,
    # against meridian's 7.19%.
    MAX_SUNWARD_DARK = {
        palette.OUTLINE_LIGHT: 0.10,
        OUTLINE_RIM: 0.10,
        OUTLINE_HEAVY: 0.70,
    }

    def test_the_sunward_edge_is_lit_rather_than_outlined(self):
        """Selective outlining: the sun side of the silhouette LIGHTENS.

        A pixel whose only break is up or left steps up its own ramp instead
        of going black, so the two sides the light comes from read as an edge
        without spending the plane behind them. Measured over both poses of
        all 18 units, 7.19% of meridian's are still S0 against 100% under the
        band — and the remainder is not slack: it is the far side of a
        self-overlap (a hull passing behind a turret is a dark line wherever
        it lies) and the handful the despeckle settles.

        Both other grades are the same rule with one more question asked of it
        (`palette.clears_the_ground`), so they are measured on the same
        reading rather than exempted from it: neutral and Iron light the
        sunward edge wherever the lift clears the ground's band and take the
        contour where it cannot, and aurora and verdant climb to the rim
        instead — which spends no more of the edge on S0 than meridian does.
        """
        for grade in (palette.OUTLINE_LIGHT, OUTLINE_RIM, OUTLINE_HEAVY):
            with self.subTest(grade=grade):
                dark, total = self._sunward(grade)
                self.assertLess(dark / total, self.MAX_SUNWARD_DARK[grade])

    def _sunward(self, grade: int) -> tuple[int, int]:
        """(dark, all) sunward silhouette pixels of the rows wearing `grade`."""
        dark = total = 0
        for fac in FACTIONS:
            if fac.outline != grade:
                continue
            for uid in ATLAS_ORDER:
                for pose in Pose:
                    sprite = render_indexed(build_model(uid, pose), fac)
                    img = sprite.image
                    px = img.load()
                    w, h = img.size

                    def opaque(x, y, px=px, w=w, h=h):
                        return 0 <= x < w and 0 <= y < h and px[x, y][3] == 255

                    for y in range(h):
                        for x in range(w):
                            if not opaque(x, y):
                                continue
                            if not opaque(x, y + 1) or not opaque(x + 1, y):
                                continue
                            if opaque(x, y - 1) and opaque(x - 1, y):
                                continue
                            total += 1
                            dark += sprite.mid(x, y) == MID_CONTOUR
        return dark, total

    # What S0 may cost, per outline grade: (worst single sprite, whole grade).
    # The light grade is round 11's bill — 24.22% on meridian's b_copter frame
    # B and 14.22% over its row. The heavy grade pays for its ground contour
    # out of the same budget and lands at 30.76% (neutral's b_copter frame B)
    # and 17.35%, both well under the band's 53.1% and 34.5%. The rim grade
    # buys its ground contrast UPWARD and so is held to the light grade's
    # budget: 24.67% (aurora's b_copter frame B; verdant's is 24.37%) and
    # 14.28%. The copters'
    # frame B stays the worst sprite through the 2026-08-24 rotor tick, and
    # moved a fifth of a point when it landed.
    MAX_CONTOUR = {
        palette.OUTLINE_LIGHT: (0.28, 0.15),
        OUTLINE_RIM: (0.28, 0.15),
        OUTLINE_HEAVY: (0.32, 0.20),
    }

    def test_the_outline_costs_a_pixel_and_not_a_band(self):
        """The line is one pixel: what it does not take is the picture.

        `CONTOUR_WEIGHT`'s band spent 34.5% of every unit's own pixels on S0
        and 53.1% on the worst sprite (b_copter's frame B, whose rotor is a
        1px lattice and so nearly all boundary). The G-buffer outline spends
        14.22% and 24.22% on the row wearing the light grade, 14.28% and
        24.67% on the two wearing the rim grade, and 17.35% and 30.76% on the
        two that wear the heavy one. That difference is the faction livery,
        the fittings and the plane structure the band was eating, and it is
        measured here so a future pass cannot quietly grow a band back —
        including through the two ground-aware grades, which is why every
        grade is budgeted rather than exempted.
        """
        for grade in (palette.OUTLINE_LIGHT, OUTLINE_RIM, OUTLINE_HEAVY):
            worst = 0.0
            dark = total = 0
            for fac in FACTIONS:
                if fac.outline != grade:
                    continue
                for uid in ATLAS_ORDER:
                    for pose in Pose:
                        sprite = render_indexed(build_model(uid, pose), fac)
                        img = sprite.image
                        px = img.load()
                        w, h = img.size
                        drawn = [
                            (x, y)
                            for y in range(h)
                            for x in range(w)
                            if px[x, y][3] == 255
                        ]
                        black = sum(
                            1 for x, y in drawn if sprite.mid(x, y) == MID_CONTOUR
                        )
                        total += len(drawn)
                        dark += black
                        worst = max(worst, black / len(drawn))
            max_worst, max_share = self.MAX_CONTOUR[grade]
            with self.subTest(grade=grade):
                self.assertLess(worst, max_worst)
                self.assertLess(dark / total, max_share)

    def test_no_isolated_pixel_outside_the_dither(self):
        """Spec item 10: a pixel differing from all four of its orthogonal
        neighbours is dirt at cut-in and shimmer at zoom-out. The foam is
        the intentional dither, and the cast shadow thins to a pixel at the
        ends of its ellipse; both are exempt by colour."""
        intentional = {self.SHADOW, self.FOAM}
        for fac in FACTIONS:
            for uid in ATLAS_ORDER:
                cell = pose_cell(uid, fac).convert("RGBA")
                px = cell.load()
                w, h = cell.size
                stray = []
                for y in range(1, h - 1):
                    for x in range(1, w - 1):
                        here = px[x, y]
                        if here[3] != 255 or here[:3] in intentional:
                            continue
                        neigh = [
                            px[x - 1, y],
                            px[x + 1, y],
                            px[x, y - 1],
                            px[x, y + 1],
                        ]
                        if any(
                            n[3] != 255 or n[:3] in intentional for n in neigh
                        ) or any(n[:3] == here[:3] for n in neigh):
                            continue
                        stray.append((x, y))
                with self.subTest(faction=fac.key, unit=uid):
                    self.assertEqual(stray, [])

    # Which row owns the bright band was pinned here as a ratio against one
    # measured moment, which is what let iron come back as the loudest row
    # (round 6). It is one gate now and it is an ordering:
    # `UnitBandCoverage.test_no_row_out_lights_the_chromatic_band`. Pinning a
    # ramp SLOT instead is the rejected alternative — Iron's mid slots are
    # brighter than the chromatic ones by design, which is the inverted
    # identity itself, so only the pixels a model actually spends can say
    # which row reads loudest.

    def test_the_contour_is_the_factions_own_darkest_slot(self):
        """Not a universal black stuck on after tinting — the shipped sheets
        carried #101218 exactly 1,236 times in all five rows."""
        for fac in FACTIONS:
            with self.subTest(faction=fac.key):
                sprite = render_indexed(build_model("tank", 0), fac)
                px = sprite.image.load()
                contour = {
                    px[x, y][:3]
                    for y in range(sprite.image.height)
                    for x in range(sprite.image.width)
                    if sprite.mid(x, y) == 0 and px[x, y][3] == 255
                }
                self.assertIn(RAMPS[fac.key][0], contour)


if __name__ == "__main__":
    unittest.main()
