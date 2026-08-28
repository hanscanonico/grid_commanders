"""The preview images: the checkerboard sheet backdrop and the demo board.

Neither is a shipped asset — `preview_units.png`, `preview_terrain.png` and
`preview_map.png` are what a human looks at to judge the sheets. The demo board
is the interesting one: it draws the game's own autotile and phase rules over a
small authored map, so it shows the CELLS the board would paint rather than the
tiles the atlas holds.
"""

from __future__ import annotations

from collections.abc import Callable

from PIL import Image

from . import autotile, terrain
from .atlas import CELL_H, CELL_W, unit_cell
from .palette import FACTIONS


def checker(w: int, h: int) -> Image.Image:
    img = Image.new("RGBA", (w, h), (52, 52, 60, 255))
    px = img.load()
    for y in range(h):
        for x in range(w):
            if ((x // 8) + (y // 8)) % 2:
                px[x, y] = (60, 60, 69, 255)
    return img


def preview(atlas: Image.Image, zoom: int = 2) -> Image.Image:
    base = checker(atlas.width, atlas.height)
    base.alpha_composite(atlas.convert("RGBA"))
    return base.resize((atlas.width * zoom, atlas.height * zoom), Image.NEAREST)


# Phase-keyed terrains, and how many phases each of their sheets holds — the
# game's TerrainAutotiles.PHASE_COUNTS, restated against this generator's own
# tables so the two cannot drift apart.
_PHASE_COUNTS = {
    "plains": len(terrain.PLAINS_PHASES),
    "sea": len(terrain.SEA_PHASES),
    "mountain": len(terrain.MOUNTAIN_PHASES),
}
_PHASED = {
    "plains": terrain.plains,
    "sea": terrain.sea,
    "mountain": terrain.mountain,
}
_I64 = 1 << 64


def _wrap64(v: int) -> int:
    """GDScript's int, which is a wrapping 64-bit signed one."""
    v &= _I64 - 1
    return v - _I64 if v >> 63 else v


def phase(x: int, y: int, count: int) -> int:
    """Which of `count` phases the cell at (x, y) wears — grid_commanders'
    TerrainAutotiles.phase (scenes/battle/terrain_autotiles.gd), arithmetic for
    arithmetic. The board hashes the coordinate rather than drawing a number,
    so copying the hash is what makes this preview the game's board cell for
    cell rather than a plausible-looking one."""
    bits = _wrap64(_wrap64(x * 0x9E3779B1) ^ _wrap64(y * 0x85EBCA77))
    bits = _wrap64((bits ^ (bits >> 13)) * 0xC2B2AE3D)
    return (bits >> 17) % count  # Python's % on a positive divisor is posmod


def phased_tile(tid: str, x: int, y: int) -> Image.Image:
    """The tile the board would paint at (x, y): a phase variant where the
    terrain has phases, the one tile where it does not."""
    count = _PHASE_COUNTS.get(tid)
    if count is None:
        return terrain.tile(tid, FACTIONS[0])
    return _PHASED[tid](phase(x, y, count))


# A small authored scene proving the sheet works as a map: a board in
# grid_commanders' own map syntax (the `symbol` of each data/terrain resource),
# then units placed on top with mixed factions. Roads, the river, the bridge,
# every coastline and every wood's tree line resolve through the autotile
# variants, and plains, sea and mountain draw the phase their coordinate hashes
# to, so the preview shows the connected, varied look the game gets — the same
# cells, not merely the same tiles.
#
# The terrain mix is the mix of the shipped maps (grid_commanders/maps, 31
# boards): about 56% plains, 12% sea, 11% road, 6% woods, 4% mountain, the rest
# properties and water features. A demo that is half open sea proves the sea
# tile and little else.
_DEMO_MAP = [
    ".F..MM...F...SS",
    "Q=B..M......CSS",
    ".=..F........_S",
    ".=.F...~...PSS*",
    ".=M....~.FF..SS",
    ".======+====.SS",
    "....FF.~...A.SS",
    ".......~....CSS",
    "B...C..~...Q._S",
]
_DEMO_LEGEND = {
    ".": "plains",
    "F": "woods",
    "M": "mountain",
    "S": "sea",
    "*": "reef",
    "_": "shoal",
    "=": "road",
    "~": "river",
    "+": "bridge",
    "C": "city",
    "B": "base",
    "Q": "hq",
    "A": "airport",
    "P": "port",
}
# Tiles that read as open water (no coastline against them).
_WATERY = frozenset({"sea", "reef", "river", "bridge", "port"})
# Shoals carry their own surf, so the sea draws no coast against them — only
# against hard land, which is every other terrain the legend can name.
_HARD_LAND = frozenset(_DEMO_LEGEND.values()) - _WATERY - {"shoal"}
# (unit, faction row, col, row)
_DEMO_UNITS = [
    ("infantry", 1, 3, 2),
    ("mech", 1, 2, 3),
    ("recon", 1, 4, 5),
    ("tank", 1, 6, 4),
    ("apc", 1, 5, 3),
    ("artillery", 1, 1, 6),
    ("rockets", 1, 8, 6),
    ("anti_air", 2, 10, 2),
    ("missiles", 2, 10, 7),
    ("md_tank", 2, 9, 5),
    ("fighter", 1, 6, 1),
    ("bomber", 2, 9, 3),
    ("b_copter", 2, 12, 5),
    ("t_copter", 1, 3, 7),
    ("battleship", 2, 14, 4),
    ("cruiser", 2, 13, 6),
    ("sub", 2, 14, 7),
    ("lander", 1, 13, 8),
]
_EDGES = (
    (autotile.N, (0, -1)),
    (autotile.E, (1, 0)),
    (autotile.S, (0, 1)),
    (autotile.W, (-1, 0)),
)
# The same bits for the DIAGONAL neighbours, N reading north-east and going
# clockwise — the contract the coast and shoal tiles round their outside
# corners against.
_CORNERS = (
    (autotile.N, (1, -1)),
    (autotile.E, (1, 1)),
    (autotile.S, (-1, 1)),
    (autotile.W, (-1, -1)),
)


def _neighbours(
    at: Callable[[int, int], str],
    x: int,
    y: int,
    joins: frozenset[str],
    diagonal: bool = False,
) -> int:
    m = 0
    for bit, (dx, dy) in _CORNERS if diagonal else _EDGES:
        if at(x + dx, y + dy) in joins:
            m |= bit
    return m


def build_demo() -> Image.Image:
    rows = [[_DEMO_LEGEND[c] for c in r] for r in _DEMO_MAP]
    h, w = len(rows), len(rows[0])
    img = Image.new("RGBA", (w * terrain.CELL, h * terrain.CELL))

    def at(x: int, y: int) -> str:
        if 0 <= x < w and 0 <= y < h:
            return rows[y][x]
        return "sea"  # off-map reads as open sea

    road_joins = frozenset({"road", "bridge"})
    river_joins = frozenset({"river", "bridge", "sea"})
    for y, row in enumerate(rows):
        for x, tid in enumerate(row):
            if tid == "road":
                tile = autotile.road_tile(_neighbours(at, x, y, road_joins))
            elif tid == "river":
                tile = autotile.river_tile(
                    _neighbours(at, x, y, river_joins), salt=x * 7 + y
                )
            elif tid == "shoal":
                tile = autotile.shoal_tile(
                    _neighbours(at, x, y, _WATERY),
                    _neighbours(at, x, y, _WATERY, diagonal=True),
                )
            elif tid == "woods":
                tile = autotile.woods_tile(_neighbours(at, x, y, frozenset({"woods"})))
            elif tid == "bridge":
                horiz = bool(
                    _neighbours(at, x, y, road_joins) & (autotile.E | autotile.W)
                )
                tile = autotile.bridge_tile(horiz)
            elif tid == "sea":
                edges = _neighbours(at, x, y, _HARD_LAND)
                corners = _neighbours(at, x, y, _HARD_LAND, diagonal=True)
                tile = (
                    autotile.coast_tile(edges, corners)
                    if edges or corners
                    else phased_tile("sea", x, y)
                )
            elif tid in terrain.PROPERTY:
                # west half to one faction, east half to the other
                tile = terrain.tile(tid, FACTIONS[1 if x < w // 2 else 2])
            else:
                tile = phased_tile(tid, x, y)
            if tid in terrain.PROPERTY:
                # A property ships as a transparent overlay, so the ground
                # under it is the board's to paint — the plains phase that
                # cell hashes to, exactly as the board paints it.
                img.paste(
                    phased_tile("plains", x, y),
                    (x * terrain.CELL, y * terrain.CELL),
                )
                img.alpha_composite(tile, (x * terrain.CELL, y * terrain.CELL))
            else:
                img.paste(tile.convert("RGBA"), (x * terrain.CELL, y * terrain.CELL))
    # A unit cell is anchored by its ground line, so it is placed against the
    # BOTTOM of its tile: a taller cell hangs off the top, over the tile behind.
    for uid, fac_row, x, y in _DEMO_UNITS:
        img.alpha_composite(
            unit_cell(uid, FACTIONS[fac_row]),
            (
                x * terrain.CELL + (terrain.CELL - CELL_W) // 2,
                (y + 1) * terrain.CELL - CELL_H,
            ),
        )
    return img
