"""Contract tests for the terrain value band the units sit above.

The ceiling itself, the units' use of the band above it, the tans that had to
be pulled apart, and the ship line's own order.

Two `luminance` scales meet here and are qualified by module on purpose:
`terrain.luminance` is Rec. 709, the scale the terrain ceilings are stated
on, and `palette.luminance` is Rec. 601, the scale the ramps are built on.
"""

from __future__ import annotations

import statistics
import unittest
from collections import Counter

from spritegen import atlas, palette, terrain
from spritegen.palette import FACTIONS, RAMPS, faction_by_key
from spritegen.terrain import (
    BUILDING_KEY_CEILING,
    CELL,
    TERRAIN_MEDIAN_CEILING,
    TERRAIN_VALUE_CEILING,
)
from spritegen.units import ATLAS_ORDER, UNITS, Pose

from pixel_helpers import opaque_pixels, share_above, dominant


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
    # The band the rows are ordered on, and the four rows that own it.
    ROW_BAND = 160.0
    CHROMATIC = ("meridian", "aurora", "verdant", "gold")
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

        The chromatic rows are the band's owners because their bodies are
        the design-system tokens themselves; neutral and iron are authored
        around them (khaki for hue separation, inverted for its near-black
        panels), so what they may never do is out-light the armies whose
        colour the band is for. Gold joined them with the fifth row: its body
        is a fifth such token, and its ramp is authored a step under it
        (`palette._GOLD_L`) rather than around another row's.
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


if __name__ == "__main__":
    unittest.main()
