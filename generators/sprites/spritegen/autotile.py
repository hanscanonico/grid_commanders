"""Direction-aware tile variants: road/river autotiles, bridges, coastlines.

The main terrain atlas keeps its fixed 14-column contract (whole-tile road,
E-W river and bridge) so it stays a drop-in for the game. This module is the
opt-in upgrade path: 16-variant connection sets for roads and rivers, both
bridge orientations, and coast tiles for sea that borders land — so roads can
turn, rivers can flow north-south, and shorelines stop being a hard blue
edge. The demo map composes from these, and sprite_generator exports the
variant sheets under out/autotiles/. Deterministic like everything else here.

Connection masks are N|E|S|W bits naming which neighbours continue the
feature (for coast: which edges touch land). A road's mask 0 falls back to
E|W; a river's is a pond, since a watercourse joined to nothing is a pool.
"""

from __future__ import annotations

from PIL import Image

from .palette import h01, lighten, mix
from .terrain import (
    CELL,
    E,
    GRASS_DARK,
    MOUNTAIN_PHASES,
    N,
    PLAINS_PHASES,
    ROAD,
    ROAD_DARK,
    S,
    SAND,
    SAND_DARK,
    SEA_PHASES,
    SNOW,
    TIMBER,
    TIMBER_DARK,
    W,
    WATER,
    WATER_DARK,
    WATER_LIGHT,
    _ground,
    _lit,
    _rect,
    mountain,
    plains,
    sea,
    woods,
)

_RLO, _RHI = 22, 42  # road band bounds (20px wide)
_WLO, _WHI = 20, 44  # river channel bounds (24px wide)
_BLO, _BHI = 16, 48  # the bank the channel is cut into: 4px of shore a side

# Bank tones, mixed from the ground and water constants the atlas already
# authors under the terrain ceiling rather than written as fresh hexes — the
# woods-seam rule: a bank that carried its own green would step against the
# plains it borders the moment either moved. Silt where the grass gives out,
# its shaded outer edge, and wet mud at the waterline.
BANK = mix(SAND, GRASS_DARK, 0.2)
BANK_DARK = mix(BANK, GRASS_DARK, 0.55)
BANK_WET = mix(SAND_DARK, WATER_DARK, 0.25)

# A run that stops has a rounded nose rather than a sawn-off bar: the water
# ends on a semicircle centred in the joint square, the bank ringing it at the
# same width it keeps along the channel.
_HEAD_R = (_WHI - _WLO) / 2
_BANK_R = _HEAD_R + (_WLO - _BLO)
_POND_R = 14.0  # a standalone cell reads as a pool, so its water is wider

# The pond's own bank (design review round 6). One width and one tone around a
# circle of water is a button: the round-5 pond read as a badge with a cream
# outline. Everything about this ring varies except its minimum — water may
# never meet grass, which is the lip rule the channel tiles are held to — so it
# is widest and darkest on the lower-right, the shadow side away from the light
# every tile is lit from, and thins to that lip in the notches the reeds stand
# in. Its tone is ~20L under the channel's own BANK, mixed from the same ground
# constants: a bank that carried its own hex would step against the shore the
# moment either moved.
POND_BANK = mix(BANK, GRASS_DARK, 0.65)
POND_BANK_DK = mix(POND_BANK, BANK_WET, 0.55)
_POND_LIP = 1
_POND_BANK_MIN, _POND_BANK_MAX = 2.0, 7.0
_POND_SHADE_DIR = (0.5**0.5, 0.5**0.5)  # down-right, away from the light
# Screen directions the reeds stand in, and how wide a clump notches the ring.
_REEDS = ((-0.94, -0.34), (0.20, -0.98), (-0.55, 0.84))
_REED_NOTCH = 0.93


# The two screen directions the light comes from, and the tone each region's
# sunward edge steps up to (see `_edge_pass`). Every one of them is a tone the
# tile already spends — a road stone's highlight, the water's half-glint —
# except the bank's, which is the largest step the ground ceiling leaves over
# BANK itself: the shore is authored right under the plains it borders, so its
# lit edge reads against BANK_DARK opposite rather than against the grass.
_SUNWARD = ((-1, 0), (0, -1))
ROAD_LIT = lighten(ROAD, 0.12)
BANK_LIT = mix(BANK, SAND, 0.25)
WATER_LIT = mix(WATER, WATER_LIGHT, 0.5)


