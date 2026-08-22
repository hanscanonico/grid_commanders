"""The 14 terrain tiles, drawn native at the 64px atlas cell.

Ground hues are the game's tools/generate_tiles.gd palette, revalued under
the ceiling below so scenery never out-keys an army; the detail on top
(painted canopies, terraced mountains, foam, wear) is what this generator
adds. Ground fills are seamless — repeated tiles butt with no
border treatment (design review 2026-08-13: the old darkened-edge
convention read as a seam grid over any open field). Non-property tiles
are identical on every faction row; property tiles are transparent
overlays — a faction-tinted voxel building and its shadow, with the ground
around them left empty for the board to paint (see `property_overlay`).
"""

from __future__ import annotations

from PIL import Image

from . import buildings
from .palette import (
    AMBIENT,
    RGB,
    FACTIONS,
    Faction,
    _at_luminance,
    _full_chroma,
    _rgb_to_hsv,
    _rotate,
    _SKY_HUE,
    darken,
    h01,
    lighten,
    mix,
)
from .palette import luminance as _luminance_601
from .voxel import SHADOW_OFFSET, place_in_cell, render

CELL = 64

# Connection bits, shared with autotile.py: which neighbours a tile's feature
# continues into.
N, E, S, W = 1, 2, 4, 8


def luminance(c: RGB) -> float:
    """Rec. 709 luma, the scale every ceiling in this module is stated on."""
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


# --- ground tone shaping ----------------------------------------------------
#
# The ten ground tones below used to be ten hand-typed literals, and what they
# said about the light was: nothing. A tile's shadow tone was its lit tone with
# the value pulled down and the hue left where it was — grass shifted 2.6°,
# water 2.8°, road and sand and timber under a degree. The units next to them
# have been lit by a sky since the ramp rewrite (`palette.AMBIENT`, up to 14°
# of rotation into the blue on the dark rungs), so the board was two scenes:
# armies under a warm sun and a cool sky, standing on ground lit by neither.
#
# So a shadow tone is now BUILT from its lit tone, by the same three steps
# `palette._shape` builds a ramp's dark rungs with — rotate the hue toward the
# sky, keep a touch more chroma than the lit face, blend in AMBIENT — and then
# re-keyed onto the luma the tone was already authored at. That last step is
# what makes this safe to do wholesale: every value ceiling, every gap between
# two grounds and the `palette.GROUND_BAND` the outline grade is chosen out of
# are properties of the LUMA, and the luma is preserved by construction. Only
# the hue and the chroma move. Measured before/after in docs/terrain_tones.md.
#
# One thing here is not `_shape`'s, and it is what gives the greys a
# TEMPERATURE. `_rotate` moves a hue toward the sky the short way round the
# wheel, which is a sane 6-11° for the grass and the water but meaningless for
# gravel and rock: they sit almost OPPOSITE the sky, so a small rotation is a
# coin flip that lands on red and makes a shadow warmer than the face casting
# it. A tone with that little chroma has no hue to defend, so under
# `_SHADE_GREY` the shaded face simply takes the sky's hue — warm stone in the
# light, cool stone in the shade, the split the greys never had. Above it, the
# tans and the greens keep their own hue and only lean.
_SHADE_HUE = -0.45  # fraction of palette._HUE_ARC rotated toward the sky
_SHADE_SAT = 1.10  # a shaded face keeps slightly more chroma than a lit one
_SHADE_AMBIENT = 0.16  # how much of the sky is mixed into it
_SHADE_GREY = 0.20  # under this saturation, a shadow IS the sky's hue


def _at_value(c: RGB, target: float) -> RGB:
    """`palette._at_luminance`, restated on this module's Rec. 709 scale.

    Both lumas are linear in RGB, so scaling a colour scales both by the same
    factor: asking `_at_luminance` for the Rec. 601 value that the Rec. 709
    target corresponds to lands the result exactly on the target."""
    lum = luminance(c)
    if lum <= 0.0:
        return _at_luminance(c, target)
    return _at_luminance(c, _luminance_601(c) * target / lum)


def _tone(c: RGB, sat: float, value: float | None = None) -> RGB:
    """`c`'s hue at an exact saturation, keyed to `value` (default: its own).

    Chroma at constant luminance — the one move that changes how saturated a
    ground reads without touching a single band or gap it is measured on."""
    h, _, _ = _rgb_to_hsv(c)
    return _at_value(
        _full_chroma(h * 360.0, sat), luminance(c) if value is None else value
    )


def _shade(lit: RGB, value: float) -> RGB:
    """The shadow of a lit ground tone, at the luma that tone's dark was
    authored at. Mirrors `palette._shape`'s dark rungs; see the note above."""
    h, s, _ = _rgb_to_hsv(lit)
    hue = _SKY_HUE if s < _SHADE_GREY else _rotate(h * 360.0, _SHADE_HUE)
    chroma = _full_chroma(hue, min(1.0, s * _SHADE_SAT))
    chroma = mix(chroma, _at_luminance(AMBIENT, _luminance_601(chroma)), _SHADE_AMBIENT)
    return _at_value(chroma, value)


