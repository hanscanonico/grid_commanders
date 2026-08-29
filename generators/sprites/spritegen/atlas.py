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
unit cells        — <unit id>_<team>.png, one units-atlas cell each, exported
                    for assets/sprites/units as a reviewable copy of art the
                    atlas already carries; the game loads the atlas, not these.
building cells    — <building>_<team>.png, one terrain cell each, RGBA
                    transparent-backed sprites for assets/sprites/iso_buildings.
"""

from __future__ import annotations

from typing import NamedTuple

from PIL import Image

from . import aa, terrain, units
from .palette import FACTIONS, Faction
from .units import ATLAS_ORDER, UNITS, WAKE, Pose, build_model
from .voxel import (
    AIR_BOTTOM,
    GROUND_BOTTOM,
    compose_cell,
    place_in_cell,
    render_indexed,
    sprite_origin,
    sprite_size,
)

# The units atlas's cell: one tile wide, half a tile taller than that. A
# silhouette with more mass than the grass tile it stands on has to overflow
# that tile upward, and compose_cell anchors everything to the cell's bottom
# edge, so the extra height is sky above the sprite and an unchanged model
# draws exactly where it always did. Half a tile of headroom is what a raised
# turret needs; a taller cell than that is mostly empty column.
CELL_W = 64
CELL_H = 96
# Ambient animation frame B is pose B of every model plus this bob, for the
# kinds that are not standing on the ground. It is ONE BOARD TEXEL: the board
# draws this 64x96 cell at 0.25 scale, so four atlas pixels are one texel at
# zoom rung 1 and a whole texel at every rung above it — the argument
# `_shadow_ellipse` makes about parity, made about motion. The 1px bob this
# replaces moved no visible pixel at all; it only changed which source pixel
# the resample kept, which is a flicker across a third of the sprite and a
# hover nowhere.
#
# What stays put under the bob is the SURFACE — cast shadow, displacement
# ellipse, wake and waterline foam all sit on compose_cell's `ground` — so an
# aircraft gains altitude over its own shadow and a ship rides a swell past a
# fixed foam line, instead of the sea heaving with the hull.
#
# Two other readings of the sea bob were rendered and measured against this
# one. Settling the hull INTO a pinned ellipse reads best of the three by eye
# and buries it: the sheet's shadow-direction gate then measures the sub's
# remaining crescent as lying 0.64px up-LEFT of its caster, where the ellipse
# is laid 2px down-right. Bobbing the hull with its wake still attached costs
# the sub its identity — frame B then resembles the BATTLESHIP's frame A
# (0.682 IoU) more than its own (0.672) — which is what says the wake belongs
# to the water; left there, the sub scores 0.698 against its own frame A and
# 0.604 against the nearest other unit.
#
# Land units hold their ground line and say the beat in the model instead — a
# walked tread, a settled suspension, a rested weapon.
#
# The bob rides the FRAME, not the clip (`units.beat`): a helicopter under way
# hops on MOVE_B exactly as it does on B. What placement never does is carry a
# unit sideways. A move frame shows GAIT only — the travel across the board is
# the consumer's tween (`battle_animator.animate_path`), and a hull already
# translated in-sheet would double it and then snap back on arrival.
BOB_PX = 4
_BOBBING = frozenset({"air", "sea"})

# Pose A's crop, per unit id, as (minx, miny, width, height): the placement
# reference every other pose is pinned to. Poses differ in extent — t_copter's
# pose B was 4px wider than its A when the rotor swept 45 degrees, and is a
# pixel taller than it now that the rotor ticks instead — so centring each
# pose's OWN bounding box slid the whole helicopter 2px sideways every beat
# and pumped its cast shadow by 9% (159px to 173px) with it. Cached because
# the sheet composes each unit 20 times (5 rows x 2 poses x 2 shadow
# variants) and this costs a model build, not a render: `sprite_origin` and
# `sprite_size` read the crop off the voxels.
_POSE_A_BOX: dict[str, tuple[int, int, int, int]] = {}


def _pose_a_box(uid: str) -> tuple[int, int, int, int]:
    box = _POSE_A_BOX.get(uid)
    if box is None:
        model = build_model(uid, Pose.A)
        box = _POSE_A_BOX[uid] = (*sprite_origin(model), *sprite_size(model))
    return box


class Placement(NamedTuple):
    """Where one pose of one unit goes in its cell.

    `origin` is the cell pixel model space's screen origin lands on — NOT the
    sprite's top-left, which is a different point of the model in every pose.
    Pinning it is what makes an idle beat a unit MOVING rather than a unit
    sliding: it is the same pair for both poses of a land unit, and `BOB_PX`
    higher for pose B of an air or sea one.

    `footprint_w` and `ground` are pose-invariant by construction — the width
    every cast shadow is sized from and the surface row it sits on — so the
    origin is the only one of the three a beat may move.
    """

    origin: tuple[int, int]
    footprint_w: int
    ground: int


def cell_placement(uid: str, pose: Pose) -> Placement:
    kind = UNITS[uid][1]
    minx_a, miny_a, w_a, h_a = _pose_a_box(uid)
    ground = CELL_H - (AIR_BOTTOM if kind == "air" else GROUND_BOTTOM)
    bob = BOB_PX if units.beat(pose) and kind in _BOBBING else 0
    # Pose A's own placement — centred on the cell, anchored to the ground row
    # — with every other pose hung off that same origin.
    return Placement(
        ((CELL_W - w_a) // 2 - minx_a, ground - h_a - miny_a - bob), w_a, ground
    )


def unit_cell(
    uid: str, fac: Faction, pose: Pose = Pose.A, shadow: bool = True
) -> Image.Image:
    """One atlas cell. Units render through the indexed ramps; terrain keeps
    the shading renderer until its own pass moves it."""
    kind = UNITS[uid][1]
    model = build_model(uid, pose)
    place = cell_placement(uid, pose)
    minx, miny = sprite_origin(model)
    # Softening is the LAST word on the art (see spritegen.aa): after the
    # contour and the despeckle, before the cell composes a shadow under it —
    # the shadow is not the unit's silhouette and has no staircase of its own
    # to answer for.
    sprite = aa.soften_sprite(render_indexed(model, fac).image, model, fac)
    return compose_cell(
        sprite,
        kind,
        cell=(CELL_W, CELL_H),
        origin=(place.origin[0] + minx, place.origin[1] + miny),
        footprint_w=place.footprint_w,
        ground=place.ground,
        wake=uid in WAKE,
        shadow=shadow,
        # The move clip is the one the consumer MIRRORS, so its shadow gives
        # up the sun's x and is drawn symmetric about the cell's flip axis.
        # Not a ship's: that ellipse is the water the hull displaces, and
        # `voxel._waterline_foam` breaks around the composed cell's own
        # spans, so recentring it would drag the foam line off the water,
        # which is the one thing a move frame may not do (the foam-line test
        # in `MoveFrames`). A displacement patch is also not read as a cast
        # shadow, so its handedness is not what a mirrored sprite is caught
        # on: the hard ellipse a tank lays on grass is.
        centred_shadow=units.moving(pose) and kind != "sea",
        # What a ship's move frames get instead of a recentred shadow: white
        # water at the bow. It is repainted DISPLACEMENT (`voxel._bow_wave`),
        # so it lands on the water plane by construction, cannot heave with
        # the bob, and leaves the ambient waterline foam where pose A put it.
        under_way=units.moving(pose) and kind == "sea",
    )


def cell_box(uid: str, fac: Faction) -> tuple[int, int, int, int]:
    """Where one unit's faction row sits in the units atlas, as a crop box —
    the one statement of the grid `build_units_atlas` lays cells out on, so a
    cell cut back out of a sheet lands on the cell that was composed into it."""
    x, y = ATLAS_ORDER.index(uid) * CELL_W, FACTIONS.index(fac) * CELL_H
    return x, y, x + CELL_W, y + CELL_H


def build_units_atlas(pose: Pose = Pose.A, shadow: bool = True) -> Image.Image:
    atlas = Image.new(
        "RGBA", (len(ATLAS_ORDER) * CELL_W, len(FACTIONS) * CELL_H), (0, 0, 0, 0)
    )
    for fac in FACTIONS:
        for uid in ATLAS_ORDER:
            x, y, _, _ = cell_box(uid, fac)
            atlas.alpha_composite(unit_cell(uid, fac, pose, shadow), (x, y))
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
    sprite = terrain.property_sprite(bid, fac)
    out = Image.new("RGBA", (terrain.CELL, terrain.CELL), (0, 0, 0, 0))
    cx, bottom = terrain.PROPERTY_ANCHOR[bid]
    place_in_cell(out, sprite, cx - sprite.width // 2, bottom - sprite.height)
    return out


# The demo board and the preview backdrop live in `demo.py`; they are
# re-exported here because the driver and the tests reach them through this
# module.
from .demo import (  # noqa: E402
    _DEMO_LEGEND,
    _DEMO_MAP,
    _DEMO_UNITS,
    build_demo,
    checker,
    phase,
    phased_tile,
    preview,
)

__all__ = [
    "_DEMO_LEGEND",
    "_DEMO_MAP",
    "_DEMO_UNITS",
    "build_demo",
    "checker",
    "phase",
    "phased_tile",
    "preview",
]
