"""The 14 terrain tiles, drawn native at the 64px atlas cell.

Ground colors and the darkened-edge grid convention mirror the game's
tools/generate_tiles.gd so a regenerated atlas drops into the same map
without shifting the world's palette; the detail on top (voxel trees,
terraced mountains, foam, wear) is what this generator adds. Non-property
tiles are identical on every faction row; property tiles compose a
faction-tinted voxel building onto their ground.
"""

from __future__ import annotations

from PIL import Image

from . import buildings
from .palette import RGB, Faction, darken, h01, lighten, mix
from .voxel import _shadow_ellipse, place_in_cell, render

CELL = 64

# generate_tiles.gd palette (hex constants), the map's established hues
GRASS = (120, 200, 80)  # 78c850
GRASS_DARK = (90, 166, 60)  # 5aa63c
ROAD = (201, 184, 132)  # c9b884
ROAD_DARK = (168, 152, 104)  # a89868
WATER = (63, 143, 220)  # 3f8fdc
WATER_DARK = (42, 111, 191)  # 2a6fbf
WATER_LIGHT = (124, 196, 240)  # 7cc4f0
SAND = (224, 211, 164)  # e0d3a4
SAND_DARK = (196, 181, 133)  # c4b585
ASPHALT = (111, 116, 124)  # 6f747c
SNOW = (238, 238, 238)  # eeeeee


def _ground(c: RGB, salt: int, grain: float = 0.05) -> Image.Image:
    """Base tile: darkened(0.12) 4px grid edge + inner fill with 4px-block
    grain (kept at 4px so it survives the game's 4:1 nearest downsample)."""
    img = Image.new("RGBA", (CELL, CELL), (*darken(c, 0.12), 255))
    px = img.load()
    for by in range(4, 60, 4):
        for bx in range(4, 60, 4):
            n = (h01(bx, by, salt) - 0.5) * grain * 2
            t = lighten(c, n) if n > 0 else darken(c, -n)
            for yy in range(by, min(by + 4, 60)):
                for xx in range(bx, min(bx + 4, 60)):
                    px[xx, yy] = (*t, 255)
    return img


def _rect(img: Image.Image, x0: int, y0: int, w: int, h: int, c: RGB) -> None:
    px = img.load()
    for yy in range(max(0, y0), min(CELL, y0 + h)):
        for xx in range(max(0, x0), min(CELL, x0 + w)):
            px[xx, yy] = (*c, 255)