# The terrain value ceiling (fix spec round 4, item 7). The rule was not
# merely unimplemented, it was inverted: plains sat at median L174, road L183
# and shoal L202 while unit pixels top out at L145-165 at the 95th percentile,
# so the ground out-keyed 95% of every army on the board. The top of the ramp
# is reserved for units — L175-255 is theirs — and terrain is authored under
# that line rather than dimmed afterwards, because a post-multiply over a
# finished tile flattens the contrast that separates one ground from another.
TERRAIN_VALUE_CEILING = 175.0  # no more than 5% of a tile's pixels above it
TERRAIN_MEDIAN_CEILING = 165.0  # and no tile's median may reach it
# Property buildings out-keyed units by ~90L (highlights at L248 against a
# unit 95th percentile of 155). Units carry their own highlight band above
# L200; a building may only glint into it — lit windows, glazing — so its
# share there stays a third of the share the unit sheet is held to.
BUILDING_KEY_CEILING = 200.0

# generate_tiles.gd's hues, revalued under the ceiling above. The hues are the
# map's own; what moved is their value, plus the three tans that had collapsed
# into one: road, bridge deck and shoal sand now sit ~18L apart with a hue
# split — gravel grey, timber brown, beach sand — so movement cost reads from
# across the room.
#
# Two more things moved on 2026-08-22, both at constant luma. The chroma of
# the two grounds that cover the board came down — 79% of a map's pixels were
# a saturated green or a saturated blue, which is a poster rather than a place
# and leaves the five armies nothing to be the colourful thing on — and every
# _DARK is now `_shade`d out of its lit tone instead of typed.
# GRASS is S0.51 and not the S0.48 the sweep asked for because of a knife
# edge in `WoodsSeam`: the plains plate and the woods plate are the same GRASS
# under two different grain salts, and they are only tone FOR tone identical
# where the ±3% grain rounds to the same 25 integers on both salts. S0.48
# misses by one tone at each end of the band, which is a seam the test is
# right to refuse. S0.508-0.511 is the admissible window nearest the target.
GRASS = _tone((108, 181, 73), 0.51)  # L158, was S0.60
GRASS_DARK = _shade(GRASS, 128.4)  # L128
ROAD = (146, 142, 133)  # gravel, L142 — road is ground
ROAD_DARK = _shade(ROAD, 111.3)  # L111
TIMBER = (150, 120, 87)  # bridge deck, L124 — bridge is structure
TIMBER_DARK = _shade(TIMBER, 93.1)  # L93
WATER = _tone((63, 143, 220), 0.60)  # 3f8fdc at S0.60, was S0.71
WATER_DARK = _shade(WATER, 102.1)  # L102 — the sky puts the chroma back, S0.64
WATER_LIGHT = _tone((113, 179, 219), 0.41)  # L168, the same drop as WATER
SAND = (178, 166, 127)  # L166
SAND_DARK = _shade(SAND, 139.0)  # L139
SNOW = (168, 174, 182)  # cool foam/marking grey, L173
WILDFLOWER = (214, 163, 57)  # the field's one warm accent, L172

# Woods canopy tones (design review round 3): the tile is a filled canopy
# with its own value band — clearly darker than plains underfoot and than
# verdant hull green (58, 130, 64), so a green unit standing in woods stays
# separable from the tile it occupies.
CANOPY = (36, 96, 44)
CANOPY_DK = (24, 70, 33)
CANOPY_LT = (82, 152, 74)
TRUNK = (109, 76, 65)
# The canopy's lit top plane (design review rounds 6 and 7). A crown drawn as
# one body tone with a rim is a green disc, and a dark or green unit standing
# on it had nothing to separate against — a verdant bomber on woods measured
# 0.00-0.72 ramp steps. The top of each crown catches the light the whole sheet
# is lit from, which is a value step inside the tile rather than a brighter
# tile: both tones are mixed toward the plains ground and stop under its band,
# so the woods plate still cannot out-key the plains it borders.
# Round 6 authored that plane at L143 over a sixteenth of the tile and moved
# verdant-on-woods by 0.021 — a nudge, because a plane that narrow and that
# close to a verdant hull's own top slot (L153) is not something a silhouette
# crosses. Round 7 takes it as far as the seam rule allows: the tone sits one
# luma step under the dimmest plains pixel, which is the ceiling, and the band
# it is painted over is widened (`_crown_light`) until the lit top is the
# crown's dominant plane rather than a fleck on it.
CANOPY_TOP = mix(CANOPY_LT, GRASS, 0.78)
CANOPY_MID = mix(CANOPY_TOP, CANOPY, 0.5)

