"""Contract tests for what the generator actually emits.

Everything here renders sprites and asserts properties of the resulting
pixels: the atlas sizes the game reads, byte-for-byte determinism, the
livery convention (desaturated chassis, pure-faction identity surfaces,
neutral buildings under faction roofs) and the autotile connection masks.

Run with `.venv/bin/python -m unittest discover tests`.
"""

from __future__ import annotations

import statistics
import unittest

from spritegen import atlas, autotile, terrain
from spritegen.autotile import E, N, S, W
from spritegen.palette import FACTIONS, faction_by_key, resolve
from spritegen.terrain import CELL, ROAD, ROAD_DARK, WATER, WATER_DARK
from spritegen.units import ATLAS_ORDER

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
        self.assertEqual(img.size, (len(ATLAS_ORDER) * 64, len(FACTIONS) * 64))
        self.assertEqual(img.size, (1152, 320))
        self.assertEqual(img.mode, "RGBA")

    def test_terrain_atlas_is_14_by_5_rgb_cells(self):
        img = atlas.build_terrain_atlas()
        self.assertEqual(
            img.size, (len(terrain.TERRAIN_ORDER) * 64, len(FACTIONS) * 64)
        )
        self.assertEqual(img.size, (896, 320))
        self.assertEqual(img.mode, "RGB")

    def test_every_atlas_row_renders_its_own_faction(self):
        img = atlas.build_units_atlas()
        rows = [
            img.crop((0, r * 64, img.width, r * 64 + 64)).tobytes()
            for r in range(len(FACTIONS))
        ]
        self.assertEqual(len(set(rows)), len(FACTIONS))


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
        ):
            with self.subTest(builder=builder.__name__):
                self.assertEqual(
                    autotile.variant_sheet(builder).tobytes(),
                    autotile.variant_sheet(builder).tobytes(),
                )


class Livery(unittest.TestCase):
    """Team color as livery, not a paint dip."""

    def test_hull_ramp_sits_between_faction_and_chassis_grey(self):
        for fac in FACTIONS:
            with self.subTest(faction=fac.key):
                hull = resolve("hull", fac)
                self.assertNotEqual(hull, fac.body)
                self.assertLessEqual(saturation(hull), saturation(fac.body))

    def test_vehicles_keep_a_desaturated_chassis_and_pure_accents(self):
        red, blue = faction_by_key("red"), faction_by_key("blue")
        pure = saturation(red.body)
        for uid in ("tank", "md_tank", "apc", "fighter", "battleship"):
            with self.subTest(unit=uid):
                px = faction_pixels(
                    atlas.unit_cell(uid, red), atlas.unit_cell(uid, blue)
                )
                self.assertGreater(len(px), 100)
                sats = [saturation(c) for c in px]
                # the bulk of the team-colored area is livery, not body color
                self.assertLess(statistics.median(sats), pure * 0.85)
                # identity surfaces still wear the pure faction color
                self.assertGreaterEqual(max(sats), pure * 0.95)

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

    def test_mask_zero_falls_back_to_east_west(self):
        self.assertEqual(self._edges_reaching(autotile.road_tile(0), ROAD_TONES), E | W)
        self.assertEqual(
            self._edges_reaching(autotile.river_tile(0), WATER_TONES), E | W
        )

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
        # E-W deck spans the tile horizontally, N-S vertically
        self.assertEqual({ew[0, CELL // 2], ew[CELL - 1, CELL // 2]}, {ROAD})
        self.assertEqual({ns[CELL // 2, 0], ns[CELL // 2, CELL - 1]}, {ROAD})
        sheet = autotile.bridge_sheet()
        self.assertEqual(sheet.size, (2 * (CELL + 2) + 2, CELL + 4))
        for i, deck in enumerate(
            (autotile.bridge_tile(True), autotile.bridge_tile(False))
        ):
            x = i * (CELL + 2) + 2
            cut = sheet.crop((x, 2, x + CELL, 2 + CELL))
            self.assertEqual(cut.tobytes(), deck.convert("RGB").tobytes())


if __name__ == "__main__":
    unittest.main()
