"""Atlas assembly and per-cell export, matching grid_commanders' contracts.

units_atlas.png   — 18 columns x 5 rows of CELL_W x CELL_H RGBA cells,
                    columns in data/units atlas_col order, rows in
                    SideIdentity order (neutral, meridian, aurora, iron,
                    verdant).
units_atlas_figures.png
                  — the same sheet with the tile's cast shadow left off,
                    for the cut-ins, which draw the art at 1:1 over a ground
                    plane of their own (see compose_cell's `shadow`).
terrain_atlas.png — 14 columns x 5 rows of terrain.CELL square RGBA cells,
                    columns in tools/generate_tiles.gd order; non-property
                    columns repeat one opaque tile down all rows, property
                    columns are faction-tinted per row and transparent
                    around the building, for the board to paint under.
unit cells        — <unit id>_<team>.png, one units-atlas cell each, the
                    inputs tools/paste_unit_sprites.gd consumes.
building cells    — <building>_<team>.png, one terrain cell each, RGBA
                    transparent-backed sprites for assets/sprites/iso_buildings.
"""

from __future__ import annotations

from PIL import Image

from . import aa, autotile, buildings, terrain
from .palette import FACTIONS, Faction
from .units import ATLAS_ORDER, UNITS, WAKE, Pose, build_model
from .voxel import compose_cell, place_in_cell, render, render_indexed

# The units atlas's cell: one tile wide, half a tile taller than that. A
# silhouette with more mass than the grass tile it stands on has to overflow
# that tile upward, and compose_cell anchors everything to the cell's bottom
# edge, so the extra height is sky above the sprite and an unchanged model
# draws exactly where it always did. Half a tile of headroom is what a raised
# turret needs; a taller cell than that is mostly empty column.
CELL_W = 64
CELL_H = 96
# Ambient animation frame B is pose B of every model plus this bob: air and
# sea units ride one voxel-scale pixel higher (their shadows stay put, so the
# bob reads as hover/swell). Land units hold their ground line and say it in
# the model instead — a walked tread, a settled suspension, a rested weapon.
# Stated as heights above the cell's bottom edge, like compose_cell's own
# landmarks.
_BOB_BOTTOM = {"air": 21, "sea": 10}


def unit_cell(
    uid: str, fac: Faction, pose: Pose = Pose.A, shadow: bool = True
) -> Image.Image:
    """One atlas cell. Units render through the indexed ramps; terrain and
    buildings keep the shading renderer until their own pass moves them."""
    kind = UNITS[uid][1]
    bob = _BOB_BOTTOM.get(kind) if pose is Pose.B else None
    model = build_model(uid, pose)
    # Softening is the LAST word on the art (see spritegen.aa): after the
    # contour and the despeckle, before the cell composes a shadow under it —
    # the shadow is not the unit's silhouette and has no staircase of its own
    # to answer for.
    sprite = aa.soften_unit(render_indexed(model, fac).image, model, fac)
    return compose_cell(
        sprite,
        kind,
        cell=(CELL_W, CELL_H),
        bottom=None if bob is None else CELL_H - bob,
        wake=uid in WAKE,
        shadow=shadow,
    )


def build_units_atlas(pose: Pose = Pose.A, shadow: bool = True) -> Image.Image:
    atlas = Image.new(
        "RGBA", (len(ATLAS_ORDER) * CELL_W, len(FACTIONS) * CELL_H), (0, 0, 0, 0)
    )
    for row, fac in enumerate(FACTIONS):
        for col, uid in enumerate(ATLAS_ORDER):
            atlas.alpha_composite(
                unit_cell(uid, fac, pose, shadow), (col * CELL_W, row * CELL_H)
            )
    return atlas


def build_terrain_atlas() -> Image.Image:
    tile_px = terrain.CELL
    atlas = Image.new(
        "RGBA", (len(terrain.TERRAIN_ORDER) * tile_px, len(FACTIONS) * tile_px)
    )
    for col, tid in enumerate(terrain.TERRAIN_ORDER):
        if tid in terrain.PROPERTY:
            for row, fac in enumerate(FACTIONS):
                atlas.paste(terrain.tile(tid, fac), (col * tile_px, row * tile_px))
        else:
            one = terrain.tile(tid, FACTIONS[0])
            for row in range(len(FACTIONS)):
                atlas.paste(one, (col * tile_px, row * tile_px))
    return atlas


def building_cell(bid: str, fac: Faction) -> Image.Image:
    """A property building alone on a transparent cell, placed exactly as the
    terrain tiles place it, for the game's iso_buildings compositor."""
    # model_for, not BUILDINGS[bid]: the neutral row swaps hue-carrying
    # materials for greys, and the exported cells must match the tiles.
    sprite = render(buildings.model_for(bid, fac), fac)
    out = Image.new("RGBA", (terrain.CELL, terrain.CELL), (0, 0, 0, 0))
    cx, bottom = terrain.PROPERTY_ANCHOR[bid]
    place_in_cell(out, sprite, cx - sprite.width // 2, bottom - sprite.height)
    return out


# ---------------------------------------------------------------------------
# previews
# ---------------------------------------------------------------------------


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


def build_demo() -> Image.Image:
    rows = [[_DEMO_LEGEND[c] for c in r] for r in _DEMO_MAP]
    h, w = len(rows), len(rows[0])
    img = Image.new("RGBA", (w * terrain.CELL, h * terrain.CELL))

    def at(x: int, y: int) -> str:
        if 0 <= x < w and 0 <= y < h:
            return rows[y][x]
        return "sea"  # off-map reads as open sea

    def mask(x: int, y: int, joins: frozenset[str]) -> int:
        m = 0
        for bit, (dx, dy) in (
            (autotile.N, (0, -1)),
            (autotile.E, (1, 0)),
            (autotile.S, (0, 1)),
            (autotile.W, (-1, 0)),
        ):
            if at(x + dx, y + dy) in joins:
                m |= bit
        return m

    road_joins = frozenset({"road", "bridge"})
    river_joins = frozenset({"river", "bridge", "sea"})
    for y, row in enumerate(rows):
        for x, tid in enumerate(row):
            if tid == "road":
                tile = autotile.road_tile(mask(x, y, road_joins))
            elif tid == "river":
                tile = autotile.river_tile(mask(x, y, river_joins), salt=x * 7 + y)
            elif tid == "shoal":
                tile = autotile.shoal_tile(mask(x, y, _WATERY))
            elif tid == "woods":
                tile = autotile.woods_tile(mask(x, y, frozenset({"woods"})))
            elif tid == "bridge":
                horiz = bool(mask(x, y, road_joins) & (autotile.E | autotile.W))
                tile = autotile.bridge_tile(horiz)
            elif tid == "sea":
                # shoals carry their own surf, so the sea draws no coast
                # against them — only against hard land
                def hard_land(t: str) -> bool:
                    return t not in _WATERY and t != "shoal"

                edges = 0
                corners = 0
                for bit, (dx, dy) in (
                    (autotile.N, (0, -1)),
                    (autotile.E, (1, 0)),
                    (autotile.S, (0, 1)),
                    (autotile.W, (-1, 0)),
                ):
                    if hard_land(at(x + dx, y + dy)):
                        edges |= bit
                for bit, (dx, dy) in (
                    (autotile.N, (1, -1)),
                    (autotile.E, (1, 1)),
                    (autotile.S, (-1, 1)),
                    (autotile.W, (-1, -1)),
                ):
                    if hard_land(at(x + dx, y + dy)):
                        corners |= bit
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
