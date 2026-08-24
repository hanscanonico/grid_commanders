"""Contract tests for what the generator actually emits.

Everything here renders sprites and asserts properties of the resulting
pixels: the atlas sizes the game reads, byte-for-byte determinism, the
indexed unit palette (ramp membership, the colour ceiling, no isolated
pixel, no partial alpha), the terrain value band the units sit above,
neutral buildings under faction roofs, and the autotile connection masks.

Two `luminance` scales meet here and are qualified by module on purpose:
`terrain.luminance` is Rec. 709, the scale the terrain ceilings are stated
on, and `palette.luminance` is Rec. 601, the scale the ramps are built on.

Run with `.venv/bin/python -m unittest discover tests`.
"""

from __future__ import annotations

import cmath
import colorsys
import math
import statistics
import unittest
from unittest import mock
from collections import Counter

from PIL import Image

from spritegen import atlas, autotile, buildings, palette, terrain
from spritegen.autotile import E, N, S, W
from spritegen.gbuffer import project as voxel_project
from spritegen.palette import (
    FACTIONS,
    Faction,
    GROUND_BAND,
    GROUND_BREAK,
    GUNMETAL_RAMP,
    MID_CONTOUR,
    MID_FACTION,
    OUTLINE_HEAVY,
    RAMPS,
    S_BODY,
    faction_by_key,
)
from spritegen.terrain import (
    BUILDING_KEY_CEILING,
    CELL,
    GRASS,
    GRASS_DARK,
    SAND,
    SAND_DARK,
    PLAINS_SALT,
    ROAD,
    ROAD_DARK,
    TERRAIN_MEDIAN_CEILING,
    TERRAIN_VALUE_CEILING,
    TIMBER,
    WATER,
    WATER_DARK,
    WATER_LIGHT,
    WOODS_SALT,
)
from spritegen.units import ATLAS_ORDER, UNITS, Pose, build_model
from spritegen import voxel
from spritegen.voxel import (
    CAST,
    FOAM,
    _broad_flat_tops,
    _prop_contour,
    render,
    render_indexed,
)

