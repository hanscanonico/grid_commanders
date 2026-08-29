"""The units' pixel invariants, applied to the board they stand on.

`test_livery.IndexedPalette` holds every unit cell to 24 colours, to alpha
that is only 0 or 255, and to no isolated pixel outside its dither. The
terrain atlas, the autotile sheets and the property buildings are drawn by
the same generator into the same board and had none of those gates.

The three readings, and where the numbers come from:

* **Colours.** The same 24 the units are held to. The current art is under
  it everywhere — the loudest cell measured is the hq at 23, the loudest
  autotile the bridge deck at 21, the loudest building the airport at 22.
* **Alpha.** No cell carries a partial pixel anywhere, so the gate is exact:
  the ground terrains and every autotile tile are fully opaque, and the
  five property columns and the building cells are 0 or 255 — those columns
  are overlays the board composites, and cut nothing in between. The
  autotiles are read as tiles rather than off their contact sheet, which
  `autotile.sheet` pastes into an RGB image: a sheet has no alpha left to
  gate.
* **Isolated pixels.** Grain is what most of this art is made of — the
  ground plane is where ambient variety lives — so a flat zero would fail
  the field, the wood and the sea's own texture. The budgets below are the
  measured reading of the current art, kept as a ratchet: where a tile is
  smooth today (the road, the river, the sea, every building cell) the gate
  is zero, and where it is grainy the gate is the grain it already has.
"""

from __future__ import annotations

import unittest
from functools import cache

from spritegen import atlas, autotile, pipeline, terrain
from spritegen.palette import FACTIONS
from spritegen.terrain import CELL

MAX_COLOURS = 24
GUTTER = 2

# Isolated pixels each terrain column may spend on its grain, measured.
TERRAIN_GRAIN = {
    "plains": 12,
    "woods": 165,
    "mountain": 35,
    "reef": 36,
    "city": 3,
    "base": 1,
    "hq": 7,
    "airport": 2,
    "port": 3,
}

# The same reading per autotile sheet, over the worst cell in it. The rivers'
# outlier is the standalone pond, whose reeds are drawn a pixel at a time.
SHEET_GRAIN = {
    "autotiles/roads.png": 10,
    "autotiles/rivers.png": 99,
    "autotiles/coast.png": 19,
    "autotiles/shoals.png": 7,
    "autotiles/woods.png": 168,
    "autotiles/bridges.png": 3,
    "autotiles/sea.png": 0,
    "autotiles/sea_b.png": 0,
    "autotiles/plains.png": 15,
    "autotiles/mountain.png": 35,
}

# The tiles each sheet is pasted from, in sheet order. Alpha is read here
# because `autotile.sheet` pastes through `convert("RGB")`.
TILE_SOURCES = {
    "autotiles/roads.png": lambda: [autotile.road_tile(m) for m in range(16)],
    "autotiles/rivers.png": lambda: [autotile.river_tile(m) for m in range(16)],
    "autotiles/coast.png": lambda: [autotile.coast_tile(m) for m in range(16)],
    "autotiles/shoals.png": lambda: [autotile.shoal_tile(m) for m in range(16)],
    "autotiles/woods.png": lambda: [autotile.woods_tile(m) for m in range(16)],
    "autotiles/bridges.png": lambda: [
        autotile.bridge_tile(True),
        autotile.bridge_tile(False),
    ],
    "autotiles/sea.png": lambda: [
        terrain.sea(phase, 0) for phase in range(len(terrain.SEA_PHASES))
    ],
    "autotiles/sea_b.png": lambda: [
        terrain.sea(phase, 1) for phase in range(len(terrain.SEA_PHASES))
    ],
    "autotiles/plains.png": lambda: [
        terrain.plains(phase) for phase in range(len(terrain.PLAINS_PHASES))
    ],
    "autotiles/mountain.png": lambda: [
        terrain.mountain(phase) for phase in range(len(terrain.MOUNTAIN_PHASES))
    ],
}


def colours(cell) -> set[tuple[int, int, int]]:
    img = cell.convert("RGBA")
    return {p[:3] for p in img.get_flattened_data() if p[3] == 255}


def alphas(img) -> set[int]:
    return {p[3] for p in img.convert("RGBA").get_flattened_data()}


def isolated(cell) -> list[tuple[int, int]]:
    """Pixels differing from all four orthogonal neighbours — dirt at cut-in
    and shimmer at zoom-out, the same reading `test_livery` takes."""
    img = cell.convert("RGBA")
    px = img.load()
    stray = []
    for y in range(1, img.height - 1):
        for x in range(1, img.width - 1):
            here = px[x, y]
            if here[3] != 255:
                continue
            neigh = (px[x - 1, y], px[x + 1, y], px[x, y - 1], px[x, y + 1])
            if any(n[3] != 255 or n[:3] == here[:3] for n in neigh):
                continue
            stray.append((x, y))
    return stray


