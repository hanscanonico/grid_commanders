"""Contract tests for how a terrain tile is painted.

Its colour budget, its texture, the autotile connection masks, and the seams
where two families meet — woods, river bank, sea phase, canopy and coast.
"""

from __future__ import annotations

import cmath
import math
import unittest
from unittest import mock
from collections import Counter

from PIL import Image

from spritegen import atlas, autotile, palette, terrain
from spritegen.autotile import E, N, S, W
from spritegen.palette import FACTIONS, RAMPS, S_BODY
from spritegen.terrain import (
    CELL,
    GRASS,
    PLAINS_SALT,
    TERRAIN_VALUE_CEILING,
    TIMBER,
    WATER,
    WATER_DARK,
    WATER_LIGHT,
    WOODS_SALT,
)

# By module: importing the class itself would have `unittest discover` collect
# its tests a second time under this file.
import test_value_bands

from pixel_helpers import (
    opaque_pixels,
    share_above,
    ROAD_TONES,
    WATER_TONES,
    EDGE_PROBES,
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
                    test_value_bands.ValueCeiling.TERRAIN_HIGHLIGHT_SHARE,
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
                with mock.patch("spritegen.terrain.woods._CROWNS", ((32, 32, r),)):
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


if __name__ == "__main__":
    unittest.main()