ROAD_TONES = {ROAD, ROAD_DARK}
WATER_TONES = {WATER, WATER_DARK}
# Edge midpoints, in N, E, S, W order, of a 64px tile.
EDGE_PROBES = (
    (CELL // 2, 0),
    (CELL - 1, CELL // 2),
    (CELL // 2, CELL - 1),
    (0, CELL // 2),
)


def saturation(rgb: tuple[int, int, int]) -> float:
    hi, lo = max(rgb), min(rgb)
    return 0.0 if hi == 0 else (hi - lo) / hi


def hue(rgb: tuple[int, int, int]) -> float:
    """Hue in degrees; 0 for a grey, which has none."""
    return colorsys.rgb_to_hsv(*(v / 255.0 for v in rgb))[0] * 360.0


def hue_gap(rgb: tuple[int, int, int], target: float) -> float:
    """Shortest angle, in degrees, between a colour's hue and `target`."""
    return abs((hue(rgb) - target + 180.0) % 360.0 - 180.0)


def opaque_pixels(img) -> list[tuple[int, int, int]]:
    """Every solid pixel of a sprite or tile, colour only."""
    img = img.convert("RGBA")
    px = img.load()
    return [
        px[x, y][:3]
        for y in range(img.height)
        for x in range(img.width)
        if px[x, y][3] > 200
    ]


def _touches_transparency(px, w: int, h: int, x: int, y: int) -> bool:
    """Is this pixel on the silhouette? Diagonals and the frame edge count."""
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            nx, ny = x + dx, y + dy
            if not (0 <= nx < w and 0 <= ny < h) or px[nx, ny][3] != 255:
                return True
    return False


def share_above(pixels, level: float) -> float:
    """Fraction of `pixels` brighter than `level` — the ramp band measure."""
    return sum(1 for c in pixels if terrain.luminance(c) > level) / len(pixels)


def dominant(pixels) -> tuple[int, int, int]:
    return Counter(pixels).most_common(1)[0][0]


def faction_pixels(sprite_a, sprite_b) -> list[tuple[int, int, int]]:
    """Opaque pixels of `sprite_a` that carry team color — i.e. the ones that
    differ when the same sprite is rendered for another faction."""
    a, b = sprite_a.convert("RGBA"), sprite_b.convert("RGBA")
    pa, pb = a.load(), b.load()
    out = []
    for y in range(a.height):
        for x in range(a.width):
            if pa[x, y][3] > 200 and pa[x, y][:3] != pb[x, y][:3]:
                out.append(pa[x, y][:3])
    return out


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


class FigureSheet(unittest.TestCase):
    """units_atlas_figures.png: the board's army, minus the tile's shadow.

    The cut-ins draw the art at 1:1 over a ground plane of their own, with a
    contact shadow of their own under it, so the tile's would be a second
    shadow rather than the same one. What the sheet must never be is a second
    opinion on the ART: the figure a cut-in blows up has to be the figure the
    board shows.
    """

    def test_it_removes_shadow_pixels_and_changes_nothing_else(self):
        board = atlas.build_units_atlas().load()
        figures = atlas.build_units_atlas(shadow=False).load()
        removed = 0
        for y in range(len(FACTIONS) * atlas.CELL_H):
            for x in range(len(ATLAS_ORDER) * atlas.CELL_W):
                if board[x, y] == figures[x, y]:
                    continue
                # The only legal difference: an opaque shadow pixel is gone.
                self.assertEqual(figures[x, y][3], 0, f"repainted pixel at {x},{y}")
                self.assertEqual(board[x, y][3], 255, f"half-shadow at {x},{y}")
                removed += 1
        self.assertGreater(removed, 0)

    def test_every_unit_of_every_faction_loses_its_shadow(self):
        board = atlas.build_units_atlas()
        figures = atlas.build_units_atlas(shadow=False)
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
                    f"{uid} ({fac.key}) has no shadow to leave off",
                )

    def test_the_figure_sheet_is_reproducible(self):
        self.assertEqual(
            atlas.build_units_atlas(shadow=False).tobytes(),
            atlas.build_units_atlas(shadow=False).tobytes(),
        )


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


class ValueCeiling(unittest.TestCase):
    """The top of the ramp belongs to units.

    The 2026-08-17 fix spec measured the rule inverted: plains sat at median
    L174, road L183 and shoal L202 while unit pixels top out at L145-165 at
    the 95th percentile, so the ground out-keyed 95% of every army on the
    board and property highlights out-keyed them by ~90L. These are the three
    numbers that hold it the right way up.
    """

    # Highlights that may cross into the unit band: a lit window, a windsock.
    # Units are held to carrying 3% of their pixels above the building
    # ceiling, so a building glinting at a third of that cannot out-key one.
    BUILDING_GLINT_SHARE = 0.01
    TERRAIN_HIGHLIGHT_SHARE = 0.05
    # Round 6 measured the band the other buildings' pixels sit in rather than
    # their median: the port put 13.1% of its pixels above the terrain ceiling,
    # the HQ 7.2% and the city 6.0%, against 0% for every non-property tile.
    # What may stay there is a lit window and a pane of glazing, which is what
    # this budget is the size of — the masonry itself is held to none of it,
    # one test below, where the unowned row has neither.
    PROPERTY_GLAZING_SHARE = 0.02
    # Round 7 measured the other half of that finding: holding the top 5% of a
    # property under L175 said nothing about where the MASS of a wall sat, and
    # it sat at L150-164 lit — exactly the band every faction's S4 top slot
    # occupies (L135-156), so a unit standing on a property had its own lit
    # planes to read against a wall of the same value. This bounds the lit half
    # of a property, which is the wall and roof area a silhouette is actually
    # seen against: L107-138 before the masonry ladder stepped down a rung,
    # L70-109 after (re-measured 2026-08-23, with the faction-read pass).
    PROPERTY_MASS_CEILING = 120.0

    def _tiles(self):
        for tid in terrain.TERRAIN_ORDER:
            for fac in FACTIONS:
                yield tid, fac, opaque_pixels(terrain.tile(tid, fac))
                if tid not in terrain.PROPERTY:
                    break

    def test_no_tile_medians_into_the_unit_band(self):
        for tid, fac, px in self._tiles():
            with self.subTest(tile=tid, faction=fac.key):
                median = statistics.median(terrain.luminance(c) for c in px)
                self.assertLess(median, TERRAIN_MEDIAN_CEILING)

    def test_grounds_keep_their_highlight_share_off_the_unit_band(self):
        # Ground only. A property cell has no ground left to hold — it is a
        # building and its shadow on transparent pixels — and how much of a
        # building may reach into the unit band is the building ceiling's
        # question, asked one test below on the same pixels.
        for tid, fac, px in self._tiles():
            if tid in terrain.PROPERTY:
                continue
            with self.subTest(tile=tid, faction=fac.key):
                share = share_above(px, TERRAIN_VALUE_CEILING)
                self.assertLessEqual(share, self.TERRAIN_HIGHLIGHT_SHARE)

    def test_property_masonry_stays_out_of_the_units_band(self):
        # The unowned row carries no lit window and no glazing — every
        # hue-carrying material resolves onto the cool concrete rungs — so its
        # share of
        # the band is the buildings' own construction, and it is none.
        for bid in sorted(terrain.PROPERTY):
            with self.subTest(building=bid):
                px = opaque_pixels(atlas.building_cell(bid, FACTIONS[0]))
                self.assertEqual(share_above(px, TERRAIN_VALUE_CEILING), 0.0)

    def test_a_property_only_glazes_into_the_terrain_band(self):
        for bid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                with self.subTest(building=bid, faction=fac.key):
                    px = opaque_pixels(atlas.building_cell(bid, fac))
                    share = share_above(px, TERRAIN_VALUE_CEILING)
                    self.assertLessEqual(share, self.PROPERTY_GLAZING_SHARE)

    def test_the_wall_and_roof_mass_stays_under_the_slot_units_key_in(self):
        for bid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                with self.subTest(building=bid, faction=fac.key):
                    lums = sorted(
                        terrain.luminance(c)
                        for c in opaque_pixels(atlas.building_cell(bid, fac))
                    )
                    lit_half = lums[len(lums) // 2 :]
                    self.assertLess(
                        statistics.median(lit_half), self.PROPERTY_MASS_CEILING
                    )

    def test_property_buildings_only_glint_above_the_key_ceiling(self):
        for bid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                with self.subTest(building=bid, faction=fac.key):
                    px = opaque_pixels(atlas.building_cell(bid, fac))
                    share = share_above(px, BUILDING_KEY_CEILING)
                    self.assertLessEqual(share, self.BUILDING_GLINT_SHARE)

    def test_the_unit_sheet_still_out_keys_every_tile(self):
        units = sorted(
            terrain.luminance(c) for c in opaque_pixels(atlas.build_units_atlas())
        )
        top_of_ramp = units[int(len(units) * 0.99)]
        for tid, fac, px in self._tiles():
            with self.subTest(tile=tid, faction=fac.key):
                self.assertLess(max(terrain.luminance(c) for c in px), top_of_ramp)


class UnitBandCoverage(unittest.TestCase):
    """The other half of the value ceiling: units have to USE the band.

    `ValueCeiling` above keeps the ground out of L200+; the round-5 verdict
    measured that half the land group barely entered it (Meridian infantry
    0.9%, apc 0.9%, artillery 1.3% of pixels above L200 against the spec's
    3%), because the rim fired only on a model's single front corner. A band
    reserved for units that units do not stand in is a band nothing keys off.

    Measured over the unit's own pixels: the composed shadow and the foam are
    identical on every row and belong to the cell, not the army — the same
    exclusion `RowSeparation` and `tests/measure_livery.py` make.
    """

    BRIGHT_BAND = 200.0
    MIN_RIM_SHARE = 0.03
    # The band the rows are ordered on, and the three rows that own it.
    ROW_BAND = 160.0
    CHROMATIC = ("meridian", "aurora", "verdant")
    # How far over the widest chromatic row a row may sit. A percentage point
    # is a row a reader cannot pick out of a contact sheet; the two defects
    # this bound was written against were 12 pp (neutral, round 5) and 2.4 pp
    # (iron, round 6).
    ROW_BAND_TOLERANCE = 0.01
    # The spec's build gate, section 9. No unit is exempt: it was written
    # against a bomber at 46% and a b_copter at 50%, and a gate that names
    # its own violators is a note, not a gate.
    MIN_FACTION_SHARE = 0.55
    COMPOSED = {(16, 18, 24), (226, 240, 250)}  # cast shadow, waterline foam

    def _unit_pixels(self, cell):
        px = cell.convert("RGBA").load()
        return [
            (x, y, px[x, y][:3])
            for y in range(cell.height)
            for x in range(cell.width)
            if px[x, y][3] == 255 and px[x, y][:3] not in self.COMPOSED
        ]

    def _row_bright_shares(self) -> dict[str, float]:
        """Each row's share of the band above `ROW_BAND`, over its own pixels."""
        shares = {}
        for fac in FACTIONS:
            px = [
                c
                for uid in ATLAS_ORDER
                for _, _, c in self._unit_pixels(atlas.unit_cell(uid, fac))
            ]
            shares[fac.key] = share_above(px, self.ROW_BAND)
        return shares

    def test_every_unit_stands_in_the_band_reserved_for_it(self):
        for fac in FACTIONS:
            for uid in ATLAS_ORDER:
                px = self._unit_pixels(atlas.unit_cell(uid, fac))
                lit = sum(
                    1 for _, _, c in px if terrain.luminance(c) > self.BRIGHT_BAND
                )
                with self.subTest(faction=fac.key, unit=uid):
                    self.assertGreaterEqual(lit / len(px), self.MIN_RIM_SHARE)

    def test_every_unit_wears_its_team_on_most_of_itself(self):
        for uid in ATLAS_ORDER:
            for pose in Pose:
                red = atlas.unit_cell(uid, faction_by_key("red"), pose)
                blue = atlas.unit_cell(uid, faction_by_key("blue"), pose).convert(
                    "RGBA"
                )
                other = blue.load()
                px = self._unit_pixels(red)
                worn = sum(1 for x, y, c in px if other[x, y][:3] != c)
                with self.subTest(unit=uid, pose=pose.name):
                    self.assertGreaterEqual(worn / len(px), self.MIN_FACTION_SHARE)

    def test_the_unowned_row_is_never_the_loudest_one(self):
        """Neutral was 27% of its pixels above L160 — 4,280 of them its S4 top
        plane alone — against 7-8% for every faction, so the army nobody owns
        was the loudest thing on the sheet by four times.

        The bound is 'never the brightest row' rather than 'the dimmest row':
        neutral is a mid-value khaki because what separates it from Iron is
        HUE (`RowSeparation`, and the ramp's own comment), so a neutral
        authored down to the dimmest mean walks straight into the collapsed
        neutral/iron pair the 2026-08-13 review blocked on. That tension is
        measured, not asserted: the row means sit 64.8 apart against
        `RowSeparation`'s bar of 60, and darkening neutral's three mid slots
        by 15% takes the pair to 56.4 — under the bar. So neutral is still
        the brightest row by mean (109.8 against 93-103) and this gate says
        only that it no longer owns the bright band by four times. What the
        top plane may not do is sit in that band at all, which is the
        4,280-pixel half of the finding and is pinned first.

        Round 6 levelled the rows to within 0.15 pp of each other, so what
        decides this assertion is now 0.02 pp (neutral 15.58% against iron's
        15.60%). A flip is therefore not by itself an art defect: read it
        against `test_no_row_out_lights_the_chromatic_band`, which is where
        a row actually running away with the band shows up.

        Round 10 took the flip at that same hair's width, and round 11's 1px
        outline kept it while lifting every row about five points (the band
        was eating a third of every sprite): neutral 18.67% against verdant's
        18.66%, meridian and iron 18.63%, aurora 17.92%. Iron is no longer
        the row just under neutral, and none of that is a reader's
        difference — `ROW_BAND_TOLERANCE` is a whole percentage point. So
        the gate says what the paragraph above already argued it means: the
        unowned row may not OWN the band, `ROW_BAND_TOLERANCE` being the
        percentage point a reader cannot pick out of a contact sheet, and it
        is the sibling gate that catches a row running away with it.
        """
        self.assertLess(palette.luminance(RAMPS["neutral"][palette.S_TOP]), 160.0)
        shares = self._row_bright_shares()
        loudest_army = max(v for k, v in shares.items() if k != "neutral")
        self.assertLessEqual(shares["neutral"], loudest_army + self.ROW_BAND_TOLERANCE)

    def test_no_row_out_lights_the_chromatic_band(self):
        """The rows are held to an ORDER, not to a number.

        Round 5 pinned iron's bright share as a ratio against the chromatic
        rows' at one measured moment; the rim pass then lifted every row, and
        iron's light-steel S4 sat just under L160 while the chromatic S4s sat
        well under it, so iron's rims pushed mass over the line that theirs
        did not — 17.3% of iron's pixels above L160 against 14.0-14.9% for
        every other row, and the frozen number caught none of it.

        The chromatic three are the band's owners because their bodies are
        the design-system tokens themselves; neutral and iron are authored
        around them (khaki for hue separation, inverted for its near-black
        panels), so what they may never do is out-light the armies whose
        colour the band is for.
        """
        shares = self._row_bright_shares()
        ceiling = max(shares[k] for k in self.CHROMATIC) + self.ROW_BAND_TOLERANCE
        for key, share in shares.items():
            with self.subTest(faction=key):
                self.assertLessEqual(share, ceiling)


class GroundSeparation(unittest.TestCase):
    """Road, bridge and shoal were three tans within 19L of each other, two of
    them sharing a dominant colour outright — which is no movement-cost signal
    at all. They are now gravel, timber and sand, a value step and a hue apart.
    """

    MIN_SEPARATION = 18.0
    # The dry half of the shoal tile: below it the tile is water and foam.
    DRY_SAND = (0, 0, CELL, 40)

    def _grounds(self) -> dict[str, tuple[int, int, int]]:
        shoal = terrain.tile("shoal", FACTIONS[0]).crop(self.DRY_SAND)
        return {
            "road": dominant(opaque_pixels(terrain.tile("road", FACTIONS[0]))),
            "bridge": dominant(opaque_pixels(terrain.tile("bridge", FACTIONS[0]))),
            "shoal": dominant(opaque_pixels(shoal)),
        }

    def test_road_and_bridge_no_longer_share_a_colour(self):
        grounds = self._grounds()
        self.assertNotEqual(grounds["road"], grounds["bridge"])

    def test_the_three_grounds_stay_a_value_step_apart(self):
        grounds = self._grounds()
        for a, b in (("road", "bridge"), ("road", "shoal"), ("bridge", "shoal")):
            with self.subTest(pair=(a, b)):
                gap = abs(terrain.luminance(grounds[a]) - terrain.luminance(grounds[b]))
                self.assertGreaterEqual(gap, self.MIN_SEPARATION)

    # A share of the tile this big is a tone the ground READS as, not a fleck:
    # the field tone and the two clump tones clear it, a tuft or a wildflower
    # does not.
    FIELD_SHARE = 0.05

    def _plains_tones(self) -> list[tuple[int, int, int]]:
        """The tones an open field is made of, commonest first."""
        px = opaque_pixels(terrain.tile("plains", FACTIONS[0]))
        counts = Counter(px)
        return [c for c, n in counts.most_common() if n >= self.FIELD_SHARE * len(px)]

    def _plains_field_tone(self) -> tuple[int, int, int]:
        """The tone the OPEN field is, as against the clumps in it.

        Plains stopped being a one-tone ground on 2026-08-22: it is GRASS with
        a darker grass clumped over a third of it, so a single `dominant()`
        over the tile now returns whichever of the two happens to win the
        count. The measurement this test was always making — the tone a
        stretch of open grass reads as — is `dominant()` over the light half,
        and on a one-tone ground that is the same number it returned before.
        """
        px = opaque_pixels(terrain.tile("plains", FACTIONS[0]))
        mid = statistics.median(terrain.luminance(c) for c in px)
        return dominant([c for c in px if terrain.luminance(c) >= mid])

    def test_plains_reads_apart_from_the_ground_it_borders(self):
        grounds = self._grounds()
        # Grass carries a hue no other ground has, so colour distance is what
        # separates it from sand — and EVERY tone the field is made of has to
        # carry it, because the clumps are a third of the tile.
        for tone in self._plains_tones():
            for tid, ground in grounds.items():
                with self.subTest(against=tid, tone=tone):
                    gap = sum((a - b) ** 2 for a, b in zip(tone, ground)) ** 0.5
                    self.assertGreaterEqual(gap, 40.0)
        # Against gravel, the ground plains shares a board edge with most
        # often, the value step has to be real too or a 1:4 downsample averages
        # the two into one grey-green. The field tone carries that step; a
        # clump does not (L143 against gravel's L142, a colour break only) —
        # measured and left open in docs/plains_field.md.
        field = self._plains_field_tone()
        self.assertGreaterEqual(
            abs(terrain.luminance(field) - terrain.luminance(grounds["road"])), 15.0
        )


class TerrainPalette(unittest.TestCase):
    """A tile may not spend colours the way the pre-indexed units did.

    `IndexedPalette` holds units to 24 colours a sprite; nothing held the
    ground to anything, and the round-5 verdict found woods carrying 71.
    That is survivable at 64px and is exactly the drift that becomes visible
    when the tiles go to 128px, so it gets a ceiling now, while every tile
    passes it with headroom.
    """

    # 2026-08-23: the canopy and the massif came onto the projection, and
    # both stopped painting tones — a crown is five banded planes over the
    # plains plate and the massif is two shared ramps — so the widest nature
    # tile on the sheet now spends 37 where woods alone spent 77. The ceiling
    # comes down with them. It is a RATCHET, like the property one below: a
    # tile that needs more than this is painting where it should be banding.
    NATURE_CEILING = 48
    # A property tile is a building plus its one shadow tone. The shading
    # renderer spent a colour per lit pixel there — 204 on the aurora airport,
    # then 75 once the contour and dither rules (docs/terrain_outlines.md) cut
    # the worst of it. The properties pass brought the buildings onto the
    # indexed ramps, which is the debt that was left, and the ceiling comes
    # down with it: the widest tile on the sheet spends 24, so this is the
    # unit cap plus the shadow rather than a headroom figure. It is a
    # RATCHET — a change that needs more colours than this is spending them
    # somewhere a slot should be, so it comes down again with the
    # faction-read pass (2026-08-23): the unowned row is drawn out of one
    # family end to end and the widest tile now spends 23.
    PROPERTY_CEILING = 24

    def _colours(self, img) -> int:
        return len(set(opaque_pixels(img)))

    def test_nature_tiles_stay_under_the_colour_ceiling(self):
        for tid in terrain.TERRAIN_ORDER:
            if tid in terrain.PROPERTY:
                continue
            with self.subTest(tile=tid):
                self.assertLessEqual(
                    self._colours(terrain.tile(tid, FACTIONS[0])), self.NATURE_CEILING
                )

    def test_autotile_variants_stay_under_the_colour_ceiling(self):
        builders = (
            autotile.road_tile,
            autotile.river_tile,
            autotile.coast_tile,
            autotile.shoal_tile,
            autotile.woods_tile,
        )
        for builder in builders:
            for mask in range(16):
                with self.subTest(sheet=builder.__name__, mask=mask):
                    self.assertLessEqual(
                        self._colours(builder(mask)), self.NATURE_CEILING
                    )
        for ew in (True, False):
            with self.subTest(sheet="bridge", ew=ew):
                self.assertLessEqual(
                    self._colours(autotile.bridge_tile(ew)), self.NATURE_CEILING
                )

    def test_property_tiles_hold_their_recorded_ceiling(self):
        for tid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                with self.subTest(tile=tid, faction=fac.key):
                    self.assertLessEqual(
                        self._colours(terrain.tile(tid, fac)), self.PROPERTY_CEILING
                    )


class TileTexture(unittest.TestCase):
    """A tile may not spend its detail budget on per-pixel noise either.

    The colour ceiling above counts tones; this counts CHANGES, which is what
    a player actually sees at the board's 4:1 nearest downsample — a texture
    finer than the sample grid arrives as a different random pixel per frame
    of camera movement, not as texture. Measured as the share of pixels whose
    right-hand neighbour is a different colour.

    The woods tile was the outlier the reading exists for: 53.7% against
    19.9-27.5% for every other tile on the sheet, because a crown carried a
    per-pixel hash on its body tone and a 14% leaf speckle over it. The hash
    still rags the boundary between two bands — that is what keeps an arc from
    reading as a painted stripe — but it no longer makes tones, and the tile
    came in at 23.2%. The ceiling is set where the noisiest tile that was
    never a problem sits (coast at 29.7%) plus room to draw in.

    The de-shingling pass spent that room and no more: the wood is drawn in
    24 crowns rather than 22, its outline is hash-ragged and its bands carry
    a two-in-ten dapple, and it comes in at 33.5% (33.7% on the widest
    variant). 28.6% of that is the crowns themselves — the tile with the
    speckle and both rags switched off — so the decoration is 5 points of it.
    """

    HIGH_FREQUENCY_CEILING = 0.35

    def _changes(self, img) -> float:
        px = img.convert("RGB").load()
        w, h = img.size
        changed = sum(
            1 for y in range(h) for x in range(w - 1) if px[x, y] != px[x + 1, y]
        )
        return changed / (h * (w - 1))

    def test_no_nature_tile_is_mostly_colour_change(self):
        for tid in terrain.TERRAIN_ORDER:
            if tid in terrain.PROPERTY:
                continue
            with self.subTest(tile=tid):
                self.assertLessEqual(
                    self._changes(terrain.tile(tid, FACTIONS[0])),
                    self.HIGH_FREQUENCY_CEILING,
                )

    def test_no_autotile_variant_is_mostly_colour_change(self):
        builders = (
            autotile.road_tile,
            autotile.river_tile,
            autotile.coast_tile,
            autotile.shoal_tile,
            autotile.woods_tile,
        )
        for builder in builders:
            for mask in range(16):
                with self.subTest(sheet=builder.__name__, mask=mask):
                    self.assertLessEqual(
                        self._changes(builder(mask)), self.HIGH_FREQUENCY_CEILING
                    )


class PropOutline(unittest.TestCase):
    """The shaded path's edge and texture, held to one decision each.

    A neighbour-averaged contour spends one near-black per lit neighbourhood
    and a per-pixel dither spends one tone per amplitude, so a building came
    out of `voxel.render` carrying 200 colours no eye could name. The rules
    that replaced them are countable, and this is where they are counted —
    see docs/terrain_outlines.md.

    The buildings left this path in the properties pass (`PropertyPalette`
    below), so what is left on it is the reef rock: a small prop, whose
    contour is still one deliberate tone per material and whose tops are
    still too narrow to carry a texture. The dither's other half — that a
    plane broad enough DOES speckle — has no model left to state it on, and
    is stated by `DITHER_MIN_TOP_AREA` alone.
    """

    def _contour_ring(self, model, fac) -> set[tuple[int, int, int]]:
        """The pixels the outline pass adds, by difference."""
        lit = render(model, fac, outline=True).load()
        bare = render(model, fac, outline=False)
        bare_px = bare.load()
        return {
            lit[x, y][:3]
            for y in range(bare.height)
            for x in range(bare.width)
            if bare_px[x, y][3] == 0 and lit[x, y][3] == 255
        }

    def _props(self):
        for size in (2, 3, 4):
            yield f"reef rock {size}", buildings.rock_outcrop(size)

    def test_a_contour_pixel_is_a_materials_own_contour_tone(self):
        for name, model in self._props():
            for fac in FACTIONS:
                allowed = {_prop_contour(m, fac) for m in set(model.vox.values())}
                with self.subTest(prop=name, faction=fac.key):
                    self.assertTrue(self._contour_ring(model, fac))
                    self.assertLessEqual(self._contour_ring(model, fac), allowed)

    def test_the_contour_spends_no_more_tones_than_the_model_has_materials(self):
        for name, model in self._props():
            with self.subTest(prop=name):
                self.assertLessEqual(
                    len(self._contour_ring(model, FACTIONS[2])),
                    len(set(model.vox.values())),
                )

    def _undithered(self, model, fac):
        """The same render with the dither hash pinned above its threshold."""
        with mock.patch.object(voxel, "h01", lambda *_: 1.0):
            return opaque_pixels(render(model, fac, outline=False))

    def test_the_area_rule_reaches_the_picture_not_just_the_plane_finder(self):
        """A prop with no broad plane renders identically with the dither off.

        `_broad_flat_tops` agreeing with its own constant proves nothing if
        the renderer ignores it, so this compares pixels: pin the hash above
        the threshold, and a narrow-topped prop's picture must not move by a
        pixel.
        """
        fac = FACTIONS[2]
        for name, model in self._props():
            with self.subTest(prop=name):
                self.assertEqual(
                    opaque_pixels(render(model, fac, outline=False)),
                    self._undithered(model, fac),
                )

    def test_a_small_prop_carries_no_dither_at_all(self):
        for size in (2, 3):
            with self.subTest(size=size):
                self.assertEqual(
                    _broad_flat_tops(buildings.rock_outcrop(size).vox), set()
                )


class PropertyPalette(unittest.TestCase):
    """A building is drawn the way a unit is: slots, not shading arithmetic.

    The properties pass (2026-08-22) took the five buildings off `voxel.render`
    and onto `render_indexed`, out of the masonry / concrete / machinery ramps
    (`palette.PROPERTY_MATERIALS`), one band under the units
    (`voxel.BUILDING_TOP_SLOT`). What that bought is measured here: the two
    numbers a building was an outlier on, held to what a unit is held to.
    """

    # The unit cap, `IndexedPalette.test_no_sprite_spends_more_than_24_colours`,
    # now reached rather than approached: the shading path spent 61-74 colours
    # a building (204 before the contour and dither rules), and the widest
    # sprite on the sheet — the aurora airport, five ramps and four accents —
    # spends 23.
    SPRITE_CEILING = 24
    # The share of a sprite's own silhouette boundary drawn as the contour,
    # per outline grade, measured over all 18 units both poses:
    #
    #   light grade  units 0.579-0.696   buildings 0.650-0.743
    #   heavy grade  units 0.791-0.941   buildings 0.821-0.985
    #
    # Buildings sit a little over the units of their grade because a lot is a
    # flat plate — its whole sunward edge is one ground-facing step — and that
    # is the gap these bands allow. What they do not allow is the shading
    # path's figure, which was 1.000 on eleven of the twenty-five sprites: an
    # unconditional keyline, drawn as hard on the side the sun is on as on the
    # side it is not.
    BOUNDARY_DARK = {palette.OUTLINE_LIGHT: (0.50, 0.75), OUTLINE_HEAVY: (0.75, 0.99)}

    def _sprite(self, bid, fac):
        return render_indexed(
            buildings.model_for(bid, fac), fac, top_slot=voxel.BUILDING_TOP_SLOT
        )

    def test_every_building_is_drawn_by_the_indexed_renderer(self):
        for bid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                with self.subTest(building=bid, faction=fac.key):
                    model = buildings.model_for(bid, fac)
                    self.assertTrue(model.indexed)
                    # ...and what terrain composes is that renderer's picture
                    self.assertEqual(
                        opaque_pixels(render(model, fac)),
                        opaque_pixels(self._sprite(bid, fac).image),
                    )
        # the nature props are the shaded path's, and stay on it
        self.assertFalse(buildings.rock_outcrop(2).indexed)

    def test_no_building_spends_more_than_a_unit_does(self):
        for bid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                with self.subTest(building=bid, faction=fac.key):
                    colours = len(set(opaque_pixels(self._sprite(bid, fac).image)))
                    self.assertLessEqual(colours, self.SPRITE_CEILING)

    def test_the_boundary_is_a_break_rather_than_a_keyline(self):
        for bid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                sprite = self._sprite(bid, fac)
                img = sprite.image
                px = img.load()
                w, h = img.size
                edge = [
                    (x, y)
                    for y in range(h)
                    for x in range(w)
                    if px[x, y][3] == 255
                    and not all(
                        0 <= x + dx < w
                        and 0 <= y + dy < h
                        and px[x + dx, y + dy][3] == 255
                        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                    )
                ]
                dark = sum(1 for x, y in edge if sprite.mid(x, y) == MID_CONTOUR)
                lo, hi = self.BOUNDARY_DARK[fac.outline]
                with self.subTest(building=bid, faction=fac.key):
                    self.assertGreaterEqual(dark / len(edge), lo)
                    self.assertLessEqual(dark / len(edge), hi)

    def test_the_owner_reads_out_of_the_factions_own_ramp(self):
        for bid in sorted(terrain.PROPERTY):
            for fac in FACTIONS[1:]:  # the unowned row wears no faction pixel
                sprite = self._sprite(bid, fac)
                px = sprite.image.load()
                worn = [
                    px[x, y][:3]
                    for y in range(sprite.image.height)
                    for x in range(sprite.image.width)
                    if sprite.mid(x, y) == MID_FACTION
                ]
                with self.subTest(building=bid, faction=fac.key):
                    self.assertGreater(len(worn), 40)
                    self.assertEqual(set(worn) - set(RAMPS[fac.key]), set())

    def test_two_owners_of_the_same_building_are_tellable_apart(self):
        """The 1x reading, kept beside the board-scale one above.

        `RowSeparation` holds the armies apart but says nothing about the
        board's flags, and the pair that costs the most is the same one it
        costs on the units: the unowned row against Iron, two greys, which
        meet at 45.0 here (the widest pair, meridian against aurora on the
        base, is 176.2). Measured over the pixels that actually DIFFER
        between two rows of one building, which is a different question from
        the one the 4:1 gate asks — this bounds how far apart the changed
        pixels are, that one bounds how much of the cell changed at all. The
        faction-read pass moved both: the unowned row swapped families, so
        far more pixels differ and each of them by less.
        """
        for bid in sorted(terrain.PROPERTY):
            rows = {f.key: self._sprite(bid, f).image for f in FACTIONS}
            for i, a in enumerate(FACTIONS):
                for b in FACTIONS[i + 1 :]:
                    pa, pb = rows[a.key].load(), rows[b.key].load()
                    w, h = rows[a.key].size
                    seen = [
                        (pa[x, y], pb[x, y])
                        for y in range(h)
                        for x in range(w)
                        if pa[x, y] != pb[x, y]
                    ]
                    apart = sum(
                        sum((c[k] - d[k]) ** 2 for k in range(3)) ** 0.5
                        for c, d in seen
                    ) / len(seen)
                    with self.subTest(building=bid, pair=(a.key, b.key)):
                        self.assertGreater(apart, 40.0)

    # The board draws a 64px tile into a 16px cell — 4:1, NEAREST — and an
    # owner is read there, not in the atlas. The measure is the mean RGB
    # distance between two rows of ONE property over that downsample, taken
    # over every pixel either row draws (the shared transparent surround is
    # not evidence of anything). The units answer the same measure at 34-95,
    # so a property is allowed to say less than an army does and no less than
    # this.
    #
    # The properties pass left the faction read at 12-27 here, and the pair it
    # left worst is the pair whose colours are both greys: the unowned row and
    # Iron, 12.4 on the airport. Owned rows now differ by more than which
    # dark roof they wear — the paint comes down the front of the building
    # (`buildings.ROOF_TRIM`) — and the unowned row is built out of cool
    # concrete against the owned rows' warm masonry, which is the one thing
    # Iron's own grey cannot be told from by value.
    BOARD_ZOOM = 4
    OWNERS_APART = 25.0
    # Neutral against Iron is a grey against a grey and buys its margin with
    # hue alone, so it is held to a floor of its own rather than to the bar
    # every coloured pair clears.
    NEUTRAL_IRON_APART = 20.0

    def _board_cell(self, tid: str, fac):
        """One property tile as the board samples it: 4:1, nearest."""
        tile = terrain.tile(tid, fac).convert("RGBA")
        size = (tile.width // self.BOARD_ZOOM, tile.height // self.BOARD_ZOOM)
        return tile.resize(size, Image.NEAREST)

    def test_two_owners_are_tellable_apart_at_the_boards_own_scale(self):
        for tid in sorted(terrain.PROPERTY):
            rows = {f.key: self._board_cell(tid, f) for f in FACTIONS}
            for i, a in enumerate(FACTIONS):
                for b in FACTIONS[i + 1 :]:
                    pa, pb = rows[a.key].load(), rows[b.key].load()
                    w, h = rows[a.key].size
                    drawn = [
                        (pa[x, y], pb[x, y])
                        for y in range(h)
                        for x in range(w)
                        if pa[x, y][3] or pb[x, y][3]
                    ]
                    apart = sum(
                        sum((c[k] - d[k]) ** 2 for k in range(3)) ** 0.5
                        for c, d in drawn
                    ) / len(drawn)
                    pair = {a.key, b.key}
                    bar = (
                        self.NEUTRAL_IRON_APART
                        if pair == {"neutral", "iron"}
                        else self.OWNERS_APART
                    )
                    with self.subTest(property=tid, pair=(a.key, b.key)):
                        self.assertGreater(apart, bar)

    def test_a_property_never_takes_the_rim_step_a_unit_keys_off(self):
        """`BUILDING_TOP_SLOT`: the band over the top plane is the army's."""
        rim = {ramp[-1] for ramp in RAMPS.values()}
        rim |= {
            palette.MASONRY_RAMP[-1],
            palette.CONCRETE_RAMP[-1],
            palette.MACHINE_RAMP[-1],
        }
        for bid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                with self.subTest(building=bid, faction=fac.key):
                    drawn = set(opaque_pixels(self._sprite(bid, fac).image))
                    self.assertEqual(drawn & rim, set())


class PropertyOverlays(unittest.TestCase):
    """A property is a building on transparent ground, not a tile of grass.

    Design review rounds 4 and 5: the five property columns baked the plains
    green into their cells, so a city on road or beach wore a green square.
    They now carry the building, its base plate and its solid shadow, and
    nothing else; the board paints the ground under them.
    """

    def _cell(self, tid: str, fac) -> Image.Image:
        return terrain.tile(tid, fac).convert("RGBA")

    def test_only_the_property_columns_carry_transparency(self):
        img = atlas.build_terrain_atlas()
        px = img.load()
        for col, tid in enumerate(terrain.TERRAIN_ORDER):
            clear = sum(
                1
                for y in range(img.height)
                for x in range(col * CELL, col * CELL + CELL)
                if px[x, y][3] == 0
            )
            with self.subTest(tile=tid):
                if tid in terrain.PROPERTY:
                    self.assertGreater(clear, 0)
                else:
                    self.assertEqual(clear, 0)

    def test_a_property_leaves_its_corners_to_the_ground(self):
        # The corners are the ground plate's, wherever the building stands.
        for tid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                px = self._cell(tid, fac).load()
                for corner in (
                    (0, 0),
                    (CELL - 1, 0),
                    (0, CELL - 1),
                    (CELL - 1, CELL - 1),
                ):
                    with self.subTest(tile=tid, faction=fac.key, corner=corner):
                        self.assertEqual(px[corner][3], 0)

    def test_property_cells_carry_no_semi_transparent_pixel(self):
        # The units' rule, held for the terrain sheet's buildings too: a soft
        # alpha edge is a halo on the board and a grey stain in the cut-in.
        for tid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                with self.subTest(tile=tid, faction=fac.key):
                    cell = self._cell(tid, fac)
                    raw = cell.tobytes()
                    self.assertEqual({raw[i] for i in range(3, len(raw), 4)}, {0, 255})

    def _shadow(self, tid: str, fac) -> list[tuple[int, int]]:
        px = self._cell(tid, fac).load()
        return [
            (x, y)
            for y in range(CELL)
            for x in range(CELL)
            if px[x, y] == (*terrain.SHADOW, 255)
        ]

    def test_the_shadow_is_opaque_and_solid(self):
        # Both parities, so it cannot go back to a 1px checkerboard unnoticed
        # — see CastShadow for the measurement that retired that shape.
        for tid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                with self.subTest(tile=tid, faction=fac.key):
                    shadow = self._shadow(tid, fac)
                    self.assertGreater(len(shadow), 0)
                    self.assertEqual({(x + y) % 2 for x, y in shadow}, {0, 1})

    # CastShadow's tolerance is 0.15 over a whole army; a building's shadow is
    # a ~130px band two pixels wide, so at 4:1 the sampling grid still lands on
    # more of one diagonal than another and solid comes in at 0.69-1.38. That
    # residual is the band's SHAPE. The checkerboard's was structure: 0.00-2.76
    # at 4:1 and 0.00-2.00 at 2:1, where a phase draws none of the shadow at
    # all. Solid measures 0.97-1.06 at 2:1 and exactly 1.0 at 1:1.
    RUNG_TOLERANCE = 0.45

    def test_every_rung_draws_the_same_share_of_the_shadow(self):
        for tid in sorted(terrain.PROPERTY):
            shadow = self._shadow(tid, FACTIONS[1])
            for ratio in (4, 2, 1):
                for phase_y in range(ratio):
                    for phase_x in range(ratio):
                        drawn = sum(
                            1
                            for x, y in shadow
                            if x % ratio == phase_x and y % ratio == phase_y
                        )
                        share = drawn * ratio * ratio / len(shadow)
                        with self.subTest(
                            tile=tid, ratio=ratio, phase=(phase_x, phase_y)
                        ):
                            self.assertAlmostEqual(
                                share, 1.0, delta=self.RUNG_TOLERANCE
                            )

    def test_the_tile_and_the_exported_cell_place_one_building(self):
        # The atlas tile is the exported iso_buildings cell plus a shadow, so
        # the two surfaces cannot drift into placing the same building twice.
        for tid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                tile_px = self._cell(tid, fac).load()
                cell_px = atlas.building_cell(tid, fac).convert("RGBA").load()
                with self.subTest(tile=tid, faction=fac.key):
                    for y in range(CELL):
                        for x in range(CELL):
                            if cell_px[x, y][3] == 0:
                                continue
                            self.assertEqual(tile_px[x, y], cell_px[x, y])


class AutotileMasks(unittest.TestCase):
    """Sheets laid out row-major, bits N=1 E=2 S=4 W=8."""

    def _edges_reaching(self, tile, tones) -> int:
        px = tile.convert("RGB").load()
        bits = 0
        for bit, (x, y) in zip((N, E, S, W), EDGE_PROBES):
            if px[x, y] in tones:
                bits |= bit
        return bits

    def test_road_variants_reach_exactly_their_connected_edges(self):
        for mask in range(1, 16):
            with self.subTest(mask=mask):
                self.assertEqual(
                    self._edges_reaching(autotile.road_tile(mask), ROAD_TONES), mask
                )

    def test_river_variants_reach_exactly_their_connected_edges(self):
        for mask in range(1, 16):
            with self.subTest(mask=mask):
                self.assertEqual(
                    self._edges_reaching(autotile.river_tile(mask), WATER_TONES), mask
                )

    def test_a_roads_mask_zero_falls_back_to_east_west(self):
        self.assertEqual(self._edges_reaching(autotile.road_tile(0), ROAD_TONES), E | W)

    def test_a_rivers_mask_zero_is_a_pond_rather_than_a_bar(self):
        # a watercourse joined to nothing is a pool, so it reaches no edge —
        # against the E|W bar the same mask used to draw
        self.assertEqual(self._edges_reaching(autotile.river_tile(0), WATER_TONES), 0)

    def test_sheets_lay_all_sixteen_masks_out_row_major(self):
        sheet = autotile.variant_sheet(autotile.road_tile)
        self.assertEqual(sheet.size, (4 * (CELL + 2) + 2, 4 * (CELL + 2) + 2))
        for mask in range(16):
            with self.subTest(mask=mask):
                x = (mask % 4) * (CELL + 2) + 2
                y = (mask // 4) * (CELL + 2) + 2
                cut = sheet.crop((x, y, x + CELL, y + CELL))
                self.assertEqual(
                    cut.tobytes(), autotile.road_tile(mask).convert("RGB").tobytes()
                )

    def test_both_bridge_decks_are_exported(self):
        ew = autotile.bridge_tile(True).convert("RGB").load()
        ns = autotile.bridge_tile(False).convert("RGB").load()
        # E-W deck spans the tile horizontally, N-S vertically — in timber,
        # which is what tells a bridge from the road it carries
        self.assertEqual({ew[0, CELL // 2], ew[CELL - 1, CELL // 2]}, {TIMBER})
        self.assertEqual({ns[CELL // 2, 0], ns[CELL // 2, CELL - 1]}, {TIMBER})
        sheet = autotile.bridge_sheet()
        self.assertEqual(sheet.size, (2 * (CELL + 2) + 2, CELL + 4))
        for i, deck in enumerate(
            (autotile.bridge_tile(True), autotile.bridge_tile(False))
        ):
            x = i * (CELL + 2) + 2
            cut = sheet.crop((x, 2, x + CELL, 2 + CELL))
            self.assertEqual(cut.tobytes(), deck.convert("RGB").tobytes())


class WoodsSeam(unittest.TestCase):
    """A wood's ground is the plains ground, tone for tone.

    The game shipped a woods sheet baked before the terrain value ceiling: its
    plate still held the pre-ceiling grass while the atlas plains had come down
    to GRASS, so every woods cell drew a bright rectangle at its own cell edge.
    Both plates are that one GRASS tone under the same grain, so the step
    cannot exist — measured against `_ground` rather than the plains tile
    because the tile's wildflower is brighter than the ground band and would
    let exactly the tone that caused the seam back through.
    """

    OLD_PLATE_GREEN = (119, 198, 79)  # what the game's committed sheet holds

    def _plate(self, salt: int) -> set[tuple[int, int, int]]:
        """Every tone the grass ground is made of: the grain over GRASS plus
        the two flat clump tones the field is clumped with (2026-08-22)."""
        return set(opaque_pixels(terrain._grass_ground(salt)))

    def _band(self, salt: int) -> tuple[float, float]:
        """The band of the plate's FIELD tone — the grain over GRASS, without
        the clumps. This is the band a woods pixel may not cross, and it is
        the same band it always was: the clumps only darken, and the canopy's
        lit top is authored one step under this floor, so folding them in
        would drop the floor past CANOPY_TOP and stop measuring anything."""
        lums = [
            terrain.luminance(c) for c in opaque_pixels(terrain._ground(GRASS, salt))
        ]
        return min(lums), max(lums)

    # every variant clears at least this much plate between its crowns; the
    # thinnest today is 465px, so a plate that stopped being the plains one
    # in either direction empties this rather than merely thinning it
    CLEARING_FLOOR = 300

    def test_the_woods_plate_is_the_plains_plate(self):
        self.assertLessEqual(self._plate(WOODS_SALT), self._plate(PLAINS_SALT))
        self.assertEqual(self._band(WOODS_SALT), self._band(PLAINS_SALT))
        # and the tile really shows that plate: a decoupled plate is caught
        # from below here and from above by the ceiling test, whereas the two
        # salts alone are a statement about the grain and not about the tile
        ground = self._plate(PLAINS_SALT)
        for mask in range(16):
            with self.subTest(mask=mask):
                shown = sum(
                    1 for c in opaque_pixels(autotile.woods_tile(mask)) if c in ground
                )
                self.assertGreaterEqual(shown, self.CLEARING_FLOOR)

    def test_no_woods_pixel_out_keys_the_plains_ground(self):
        lo, hi = self._band(PLAINS_SALT)
        # the bound is only worth asserting if it refuses the tone that caused
        # the seam in the first place
        self.assertGreater(terrain.luminance(self.OLD_PLATE_GREEN), hi)
        ground = self._plate(PLAINS_SALT)
        for mask in range(16):
            with self.subTest(mask=mask):
                for c in set(opaque_pixels(autotile.woods_tile(mask))):
                    lum = terrain.luminance(c)
                    self.assertLessEqual(lum, hi)
                    # every tone is either a plains ground tone or shade over
                    # one: canopy, trunk and contact shadow sit below the band
                    if lum >= lo:
                        self.assertIn(c, ground)

    def _edge_ground(self, tile, bit: int) -> int:
        """Ground pixels along one border — how far the tree line scallops
        back from it."""
        px = tile.convert("RGB").load()
        ground = self._plate(PLAINS_SALT)
        line = {
            N: [(x, 0) for x in range(CELL)],
            S: [(x, CELL - 1) for x in range(CELL)],
            W: [(0, y) for y in range(CELL)],
            E: [(CELL - 1, y) for y in range(CELL)],
        }[bit]
        return sum(1 for x, y in line if px[x, y] in ground)

    def test_the_tree_line_scallops_off_every_open_edge(self):
        walled_in = autotile.woods_tile(15)
        for mask in range(16):
            for bit in (N, E, S, W):
                if mask & bit:  # the wood continues: canopy keeps its overhang
                    continue
                with self.subTest(mask=mask, edge=bit):
                    self.assertGreater(
                        self._edge_ground(autotile.woods_tile(mask), bit),
                        self._edge_ground(walled_in, bit),
                    )

    def test_mask_fifteen_is_the_atlas_tile(self):
        # the game's TerrainAutotiles keeps a wood walled in by wood on the
        # base atlas, so the sheet's 15 has to be that same tile
        self.assertEqual(
            autotile.woods_tile(15).convert("RGB").tobytes(),
            terrain.woods().convert("RGB").tobytes(),
        )


class RiverBanks(unittest.TestCase):
    """A river has a shore, the way the coast family already does.

    The round-5 review read the water on `first_steps` as "a hard-edged
    rectangle with a pale outline, no shore blend": `river_tile` filled a blue
    bar straight onto the grass, ended a run with a sawn-off square, and drew
    mask 0 as an E|W bar rather than as the pool a cell joined to nothing is.
    These pin the three fixes, each against a control that would have passed
    before them.
    """

    OLD_PLATE_GREEN = WoodsSeam.OLD_PLATE_GREEN
    BANK_TONES = (
        autotile.BANK,
        autotile.BANK_DARK,
        autotile.BANK_WET,
        autotile.POND_BANK,
        autotile.POND_BANK_DK,
    )
    # Every tone a river's water can be: the channel, its rim, the glints.
    WATER_FAMILY = frozenset(
        {WATER, WATER_DARK, WATER_LIGHT, palette.mix(WATER, WATER_LIGHT, 0.5)}
    )

    def _ground(self) -> set[tuple[int, int, int]]:
        return set(opaque_pixels(terrain._grass_ground(PLAINS_SALT)))

    def _hard_edged(self, mask: int, outline=None):
        """The tile as it was drawn before this pass: water straight onto the
        plate, its only lip the one-pixel outline the edge pass drew."""
        t = terrain.plains()
        autotile._fill_arms(t, mask, autotile._WLO, autotile._WHI, WATER)
        if outline is not None:
            autotile._edge_pass(t, lambda c: c == WATER, WATER_DARK, outline)
        return t

    def _water_meeting_no_bank(self, tile) -> int:
        """Water pixels with a neighbour that is neither water nor bank — the
        waterline running straight onto the plate or onto a bare outline."""
        px = tile.convert("RGB").load()
        bank = set(self.BANK_TONES)
        return sum(
            1
            for y in range(CELL)
            for x in range(CELL)
            if px[x, y] in self.WATER_FAMILY
            and any(
                px[nx, ny] not in self.WATER_FAMILY and px[nx, ny] not in bank
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1))
                if 0 <= nx < CELL and 0 <= ny < CELL
            )
        )

    def _water_in_row(self, tile, y: int) -> int:
        px = tile.convert("RGB").load()
        return sum(1 for x in range(CELL) if px[x, y] in self.WATER_FAMILY)

    def test_the_bank_is_mixed_from_the_ground_constants(self):
        """Shared derivation, never a copied hex — the woods-seam rule: a bank
        carrying its own tan would step against the shore tones the moment
        either moved."""
        parents = {
            autotile.BANK: (terrain.SAND, terrain.GRASS_DARK),
            autotile.BANK_DARK: (autotile.BANK, terrain.GRASS_DARK),
            autotile.BANK_WET: (terrain.SAND_DARK, WATER_DARK),
            autotile.POND_BANK: (autotile.BANK, terrain.GRASS_DARK),
            autotile.POND_BANK_DK: (autotile.POND_BANK, autotile.BANK_WET),
        }
        for tone, (a, b) in parents.items():
            with self.subTest(tone=tone):
                self.assertNotIn(tone, (a, b))
                for ch, pair in zip(tone, zip(a, b)):
                    self.assertGreaterEqual(ch, min(pair))
                    self.assertLessEqual(ch, max(pair))

    def test_no_bank_tone_out_keys_the_plains_ground(self):
        hi = max(terrain.luminance(c) for c in self._ground())
        # worth asserting only if it refuses the pre-ceiling green that caused
        # the woods seam — the same control, since this is the same rule
        self.assertGreater(terrain.luminance(self.OLD_PLATE_GREEN), hi)
        for tone in self.BANK_TONES:
            with self.subTest(tone=tone):
                self.assertLessEqual(terrain.luminance(tone), hi)

    def test_no_river_pixel_reaches_the_unit_band(self):
        for mask in range(16):
            with self.subTest(mask=mask):
                for c in set(opaque_pixels(autotile.river_tile(mask))):
                    self.assertLessEqual(terrain.luminance(c), TERRAIN_VALUE_CEILING)

    def test_every_bank_edge_carries_a_lip(self):
        # both controls are how the river used to be drawn: bare water on the
        # plate, and water fenced by the one-pixel dark-grass outline the
        # round-5 review read as "a pale outline, no shore blend"
        self.assertGreater(self._water_meeting_no_bank(self._hard_edged(E | W)), 0)
        self.assertGreater(
            self._water_meeting_no_bank(self._hard_edged(E | W, terrain.GRASS_DARK)), 0
        )
        for mask in range(16):
            with self.subTest(mask=mask):
                self.assertEqual(
                    self._water_meeting_no_bank(autotile.river_tile(mask)), 0
                )

    def test_a_run_that_terminates_tapers_to_a_nose(self):
        # a row 11px past the joint centre: through-flow keeps the full
        # channel there, a terminating run has rounded most of it away
        far = CELL // 2 + 11
        self.assertEqual(
            self._water_in_row(autotile.river_tile(N | S), far),
            autotile._WHI - autotile._WLO,
        )
        narrowed = self._water_in_row(autotile.river_tile(N), far)
        self.assertGreater(narrowed, 0)
        self.assertLess(narrowed, autotile._WHI - autotile._WLO)

    def test_mask_zero_is_a_pond_ringed_on_every_side(self):
        px = autotile.river_tile(0).convert("RGB").load()
        mid = CELL // 2
        self.assertIn(px[mid, mid], self.WATER_FAMILY)
        bank = set(self.BANK_TONES)
        ground = self._ground()
        for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
            with self.subTest(direction=(dx, dy)):
                walk = [
                    px[mid + dx * k, mid + dy * k]
                    for k in range(1, mid)
                    if 0 <= mid + dx * k < CELL and 0 <= mid + dy * k < CELL
                ]
                water = max(i for i, c in enumerate(walk) if c in self.WATER_FAMILY)
                ringed = [i for i, c in enumerate(walk) if c in bank]
                self.assertTrue(ringed)
                self.assertGreater(min(ringed), water)
                self.assertIn(walk[-1], ground)

    def _ring_depth(self, px, dx: float, dy: float) -> int:
        """Bank pixels a ray out of the pond's centre crosses."""
        bank = set(self.BANK_TONES)
        length = (dx * dx + dy * dy) ** 0.5
        seen, depth, k = set(), 0, 0.0
        while k < CELL / 2:
            x, y = round(31.5 + dx / length * k), round(31.5 + dy / length * k)
            if 0 <= x < CELL and 0 <= y < CELL and (x, y) not in seen:
                seen.add((x, y))
                depth += px[x, y] in bank
            k += 0.25
        return depth

    def test_the_ponds_ring_is_darker_than_the_channels_own_bank(self):
        """Round 6 read the pond as a badge: a rounded capsule with a cream
        outline. The ring keeps the channel's derivation and drops ~20L, which
        is what stops it reading as an outline drawn around a shape."""
        drop = terrain.luminance(autotile.BANK) - terrain.luminance(autotile.POND_BANK)
        self.assertGreater(drop, 15.0)
        self.assertLess(
            terrain.luminance(autotile.POND_BANK_DK),
            terrain.luminance(autotile.POND_BANK),
        )

    def test_the_ponds_ring_is_not_one_weight_all_the_way_round(self):
        """The other half of the badge read. The bank is widest down the
        shadow diagonal and thins to its lip in the reed notches; that it
        never thins past one is `test_every_bank_edge_carries_a_lip`'s."""
        px = autotile.river_tile(0).convert("RGB").load()
        shadow = self._ring_depth(px, 1, 1)
        lit = self._ring_depth(px, -1, -1)
        self.assertGreaterEqual(shadow, lit + 3)
        for direction in autotile._REEDS:
            with self.subTest(reed=direction):
                self.assertLessEqual(self._ring_depth(px, *direction), 2)


class SeaPhases(unittest.TestCase):
    """One sea tile repeated is a lattice, however its glints are spread.

    Rounds 3 and 6: a field of sea reads visibly row-aligned across a whole
    frame, because the repeat is what lines up rather than anything inside the
    tile. The generator emits phase variants; placing them is the game's, by
    coordinate hash. Phase 0 stays the atlas column exactly, so a board that
    has not adopted the sheet is unchanged and adoption is additive.
    """

    def _phases(self):
        return [terrain.sea(phase) for phase in range(len(terrain.SEA_PHASES))]

    def test_phase_zero_is_the_atlas_sea_column(self):
        col = terrain.TERRAIN_ORDER.index("sea")
        column = atlas.build_terrain_atlas().crop(
            (col * CELL, 0, col * CELL + CELL, CELL)
        )
        self.assertEqual(
            column.convert("RGB").tobytes(), terrain.sea(0).convert("RGB").tobytes()
        )

    def test_every_phase_moves_the_water(self):
        frames = [tile.convert("RGB").tobytes() for tile in self._phases()]
        self.assertGreaterEqual(len(frames), 2)
        self.assertEqual(len(set(frames)), len(frames))

    def test_no_phase_leaves_the_terrain_band_or_the_colour_ceiling(self):
        for phase, tile in enumerate(self._phases()):
            with self.subTest(phase=phase):
                px = opaque_pixels(tile)
                self.assertLessEqual(
                    share_above(px, TERRAIN_VALUE_CEILING),
                    ValueCeiling.TERRAIN_HIGHLIGHT_SHARE,
                )
                self.assertLessEqual(len(set(px)), TerrainPalette.NATURE_CEILING)

    def test_the_sheet_lays_the_phases_out_in_order(self):
        sheet = autotile.sea_sheet()
        phases = self._phases()
        self.assertEqual(sheet.size, (len(phases) * (CELL + 2) + 2, CELL + 4))
        for i, tile in enumerate(phases):
            with self.subTest(phase=i):
                x = i * (CELL + 2) + 2
                cut = sheet.crop((x, 2, x + CELL, 2 + CELL))
                self.assertEqual(cut.tobytes(), tile.convert("RGB").tobytes())


class CanopyLight(unittest.TestCase):
    """The woods canopy has a lit top plane, so what stands on it separates.

    Round 6: verdant-on-woods is green-on-green — a verdant bomber measured
    0.00-0.72 ramp steps against the tile behind it, because a crown was one
    body tone with a rim and a dark green unit had nothing to cross. The plane
    is a value step INSIDE the tile: it may not raise the tile's key, which is
    `WoodsSeam` and `ValueCeiling`'s to refuse, and both still pass.

    Round 6's plane was L143 over a sixteenth of the tile and moved the
    measurement by 0.021, so round 7 restates the numbers as what the plane is
    FOR: a dark green hull has to have something to be seen against, and a
    plane that thin at that value is not it. Every bound below is set where
    the round-6 art fails it.
    """

    MIN_STEP = 68.0  # a lit plane a player can see, in luma (round 6: 63.8)
    MIN_SHARE = 0.24  # lit plane and shoulder together (round 6: 0.164)
    MIN_TOP_SHARE = 0.12  # the plane alone, so a widened shoulder cannot pay
    # for it (round 6: 0.061)
    # What the plane exists to silhouette: the darkest green hull that can
    # stand on a woods tile. A unit's body slot is the plane a tile is mostly
    # read against, and the round-6 canopy cleared verdant's by 34L — inside
    # one ramp step of that same ramp, which is the collision the harness
    # measured. Round 7's sub took ship hulls a band lower still (the under
    # slot, verdant L63), but no boat ever stands in woods and a darker hull
    # only clears this plane by more, so the body slot stays the bound.
    HULL_CLEARANCE = 40.0

    def _verdant_hull(self) -> float:
        return terrain.luminance(RAMPS["verdant"][S_BODY])

    def test_the_lit_plane_clears_a_dark_green_hull(self):
        clearance = terrain.luminance(terrain.CANOPY_TOP) - self._verdant_hull()
        self.assertGreater(clearance, self.HULL_CLEARANCE)

    def test_the_lit_plane_is_a_real_value_step_over_the_canopy(self):
        step = terrain.luminance(terrain.CANOPY_TOP) - terrain.luminance(terrain.CANOPY)
        self.assertGreater(step, self.MIN_STEP)
        self.assertGreater(
            terrain.luminance(terrain.CANOPY_TOP),
            terrain.luminance(terrain.CANOPY_MID),
        )
        self.assertGreater(
            terrain.luminance(terrain.CANOPY_MID), terrain.luminance(terrain.CANOPY)
        )

    def test_the_lit_plane_still_sits_under_the_plains_ground(self):
        # the seam rule from the other side: the plate is the plains plate, so
        # the brightest thing the canopy may hold is darker than the dimmest
        # thing the ground does
        plate = [
            terrain.luminance(c)
            for c in set(opaque_pixels(terrain._ground(GRASS, PLAINS_SALT)))
        ]
        self.assertLess(terrain.luminance(terrain.CANOPY_TOP), min(plate))

    def test_a_crown_is_a_disc_in_the_sheets_projection(self):
        """And the plane is a plane: a canopy is a ground-parallel disc, and
        this camera draws one at 2:1 — the same 2:1 a voxel top face is drawn
        at and the massif's foot lies on. The crowns were orthographic
        CIRCLES, the one shape the projection cannot produce.

        Read off `_crown_reach`, which is what the drawer measures a crown's
        top plane with, and confirmed on the tile: the canopy's own tones fill
        twice as many columns as rows around each crown."""
        for _, _, r in terrain._CROWNS:
            with self.subTest(radius=r):
                up, _ = terrain._crown_reach(r)
                self.assertAlmostEqual(2 * up, r, delta=1)

    # A crown's top plane, drawn alone, against the projection's own 2:1.
    # Measured 2.00-2.29 over the four radii the table spends; a crown drawn
    # as the orthographic circle this replaces scores 1.0.
    MIN_PLANE_ASPECT = 1.8
    MAX_PLANE_ASPECT = 2.6

    def test_a_crowns_top_plane_is_drawn_at_two_to_one(self):
        """The same claim on the picture rather than on the helper: one crown
        on an otherwise empty wood, measured across the tones its top plane is
        banded in."""
        plane = {terrain.CANOPY_TOP, terrain.CANOPY_MID, terrain.CANOPY_LT}
        for r in sorted({r for _, _, r in terrain._CROWNS}):
            with self.subTest(radius=r):
                with mock.patch.object(terrain, "_CROWNS", ((32, 32, r),)):
                    px = terrain.woods().convert("RGB").load()
                pts = [
                    (x, y)
                    for y in range(CELL)
                    for x in range(CELL)
                    if px[x, y] in plane
                ]
                width = max(x for x, _ in pts) - min(x for x, _ in pts) + 1
                depth = max(y for _, y in pts) - min(y for _, y in pts) + 1
                self.assertGreaterEqual(width / depth, self.MIN_PLANE_ASPECT)
                self.assertLessEqual(width / depth, self.MAX_PLANE_ASPECT)

    def test_every_woods_variant_wears_the_plane(self):
        for mask in range(16):
            with self.subTest(mask=mask):
                px = opaque_pixels(autotile.woods_tile(mask))
                lit = sum(
                    1 for c in px if c in (terrain.CANOPY_TOP, terrain.CANOPY_MID)
                )
                top = sum(1 for c in px if c == terrain.CANOPY_TOP)
                self.assertGreater(lit / len(px), self.MIN_SHARE)
                self.assertGreater(top / len(px), self.MIN_TOP_SHARE)


class CanopyGrain(unittest.TestCase):
    """A wood is trees, and trees are not laid in courses.

    The first projection pass put the canopy on the sheet's own 2:1 and the
    tile came out READING as roof shingles: one crown stamp at one depth, six
    staggered courses of it, and a lit rim round every ellipse. The value
    gates above could not see it — a tray of pills wears the same lit plane a
    wood does — so what the eye caught is measured here instead, as PERIOD.

    Every crown course of pitch p puts a band into the tile's row profile
    (mean luma per row) at period p. The crowns are 15-23px wide and half
    that deep, so a course of them lands between 8 and 16px, and that is the
    band read: the strongest component in it is the answer to "is this one
    stamp repeated?". The shingled tile scored 12.05L on its worst variant,
    the round-5 wood that read as trees 7.55L, and this canopy 6.22L — 3.32L
    on the atlas tile, against 0.70L for the bare grass plate underneath.
    """

    PERIOD_CEILING = 7.0  # measured worst variant: 6.22L
    MIN_CROWN_SIZES = 3  # a wood of one crown size is one stamp: today 5

    def _row_profile(self, img) -> list[float]:
        px = img.convert("RGB").load()
        return [
            sum(terrain.luminance(px[x, y]) for x in range(CELL)) / CELL
            for y in range(CELL)
        ]

    def _period_amplitude(self, profile) -> float:
        """The strongest crown-scale period in a row profile, in luma. A plain
        DFT over the periods a course of crowns can land on (8-16px), stated
        as the amplitude of that component rather than as its power."""
        n = len(profile)
        mean = sum(profile) / n
        return max(
            abs(
                sum(
                    (v - mean) * cmath.exp(-2j * cmath.pi * k * i / n)
                    for i, v in enumerate(profile)
                )
            )
            / n
            for k in range(n // 16, n // 8 + 1)
        )

    def test_no_woods_variant_repeats_a_crown_course(self):
        for mask in range(16):
            with self.subTest(mask=mask):
                self.assertLessEqual(
                    self._period_amplitude(
                        self._row_profile(autotile.woods_tile(mask))
                    ),
                    self.PERIOD_CEILING,
                )

    def test_the_reading_refuses_a_tile_laid_in_courses(self):
        # worth asserting only if it catches the thing it is named for: the
        # canopy's own profile with a 12.8px course of ±6L laid over it — the
        # pitch and the depth the shingled tile was drawn at — fails it
        profile = self._row_profile(terrain.woods())
        coursed = [
            v + 12.0 * math.cos(2 * math.pi * i / 12.8) for i, v in enumerate(profile)
        ]
        self.assertGreater(self._period_amplitude(coursed), self.PERIOD_CEILING)

    def test_the_wood_is_drawn_in_more_than_one_crown(self):
        """Size and place: the table spends several half-widths, no two crowns
        share a row, and the mass under a crown scales with it."""
        radii = {r for _, _, r in terrain._CROWNS}
        self.assertGreaterEqual(len(radii), self.MIN_CROWN_SIZES)
        self.assertGreaterEqual(
            len({terrain._crown_depth(r) for r in radii}), self.MIN_CROWN_SIZES
        )
        rows = Counter(y for _, y, _ in terrain._CROWNS)
        self.assertLessEqual(max(rows.values()), 2)
        self.assertGreaterEqual(len(rows), len(terrain._CROWNS) - 3)

    def test_the_hash_moves_every_crown_off_the_table(self):
        moved = sum(
            1
            for cx, cy, _ in terrain._CROWNS
            if terrain._crown_jitter(cx, cy) != (0, 0)
        )
        self.assertEqual(moved, len(terrain._CROWNS))

    # How ragged a wood's outer boundary has to be, in pixels of spread
    # between the shallowest and the deepest bite the tree line takes out of
    # an edge it ends at. A canopy laid tangent to the border — which is what
    # the shingled tile did — scores 0 to 2 and reads as a cut rectangle.
    MIN_TREE_LINE_SPREAD = 6

    def test_the_tree_line_is_bays_and_points_rather_than_a_straight_cut(self):
        for mask in range(16):
            for bit, deep in ((N, False), (S, True)):
                if mask & bit:
                    continue  # the wood continues: no boundary to read here
                with self.subTest(mask=mask, edge=bit):
                    px = autotile.woods_tile(mask).convert("RGB").load()
                    plate = set(opaque_pixels(terrain._grass_ground(PLAINS_SALT)))
                    rows = range(CELL - 1, -1, -1) if deep else range(CELL)
                    depths = []
                    for x in range(CELL):
                        depth = 0
                        for y in rows:
                            if px[x, y] not in plate:
                                break
                            depth += 1
                        depths.append(depth)
                    self.assertGreaterEqual(
                        max(depths) - min(depths), self.MIN_TREE_LINE_SPREAD
                    )

    def test_a_trunk_stands_under_a_crown_rather_than_at_a_tile_offset(self):
        """The old pair of trunks was two fixed coordinates that all sixteen
        variants repeated. A trunk belongs to the crown it holds up now, so
        the variants disagree about where the trunks are — and every one of
        them still shows at least one."""
        bark = {terrain.TRUNK, terrain.darken(terrain.TRUNK, 0.25)}
        seen = []
        for mask in range(16):
            px = autotile.woods_tile(mask).convert("RGB").load()
            trunks = frozenset(
                (x, y) for y in range(CELL) for x in range(CELL) if px[x, y] in bark
            )
            with self.subTest(mask=mask):
                self.assertTrue(trunks)
            seen.append(trunks)
        # a handful of interior crowns stand clear in every variant, so the
        # reading is that the variants MOSTLY disagree: four times as many
        # trunk pixels over the sheet as the ones they all share
        common = set.intersection(*(set(s) for s in seen))
        every = set().union(*seen)
        self.assertGreaterEqual(len(set(seen)), 6)
        self.assertGreater(len(every), 4 * len(common))


class Shoreline(unittest.TestCase):
    """A coast is bays and points, and it joins up across the cell.

    `CanopyGrain` above measures the same thing for a wood's tree line, and
    the shore had exactly the fault the canopy was fixed for: the waterline
    was a ruled full-width rect on every seaward edge — 4px of sand on a
    coast, 8px of water on a shoal, the same row in every column — with the
    wobble spent on decorative foam flecks laid over a straight cut. A beach
    cell read as a beige square in a dashed blue picture frame.

    The reading is the WET LIP, which is the waterline by construction: one
    pixel of `SAND_DARK` between the water and the dry sand, scanned in from
    the water side of the edge under test. Columns where a perpendicular
    edge's water covers the whole scan — the corners of a two-sided tile,
    where the shore has turned and belongs to the other edge — have no lip of
    their own and drop out.

    Two numbers, both of which a ruled line fails outright (one distinct row,
    mode share 1.00): how many rows the boundary visits, and how much of it
    sits on any single row — the strongest band in the profile. The flattest
    variant on the sheet today visits 5 rows with a 0.54 mode share.
    """

    MIN_BOUNDARY_ROWS = 3
    MODE_SHARE_CEILING = 0.60  # measured flattest variant: 0.54
    SEAM_LUMA_STEP = 4.0  # docs/plains_field.md's reading, across a cell edge
    CORNER_CUT = 1  # px of the mitre point taken off; crossing bands cut 0

    def _lip_profile(self, img, bit: int, beach: bool) -> list[int]:
        """Where the wet lip stands along edge `bit`, one entry per pixel
        along it.

        Scanned from the WATER side and stopped at the tile's midline, so
        neither a facing edge's own lip nor the dry sand's `SAND_DARK`
        speckles can answer first: a shoal's water lies against the tile
        border and a coast's fills the middle.
        """
        px = img.convert("RGB").load()
        half = CELL // 2
        span = range(half) if bit in (N, W) else range(half, CELL)
        scan = list(span) if beach == (bit in (N, W)) else list(span)[::-1]
        out = []
        for u in range(CELL):
            for k in scan:
                p = px[u, k] if bit in (N, S) else px[k, u]
                if p == terrain.SAND_DARK:
                    out.append(k)
                    break
        return out

    def _edges(self, mask: int):
        return [bit for bit in (N, E, S, W) if mask & bit]

    def test_the_waterline_is_bays_and_points_rather_than_a_ruled_line(self):
        for builder, beach in (
            (autotile.coast_tile, False),
            (autotile.shoal_tile, True),
        ):
            for mask in range(1, 16):
                tile = builder(mask)
                for bit in self._edges(mask):
                    with self.subTest(sheet=builder.__name__, mask=mask, edge=bit):
                        prof = self._lip_profile(tile, bit, beach)
                        self.assertGreater(len(prof), CELL // 2)
                        self.assertGreaterEqual(len(set(prof)), self.MIN_BOUNDARY_ROWS)
                        top = Counter(prof).most_common(1)[0][1]
                        self.assertLessEqual(top / len(prof), self.MODE_SHARE_CEILING)

    def test_the_shore_runs_on_into_the_next_cell(self):
        """The wobble is a function of the position ALONG the edge and wraps
        on the cell, so the shore of the tile to the left ends where this
        one's begins: a bay may not be cut off by a tile border."""
        for builder, beach in (
            (autotile.coast_tile, False),
            (autotile.shoal_tile, True),
        ):
            with self.subTest(sheet=builder.__name__):
                prof = self._lip_profile(builder(N), N, beach)
                self.assertLessEqual(abs(prof[0] - prof[-1]), 1)
                strip = Image.new("RGB", (CELL * 2, CELL))
                for i in range(2):
                    strip.paste(builder(N).convert("RGB"), (i * CELL, 0))
                px = strip.load()
                left = [terrain.luminance(px[CELL - 1, y]) for y in range(CELL)]
                right = [terrain.luminance(px[CELL, y]) for y in range(CELL)]
                step = abs(sum(left) - sum(right)) / CELL
                self.assertLessEqual(step, self.SEAM_LUMA_STEP)

    def test_a_beach_corner_is_cut_back_rather_than_mitred(self):
        """Where two seaward edges meet, the point of sand they would leave
        is taken off (`autotile._inland`'s rounded-rectangle distance).

        Two crossing bands leave the beach exactly the INTERSECTION of what
        the two one-edge tiles leave — a right-angled point. Combining the
        two depths as a distance instead takes the tip of that point off, so
        some pixels dry in both one-edge tiles are wet in the two-edge one.
        Crossing bands score 0 by construction; the fillet is shallow (it is
        a smooth-min, not a full radius-7 quarter circle), so the bound is
        the presence of the cut, not its size.
        """
        box = 20
        dry = (terrain.SAND, terrain.SAND_DARK)
        for a, b, (x0, y0) in ((N, E, (CELL - box, 0)), (S, W, (0, CELL - box))):
            with self.subTest(edges=(a, b)):
                both = autotile.shoal_tile(a | b).convert("RGB").load()
                one = autotile.shoal_tile(a).convert("RGB").load()
                two = autotile.shoal_tile(b).convert("RGB").load()
                cut = sum(
                    one[x, y] in dry and two[x, y] in dry and both[x, y] not in dry
                    for y in range(y0, y0 + box)
                    for x in range(x0, x0 + box)
                )
                self.assertGreaterEqual(cut, self.CORNER_CUT)


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
    """

    OFFSET = voxel.SHADOW_OFFSET
    # The measured floor on the units, whose shadow is an ellipse under the
    # hull rather than the hull's own silhouette: rockets, whose long barrel
    # sits left of its own cell centre, comes in at +0.37px lateral.
    MIN_UNIT_LATERAL = 0.2

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
            for pose in Pose:
                cast, hull = self._split(atlas.unit_cell(uid, fac, pose), voxel.SHADOW)
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
        for uid in ATLAS_ORDER:
            for pose in Pose:
                with self.subTest(unit=uid, pose=pose.name):
                    lit, _ = self._split(atlas.unit_cell(uid, fac, pose), voxel.SHADOW)
                    with mock.patch.object(voxel, "SHADOW_OFFSET", (0, 0)):
                        bare, _ = self._split(
                            atlas.unit_cell(uid, fac, pose), voxel.SHADOW
                        )
                    (lx, ly), (bx, by) = self._centroid(lit), self._centroid(bare)
                    self.assertGreaterEqual(lx - bx, 1.0)
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

    def _stamped(self, draw, offset):
        """The shadow a tile drawer stamps, read by DIFFERENCE against the
        same tile drawn with no offset at all — which is the only way to tell
        a wood's contact shadow from the tufts standing in its clearings,
        both being GRASS_DARK, without the test copying their coordinates.

        The plate the ground pixels are recognised by is the CLUMPED grass
        plate every scenery tile stands on: read against the plain `_ground`
        the clumps count as casters, and a clump four pixels up-left of a
        shadow pixel vouches for it, which makes both readings vacuous."""
        with mock.patch.object(terrain, "SHADOW_OFFSET", offset):
            lit = draw().convert("RGB")
        with mock.patch.object(terrain, "SHADOW_OFFSET", (0, 0)):
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
            cell = atlas.unit_cell(uid, fac).convert("RGBA")
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
                px = faction_pixels(
                    atlas.unit_cell(uid, red), atlas.unit_cell(uid, blue)
                )
                sats = sorted(saturation(c) for c in px)
                self.assertGreater(statistics.median(sats), 0.45)


class AmbientFrames(unittest.TestCase):
    """Frame B is the same army breathing, never a different army."""

    # An idle key pose shifts weight; it does not swap the sprite. The
    # silhouette's pixel count may move a little (a settled cab hides a row,
    # a swept rotor disc thins) and no more.
    MAX_MASS_DRIFT = 0.08

    def test_frame_b_is_reproducible_and_distinct(self):
        b1 = atlas.build_units_atlas(Pose.B)
        self.assertEqual(b1.tobytes(), atlas.build_units_atlas(Pose.B).tobytes())
        self.assertNotEqual(b1.tobytes(), atlas.build_units_atlas().tobytes())

    # What the board draws. BattleView scales the 64x96 cell by 0.25 per zoom
    # rung with nearest filtering, so rung 1 — the furthest the board zooms
    # out, and the hardest sample an idle has to survive — is a 16x24 texel
    # sample of the cell, where a pose delta under 4 atlas px moves nothing.
    RUNG_1 = (16, 24)
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
        their own riding it; fighter and bomber by the hop alone, which is
        one texel of altitude exactly.
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
        """Rung-1 texels the two poses disagree on, and how many of those
        disagreements are the silhouette rather than the tone."""
        w, h = self.RUNG_1
        pa, pb = (
            atlas.unit_cell(uid, fac, pose).resize(self.RUNG_1, Image.NEAREST).load()
            for pose in (Pose.A, Pose.B)
        )
        changed = silhouette = 0
        for y in range(h):
            for x in range(w):
                ca, cb = pa[x, y], pb[x, y]
                if ca != cb:
                    changed += 1
                    if (ca[3] > 128) != (cb[3] > 128):
                        silhouette += 1
        return changed, silhouette

    def test_the_key_pose_keeps_the_units_mass(self):
        for uid in ATLAS_ORDER:
            for fac in FACTIONS:
                a = self._mass(atlas.unit_cell(uid, fac))
                b = self._mass(atlas.unit_cell(uid, fac, Pose.B))
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
                        self._shadow(atlas.unit_cell(uid, fac)),
                        self._shadow(atlas.unit_cell(uid, fac, Pose.B)),
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

    def test_the_bob_lifts_the_whole_aircraft_and_nothing_else(self):
        """The placement above is a plan; this is the composed cell.

        `fighter` and `bomber` draw the same voxels in both poses — the beat
        IS the bob for them — so frame B has to be frame A moved up exactly
        `BOB_PX` and nothing else: identical pixels from the hover line down,
        which is where the cast shadow lives. A bob that moved a fraction of
        a board texel, or that carried the shadow with it, fails here."""
        # One board texel and not a pixel less: the board draws the 64x96
        # cell at 0.25 scale, so a bob under 4px moves no visible pixel at
        # all — it only changes which source pixel the resample keeps, which
        # is the flicker the 1px bob shipped as a hover.
        self.assertEqual(atlas.BOB_PX, 4)
        for uid in ("fighter", "bomber"):
            self.assertEqual(build_model(uid, Pose.A).vox, build_model(uid, Pose.B).vox)
            ground = atlas.cell_placement(uid, Pose.A).ground
            for fac in FACTIONS:
                a = atlas.unit_cell(uid, fac)
                b = atlas.unit_cell(uid, fac, Pose.B)
                with self.subTest(unit=uid, faction=fac.key):
                    self.assertEqual(
                        b.crop((0, 0, atlas.CELL_W, ground - atlas.BOB_PX)).tobytes(),
                        a.crop((0, atlas.BOB_PX, atlas.CELL_W, ground)).tobytes(),
                    )
                    self.assertEqual(
                        b.crop((0, ground, atlas.CELL_W, atlas.CELL_H)).tobytes(),
                        a.crop((0, ground, atlas.CELL_W, atlas.CELL_H)).tobytes(),
                    )

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
    # the shape is one part: the rotor. Measured on 2026-08-24, cell IoU with
    # the bob taken out is 0.879 (b_copter) and 0.865 (t_copter); the
    # 45-degree sweep these replaced drew a DIFFERENT blade set in frame B —
    # four axial blades against two long diagonals — and scored 0.74 and
    # 0.74, which read as two aircraft alternating rather than one turning.
    MIN_ROTOR_IOU = 0.85
    # ...while still moving what the board can see: 28 and 30 texels at rung
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
            for pose in Pose:
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
            for pose in Pose:
                cell = atlas.unit_cell(uid, neutral, pose, shadow=False)
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
                atlas.unit_cell(uid, neutral, pose).resize((16, 24), Image.NEAREST)
                for pose in Pose
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
                    a = self._foam(atlas.unit_cell(uid, fac))
                    self.assertTrue(a)
                    self.assertEqual(a, self._foam(atlas.unit_cell(uid, fac, Pose.B)))

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
        cell = atlas.unit_cell(uid, faction_by_key("neutral"), pose)
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

    The three chromatic rows are unmoved, and deliberately: their bodies are
    the design-system tokens, so a lit edge that ties with the grass or the
    sand in VALUE still breaks with it in COLOUR — which is what
    `test_a_light_row_that_ties_in_value_still_breaks_in_colour` holds them
    to instead — with two same-hue pairs named and left open (`SAME_HUE`).
    """

    WEAK = GROUND_BREAK  # under this much luma, boundary and tile read as one
    # The two grounds an army spends its game on.
    GROUNDS = ("plains", "shoal")
    MAX_WEAK_ROW = 0.02  # per row x ground; measured 0.0046-0.0079
    MAX_WEAK_UNIT = 0.04  # per sprite; measured 0.0224 (tank, shoal)
    # A light-grade row gives up value and must still break in colour. As a
    # distance in RGB, over the same boundary: measured 0.15% at worst on
    # shoal (meridian, verdant) and 0.00% on plains, once the two same-hue
    # pairs below are set aside.
    COLOUR_BREAK = 40.0
    MAX_WEAK_LIGHT = 0.02
    # The two places a light row shares its HUE with the ground as well as
    # its band, where the colour half of the argument cannot save it: verdant
    # on the plains grass (12.5% of its boundary), and aurora over the water
    # a shoal is half made of (7.9%). Named rather than folded into the
    # bound, because they are defects to answer and not a rule to live with —
    # docs/outlines.md carries them as open.
    SAME_HUE = {("verdant", "plains"), ("aurora", "shoal")}
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
        cell = atlas.unit_cell(uid, fac, pose, False).convert("RGBA")
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
                if fac.outline == OUTLINE_HEAVY or (fac.key, name) in self.SAME_HUE:
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
            px = atlas.unit_cell(uid, fac).convert("RGBA").load()
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
        cell = atlas.unit_cell(uid, faction_by_key("neutral")).convert("RGBA")
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
                    self.assertGreater(iou, 0.85)  # debt still real
                else:
                    self.assertLessEqual(iou, 0.85)

    def test_no_two_units_share_a_silhouette_zoomed_out(self):
        for a, b, iou in self._pairs(self.RUNG_1):
            pair = frozenset((a, b))
            with self.subTest(pair=(a, b)):
                if pair in self.KNOWN_CLONES:
                    self.assertGreater(iou, self.RUNG_1_BAR)  # debt still real
                else:
                    self.assertLessEqual(iou, self.RUNG_1_BAR)


class HullValues(unittest.TestCase):
    """The sub is the DARKEST ship in the line (design review round 7).

    Round 6 gave the sub its mass back and the hull came back in the body
    slot, which left its hull median (0.188) on the same side of the bar as
    the water it swims in (0.404) — a hull-value contest against open sea,
    which is the one contest a boat awash cannot win. So the hull and the
    awash deck drop to the under and shadow slots and the boat separates as a
    contrast pair instead: a dark hull under a lit sail and a light wake edge.

    The hull region is the lower half of a ship's own vertical extent — hull
    and waterline below, superstructure above — measured over the unit's own
    pixels, excluding the composed shadow and foam, the same exclusion
    `UnitBandCoverage` and `tests/measure_livery.py` make.
    """

    # Read off the registry's own cell kind, so a ship added later is held to
    # the same gate instead of quietly sitting outside a hand-written list.
    SHIPS = tuple(uid for uid, (_, kind) in UNITS.items() if kind == "sea")
    COMPOSED = UnitBandCoverage.COMPOSED

    def _hull_median(self, uid: str, fac) -> float:
        cell = atlas.unit_cell(uid, fac).convert("RGBA")
        px = cell.load()
        pixels = [
            (y, px[x, y][:3])
            for y in range(cell.height)
            for x in range(cell.width)
            if px[x, y][3] == 255 and px[x, y][:3] not in self.COMPOSED
        ]
        ys = [y for y, _ in pixels]
        waterline = (min(ys) + max(ys)) / 2
        hull = [c for y, c in pixels if y >= waterline]
        return statistics.median(terrain.luminance(c) for c in hull) / 255

    def test_the_sub_is_the_darkest_hull_afloat(self):
        for fac in FACTIONS:
            medians = {uid: self._hull_median(uid, fac) for uid in self.SHIPS}
            for uid in self.SHIPS:
                if uid == "sub":
                    continue
                with self.subTest(faction=fac.key, against=uid):
                    self.assertLess(medians["sub"], medians[uid])


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
                        len(set(self._opaque(atlas.unit_cell(uid, fac)))), 24
                    )

    def test_the_atlas_carries_no_semi_transparent_pixel(self):
        # 9.8% of the shipped atlas was partial alpha — halos at cut-in.
        for pose in Pose:
            with self.subTest(pose=pose.name):
                alpha = {p[3] for p in self._pixels(atlas.build_units_atlas(pose))}
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
    # — 64.8% of it does, and the 35% that stays light is the rim flash those
    # two rows key off (`GroundContrast`, docs/outlines.md).
    MAX_SUNWARD_DARK = {palette.OUTLINE_LIGHT: 0.10, OUTLINE_HEAVY: 0.70}

    def test_the_sunward_edge_is_lit_rather_than_outlined(self):
        """Selective outlining: the sun side of the silhouette LIGHTENS.

        A pixel whose only break is up or left steps up its own ramp instead
        of going black, so the two sides the light comes from read as an edge
        without spending the plane behind them. Measured over both poses of
        all 18 units in the three rows that wear the light grade, 7.07% of
        those pixels are still S0 against 100% under the band — and the
        remainder is not slack: it is the far side of a self-overlap (a hull
        passing behind a turret is a dark line wherever it lies) and the
        handful the despeckle settles.

        The heavy grade is the same rule with one more question asked of it
        (`palette.clears_the_ground`), so it is measured on the same reading
        rather than exempted from it: neutral and Iron light the sunward edge
        wherever the lift clears the ground's band, and take the contour
        where it cannot.
        """
        for grade in (palette.OUTLINE_LIGHT, OUTLINE_HEAVY):
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
    # The light grade is round 11's bill — 24.52% on verdant's b_copter frame
    # B and 14.16% over the three rows. The heavy grade pays for its ground
    # contour out of the same budget and lands at 30.76% (neutral's b_copter
    # frame B) and 17.33%, both well under the band's 53.1% and 34.5%. The
    # copters' frame B stays the worst sprite through the 2026-08-24 rotor
    # tick, and moved a fifth of a point when it landed.
    MAX_CONTOUR = {
        palette.OUTLINE_LIGHT: (0.28, 0.15),
        OUTLINE_HEAVY: (0.32, 0.20),
    }

    def test_the_outline_costs_a_pixel_and_not_a_band(self):
        """The line is one pixel: what it does not take is the picture.

        `CONTOUR_WEIGHT`'s band spent 34.5% of every unit's own pixels on S0
        and 53.1% on the worst sprite (b_copter's frame B, whose rotor is a
        1px lattice and so nearly all boundary). The G-buffer outline spends
        14.16% and 24.52% on the rows wearing the light grade, and 17.33%
        and 30.76% on the two that wear the heavy one. That difference is the
        faction livery, the fittings and the plane structure the band was
        eating, and it is measured here so a future pass cannot quietly grow
        a band back — including through the heavy grade, which is why that
        grade is budgeted rather than exempted.
        """
        for grade in (palette.OUTLINE_LIGHT, OUTLINE_HEAVY):
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
                cell = atlas.unit_cell(uid, fac).convert("RGBA")
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