def _closed_half(x: int, y: int, open_bit: int) -> bool:
    """Whether a pixel is past the joint centre on the side a one-connection
    run terminates — the half the nose is cut into."""
    return {
        N: y * 2 >= CELL,
        S: y * 2 < CELL,
        E: x * 2 < CELL,
        W: x * 2 >= CELL,
    }[open_bit]


def _radius(x: int, y: int) -> float:
    half = CELL / 2
    return ((x + 0.5 - half) ** 2 + (y + 0.5 - half) ** 2) ** 0.5


def _fill_arms(img: Image.Image, mask: int, lo: int, hi: int, c) -> None:
    """The joint square plus a rect running to each connected edge."""
    _rect(img, lo, lo, hi - lo, hi - lo, c)
    if mask & N:
        _rect(img, lo, 0, hi - lo, lo, c)
    if mask & S:
        _rect(img, lo, hi, hi - lo, CELL - hi, c)
    if mask & E:
        _rect(img, hi, lo, CELL - hi, hi - lo, c)
    if mask & W:
        _rect(img, 0, lo, lo, hi - lo, c)


def _edge_pass(img: Image.Image, inside, edge_c, outside_c=None, lit_c=None) -> None:
    """Outline a filled region under the sheet's one light.

    Inside pixels touching outside get `edge_c`, and outside pixels touching
    inside optionally get `outside_c` (banks). Where `lit_c` is given the
    outline is DIRECTIONAL, the way `voxel._selective_outline` is on the
    units: an inside pixel whose break is up or left faces the sun, so it
    steps up to `lit_c` instead of going dark, and only the two sides turned
    away from the light keep `edge_c`. An outline of one tone on all four
    sides is a stamped sticker at any zoom — it says the feature is cut out
    of the tile rather than lying on it.
    """
    px = img.load()
    marks = []
    for y in range(CELL):
        for x in range(CELL):
            a = inside(px[x, y][:3])
            broke = [
                (nx - x, ny - y)
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1))
                if 0 <= nx < CELL and 0 <= ny < CELL and a != inside(px[nx, ny][:3])
            ]
            if not broke:
                continue
            if a:
                sunward = lit_c is not None and any(d in _SUNWARD for d in broke)
                marks.append((x, y, lit_c if sunward else edge_c))
            elif outside_c is not None:
                marks.append((x, y, outside_c))
    for x, y, c in marks:
        px[x, y] = (*c, 255)


def road_tile(mask: int) -> Image.Image:
    """A road running to each connected edge over a plains base."""
    if mask == 0:
        mask = E | W
    t = plains()
    _fill_arms(t, mask, _RLO, _RHI, ROAD)
    _edge_pass(t, lambda c: c == ROAD, ROAD_DARK, lit_c=ROAD_LIT)
    # centre dashes along each arm, clear of the joint
    dash = ROAD_DARK
    cy = (_RLO + _RHI) // 2 - 2
    if mask & W:
        _rect(t, 6, cy, 9, 3, dash)
    if mask & E:
        _rect(t, 49, cy, 9, 3, dash)
    if mask & N:
        _rect(t, cy, 6, 3, 9, dash)
    if mask & S:
        _rect(t, cy, 49, 3, 9, dash)
    # a few embedded stones for wear
    for sx, sy in ((26, 26), (36, 37), (30, 34)):
        _rect(t, sx, sy, 3, 2, ROAD_DARK)
        _rect(t, sx, sy, 2, 1, ROAD_LIT)
    return t


def _shape_river(t: Image.Image, base: Image.Image, mask: int) -> None:
    """Cut the channel and its banks into the plains plate `t`, `base` being
    the untouched plate a rounded end gives ground back to."""
    if mask == 0:
        _pond(t, base)
        return
    _fill_arms(t, mask, _BLO, _BHI, BANK)
    _fill_arms(t, mask, _WLO, _WHI, WATER)
    if mask in (N, E, S, W):
        _round_head(t, base, mask)