# Grain salts for the two GRASS grounds. They differ so a wood's clearings do
# not repeat the field's tufts; the tone they perturb is the one GRASS above,
# so a woods cell and the plains it borders cannot step in value.
PLAINS_SALT = 2
WOODS_SALT = 3


def _lit(c: RGB, t: float) -> RGB:
    """A highlight, held under the ceiling. Lightening is the one way an
    authored tone leaves its band, so the ceiling is applied here — on the
    tone, at the moment it is chosen — and scaling keeps its hue."""
    hi = lighten(c, t)
    lum = luminance(hi)
    if lum <= TERRAIN_VALUE_CEILING:
        return hi
    scaled = [v * TERRAIN_VALUE_CEILING / lum for v in hi]
    out = [round(v) for v in scaled]
    # Rounding three channels can put the tone back over the line it was just
    # scaled onto (the grass tuft highlight lands at L175.04). The ceiling is a
    # hard "no pixel above it", so the channel that gained most from rounding
    # gives its step back until the tone is under.
    while luminance(out) > TERRAIN_VALUE_CEILING:
        i = max(range(3), key=lambda j: out[j] - scaled[j])
        out[i] -= 1
    return (out[0], out[1], out[2])


def _grain(c: RGB, bx: int, by: int, salt: int, grain: float = 0.03) -> RGB:
    """One 4px block's tone: `c` nudged by the block's own hash."""
    n = (h01(bx, by, salt) - 0.5) * grain * 2
    return _lit(c, n) if n > 0 else darken(c, -n)


def _ground(c: RGB, salt: int, grain: float = 0.03) -> Image.Image:
    """Base tile: edge-to-edge fill with 4px-block grain (kept at 4px so it
    survives the game's 4:1 nearest downsample). No border treatment — the
    border must be statistically indistinguishable from the interior so
    repeated ground tiles butt seamlessly."""
    img = Image.new("RGBA", (CELL, CELL), (*c, 255))
    px = img.load()
    for by in range(0, CELL, 4):
        for bx in range(0, CELL, 4):
            t = _grain(c, bx, by, salt, grain)
            for yy in range(by, by + 4):
                for xx in range(bx, bx + 4):
                    px[xx, yy] = (*t, 255)
    return img


# The field's second and third grass tones (design review 2026-08-22). The
# ±3% grain above is a texture no eye reads: 97.9% of a plains tile's pixels
# sat within 8L of its mean (sd 4.5), so a board that is ~78% flat green read
# as one painted rectangle per cell. What breaks that is not more grain — a
# per-pixel wobble averages out under the game's 4:1 nearest downsample — but
# CLUMPS: patches of a darker grass, several blocks across, so the field keeps
# a shape at the board's rung as well as at 1x.
# Both tones are mixes toward GRASS_DARK, which keeps the hue the saturated
# green `GroundContrast`'s COLOUR_BREAK relies on, and neither goes below
# GRASS_DARK, the tuft tone at the floor of `palette.GROUND_BAND` — the band
# the outline grade is chosen out of, so a clump cannot make a silhouette's
# ground-facing contour a decision the renderer did not already account for.
# The field DARKENS only: the median stays GRASS and TERRAIN_MEDIAN_CEILING
# keeps its headroom.
CLUMP = mix(GRASS, GRASS_DARK, 0.5)  # L143, 15L under the field
CLUMP_DK = mix(GRASS, GRASS_DARK, 0.88)  # L132, one step over the tuft tone

_CLUMP_LATTICE = 16  # px between field nodes — four across the cell, so it wraps
# Coverage is fixed by RANK, not by a threshold on the field: with four nodes
# across a tile, an absolute cut gave one phase 4% clumps and another 43%. The
# darkest twelfth and the next fifth of each tile's blocks take the two tones,
# so every phase is the same field in a different arrangement — which is what
# lets the woods plate and the plains plate stay tone for tone identical.
_CLUMP_DEEP_SHARE = 0.12
_CLUMP_SHARE = 0.30


def _clump_field(x: int, y: int, salt: int) -> float:
    """A smooth value field on a 16px lattice that wraps at the cell, roughened
    by the block's own hash so a clump's edge is ragged instead of a circle."""
    g = CELL // _CLUMP_LATTICE
    fx, fy = x / _CLUMP_LATTICE, y / _CLUMP_LATTICE
    i, j = int(fx), int(fy)
    tx, ty = fx - i, fy - j
    sx, sy = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)

    def node(a: int, b: int) -> float:
        return h01(a % g, b % g, salt)

    top = node(i, j) * (1 - sx) + node(i + 1, j) * sx
    bot = node(i, j + 1) * (1 - sx) + node(i + 1, j + 1) * sx
    return top * (1 - sy) + bot * sy + (h01(x, y, salt + 101) - 0.5) * 0.3


