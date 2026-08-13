"""Atlas assembly and per-cell export, matching grid_commanders' contracts.

units_atlas.png   — 18 columns x 5 rows of 64px RGBA cells (1152x320),
                    columns in data/units atlas_col order, rows in
                    SideIdentity order (neutral, meridian, aurora, iron,
                    verdant).
terrain_atlas.png — 14 columns x 5 rows of 64px RGB cells (896x320),
                    columns in tools/generate_tiles.gd order; non-property
                    columns repeat one tile down all rows, property columns
                    are faction-tinted per row.
unit cells        — <unit id>_<team>.png, 64x64 RGBA, the inputs
                    tools/paste_unit_sprites.gd consumes.
building cells    — <building>_<team>.png, 64x64 RGBA transparent-backed
                    sprites for assets/sprites/iso_buildings.
"""

from __future__ import annotations

from PIL import Image

from . import buildings, terrain
from .palette import FACTIONS, Faction
from .units import ATLAS_ORDER, UNITS
from .voxel import compose_cell, render

CELL = 64


def unit_cell(uid: str, fac: Faction) -> Image.Image:
    builder, kind = UNITS[uid]
    return compose_cell(render(builder(), fac), kind)


def build_units_atlas() -> Image.Image:
    atlas = Image.new("RGBA", (len(ATLAS_ORDER) * CELL, len(FACTIONS) * CELL),
                      (0, 0, 0, 0))
    for row, fac in enumerate(FACTIONS):
        for col, uid in enumerate(ATLAS_ORDER):
            atlas.alpha_composite(unit_cell(uid, fac), (col * CELL, row * CELL))
    return atlas


def build_terrain_atlas() -> Image.Image:
    atlas = Image.new("RGBA", (len(terrain.TERRAIN_ORDER) * CELL,
                               len(FACTIONS) * CELL))
    for col, tid in enumerate(terrain.TERRAIN_ORDER):
        if tid in terrain.PROPERTY:
            for row, fac in enumerate(FACTIONS):
                atlas.paste(terrain.tile(tid, fac), (col * CELL, row * CELL))
        else:
            one = terrain.tile(tid, FACTIONS[0])
            for row in range(len(FACTIONS)):
                atlas.paste(one, (col * CELL, row * CELL))
    return atlas.convert("RGB")


def building_cell(bid: str, fac: Faction) -> Image.Image:
    """A property building alone on a transparent cell, placed exactly as the
    terrain tiles place it, for the game's iso_buildings compositor."""
    sprite = render(buildings.BUILDINGS[bid](), fac)
    out = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    if bid == "airport":
        cx, bottom = 31, 46
    elif bid == "port":
        cx, bottom = 32, 52
    else:
        cx, bottom = 32, 61
    out.alpha_composite(sprite, (cx - sprite.width // 2, bottom - sprite.height))
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


# A small authored scene proving the sheet works as a map: terrain ids per
# cell, then units placed on top with mixed factions.
_DEMO_MAP = [
    "sea    sea    sea    sea    sea    sea    sea    sea    sea    sea",
    "sea    reef   shoal  plains woods  plains city   road   port   sea",
    "sea    shoal  plains road   road   road   road   road   hq     sea",
    "sea    plains woods  road   mount  river  bridge road   city   sea",
    "sea    base   road   road   plains river  bridge road   base   sea",
    "sea    plains airport plains woods river  bridge plains plains sea",
    "sea    sea    sea    sea    sea    sea    sea    sea    sea    sea",
]
_DEMO_ALIAS = {"mount": "mountain"}
# (unit, faction row, col, row)
_DEMO_UNITS = [
    ("infantry", 1, 3, 2), ("tank", 1, 4, 2), ("recon", 1, 2, 3),
    ("mech", 2, 7, 2), ("md_tank", 2, 6, 4), ("artillery", 2, 7, 5),
    ("rockets", 1, 1, 4), ("apc", 2, 5, 1), ("anti_air", 1, 3, 5),
    ("missiles", 2, 8, 5), ("fighter", 1, 5, 3), ("bomber", 2, 2, 5),
    ("b_copter", 1, 6, 1), ("t_copter", 2, 4, 5), ("battleship", 1, 1, 6),
    ("cruiser", 2, 8, 6), ("sub", 1, 3, 0), ("lander", 2, 6, 6),
]


def build_demo() -> Image.Image:
    rows = [r.split() for r in _DEMO_MAP]
    h, w = len(rows), len(rows[0])
    img = Image.new("RGBA", (w * CELL, h * CELL))
    fac_for_prop = {(6, 1): 2, (8, 1): 2, (8, 2): 2, (8, 3): 2, (8, 4): 2,
                    (1, 4): 1, (2, 5): 1, (0, 0): 0}
    for y, row in enumerate(rows):
        for x, tid in enumerate(row):
            tid = _DEMO_ALIAS.get(tid, tid)
            fac_row = fac_for_prop.get((x, y), 1 if x < 5 else 2)
            if tid in terrain.PROPERTY:
                fac = FACTIONS[fac_row]
            else:
                fac = FACTIONS[0]
            img.paste(terrain.tile(tid, fac).convert("RGBA"), (x * CELL, y * CELL))
    for uid, fac_row, x, y in _DEMO_UNITS:
        img.alpha_composite(unit_cell(uid, FACTIONS[fac_row]), (x * CELL, y * CELL))
    return img