@cache
def terrain_atlas():
    return atlas.build_terrain_atlas()


@cache
def autotile_sheet(rel: str):
    return next(o for o in pipeline.SHEETS if o.rel == rel).build()


def sheet_cells(sheet):
    """Every tile of a contact sheet, which lays cells out row-major behind a
    2px gutter (`autotile.sheet`)."""
    cols = (sheet.width - GUTTER) // (CELL + GUTTER)
    rows = (sheet.height - GUTTER) // (CELL + GUTTER)
    for row in range(rows):
        for col in range(cols):
            x, y = col * (CELL + GUTTER) + GUTTER, row * (CELL + GUTTER) + GUTTER
            yield row * cols + col, sheet.crop((x, y, x + CELL, y + CELL))


def atlas_cells():
    """Every cell of the terrain atlas, which is a bare grid of terrain
    columns by faction rows."""
    sheet = terrain_atlas()
    for row, fac in enumerate(FACTIONS):
        for col, tid in enumerate(terrain.TERRAIN_ORDER):
            box = (col * CELL, row * CELL, (col + 1) * CELL, (row + 1) * CELL)
            yield tid, fac, sheet.crop(box)


def building_cells():
    for out in pipeline.building_cells():
        yield out.rel, out.build()


class TerrainAtlasInvariants(unittest.TestCase):
    def test_no_terrain_cell_spends_more_than_24_colours(self):
        for tid, fac, cell in atlas_cells():
            with self.subTest(terrain=tid, faction=fac.key):
                self.assertLessEqual(len(colours(cell)), MAX_COLOURS)

    def test_the_terrain_atlas_carries_no_semi_transparent_pixel(self):
        self.assertEqual(alphas(terrain_atlas()) - {0, 255}, set())

    def test_only_the_property_columns_are_cut_out_of_the_ground(self):
        """The five property columns are overlays the board composites over a
        ground tile; every other column is the ground itself and covers it."""
        for tid, fac, cell in atlas_cells():
            with self.subTest(terrain=tid, faction=fac.key):
                if tid in terrain.PROPERTY:
                    self.assertIn(0, alphas(cell))
                else:
                    self.assertEqual(alphas(cell), {255})

    def test_no_isolated_pixel_beyond_each_terrains_grain(self):
        for tid, fac, cell in atlas_cells():
            with self.subTest(terrain=tid, faction=fac.key):
                self.assertLessEqual(len(isolated(cell)), TERRAIN_GRAIN.get(tid, 0))


class AutotileInvariants(unittest.TestCase):
    def test_no_autotile_cell_spends_more_than_24_colours(self):
        for rel in SHEET_GRAIN:
            for index, cell in sheet_cells(autotile_sheet(rel)):
                with self.subTest(sheet=rel, cell=index):
                    self.assertLessEqual(len(colours(cell)), MAX_COLOURS)

    def test_every_sheet_states_the_tiles_it_is_pasted_from(self):
        self.assertEqual(set(TILE_SOURCES), set(SHEET_GRAIN))
        for rel, tiles in TILE_SOURCES.items():
            with self.subTest(sheet=rel):
                cells = [index for index, _ in sheet_cells(autotile_sheet(rel))]
                self.assertEqual(len(cells), len(tiles()))

    def test_every_autotile_tile_is_opaque_throughout(self):
        for rel, tiles in TILE_SOURCES.items():
            for index, tile in enumerate(tiles()):
                with self.subTest(sheet=rel, cell=index):
                    self.assertEqual(alphas(tile), {255})

    def test_no_isolated_pixel_beyond_each_sheets_grain(self):
        for rel, budget in SHEET_GRAIN.items():
            for index, cell in sheet_cells(autotile_sheet(rel)):
                with self.subTest(sheet=rel, cell=index):
                    self.assertLessEqual(len(isolated(cell)), budget)


class BuildingCellInvariants(unittest.TestCase):
    """The buildings are the one family with no grain at all: they are read as
    silhouettes against whatever ground the board puts under them."""

    def test_no_building_cell_spends_more_than_24_colours(self):
        for rel, cell in building_cells():
            with self.subTest(cell=rel):
                self.assertLessEqual(len(colours(cell)), MAX_COLOURS)

    def test_no_building_cell_carries_a_semi_transparent_pixel(self):
        for rel, cell in building_cells():
            with self.subTest(cell=rel):
                self.assertEqual(alphas(cell) - {0, 255}, set())

    def test_no_building_cell_carries_an_isolated_pixel(self):
        for rel, cell in building_cells():
            with self.subTest(cell=rel):
                self.assertEqual(isolated(cell), [])


if __name__ == "__main__":
    unittest.main()