def _grass_ground(salt: int) -> Image.Image:
    """The grass plate: `_ground`'s grain with the two-tone clump field over
    it, in 4px blocks so a clump survives the game's 4:1 nearest downsample.
    Plains and woods share this plate (see `WoodsSeam`)."""
    img = _ground(GRASS, salt)
    px = img.load()
    blocks = sorted(
        ((bx, by) for by in range(0, CELL, 4) for bx in range(0, CELL, 4)),
        key=lambda b: (_clump_field(b[0], b[1], salt), b),
    )
    deep = round(len(blocks) * _CLUMP_DEEP_SHARE)
    for rank, (bx, by) in enumerate(blocks[: round(len(blocks) * _CLUMP_SHARE)]):
        # A clump is FLAT — the grain the field carries is not repeated inside
        # it. Two reasons: a clump is meant to be a shape at the board's 4:1
        # rung, which a wobble inside it only blurs, and a grained clump spends
        # a colour per rung on a tile already close to the 80-colour ceiling
        # (woods measured 88). Flat also means both plates and all five phases
        # spend exactly these two tones, which is what `WoodsSeam` reads the
        # woods plate against the plains one on.
        tone = CLUMP_DK if rank < deep else CLUMP
        for yy in range(by, by + 4):
            for xx in range(bx, bx + 4):
                px[xx, yy] = (*tone, 255)
    return img


def _rect(img: Image.Image, x0: int, y0: int, w: int, h: int, c: RGB) -> None:
    px = img.load()
    for yy in range(max(0, y0), min(CELL, y0 + h)):
        for xx in range(max(0, x0), min(CELL, x0 + w)):
            px[xx, yy] = (*c, 255)


def _wrap_rect(img: Image.Image, x0: int, y0: int, w: int, h: int, c: RGB) -> None:
    """`_rect` around the tile's edge instead of off it. A prop moved by a phase
    offset has to keep its area, or a phase would be a thinner field rather than
    a differently arranged one."""
    px = img.load()
    for yy in range(y0, y0 + h):
        for xx in range(x0, x0 + w):
            px[xx % CELL, yy % CELL] = (*c, 255)


def _paste_prop(tile: Image.Image, prop: Image.Image, cx: int, bottom: int) -> None:
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
        _rect(t, sx, sy, 2, 1, _lit(ROAD, 0.12))
    return t