def _bank_width(ux: float, uy: float) -> float:
    """How far the pond's bank reaches out along the unit direction (ux, uy):
    widest down the shadow diagonal, cut back to the lip in a reed notch."""
    for rx, ry in _REEDS:
        if ux * rx + uy * ry > _REED_NOTCH:
            return _POND_LIP
    shade = ux * _POND_SHADE_DIR[0] + uy * _POND_SHADE_DIR[1]
    return _POND_BANK_MIN + (_POND_BANK_MAX - _POND_BANK_MIN) * (0.5 + 0.5 * shade)


def _reeds(t: Image.Image) -> None:
    """Blades standing in the notches, over the plate rather than over the
    bank: the interruption is what stops the ring reading as a stamped
    outline, and the lip guard is what keeps it a bank all the way round."""
    px = t.load()
    half = CELL / 2
    for rx, ry in _REEDS:
        bx = round(half + rx * (_POND_R + _POND_LIP + 2))
        by = round(half + ry * (_POND_R + _POND_LIP + 2))
        for dx, height in ((-2, 2), (0, 4), (2, 3)):
            for y in range(by - height + 1, by + 1):
                x = bx + dx
                if not (0 <= x < CELL and 0 <= y < CELL):
                    continue
                if _radius(x, y) > _POND_R + _POND_LIP:
                    px[x, y] = (*GRASS_DARK, 255)


def _pond(t: Image.Image, base: Image.Image) -> None:
    """A banked pool: water inside `_POND_R`, a bank of varying weight around
    it, the plate itself beyond — a lone cell is a pond, not a bar."""
    px, bp = t.load(), base.load()
    half = CELL / 2
    for y in range(CELL):
        for x in range(CELL):
            dx, dy = x + 0.5 - half, y + 0.5 - half
            d = (dx * dx + dy * dy) ** 0.5
            if d <= _POND_R:
                px[x, y] = (*WATER, 255)
                continue
            ux, uy = dx / d, dy / d
            if d > _POND_R + _bank_width(ux, uy):
                px[x, y] = bp[x, y]
                continue
            shade = ux * _POND_SHADE_DIR[0] + uy * _POND_SHADE_DIR[1]
            px[x, y] = (*(POND_BANK_DK if shade > 0.25 else POND_BANK), 255)
    _reeds(t)


def _round_head(t: Image.Image, base: Image.Image, open_bit: int) -> None:
    """Taper the closed end of a one-connection run to a rounded nose."""
    px, bp = t.load(), base.load()
    for y in range(CELL):
        for x in range(CELL):
            if not _closed_half(x, y, open_bit):
                continue
            d = _radius(x, y)
            if d <= _HEAD_R:
                continue
            px[x, y] = (*BANK, 255) if d <= _BANK_R else bp[x, y]