def _paste_prop(
    tile: Image.Image, prop: Image.Image, cx: int, bottom: int, shadow: bool = True
) -> None:
    if shadow:
        _shadow_ellipse(
            tile,
            cx,
            bottom - 2,
            max(6, int(prop.width * 0.38)),
            max(2, prop.width // 8),
            44,
        )
    place_in_cell(tile, prop, cx - prop.width // 2, bottom - prop.height)


# ---------------------------------------------------------------------------
# plain grounds
# ---------------------------------------------------------------------------


def road() -> Image.Image:
    t = _ground(ROAD, 1)
    # tire-wear bands
    _rect(t, 4, 18, 56, 3, mix(ROAD, ROAD_DARK, 0.2))
    _rect(t, 4, 43, 56, 3, mix(ROAD, ROAD_DARK, 0.2))
    # the classic centre dashes, thinned to read as lane markings
    _rect(t, 12, 30, 12, 4, ROAD_DARK)
    _rect(t, 40, 30, 12, 4, ROAD_DARK)
    # a few embedded stones
    for sx, sy in ((22, 12), (50, 50), (8, 54), (34, 8)):
        _rect(t, sx, sy, 3, 2, ROAD_DARK)
        _rect(t, sx, sy, 2, 1, lighten(ROAD, 0.12))
    return t


def plains() -> Image.Image:
    t = _ground(GRASS, 2)
    # grass tufts: a dark check with a light blade, like the old speckles
    # but drawn as 3px clusters
    spots = (
        (10, 12),
        (34, 8),
        (52, 22),
        (18, 30),
        (42, 38),
        (8, 44),
        (28, 52),
        (54, 48),
        (24, 20),
        (46, 12),
        (14, 56),
        (38, 24),
    )
    for i, (sx, sy) in enumerate(spots):
        _rect(t, sx, sy, 3, 2, GRASS_DARK)
        _rect(t, sx + (i % 2), sy - 1, 1, 1, lighten(GRASS, 0.18))
    # a couple of tiny wildflowers so big plains fields don't tile dead flat
    for fx, fy in ((30, 36), (50, 40)):
        _rect(t, fx, fy, 1, 1, SNOW)
        _rect(t, fx + 1, fy, 1, 1, (235, 179, 63))
    return t


def woods(fac: Faction) -> Image.Image:
    t = _ground(GRASS, 3)
    big = render(buildings.tree(True), fac)
    small = render(buildings.tree(False), fac)
    _paste_prop(t, big, 22, 40)
    _paste_prop(t, small, 45, 57)
    # underbrush flecks
    for sx, sy in ((8, 50), (52, 14), (12, 20)):
        _rect(t, sx, sy, 3, 2, GRASS_DARK)
    return t


def mountain() -> Image.Image:
    """A painted three-peak massif: light/dark faces split at each ridge,
    jagged dithered snow caps, altitude banding down to a talus skirt."""
    t = _ground(GRASS, 4)
    px = t.load()
    base_y = 56
    # (apex_x, apex_y, slope) — summit, right shoulder, low left foothill
    peaks = ((26, 10, 1.2), (46, 27, 1.3), (11, 36, 1.5))
    rock_hi = (178, 173, 164)
    rock_lt = (158, 154, 146)
    rock_dk = (117, 113, 108)
    rock_deep = (98, 95, 91)
    edge = (66, 63, 60)
    snow_lt = (244, 246, 250)
    snow_dk = (206, 212, 224)
    for x in range(4, 60):
        tops = [int(ay + s * abs(x - ax)) for ax, ay, s in peaks]
        y_top = min(tops)
        if y_top >= base_y - 2:
            continue
        owner = tops.index(y_top)
        ax, ay, _s = peaks[owner]
        lit = x <= ax
        # jagged snow line per column; only the two tall peaks hold snow
        zig = (x * 7) % 3 + ((x // 3) % 2) * 3
        snow_until = ay + 6 + zig if owner < 2 else y_top
        mid = (y_top + base_y) // 2
        for y in range(y_top, base_y):
            if y == y_top:
                c = edge
            elif y < snow_until:
                c = snow_lt if lit else snow_dk
            elif y == snow_until and (x + y) % 2 == 0:
                c = snow_dk if lit else mix(snow_dk, rock_dk, 0.5)  # melt dither
            elif y >= base_y - 5:
                c = rock_dk if lit else rock_deep  # talus skirt
            elif y < mid:
                c = rock_hi if lit else rock_dk  # sunlit high faces
            else:
                c = rock_lt if lit else rock_dk
            px[x, y] = (*c, 255)
    # ridge lines below the apexes and a few cracks
    for x, y0, ln in (
        (26, 17, 32),
        (18, 34, 10),
        (34, 30, 8),
        (46, 34, 16),
        (11, 41, 9),
    ):
        for y in range(y0, min(base_y - 1, y0 + ln)):
            if px[x, y][3] == 255 and px[x, y][:3] in (rock_hi, rock_lt, rock_dk):
                px[x, y] = (*mix(rock_dk, edge, 0.5), 255)
    # contact shadow and scree at the foot
    for x in range(6, 58):
        if px[x, base_y - 1][:3] in (rock_lt, rock_dk, rock_deep):
            px[x, base_y] = (*GRASS_DARK, 255)
    for sx, sy in ((8, 52), (52, 54), (14, 58), (46, 59)):
        _rect(t, sx, sy, 3, 2, GRASS_DARK)
    return t


def _water_base(deep: bool, salt: int) -> Image.Image:
    return _ground(WATER_DARK if deep else WATER, salt, grain=0.045)


def river() -> Image.Image:
    t = _water_base(False, 5)
    # flow streaks, all horizontal like the old art but layered two-tone
    for sx, sy, w in ((8, 14, 16), (36, 20, 16), (16, 38, 16), (44, 46, 12)):
        _rect(t, sx, sy, w, 2, WATER_LIGHT)
        _rect(t, sx + 2, sy + 2, w - 4, 1, mix(WATER, WATER_LIGHT, 0.5))
    # rounded pebble breaking the current
    _rect(t, 28, 54, 6, 3, mix(WATER, WATER_DARK, 0.7))
    _rect(t, 29, 53, 4, 1, WATER_LIGHT)
    return t


def sea() -> Image.Image:
    t = _water_base(True, 6)
    for sx, sy, w in ((8, 14, 16), (36, 22, 16), (14, 42, 16), (44, 50, 10)):
        _rect(t, sx, sy, w, 2, WATER)
        _rect(t, sx + 2, sy + 2, w - 4, 1, mix(WATER_DARK, WATER, 0.5))
    # whitecap flecks
    _rect(t, 48, 12, 6, 2, SNOW)
    _rect(t, 50, 11, 2, 1, SNOW)
    _rect(t, 20, 56, 5, 2, SNOW)
    return t


def shoal() -> Image.Image:
    t = _ground(SAND, 7)
    # water across the bottom with a scalloped surf line — irregular foam
    # clusters, not the uniform dashes that read as road markings
    _rect(t, 0, 40, 64, 24, WATER)
    _rect(t, 0, 40, 64, 2, SAND_DARK)  # wet sand lip
    for k, sx in enumerate(range(0, 64, 8)):
        wob = int(h01(sx, 0, 41) * 3)
        _rect(t, sx, 41 + wob, 5 + (k % 2) * 2, 2, SNOW)
        _rect(t, sx + 2, 43 + wob, 3, 1, mix(WATER, SNOW, 0.55))
    _rect(t, 8, 52, 14, 2, WATER_LIGHT)
    _rect(t, 40, 56, 12, 2, WATER_LIGHT)
    # dry-sand speckles and a shell
    for sx, sy in ((12, 12), (36, 20), (24, 32), (48, 8), (54, 30)):
        _rect(t, sx, sy, 3, 2, SAND_DARK)
    _rect(t, 44, 24, 2, 2, SNOW)
    return t


def bridge() -> Image.Image:
    t = _water_base(False, 8)
    # support shadows in the water under each pier
    for sx in (8, 28, 48):
        _rect(t, sx, 50, 10, 4, mix(WATER, (10, 30, 60), 0.35))
    # road deck carried over the water (same band as the old art)
    _rect(t, 0, 12, 64, 40, ROAD)
    _rect(t, 0, 12, 64, 2, mix(ROAD, (255, 255, 255), 0.25))  # lit rail
    _rect(t, 0, 50, 64, 2, ROAD_DARK)  # shaded rail
    _rect(t, 0, 14, 64, 1, ROAD_DARK)
    # railing posts
    for sx in range(2, 64, 8):
        _rect(t, sx, 12, 2, 4, ROAD_DARK)
        _rect(t, sx, 48, 2, 4, ROAD_DARK)
    # centre dashes matching the road tile
    _rect(t, 12, 30, 12, 4, ROAD_DARK)
    _rect(t, 40, 30, 12, 4, ROAD_DARK)
    # deck plank seams
    for sx in (21, 43):
        _rect(t, sx, 16, 1, 32, mix(ROAD, ROAD_DARK, 0.5))
    return t


def reef(fac: Faction) -> Image.Image:
    t = _water_base(True, 9)
    spots = ((14, 22, 3), (40, 16, 2), (22, 44, 2), (48, 46, 3))
    for sx, sy, size in spots:
        rock = render(buildings.rock_outcrop(size), fac)
        # foam ring where the rock breaks the surface
        _rect(
            t,
            sx - rock.width // 2 - 2,
            sy - 2,
            rock.width + 4,
            2,
            mix(WATER_DARK, SNOW, 0.55),
        )
        _paste_prop(t, rock, sx, sy, shadow=False)
    _rect(t, 8, 56, 10, 2, WATER)
    _rect(t, 52, 8, 8, 2, WATER)
    return t


# ---------------------------------------------------------------------------
# property tiles
# ---------------------------------------------------------------------------


def _grass_lot(fac: Faction, building: str, salt: int) -> Image.Image:
    t = _ground(GRASS, salt)
    prop = render(buildings.BUILDINGS[building](), fac)
    _paste_prop(t, prop, 32, 61, shadow=False)
    return t


def airport(fac: Faction) -> Image.Image:
    t = _ground(ASPHALT, 10, grain=0.04)
    # runway strip across the lower apron
    _rect(t, 0, 44, 64, 16, lighten(ASPHALT, 0.08))
    _rect(t, 0, 44, 64, 1, lighten(ASPHALT, 0.25))
    _rect(t, 0, 59, 64, 1, darken(ASPHALT, 0.2))
    for sx in range(4, 64, 12):
        _rect(t, sx, 51, 6, 2, SNOW)  # centreline dashes
    _rect(t, 2, 46, 2, 12, SNOW)  # threshold bars
    _rect(t, 6, 46, 2, 12, SNOW)
    prop = render(buildings.airport(), fac)
    _paste_prop(t, prop, 31, 46, shadow=False)
    return t


def port(fac: Faction) -> Image.Image:
    t = _water_base(True, 11)
    _rect(t, 4, 50, 12, 2, WATER)  # harbour ripples
    _rect(t, 44, 56, 14, 2, WATER)
    prop = render(buildings.port(), fac)
    _paste_prop(t, prop, 32, 52, shadow=False)
    return t


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


def tile(tid: str, fac: Faction) -> Image.Image:
    """One 64x64 RGBA tile. Non-property tiles ignore the faction."""
    if tid == "road":
        return road()
    if tid == "plains":
        return plains()
    if tid == "woods":
        return woods(fac)
    if tid == "mountain":
        return mountain()
    if tid == "river":
        return river()
    if tid == "city":
        return _grass_lot(fac, "city", 12)
    if tid == "base":
        return _grass_lot(fac, "base", 13)
    if tid == "hq":
        return _grass_lot(fac, "hq", 14)
    if tid == "sea":
        return sea()
    if tid == "airport":
        return airport(fac)
    if tid == "port":
        return port(fac)
    if tid == "shoal":
        return shoal()
    if tid == "bridge":
        return bridge()
    if tid == "reef":
        return reef(fac)
    raise KeyError(tid)