# Grass tufts: a dark check with a light blade, like the old speckles but drawn
# as 3px clusters. Followed by a couple of tiny wildflowers, so a big field does
# not tile dead flat.
_TUFTS = (
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
_WILDFLOWERS = ((30, 36), (50, 40))


# A clump's leaves, kept off GRASS_DARK so the tufts stay countable per phase.
_LEAF = darken(GRASS_DARK, 0.18)

# Bare ground worn through the field: road gravel warmed toward beach sand, L125.
# The scuff was drawn in the bridge deck's timber brown, the warmest tone on the
# ground palette — and the board keeps one source pixel in four at its default
# rung, so a 6x3 mark arrives as one or two pixels of it and reads as a stray
# faction pixel. Faction hue is the armies'; a scuff is dirt.
_EARTH = mix(SAND_DARK, ROAD_DARK, 0.5)


def _pebble(t: Image.Image, x: int, y: int) -> None:
    _rect(t, x, y + 1, 3, 2, ROAD_DARK)
    _rect(t, x + 1, y, 2, 1, ROAD)


def _flower_clump(t: Image.Image, x: int, y: int) -> None:
    _rect(t, x, y + 1, 4, 1, _LEAF)
    _rect(t, x, y, 1, 1, WILDFLOWER)
    _rect(t, x + 2, y, 1, 1, SNOW)
    _rect(t, x + 3, y + 1, 1, 1, WILDFLOWER)


def _scuff(t: Image.Image, x: int, y: int) -> None:
    _rect(t, x, y, 6, 3, _EARTH)
    _rect(t, x + 1, y + 1, 4, 1, SAND_DARK)


# A decal is scattered ground detail and nothing more: a stone, a flower clump,
# a patch of bare earth, all in the tile's own tones and all under the terrain
# value ceiling. Deliberately no signpost, fence or marker — a drawn object on
# open ground reads as a property from across the board. A decal is drawn inside
# the cell (`_rect` clips, unlike the tufts' `_wrap_rect`) so it never overhangs
# into the neighbour, and it stands clear of the tufts, which is what keeps
# every phase carrying the same field.
_DECALS = {"pebble": _pebble, "flower": _flower_clump, "scuff": _scuff}

# Phase offsets for plains — the sea's rule (SEA_PHASES below) applied to the
# ground most of a board is made of. Each entry is (salt, prop dx, dy, decals):
# the salt keys BOTH the grain and the clump field, so a phase is a different
# arrangement of the same field rather than the same picture slid sideways, and
# the props stand somewhere else on top of it. Same tone count and the same
# clump coverage every phase, which is what keeps the field's value read a
# phase apart. Phase 0 is the atlas column, so a board that has not adopted the
# sheet is unchanged and adoption is additive.
# The 2026-08-22 review measured the old table as five translations of one tuft
# grid: tile means within 0.31L of each other, with three of the five carrying
# nothing at all. Rarity is the clump field's job now — it is what a stretch of
# field varies BY — so the decals stop being the only difference between phases
# and four of the five carry a find. Phase 0 stays bare because it is the atlas
# column, which is the tile a board falls back to everywhere.
PLAINS_PHASES: tuple[tuple[int, int, int, tuple[tuple[str, int, int], ...]], ...] = (
    (PLAINS_SALT, 0, 0, ()),
    (11, 27, 19, (("flower", 52, 22), ("scuff", 24, 46))),
    (19, 45, 37, (("pebble", 6, 30), ("scuff", 40, 8))),
    (29, 13, 49, (("pebble", 21, 40), ("scuff", 43, 14))),
    (37, 55, 7, (("flower", 12, 22), ("pebble", 45, 50))),
)


def plains(phase: int = 0) -> Image.Image:
    salt, dx, dy, decals = PLAINS_PHASES[phase]
    t = _grass_ground(salt)
    for i, (sx, sy) in enumerate(_TUFTS):
        x, y = sx + dx, sy + dy
        _wrap_rect(t, x, y, 3, 2, GRASS_DARK)
        _wrap_rect(t, x + (i % 2), y - 1, 1, 1, _lit(GRASS, 0.18))
    for fx, fy in _WILDFLOWERS:
        _wrap_rect(t, fx + dx, fy + dy, 1, 1, SNOW)
        _wrap_rect(t, fx + dx + 1, fy + dy, 1, 1, WILDFLOWER)
    for kind, x, y in decals:
        _DECALS[kind](t, x, y)
    return t


# (crown x, crown y, radius) — clustered cover leaving two grass clearings,
# so the tile reads as one occupied canopy rather than scattered props.
_CROWNS = (
    (8, 6, 9),
    (26, 4, 10),
    (45, 8, 10),
    (60, 3, 8),
    (4, 20, 9),
    (19, 18, 10),
    (36, 24, 10),
    (58, 18, 9),
    (10, 34, 10),
    (27, 38, 9),
    (61, 33, 8),
    (5, 50, 9),
    (22, 54, 10),
    (42, 52, 10),
    (59, 50, 9),
    (34, 63, 8),
    (52, 62, 8),
)


def _crowns_within(open_edges: int) -> tuple[tuple[int, int, int], ...]:
    """The crown table with every disc pulled fully inside the cell on the
    edges the wood does not continue across, so a crown is never sliced flat
    by the tile border. A pulled crown stays tangent to that border, so the
    fringe scallops between crowns instead of gapping away from it. Crowns
    keep their authored overhang on a continued edge, which is what lets the
    interior of a wood butt seamlessly."""
    pulled = []
    for cx, cy, r in _CROWNS:
        if open_edges & W:
            cx = max(cx, r)
        if open_edges & E:
            cx = min(cx, CELL - 1 - r)
        if open_edges & N:
            cy = max(cy, r)
        if open_edges & S:
            cy = min(cy, CELL - 1 - r)
        pulled.append((cx, cy, r))
    return tuple(pulled)


def _crown_light(x: int, y: int, dx: float, dy: float, r: int) -> float:
    """How lit a point inside a crown of radius `r` is, on the same up-left
    axis the crown's rim is lit along. The hash term breaks the two tone
    boundaries into leaves — a clean arc reads as a painted stripe."""
    return -(dx * 0.5 + dy) / r + (h01(x, y, 35) - 0.5) * 0.22


def woods(open_edges: int = 0) -> Image.Image:
    """A filled canopy: crowns drawn back to front, each keeping its lit
    top-left rim, over grass that shows only in the clearings and at the
    fringe. The value drop against plains is the tile's read — cover, not
    decoration — and trunks at the fringe say the cover is trees.

    `open_edges` names the borders the wood ends at (see `_crowns_within`);
    0 — every edge continued — is the atlas tile."""
    t = _grass_ground(WOODS_SALT)
    px = t.load()
    covered = [[False] * CELL for _ in range(CELL)]
    for cx, cy, r in sorted(_crowns_within(open_edges), key=lambda c: c[1]):
        rim = (r - 2) * (r - 2)
        for yy in range(max(0, cy - r), min(CELL, cy + r + 1)):
            for xx in range(max(0, cx - r), min(CELL, cx + r + 1)):
                dx, dy = xx - cx, yy - cy
                d = dx * dx + dy * dy
                if d > r * r:
                    continue
                light = _crown_light(xx, yy, dx, dy, r)
                if d > rim:  # crown edge: lit toward the light, shaded away
                    c = CANOPY_LT if dx + dy * 1.5 < 0 else CANOPY_DK
                elif h01(xx, yy, 34) < 0.14:
                    c = CANOPY_DK  # leaf clumps
                elif light > 0.24:
                    c = CANOPY_TOP  # the crown's sunlit top plane
                elif light > -0.08:
                    c = CANOPY_MID  # and its shoulder, so the step is a roll
                else:
                    n = (h01(xx, yy, 33) - 0.5) * 0.12
                    c = _lit(CANOPY, n) if n > 0 else darken(CANOPY, -n)
                px[xx, yy] = (*c, 255)
                covered[yy][xx] = True
    # Contact shadow: the canopy's own shaded rim dropped by SHADOW_OFFSET, on
    # the one rule every caster on the sheet obeys. It used to be a 1px line
    # straight under the fringe, which put the wood's shade on a different sun
    # from the building beside it and from every unit standing on it. It stays
    # a LINE rather than the building's solid silhouette because the clearings
    # between the crowns are the plains plate the tile is measured on
    # (`WoodsSeam`), and a wood is not one massing casting one shadow.
    sx, sy = SHADOW_OFFSET
    for y in range(CELL):
        for x in range(CELL):
            if not covered[y][x] or (
                covered[min(y + 1, CELL - 1)][x] and covered[y][min(x + 1, CELL - 1)]
            ):
                continue  # only the fringe turned away from the light casts
            tx, ty = x + sx, y + sy
            if 0 <= tx < CELL and 0 <= ty < CELL and not covered[ty][tx]:
                px[tx, ty] = (*GRASS_DARK, 255)
    # trunks where the fringe meets the clearings
    for tx, ty in ((46, 31), (12, 59)):
        _rect(t, tx, ty, 2, 3, TRUNK)
        _rect(t, tx, ty, 1, 3, darken(TRUNK, 0.25))
    # a tuft in each clearing
    for sx, sy in ((50, 38), (5, 61)):
        _rect(t, sx, sy, 3, 2, GRASS_DARK)
    return t


# Phase variants for the mountain — the sea's rule (SEA_PHASES below) applied
# to the board's most silhouette-dominant tile, because a range is a wall of
# identical peaks wherever one is repeated. An entry is (peaks, ridges, zig
# seed): where the massif's three summits stand as (apex x, apex y, slope) —
# summit first, then shoulder, then the low foothill, which is the order the
# snow line is read off — the ridge lines and cracks that hang under them, and
# the seed of the per-column snow line. Nothing else
# varies — the ground line and the contact shadow are drawn at a fixed row in
# every phase, so a range sits on one horizon, and the rock and snow tones are
# the tile's throughout (they were authored under the value ceiling). Phase 0
# is the atlas column, so a board that has not adopted the sheet is unchanged.
MOUNTAIN_PHASES: tuple[
    tuple[tuple[tuple[int, int, float], ...], tuple[tuple[int, int, int], ...], int],
    ...,
] = (
    (
        ((26, 10, 1.2), (46, 27, 1.3), (11, 36, 1.5)),
        ((26, 17, 32), (18, 34, 10), (34, 30, 8), (46, 34, 16), (11, 41, 9)),
        7,
    ),
    (
        ((38, 11, 1.25), (17, 26, 1.35), (53, 35, 1.45)),
        ((38, 18, 30), (29, 33, 9), (45, 31, 8), (17, 33, 15), (53, 42, 9)),
        11,
    ),
    (
        ((21, 12, 1.15), (43, 25, 1.35), (54, 38, 1.5)),
        ((21, 19, 30), (13, 33, 10), (32, 32, 8), (43, 32, 15), (54, 45, 7)),
        13,
    ),
)


# The massif's four rock tones, in the order the faces use them: two sunlit,
# two shaded. They are one warm grey under two lights — the lit faces carry the
# sun's own warmth (S0.14, where they used to be the S0.07 of cut card), the
# shaded ones are `_shade`s of the lit face and so take the sky (see
# `_SHADE_GREY`). Every luma is the one the tone was authored at.
ROCK: tuple[RGB, RGB, RGB, RGB] = (
    _tone((166, 161, 153), 0.14),
    _tone((148, 144, 137), 0.14),
    _shade(_tone((148, 144, 137), 0.14), luminance((117, 113, 108))),
    _shade(_tone((148, 144, 137), 0.14), luminance((98, 95, 91))),
)


def mountain(phase: int = 0) -> Image.Image:
    """A painted three-peak massif: light/dark faces split at each ridge,
    jagged dithered snow caps, altitude banding down to a talus skirt."""
    peaks, ridges, zig_seed = MOUNTAIN_PHASES[phase]
    # The massif stands on the same clumped grass plate plains and woods are
    # drawn on: a flat-green apron around a mountain reads as a lighter cell
    # against the field it borders, which is the seam the woods plate was
    # fixed for.
    t = _grass_ground(4)
    px = t.load()
    base_y = 56
    rock_hi, rock_lt, rock_dk, rock_deep = ROCK
    edge = (66, 63, 60)
    # cool light-grey snow, authored under TERRAIN_VALUE_CEILING: the caps
    # were the brightest thing on the board, louder than any unit highlight
    snow_lt = (164, 171, 182)
    snow_dk = (138, 148, 166)
    for x in range(4, 60):
        tops = [int(ay + s * abs(x - ax)) for ax, ay, s in peaks]
        y_top = min(tops)
        if y_top >= base_y - 2:
            continue
        owner = tops.index(y_top)
        ax, ay, _s = peaks[owner]
        lit = x <= ax
        # jagged snow line per column; only the two tall peaks hold snow
        zig = (x * zig_seed) % 3 + ((x // 3) % 2) * 3
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
    for x, y0, ln in ridges:
        for y in range(y0, min(base_y - 1, y0 + ln)):
            if px[x, y][3] == 255 and px[x, y][:3] in (rock_hi, rock_lt, rock_dk):
                px[x, y] = (*mix(rock_dk, edge, 0.5), 255)
    # Contact shadow and scree at the foot. The shadow is the massif's own
    # foot dropped by SHADOW_OFFSET — same sun, same direction as the woods
    # beside it and the units standing on both.
    drop_x, drop_y = SHADOW_OFFSET
    for x in range(6, 58):
        if px[x, base_y - 1][:3] not in (rock_lt, rock_dk, rock_deep):
            continue
        for y in range(base_y, min(CELL, base_y + drop_y)):
            if x + drop_x < CELL:
                px[x + drop_x, y] = (*GRASS_DARK, 255)
    for sx, sy in ((8, 52), (52, 54), (14, 58), (46, 59)):
        _rect(t, sx, sy, 3, 2, GRASS_DARK)
    return t


def _water_base(deep: bool, salt: int) -> Image.Image:
    return _ground(WATER_DARK if deep else WATER, salt, grain=0.027)


def _glints(t: Image.Image, base: RGB, light: RGB, salt: int) -> None:
    """Three hash-placed flow glints: short, staggered, low-contrast.

    The old four dashes sat on the same rows in every repeated tile, and a
    stretch of water read as a lattice from across the room (round 3). The
    hash spreads them with no shared row; nothing here aligns to a grid.
    """
    for i in range(3):
        sx = 3 + int(h01(i, 0, salt) * 42)
        sy = 4 + int(h01(i, 1, salt) * 55)
        w = 7 + int(h01(i, 2, salt) * 7)
        _rect(t, sx, sy, w, 1, mix(base, light, 0.55))
        _rect(t, sx + 2 + i, sy + 1, max(3, w - 4), 1, mix(base, light, 0.3))


def river() -> Image.Image:
    t = _water_base(False, 5)
    _glints(t, WATER, WATER_LIGHT, 78)
    # rounded pebble breaking the current
    _rect(t, 28, 54, 6, 3, mix(WATER, WATER_DARK, 0.7))
    _rect(t, 29, 53, 4, 1, mix(WATER, WATER_LIGHT, 0.55))
    return t


# Phase offsets for the sea (design review rounds 3 and 6). One sea tile
# repeated over a whole frame is visibly row-aligned however the glints are
# spread inside it, because every cell spreads them the same way — the lattice
# is the repeat, not the tile. Each entry is (grain salt, glint salt): a
# variant is the same water with its texture and its flow in a different phase.
# Variant 0 is the atlas column, so it stays exactly what it was and the game
# can adopt the rest one at a time.
SEA_PHASES: tuple[tuple[int, int], ...] = ((6, 73), (14, 91), (23, 108))


def sea(phase: int = 0) -> Image.Image:
    grain, glint = SEA_PHASES[phase]
    t = _water_base(True, grain)
    _glints(t, WATER_DARK, WATER, glint)
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
    """A timber deck standing over the water. The deck is deliberately not
    the road tile's gravel: the two shared one dominant colour, so a bridge
    read as a road that happened to be wet."""
    t = _water_base(False, 8)
    # support shadows in the water under each pier
    for sx in (8, 28, 48):
        _rect(t, sx, 50, 10, 4, mix(WATER, (10, 30, 60), 0.35))
    _rect(t, 0, 12, 64, 40, TIMBER)
    _rect(t, 0, 12, 64, 2, _lit(TIMBER, 0.25))  # lit rail
    _rect(t, 0, 50, 64, 2, TIMBER_DARK)  # shaded rail
    _rect(t, 0, 14, 64, 1, TIMBER_DARK)
    # railing posts
    for sx in range(2, 64, 8):
        _rect(t, sx, 12, 2, 4, TIMBER_DARK)
        _rect(t, sx, 48, 2, 4, TIMBER_DARK)
    # plank courses across the deck, the structure's own grain
    for sy in range(18, 50, 6):
        _rect(t, 0, sy, 64, 1, mix(TIMBER, TIMBER_DARK, 0.55))
    # deck plank seams
    for sx in (21, 43):
        _rect(t, sx, 16, 1, 32, mix(TIMBER, TIMBER_DARK, 0.5))
    return t


def reef() -> Image.Image:
    t = _water_base(True, 9)
    spots = ((14, 22, 3), (40, 16, 2), (22, 44, 2), (48, 46, 3))
    for sx, sy, size in spots:
        # rock materials are faction-independent; any row renders the same
        rock = render(buildings.rock_outcrop(size), FACTIONS[0])
        # foam ring where the rock breaks the surface
        _rect(
            t,
            sx - rock.width // 2 - 2,
            sy - 2,
            rock.width + 4,
            2,
            mix(WATER_DARK, SNOW, 0.55),
        )
        _paste_prop(t, rock, sx, sy)
    _rect(t, 8, 56, 10, 2, WATER)
    _rect(t, 52, 8, 8, 2, WATER)
    return t


# ---------------------------------------------------------------------------
# property tiles
# ---------------------------------------------------------------------------


# Where each building stands in its cell: (centre x, ground line). One
# statement, read by the atlas tiles and by the iso_buildings cells, so the
# two can never place the same building differently.
PROPERTY_ANCHOR: dict[str, tuple[int, int]] = {
    "city": (32, 61),
    "base": (32, 61),
    "hq": (32, 61),
    "airport": (31, 46),
    "port": (32, 52),
}

# The shadow a building drops on whatever ground it is standing on: the
# building's own silhouette, shifted down-right away from the light every
# model is lit from, in the same tone AND by the same offset the unit cells
# cast (`voxel.SHADOW_OFFSET`, re-exported here — one sun for the sheet).
#
# The tone is the sky, keyed down: a cast shadow is the one surface on the
# sheet lit by AMBIENT and nothing else, so it is stated as AMBIENT's hue at a
# third of its chroma at L18 rather than as a near-black literal — a black
# shadow reads as a hole punched in the board rather than as shade on it, and
# a typed triple gives no way to tell which of the two it is.
#
# It evaluates to (16, 18, 24), the exact literal it replaces: the shadow was
# already the sky at S0.33, which nothing said out loud. So `voxel.SHADOW`,
# the unit cells' copy of the same triple, still agrees with it byte for byte
# — one sun and one sky for the sheet. If this derivation is ever retuned,
# that constant has to move with it.
SHADOW = _tone(AMBIENT, 0.34, 18.0)


def _drop_shadow(cell: Image.Image, sprite: Image.Image, x0: int, y0: int) -> None:
    """Stamp `sprite`'s silhouette into `cell` as a hard SOLID shadow.

    Opaque pixels, never partial alpha: the sheet is read at 16px on the board
    and blown up in the cut-in, and a soft alpha edge is a halo at one end and
    a grey stain at the other.

    It used to be a 1px checkerboard, so that half the pixels missing let the
    ground the board paints underneath read through. That argument only ever
    held at one sampling ratio: the board draws this 64px cell onto a 16px
    grid with nearest filtering at whole zoom rungs 1..5, keeping one source
    pixel in 4/z, and a 1px parity is a different picture at every one of them
    — solid zoomed out, thin at the default rung, and loose dots at rung 4
    where the art is 1:1, which is the stippled fringe a city wore. The units'
    cast shadow went solid for the same measurement (`voxel._shadow_ellipse`);
    this is the same contract, on the drawer that had been left behind.
    """
    px = cell.load()
    sp = sprite.load()
    dx, dy = SHADOW_OFFSET
    for yy in range(sprite.height):
        for xx in range(sprite.width):
            if sp[xx, yy][3] == 0:
                continue
            tx, ty = x0 + xx + dx, y0 + yy + dy
            if not (0 <= tx < CELL and 0 <= ty < CELL):
                continue
            px[tx, ty] = (*SHADOW, 255)


def property_overlay(bid: str, fac: Faction) -> Image.Image:
    """A property cell: the building and its shadow, on transparent ground.

    Design review rounds 4 and 5: baking the plains green into these five
    columns painted a green square around every city standing on road, beach
    or asphalt. The building keeps its own base plate — the plate is part of
    the model, the isometric footprint it stands on — and everything around
    it is left empty, so the board draws the ground and the building reads as
    an object sitting on it rather than as a tile of its own.
    """
    t = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    prop = render(buildings.model_for(bid, fac), fac)
    cx, bottom = PROPERTY_ANCHOR[bid]
    x0, y0 = cx - prop.width // 2, bottom - prop.height
    _drop_shadow(t, prop, x0, y0)
    place_in_cell(t, prop, x0, y0)
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