def river_tile(mask: int, salt: int = 0) -> Image.Image:
    """A river channel to each connected edge, banked and streaked to match
    its flow direction. `salt` shifts the streak placement so a run of
    same-mask tiles doesn't chain its glints into a dashed line."""
    base = plains()
    t = base.copy()
    _shape_river(t, base, mask)
    shore = {BANK, POND_BANK, POND_BANK_DK, WATER}
    _edge_pass(t, lambda c: c in shore, BANK_DARK, GRASS_DARK, BANK_LIT)
    _edge_pass(t, lambda c: c == WATER, WATER_DARK, BANK_WET, WATER_LIT)
    if mask == 0:
        _rect(t, 25, 30, 7, 2, WATER_LIGHT)
        _rect(t, 34, 36, 5, 1, WATER_LIT)
        return t
    # flow streaks oriented along each arm, drifted per tile
    half = WATER_LIT
    d1 = int(h01(salt, 1, 45) * 10) - 5
    d2 = int(h01(salt, 2, 45) * 8) - 4
    if mask & W:
        _rect(t, 5 + (d1 % 4), 27 + d2 // 2, 9, 2, WATER_LIGHT)
        _rect(t, 8, 36 + d1 // 3, 7, 1, half)
    if mask & E:
        _rect(t, 47 + (d2 % 4), 27 - d1 // 3, 9, 2, WATER_LIGHT)
        _rect(t, 46, 36 + d2 // 2, 7, 1, half)
    if mask & N:
        _rect(t, 27 + d1, 5 + (d2 % 4), 2, 9, WATER_LIGHT)
        _rect(t, 36 + d2, 8, 1, 7, half)
    if mask & S:
        _rect(t, 27 + d2, 47 + (d1 % 4), 2, 9, WATER_LIGHT)
        _rect(t, 36 + d1, 46, 1, 7, half)
    # one glint in the joint
    _rect(t, 29 + d1 // 2, 31 + d2 // 2, 4, 1, WATER_LIGHT)
    return t


def _bridge_h() -> Image.Image:
    """Horizontal timber deck carried over a north-south river."""
    t = river_tile(N | S)
    # support shadows in the water above and below the deck
    for sy in (14, 46):
        _rect(t, 24, sy, 7, 4, mix(WATER, (10, 30, 60), 0.35))
        _rect(t, 34, sy, 7, 4, mix(WATER, (10, 30, 60), 0.35))
    # timber deck, slightly wider than the gravel road band it joins
    _rect(t, 0, 20, 64, 24, TIMBER)
    _rect(t, 0, 20, 64, 2, _lit(TIMBER, 0.25))  # lit rail
    _rect(t, 0, 42, 64, 2, TIMBER_DARK)  # shaded rail
    _rect(t, 0, 22, 64, 1, TIMBER_DARK)
    for sx in range(2, 64, 8):
        _rect(t, sx, 20, 2, 4, TIMBER_DARK)  # railing posts
        _rect(t, sx, 40, 2, 4, TIMBER_DARK)
    for sy in range(24, 42, 6):
        _rect(t, 0, sy, 64, 1, mix(TIMBER, TIMBER_DARK, 0.55))  # plank courses
    for sx in (21, 43):
        _rect(t, sx, 24, 1, 16, mix(TIMBER, TIMBER_DARK, 0.5))  # plank seams
    return t


def bridge_tile(horizontal: bool = True) -> Image.Image:
    t = _bridge_h()
    return t if horizontal else t.transpose(Image.ROTATE_90)


# The shoreline (design review 2026-08-24: the shore was a ruled rectangle).
# The waterline itself carries the wobble now — the lip and the foam follow it
# rather than jittering on their own over a straight cut — and it is drawn the
# way the wood's tree line is: the fixed hash sampled at control points and
# smoothstepped between them, so the boundary is BAYS AND POINTS at a scale the
# board's 4:1 downsample can still see, not per-pixel noise it would eat. One
# control point every 16px and 5px peak to trough — which still leaves 3px of
# dry sand against the tile border at the deepest bay, so water never meets
# the grass of the land cell next door.
#
# The profile is a function of the position ALONG the edge and wraps on the
# cell, so the tile to the left ends exactly where this one begins: a run of
# coast is one continuous shore, which is the plains ring's rule. Coast and
# shoal read the same profile per direction, so a beach cell and the sea cell
# beside it agree on where the water is.
_SHORE_SPAN = 16  # px between control points — a bay, not a jitter
_SHORE_AMP = 5.0  # peak to trough of the waterline
# Four control points is four hash draws, and four draws are as likely to come
# out flat as to come out as a coastline: this salt is the one whose worst
# side of the four still spans 0.87 of the range, so no direction ships a
# shore that happens to be straight.
_SHORE_SALT = 206
_SHORE_R = 7.0  # the radius the beach turns through at an outside corner
_SIDE = {N: 0, E: 1, S: 2, W: 3}


def _shore_wobble(u: int, side: int) -> float:
    """How far the waterline is pushed inland at `u` px along a `side` edge."""
    nodes = CELL // _SHORE_SPAN
    i, f = divmod(u % CELL, _SHORE_SPAN)
    a = h01(i % nodes, side, _SHORE_SALT)
    b = h01((i + 1) % nodes, side, _SHORE_SALT)
    t = f / _SHORE_SPAN
    return (a + (b - a) * t * t * (3 - 2 * t) - 0.5) * _SHORE_AMP


def _shore_profile(edges: int, depth: float) -> dict[int, list[float]]:
    """The wobbled boundary of each active edge, as one distance per pixel
    along it, `depth` being the width the band would have if it were ruled."""
    return {
        bit: [depth + _shore_wobble(u, _SIDE[bit]) for u in range(CELL)]
        for bit in (N, E, S, W)
        if edges & bit
    }


def _inland(x: int, y: int, prof: dict[int, list[float]]) -> tuple[float, int]:
    """How deep (x, y) lies inside the region the profiles enclose, and where
    it stands along the nearest of them.

    Negative is outside. The corner where two edges meet is ROUNDED rather
    than mitred — combining the two depths as a distance to the region eroded
    by `_SHORE_R` is the rounded-rectangle trick — because a beach that turns
    a corner turns through an arc; two crossing bands meeting at 90 degrees
    are what made a coastline read as a picture frame.
    """
    total, near, along = 0.0, _SHORE_R * 4, 0
    for bit, p in prof.items():
        if bit == N:
            d, u = (y + 0.5) - p[x], x
        elif bit == S:
            d, u = (CELL - 0.5 - y) - p[x], x
        elif bit == W:
            d, u = (x + 0.5) - p[y], y
        else:
            d, u = (CELL - 0.5 - x) - p[y], y
        if d < near:
            near, along = d, u
        gap = _SHORE_R - d
        if gap > 0:
            total += gap * gap
    return _SHORE_R - total**0.5, along


def _foam_run(u: int, offset: int, run: int) -> bool:
    """The scallop the breaking foam is cut into: a run of `run` px out of
    every 8 along the shore, alternately longer, so the surf clusters instead
    of dashing evenly like a road marking."""
    k = (u // 8) % 2
    return offset <= u % 8 < offset + run + k * 2


def _draw_shore(t: Image.Image, prof: dict[int, list[float]], beach: bool) -> None:
    """Paint the waterline `prof` describes: water, a one-pixel wet lip on the
    sand side of it, dry sand beyond, and foam breaking on the water side.

    `beach` says which side of the tile the sea is on. A shoal's profiles
    enclose the SAND and the water lies against the tile edge; a coast's
    enclose the water and the sand is the ring. Either way only the half that
    is not the tile's own plate gets painted, so the sea keeps its glints and
    the beach keeps its grain.
    """
    if not prof:
        return
    px = t.load()
    foam_mix = mix(WATER, SNOW, 0.55)
    snow_w = 2.0 if beach else 1.0
    for y in range(CELL):
        for x in range(CELL):
            s, u = _inland(x, y, prof)
            d = -s if beach else s  # depth into the water, either way
            if d < -1.0:
                if not beach:
                    px[x, y] = (*SAND, 255)
            elif d < 0.0:
                px[x, y] = (*SAND_DARK, 255)
            else:
                if beach:
                    px[x, y] = (*WATER, 255)
                if d < snow_w and _foam_run(u, 0, 5):
                    px[x, y] = (*SNOW, 255)
                elif d < snow_w + 1.0 and _foam_run(u, 2, 3):
                    px[x, y] = (*foam_mix, 255)


def coast_tile(edges: int, corners: int = 0) -> Image.Image:
    """Sea with a sand-and-surf shoreline along each landward edge.

    `edges` marks which sides touch land; `corners` (same N|E|S|W bits,
    N=north-east going clockwise: N->NE, E->SE, S->SW, W->NW) adds a small
    corner patch where land touches only diagonally.
    """
    t = sea()
    _draw_shore(t, _shore_profile(edges, 5.0), beach=False)

    # diagonal-only land: a small sand nub in that corner, skipped when an
    # adjacent edge strip already reaches it
    nubs = {N: (CELL - 6, 0), E: (CELL - 6, CELL - 6), S: (0, CELL - 6), W: (0, 0)}
    adjacent = {N: N | E, E: E | S, S: S | W, W: W | N}
    for bit, (cx, cy) in nubs.items():
        if corners & bit and not edges & adjacent[bit]:
            _rect(t, cx, cy, 6, 6, SAND)
            _rect(t, cx, cy + (5 if cy == 0 else 0), 6, 1, SAND_DARK)
            _rect(t, cx + (5 if cx == 0 else 0), cy, 1, 6, SAND_DARK)
            fx = cx + (6 if cx == 0 else -2)
            fy = cy + (6 if cy == 0 else -2)
            _rect(t, fx, fy, 2, 1, SNOW)
    return t


def shoal_tile(edges: int, corners: int = 0) -> Image.Image:
    """A beach tile: dry sand with surf along each seaward edge.

    `edges` marks which sides the water is on; `corners` carries the same
    bits for water that touches only diagonally (N->NE, E->SE, S->SW, W->NW),
    the mirror of `coast_tile`'s.
    """
    if edges == 0:
        edges = S
    t = _ground(SAND, 7)
    _draw_shore(t, _shore_profile(edges, 8.0), beach=True)

    # diagonal-only water: a small pool in that corner, skipped when an
    # adjacent surf band already reaches it
    nubs = {N: (CELL - 6, 0), E: (CELL - 6, CELL - 6), S: (0, CELL - 6), W: (0, 0)}
    adjacent = {N: N | E, E: E | S, S: S | W, W: W | N}
    for bit, (cx, cy) in nubs.items():
        if corners & bit and not edges & adjacent[bit]:
            _rect(t, cx, cy, 6, 6, WATER)
            _rect(t, cx, cy + (5 if cy == 0 else 0), 6, 1, SAND_DARK)
            _rect(t, cx + (5 if cx == 0 else 0), cy, 1, 6, SAND_DARK)
    # dry-sand speckles kept clear of the surf bands
    for sx, sy in ((26, 26), (36, 20), (24, 38), (40, 32)):
        _rect(t, sx, sy, 3, 2, SAND_DARK)
    return t


def woods_tile(mask: int) -> Image.Image:
    """A wood whose canopy runs off each connected edge and scallops to a
    tree line on the rest. Mask 15 — wood on all four sides — is the atlas
    tile exactly, so only a wood's fringe leaves the base sheet."""
    return woods(~mask & 15)


def sheet(tiles: list[Image.Image], cols: int) -> Image.Image:
    """Lay tiles out row-major on the shared 2px-gutter contact sheet."""
    rows = (len(tiles) + cols - 1) // cols
    img = Image.new("RGB", (cols * (CELL + 2) + 2, rows * (CELL + 2) + 2), (52, 52, 60))
    for i, tile in enumerate(tiles):
        x = (i % cols) * (CELL + 2) + 2
        y = (i // cols) * (CELL + 2) + 2
        img.paste(tile.convert("RGB"), (x, y))
    return img


def variant_sheet(builder, cols: int = 4) -> Image.Image:
    """All 16 masks of one builder on a labelled-by-position grid sheet."""
    return sheet([builder(mask) for mask in range(16)], cols)


def bridge_sheet() -> Image.Image:
    """Both deck orientations: E-W over a north-south river, then N-S."""
    return sheet([bridge_tile(True), bridge_tile(False)], 2)


def mountain_sheet() -> Image.Image:
    """The mountain's phase variants, left to right, phase 0 first.

    The sheet contract the sea and the field already use, on the tile a range
    repeats most visibly: the peaks stand somewhere else in each phase while the
    ground line under them does not, so a ridge of them reads as a range on one
    horizon. Phase 0 is the atlas mountain column byte for byte.
    """
    return sheet(
        [mountain(phase) for phase in range(len(MOUNTAIN_PHASES))], len(MOUNTAIN_PHASES)
    )


def plains_sheet() -> Image.Image:
    """The field's phase variants, left to right, phase 0 first.

    Same sheet contract as the sea's and for the same reason: what a field of
    one tile repeats at is the tile, so the fix is more than one tile and a rule
    for choosing between them. Phase 0 is the atlas plains column byte for byte.
    """
    return sheet(
        [plains(phase) for phase in range(len(PLAINS_PHASES))], len(PLAINS_PHASES)
    )


def sea_sheet(frame: int = 0) -> Image.Image:
    """The sea's phase variants, left to right, phase 0 first.

    Phase 0 is the atlas sea column byte for byte, so a board that knows
    nothing about this sheet is unchanged and one that adopts it picks a
    column per cell (the game hashes the coordinate) to break the repeat.

    `frame` is the time frame (`terrain.sea`): the frames are separate sheets
    with the same columns in the same order, so a cell keeps its phase and
    only swaps which sheet it samples — the board animates without rehashing
    anything.
    """
    return sheet(
        [sea(phase, frame) for phase in range(len(SEA_PHASES))], len(SEA_PHASES)
    )
