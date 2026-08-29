"""The 14 terrain tiles, drawn native at the 64px atlas cell.

Ground hues are the game's tools/generate_tiles.gd palette, revalued under
the ceiling below so scenery never out-keys an army; the detail on top
(painted canopies, terraced mountains, foam, wear) is what this generator
adds. Ground fills are seamless — no tile is darkened at its edge
(design review 2026-08-13: that convention read as a seam grid over
any open field), and the grass plate goes further, drawing its border
ring out of one shared field so that any two PHASES butt without a
step as well (`_SEAM_SALT`). Non-property tiles
are identical on every faction row; property tiles are transparent
overlays — a faction-tinted voxel building and its shadow, with the ground
around them left empty for the board to paint (see `property_overlay`).
"""

from __future__ import annotations

from PIL import Image

from ..palette import Faction, darken
from ..voxel import SHADOW_OFFSET
from .mountain import MOUNTAIN_GROUND, MOUNTAIN_PHASES, ROCK, mountain
from .plains import (
    CLUMP,
    CLUMP_DK,
    PLAINS_PHASES,
    _clump_field,
    _CLUMP_SHARE,
    _DECALS,
    _grass_ground,
    _SEAM_SALT,
    _TUFTS,
    plains,
    road,
)
from .properties import PROPERTY_ANCHOR, SHADOW, property_overlay, property_sprite
from .tones import (
    BUILDING_KEY_CEILING,
    CANOPY,
    CANOPY_DK,
    CANOPY_LT,
    CANOPY_MID,
    CANOPY_TOP,
    CELL,
    E,
    GRASS,
    GRASS_DARK,
    N,
    PLAINS_SALT,
    ROAD,
    ROAD_DARK,
    S,
    SAND,
    SAND_DARK,
    SNOW,
    TERRAIN_MEDIAN_CEILING,
    TERRAIN_VALUE_CEILING,
    TIMBER,
    TIMBER_DARK,
    TRUNK,
    W,
    WATER,
    WATER_DARK,
    WATER_LIGHT,
    WILDFLOWER,
    WOODS_SALT,
    _ground,
    _lit,
    _rect,
    _shade,
    _SHADE_GREY,
    _tone,
    luminance,
)
from .water import (
    SEA_FRAMES,
    SEA_GLINT_SLIDE,
    SEA_PHASES,
    _GLINT_RING,
    _slide_x,
    _water_base,
    bridge,
    reef,
    river,
    sea,
    shoal,
)
from .woods import _CROWNS, _crown_depth, _crown_jitter, _crown_reach, woods

# The names this package answers to. Every module and every test reads the
# terrain through `spritegen.terrain`, so what the split moved is which file a
# name is authored in and nothing about where it is asked for.
__all__ = [
    "BUILDING_KEY_CEILING",
    "CANOPY",
    "CANOPY_DK",
    "CANOPY_LT",
    "CANOPY_MID",
    "CANOPY_TOP",
    "CELL",
    "CLUMP",
    "CLUMP_DK",
    "E",
    "GRASS",
    "GRASS_DARK",
    "MOUNTAIN_GROUND",
    "MOUNTAIN_PHASES",
    "N",
    "PLAINS_PHASES",
    "PLAINS_SALT",
    "PROPERTY",
    "PROPERTY_ANCHOR",
    "ROAD",
    "ROAD_DARK",
    "ROCK",
    "S",
    "SAND",
    "SAND_DARK",
    "SEA_FRAMES",
    "SEA_GLINT_SLIDE",
    "SEA_PHASES",
    "SHADOW",
    "SHADOW_OFFSET",
    "SNOW",
    "TERRAIN_MEDIAN_CEILING",
    "TERRAIN_ORDER",
    "TERRAIN_VALUE_CEILING",
    "TIMBER",
    "TIMBER_DARK",
    "TRUNK",
    "W",
    "WATER",
    "WATER_DARK",
    "WATER_LIGHT",
    "WILDFLOWER",
    "WOODS_SALT",
    "_CLUMP_SHARE",
    "_CROWNS",
    "_DECALS",
    "_GLINT_RING",
    "_PLAIN_TILES",
    "_SEAM_SALT",
    "_SHADE_GREY",
    "_TUFTS",
    "_clump_field",
    "_crown_depth",
    "_crown_jitter",
    "_crown_reach",
    "_grass_ground",
    "_ground",
    "_lit",
    "_rect",
    "_shade",
    "_slide_x",
    "_tone",
    "_water_base",
    "bridge",
    "darken",
    "luminance",
    "mountain",
    "plains",
    "property_overlay",
    "property_sprite",
    "reef",
    "river",
    "road",
    "sea",
    "shoal",
    "tile",
    "woods",
]


# ---------------------------------------------------------------------------
# registry, in atlas column order 0..13
# ---------------------------------------------------------------------------

TERRAIN_ORDER: tuple[str, ...] = (
    "road",
    "plains",
    "woods",
    "mountain",
    "river",
    "city",
    "base",
    "hq",
    "sea",
    "airport",
    "port",
    "shoal",
    "bridge",
    "reef",
)
# Tiles whose art changes with the faction row (team-tinted properties).
PROPERTY: frozenset[str] = frozenset({"city", "base", "hq", "airport", "port"})

_PLAIN_TILES = {
    "road": road,
    "plains": plains,
    "woods": woods,
    "mountain": mountain,
    "river": river,
    "sea": sea,
    "shoal": shoal,
    "bridge": bridge,
    "reef": reef,
}


def tile(tid: str, fac: Faction) -> Image.Image:
    """One 64x64 RGBA tile. Non-property tiles ignore the faction and fill
    their cell; a property tile is a transparent overlay. Every ground here
    is authored under TERRAIN_VALUE_CEILING and the buildings a property tile
    carries under BUILDING_KEY_CEILING, so nothing on the board needs dimming
    after the fact."""
    if tid in PROPERTY:
        return property_overlay(tid, fac)
    return _PLAIN_TILES[tid]()
