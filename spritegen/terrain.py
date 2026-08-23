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
from .voxel import SHADOW_OFFSET, place_in_cell, render, render_indexed

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
# (That knife edge is blunt since 2026-08-23: the grain is a ramp of three
# steps, so both salts spend the same three tones whatever the chroma is.
# Whether S0.48 is reachable again is a chroma question, not a seam one, and
# it is not asked here.)
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
WILDFLOWER = (214, 163, 57)  # L172 — unspent since 2026-08-23, when the
# field's warm flecks came off it: at 1-3px a hue-40 pixel on a hue-100
# ground is a dead pixel, not a flower (see `_DECALS`).

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
    """One 4px block's tone: `c` on a three-step ramp, picked by the block's
    own hash.

    The nudge used to be CONTINUOUS — every block a mix of its own — and the
    2026-08-23 index read what that costs: one plains tile carried 29 colours,
    28 of them green, 17 inside a single 0.03 slice of luma. A ramp of three
    steps is the same texture (the hash still decides which block is lighter)
    for three tones, which is what an indexed sheet is: a ground spends the
    tones it authored, not a tone per block.
    """
    step = min(2, int(h01(bx, by, salt) * 3))
    if step == 2:
        return _lit(c, grain)
    if step == 0:
        return darken(c, grain)
    return c


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

_BLOCK = 4  # px — the field's unit, kept at the game's 4:1 downsample step
_BLOCKS = CELL // _BLOCK
# The darkest twelfth and the next fifth of each tile's blocks take the two
# tones (by rank — see `_rank_clumps`), so every phase is the same field in a
# different arrangement, which is what lets the woods plate and the plains
# plate stay tone for tone identical.
_CLUMP_DEEP_SHARE = 0.12
_CLUMP_SHARE = 0.30

# The field's period, and why it is 60 and not 64 (seam pass, 2026-08-23).
#
# The clump field wrapped at the CELL, which makes one phase repeat seamlessly
# — and the game does not repeat one phase. It hashes a phase per cell, so what
# actually butts on a board is phase 3's right edge against phase 1's left, and
# those were two different fields cut off at the border: the mean luma step
# across a 64px boundary on a hashed 8x8 field measured 9.6 against 1.9 inside
# a tile, a five-fold discontinuity that quilts an open field.
#
# Two tiles can only butt without a step if their edges are THE SAME PIXELS, so
# the outermost block ring is drawn from one shared field (`_SEAM_SALT`) that
# every phase carries, and each phase's own field dithers in over `_SEAM_FADE`
# blocks behind it. The shared field has a period of 60px — fifteen blocks —
# so the ring's last block column IS its first: block column 15 starts at x=60
# and reads the same field value as block column 0, so the two 4px blocks that
# meet at a seam carry one tone, whichever phases meet. The period is the
# field's own rather than a duplicated column, which is what keeps the ring
# smooth against the interior it fades into.
_CLUMP_PERIOD = 60
_CLUMP_LATTICE = _CLUMP_PERIOD // 4  # px between field nodes, four to a period
_SEAM_SALT = 5
_SEAM_FADE = 2  # blocks over which a phase's own field takes over from it


def _clump_field(x: int, y: int, salt: int) -> float:
    """A smooth value field on a lattice that wraps every `_CLUMP_PERIOD` px in
    both axes, roughened by the block's own hash so a clump's edge is ragged
    instead of a circle."""
    px_, py = x % _CLUMP_PERIOD, y % _CLUMP_PERIOD
    fx, fy = px_ / _CLUMP_LATTICE, py / _CLUMP_LATTICE
    i, j = int(fx), int(fy)
    tx, ty = fx - i, fy - j
    sx, sy = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)

    def node(a: int, b: int) -> float:
        return h01(a % 4, b % 4, salt)

    top = node(i, j) * (1 - sx) + node(i + 1, j) * sx
    bot = node(i, j + 1) * (1 - sx) + node(i + 1, j + 1) * sx
    return top * (1 - sy) + bot * sy + (h01(px_, py, salt + 101) - 0.5) * 0.3


def _seam_key(bxi: int, byi: int) -> tuple[int, int]:
    """A border block's index on the shared ring, folded onto the field's
    period: 15 becomes 0, so a tile's last block column IS its first."""
    return bxi % (_CLUMP_PERIOD // _BLOCK), byi % (_CLUMP_PERIOD // _BLOCK)


def _own_field(bxi: int, byi: int, salt: int) -> float:
    """The field value a block takes behind the shared ring.

    The hand-over is DITHERED, not averaged: a block one step in takes its own
    phase's field or the shared one by its own hash, in the proportion
    `_SEAM_FADE` asks for. Averaging two fields halves their variance, and the
    field is ranked — so a smooth fade put every phase's darkest blocks in the
    middle of its tile and drew a sparse frame around every cell, which is the
    quilt this pass exists to remove. A dither keeps the distribution the rank
    is taken over identical everywhere.
    """
    edge = min(bxi, byi, _BLOCKS - 1 - bxi, _BLOCKS - 1 - byi)
    x, y = bxi * _BLOCK, byi * _BLOCK
    w = min(1.0, edge / _SEAM_FADE)
    keep = h01(bxi, byi, salt + 211) < w
    return _clump_field(x, y, salt if keep else _SEAM_SALT)


def _ring_layout() -> dict[tuple[int, int], RGB]:
    """The border every phase carries, ranked over the shared field alone."""
    field = {
        (bxi, byi): _clump_field(bxi * _BLOCK, byi * _BLOCK, _SEAM_SALT)
        for byi in range(_BLOCKS)
        for bxi in range(_BLOCKS)
    }
    return _rank_clumps(field, round(len(field) * _CLUMP_SHARE))


def _rank_clumps(
    field: dict[tuple[int, int], float], count: int, deep: int | None = None
) -> dict[tuple[int, int], RGB]:
    """The darkest `count` of `field`'s blocks, the darkest `deep` of them in
    the deeper tone. Coverage is fixed by RANK, not by a threshold on the
    field: with four nodes across a tile, an absolute cut gave one phase 4%
    clumps and another 43%."""
    if deep is None:
        deep = round(len(field) * _CLUMP_DEEP_SHARE)
    order = sorted(field, key=lambda b: (field[b], b))[:count]
    return {b: (CLUMP_DK if i < deep else CLUMP) for i, b in enumerate(order)}


def _clump_layout(salt: int) -> dict[tuple[int, int], RGB]:
    """Which of a tile's 4px blocks a phase clumps, and with which tone.

    The border ring is the shared one, read at its folded index; the interior
    is the phase's own field, ranked to whatever the ring left of the tile's
    fixed clump budget. Every phase therefore spends the same number of blocks
    on each tone — the two plates and the five phases stay one field in
    different arrangements — while their edges stay identical.
    """
    ring = _ring_layout()
    layout = {}
    for byi in range(_BLOCKS):
        for bxi in range(_BLOCKS):
            if bxi in (0, _BLOCKS - 1) or byi in (0, _BLOCKS - 1):
                tone = ring.get(_seam_key(bxi, byi))
                if tone is not None:
                    layout[(bxi, byi)] = tone
    total, deep = (
        round(_BLOCKS**2 * _CLUMP_SHARE),
        round(_BLOCKS**2 * _CLUMP_DEEP_SHARE),
    )
    inner = {
        (bxi, byi): _own_field(bxi, byi, salt)
        for byi in range(1, _BLOCKS - 1)
        for bxi in range(1, _BLOCKS - 1)
    }
    ring_deep = sum(1 for tone in layout.values() if tone == CLUMP_DK)
    layout.update(_rank_clumps(inner, total - len(layout), max(0, deep - ring_deep)))
    return layout


def _grass_ground(salt: int) -> Image.Image:
    """The grass plate: the three-step grain with the two-tone clump field over
    it, in 4px blocks so a clump survives the game's 4:1 nearest downsample.
    Plains and woods share this plate (see `WoodsSeam`)."""
    img = Image.new("RGBA", (CELL, CELL), (*GRASS, 255))
    px = img.load()
    layout = _clump_layout(salt)
    for byi in range(_BLOCKS):
        for bxi in range(_BLOCKS):
            # The border ring's grain is the shared one too, read at the same
            # folded index the ring's clumps are: a tile's last block column is
            # its first, so any two phases butt with no step at all.
            border = bxi in (0, _BLOCKS - 1) or byi in (0, _BLOCKS - 1)
            kx, ky = _seam_key(bxi, byi) if border else (bxi, byi)
            key_salt = _SEAM_SALT if border else salt
            # A clump is FLAT — the grain the field carries is not repeated
            # inside it. Two reasons: a clump is meant to be a shape at the
            # board's 4:1 rung, which a wobble inside it only blurs, and a
            # grained clump spends a colour per rung on a tile already close
            # to the 80-colour ceiling (woods measured 88). Flat also means
            # both plates and all five phases spend exactly these two tones,
            # which is what `WoodsSeam` reads the woods plate against the
            # plains one on.
            tone = layout.get((bxi, byi))
            if tone is None:
                tone = _grain(GRASS, kx * _BLOCK, ky * _BLOCK, key_salt)
            for yy in range(byi * _BLOCK, byi * _BLOCK + _BLOCK):
                for xx in range(bxi * _BLOCK, bxi * _BLOCK + _BLOCK):
                    px[xx, yy] = (*tone, 255)
    return img


def _rect(img: Image.Image, x0: int, y0: int, w: int, h: int, c: RGB) -> None:
    px = img.load()
    for yy in range(max(0, y0), min(CELL, y0 + h)):
        for xx in range(max(0, x0), min(CELL, x0 + w)):
            px[xx, yy] = (*c, 255)


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
# as 3px clusters.
#
# The pair of wildflowers that used to follow them is gone (2026-08-23). They
# were two pixels of WILDFLOWER (H40 S0.73) and two of SNOW (H214) on a hue-100
# field, at the size the board keeps one source pixel in four of: an off-palette
# fleck reads as a dead pixel, not as a flower. What a stretch of field varies
# by is the clump field; a find is a decal, and every decal is on the field's
# own ramp now.
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


# A clump's leaves, kept off GRASS_DARK so the tufts stay countable per phase.
_LEAF = _tone(GRASS_DARK, 0.44, 105.0)  # L105, S0.44 — a find's chroma bound
_BLADE = _lit(GRASS, 0.18)  # the tuft's lit blade, which a decal reuses

# The decal tones, all of them ON THE FIELD'S RAMP (2026-08-23). A decal used
# to be drawn out of the grounds it depicted — gravel for a stone, sand and
# gravel for a scuff — and at 1-3px on a hue-100 field those are not a stone
# and a scuff, they are three dead pixels: gravel is H41 S0.09, its shadow
# H225, the wildflower H40 S0.73. Nothing that small carries a material; what
# it carries is a hue, so a find is drawn in grass's own hue held under S0.45,
# which is a lichen-grey stone and a patch of dry, bleached grass. The dry tone
# leans 20° toward sand — as far as a find may go — so a patch still reads as
# ground worn thin rather than as more clump.
_STONE = _tone(GRASS, 0.10, 152.0)  # H100 S0.10, L152
_STONE_DK = _tone(GRASS, 0.14, 120.0)
_DRY_BASE = mix(GRASS, SAND, 0.55)
_DRY = _tone(_DRY_BASE, 0.34, 147.0)  # H80 S0.34, L147
_DRY_DK = _tone(_DRY_BASE, 0.38, 127.0)


def _pebble(t: Image.Image, x: int, y: int) -> None:
    _rect(t, x, y + 1, 3, 2, _STONE_DK)
    _rect(t, x + 1, y, 2, 1, _STONE)


def _tussock(t: Image.Image, x: int, y: int) -> None:
    """A knot of taller grass: a leaf base with two blades out of it."""
    _rect(t, x, y + 1, 4, 1, _LEAF)
    _rect(t, x, y, 1, 1, _LEAF)
    _rect(t, x + 2, y, 1, 1, _BLADE)
    _rect(t, x + 3, y + 1, 1, 1, _LEAF)


def _dry_patch(t: Image.Image, x: int, y: int) -> None:
    _rect(t, x, y, 6, 3, _DRY)
    _rect(t, x + 1, y + 1, 4, 1, _DRY_DK)


# A decal is scattered ground detail and nothing more: a stone, a knot of tall
# grass, a patch the summer has dried out — all in the field's own tones and
# all under the terrain value ceiling. Deliberately no signpost, fence or
# marker — a drawn object on open ground reads as a property from across the
# board. A decal is drawn inside the cell (`_rect` clips) so it never overhangs
# into the neighbour, and it stands clear of the tufts, which is what keeps
# every phase carrying the same field.
_DECALS = {"pebble": _pebble, "tussock": _tussock, "dry": _dry_patch}

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
# The salts were re-picked on 2026-08-23, when the border ring became shared:
# the ring is a fifth of a tile's clumps laid the same way in every phase, a
# floor of ~0.15 under any two phases' layout overlap, so the four that are
# free are the four whose interiors agree least — 0.31 at the worst pair,
# against 0.47 for the salts the table happened to hold.
PLAINS_PHASES: tuple[tuple[int, int, int, tuple[tuple[str, int, int], ...]], ...] = (
    (PLAINS_SALT, 0, 0, ()),
    (8, 27, 19, (("tussock", 52, 22), ("dry", 24, 46))),
    (13, 45, 37, (("pebble", 6, 30), ("dry", 40, 8))),
    (20, 13, 49, (("pebble", 21, 40), ("dry", 43, 14))),
    (49, 55, 7, (("tussock", 12, 22), ("pebble", 45, 50))),
)

# A tuft is drawn whole, inside the cell. It used to WRAP around the tile,
# which is seamless for one phase repeated and is not what the game does: it
# hashes a phase per cell, so a tuft cut at phase 3's right edge met phase 1's
# uncut left edge and the cut showed. The offset is folded into the cell and
# then held off the border, so every phase still carries all twelve tufts —
# what moves is where they stand, not how many survive.
_TUFT_MARGIN = 1


def _tuft_at(sx: int, sy: int, dx: int, dy: int) -> tuple[int, int]:
    """Where a tuft stands once its phase offset is folded into the cell.

    Both axes are clamped off the outermost pixel ring on both sides — the
    ring is the shared one every phase carries, and a tuft painted into it
    would be the one pixel that is not shared and so the one that seams. The
    low bound on y is one further in because the blade is drawn a row above.
    """
    span = CELL - _TUFT_MARGIN - 3
    x = min(max((sx + dx) % CELL, _TUFT_MARGIN), span)
    y = min(max((sy + dy) % CELL, _TUFT_MARGIN + 1), span)
    return x, y


def plains(phase: int = 0) -> Image.Image:
    salt, dx, dy, decals = PLAINS_PHASES[phase]
    t = _grass_ground(salt)
    for i, (sx, sy) in enumerate(_TUFTS):
        x, y = _tuft_at(sx, sy, dx, dy)
        _rect(t, x, y, 3, 2, GRASS_DARK)
        _rect(t, x + (i % 2), y - 1, 1, 1, _BLADE)
    for kind, x, y in decals:
        _DECALS[kind](t, x, y)
    return t


# The wood, in the projection everything else on the sheet is drawn in.
#
# A crown was an orthographic CIRCLE — a disc of leaf tone with a rim, the one
# shape this dimetric cannot produce. A canopy is a ground-parallel thing seen
# from the sheet's camera, and the camera turns a ground-parallel disc into a
# 2:1 ellipse: twice as wide as it is deep, which is the same 2:1 a voxel's top
# face is drawn at and the same 2:1 the massif's foot lies on. So a crown is
# that ellipse — the canopy's TOP PLANE — with the leaf mass hanging under it,
# and the bands on it are planes rather than a painted gradient: the top plane
# lit, its rim lit or shaded by which way it faces the sun, the mass under it
# rolling off from the shoulder to the shaded side.
#
# The old crown was also the noisiest object on the sheet: a per-pixel hash on
# the body tone and a 14% leaf speckle put 53.7% of the tile on a colour change
# against its right-hand neighbour (the mountain, the tile with the most
# geometry, ran 21%) and spent 77 colours doing it. The hash stays, but only
# where a hash belongs — in the DECISION, ragging the boundary between two
# bands so an arc does not read as a painted stripe. It no longer makes tones.
#
# Banding a crown that way also drew every crown as the same stamp: one shallow
# skirt, laid in six courses on a 12.8px pitch, its lit rim ringing each ellipse
# — and the 2026-08-23 review read the tile as roof shingles, a tray of green
# pills rather than as cover. The plane and its bands are kept; what changed is
# everything a wood is supposed to VARY by.
#
#   size    `_crown_depth` hangs the mass a crown's own width deep and tapers
#           it, so a crown is a ball of leaves at one of five sizes rather
#           than one lid on one skirt.
#   place   the table is scattered (no two crowns share a row) and every
#           centre is moved again by `_crown_jitter`.
#   order   `_crown_order` shuffles the painter's sort, so a crown is not
#           always laid over the one behind it in the same direction.
#   edge    the crown outline is hash-ragged, and the rim is split on the
#           sun's own axis and ragged across it, so it reads as a highlight
#           and not as an outline drawn round every ellipse.
#   surface `_dapple` speckles inside a band, one step along the same ramp.
#   fringe  a pulled crown stops SHORT of its border by a hash (`_crowns_
#           within`), so a wood's outer boundary is bays and points rather
#           than a rectangle, and the trunks belong to crowns rather than to
#           fixed tile coordinates.
#
# Measured on the row profile: the strongest period between 8 and 16px — the
# band a course of crowns lands in — was 12.05L on the shingled tile's worst
# variant and is 6.2L on this one's, 3.3L on the atlas tile, against 0.7L for
# the bare plate underneath (`CanopyGrain`).


def _crown_depth(r: int) -> int:
    """How far a crown's leaf mass hangs under its top plane. It scales with
    the crown, because a canopy of one depth reads as one stamp repeated
    however wide the plane over it is drawn."""
    return r + 1


# (crown x, crown y, radius): the centre of the top plane and its half-WIDTH.
# Twenty-four crowns in five half-widths, scattered rather than coursed —
# twenty-one distinct rows between them and uneven gaps, which is what keeps
# a horizontal row profile from carrying one period. The gaps that survive the
# overlap are the wood's clearings: they are the plains plate `WoodsSeam`
# reads the tile against, and the trunks stand at their heads. Every centre is
# moved again by `_crown_jitter`.
_CROWNS = (
    (36, 0, 9),
    (24, 5, 11),
    (60, 5, 8),
    (41, 7, 10),
    (12, 10, 7),
    (25, 12, 9),
    (51, 13, 11),
    (14, 19, 8),
    (33, 19, 10),
    (42, 25, 9),
    (61, 25, 7),
    (15, 27, 11),
    (56, 32, 9),
    (43, 34, 11),
    (31, 37, 8),
    (13, 39, 10),
    (46, 42, 7),
    (3, 45, 9),
    (31, 48, 11),
    (44, 51, 8),
    (22, 53, 10),
    (62, 55, 9),
    (55, 61, 7),
    (5, 63, 11),
)


def _crown_reach(r: int) -> tuple[int, int]:
    """How far a crown of half-width `r` reaches above and below its centre:
    half the width up (the ellipse) and that plus the mass hanging under it."""
    return r // 2, r // 2 + _crown_depth(r)


def _crown_jitter(cx: int, cy: int) -> tuple[int, int]:
    """Two hash draws that take a crown off the lattice it was authored on.
    The table is hand-placed, so it is regular however carefully it is typed;
    this is the fixed hash spending its one job on a POSITION rather than on
    a tone, and it is what stops the courses from lining up into stripes."""
    return int(h01(cx, cy, 51) * 5) - 2, int(h01(cx, cy, 53) * 7) - 3


def _crowns_within(open_edges: int) -> tuple[tuple[int, int, int, tuple], ...]:
    """Where each crown stands in this variant, as (x, y, r, copies).

    A crown is jittered off the authored table, then PULLED fully inside the
    cell on every edge the wood does not continue across, so it is never
    sliced flat by the tile border. A pulled crown stops a hash-keyed 0-6px
    SHORT of tangent, so the tree line rags instead of laying every crown
    against one straight edge — a wood's outer boundary is the only place the
    block silhouette is visible at all, and tangent crowns drew it as a
    rectangle. The pull is by the crown's REACH, which is not its width: the
    ellipse is half as deep as it is wide and the mass hangs below it.

    `copies` is where the same crown has to be drawn AGAIN, a whole cell
    away, for this tile to butt against the wood beside it: the tile over a
    continued border is drawing this crown a cell along, so the half of it
    that overhangs the seam is this tile's to finish. Clipped instead of
    copied — which is what the first projection pass did — the two halves are
    different crowns and a wood's interior comes out on a visible tile grid.
    A copy takes the neighbour's own coordinate on the axis it crosses, which
    is the UNPULLED one: the neighbour has wood on that side, so it did not
    pull there."""
    placed = []
    for cx, cy, r in _CROWNS:
        jx, jy = _crown_jitter(cx, cy)
        jx, jy = cx + jx, cy + jy
        up, down = _crown_reach(r)
        rag = int(h01(jx, jy, 57) * 7)
        cx, cy = jx, jy
        if open_edges & W:
            cx = max(cx, r + rag)
        if open_edges & E:
            cx = min(cx, CELL - 1 - r - rag)
        if open_edges & N:
            cy = max(cy, up + rag)
        if open_edges & S:
            cy = min(cy, CELL - 1 - down - rag)
        xs = [(cx, cy)]
        if not open_edges & W:
            xs.append((jx - CELL, cy))
        if not open_edges & E:
            xs.append((jx + CELL, cy))
        places = list(xs)
        for x, _ in xs:
            if not open_edges & N:
                places.append((x, jy - CELL))
            if not open_edges & S:
                places.append((x, jy + CELL))
        copies = tuple(
            (x, y)
            for x, y in places[1:]
            if x + r >= 0 and x - r < CELL and y + down >= 0 and y - up < CELL
        )
        placed.append((cx, cy, r, copies))
    return tuple(placed)


def _crown_order(crowns: tuple) -> list:
    """Back to front, hash-shuffled. A strict sort by depth laid every crown
    over the one behind it in the same direction, which is the brick course
    the shingle reading came from; a crown that is sometimes BEHIND its
    neighbour instead makes the overlap irregular."""
    return sorted(crowns, key=lambda c: c[1] + (h01(c[0], c[1], 59) - 0.5) * 13)


def _crown_light(x: int, y: int, dx: float, dy: float, r: int) -> float:
    """How lit a point on a crown's top plane is, on the up-left axis the whole
    sheet is lit from, in -1..1. `dy` is doubled because the plane is a 2:1
    ellipse: a pixel of screen y is two of ground. The hash term breaks the
    band boundary into leaves — a clean arc reads as a painted stripe."""
    return -(dx + dy * 2.0) / (r * 2.0) + (h01(x, y, 35) - 0.5) * 0.22


def _dapple(x: int, y: int, c: RGB) -> RGB:
    """Leaf speckle inside a band: a hash-keyed step to the neighbouring tone
    of the SAME canopy ramp, so the plane keeps its value and its colour count
    and only its surface breaks up. Keyed on a 2x2 cell rather than per pixel
    — a per-pixel speckle is finer than the board's 4:1 downsample, arrives as
    a different random pixel per frame of camera movement, and is what put
    this tile at 53.7% colour change before the projection pass
    (`TileTexture`). Two draws in ten, so the leaves read at 1:1 without the
    tile spending its texture budget on them."""
    if c is CANOPY_TOP and h01(x >> 1, y >> 1, 34) < 0.11:
        return CANOPY_LT
    if c is CANOPY_MID and h01(x >> 1, y >> 1, 36) < 0.08:
        return CANOPY
    return c


def woods(open_edges: int = 0) -> Image.Image:
    """A filled canopy: crowns drawn back to front, each a 2:1 top plane over
    the leaf mass it hangs on, over grass that shows only in the clearings and
    at the fringe. The value drop against plains is the tile's read — cover,
    not decoration — and trunks under the fringe say the cover is trees.

    `open_edges` names the borders the wood ends at (see `_crowns_within`);
    0 — every edge continued — is the atlas tile."""
    t = _grass_ground(WOODS_SALT)
    px = t.load()
    crowns = _crowns_within(open_edges)
    covered = [[False] * CELL for _ in range(CELL)]
    for cx0, cy0, r, copies in _crown_order(crowns):
        up, down = _crown_reach(r)
        depth = down - up
        for cx, cy in ((cx0, cy0), *copies):
            for yy in range(max(0, cy - up), min(CELL, cy + down + 1)):
                for xx in range(max(0, cx - r), min(CELL, cx + r + 1)):
                    dx, dy = xx - cx, yy - cy
                    # The crown's outline is RAGGED: a hash of the pixel,
                    # coarse enough to survive the board's downsample, pushes
                    # the boundary in and out by a pixel or two, so foliage
                    # ends in leaves rather than in a drawn ellipse. It is the
                    # same hash-in-the-decision rule the bands are ragged by.
                    rag = (h01(xx >> 1, yy >> 1, 39) - 0.5) * 1.6
                    rr = r + rag
                    # Half-depth of the top plane here: the 2:1 ellipse.
                    span = 1.0 - (dx / rr) ** 2 if abs(dx) < rr else -1.0
                    if span <= 0.0:
                        continue
                    hh = up * span**0.5
                    if dy < -hh:
                        continue
                    if dy > hh:  # the leaf mass under the plane
                        # It TAPERS: the underside is the bottom half of the
                        # crown, not a cylinder wall, so a tree is a rounded
                        # mass with a lit plane on top of it rather than a
                        # green tin can. Over another crown only its first
                        # rows show, so neighbours merge into one canopy
                        # instead of stacking as separate stamps.
                        if dy > (depth + rag) * span**0.5:
                            continue
                        if covered[yy][xx] and dy > hh + 1:
                            continue
                        # The mass rolls off on the same axis, so a crown is
                        # a ball of leaves and not a lit lid on a dark bucket.
                        # It rolls in the two tones BELOW the plane's — the
                        # plane's three stay the plane's, which is what keeps
                        # `CanopyLight`'s 2:1 reading a reading of the plane.
                        lit = dx / r + (dy - hh) / max(1.0, depth - hh) * 1.3
                        c = CANOPY if lit < 0.55 else CANOPY_DK
                    elif abs(dy) > hh - 1.0 or abs(dx) > r - 1.4:
                        # The plane's rim, split on the sheet's own up-left
                        # axis rather than on the horizon: lit where it faces
                        # the sun, shaded where it turns away, and hash-ragged
                        # at the changeover so it reads as a highlight instead
                        # of as an outline drawn round every crown.
                        rim = dx + dy * 2.0 + (h01(xx >> 1, yy, 37) - 0.5) * r * 0.7
                        c = CANOPY_LT if rim < 0.0 else CANOPY_DK
                    elif _crown_light(xx, yy, dx, dy, r) > 0.04:
                        c = _dapple(xx, yy, CANOPY_TOP)  # the plane itself
                    else:
                        c = _dapple(xx, yy, CANOPY_MID)  # rolling off, shaded
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
    # A trunk belongs to a CROWN, not to the tile: it stands under the crown
    # it holds up, on the crowns the hash picks, wherever that crown's skirt
    # ends over open ground. So the trunks move when the crowns do — the old
    # pair was two fixed pixels that every one of the sixteen variants
    # repeated at the same offset, which is a tile stamp, not a wood.
    for cx, cy, r, _ in crowns:
        if h01(cx, cy, 41) >= 0.60:
            continue
        tx = cx + int(h01(cx, cy, 43) * 5) - 2
        foot = cy + _crown_reach(r)[1]
        for ty in range(foot, foot + 6):
            if not (0 <= tx and tx + 1 < CELL and 0 <= ty and ty + 2 < CELL):
                continue
            if any(covered[ty + dy][tx + dx] for dy in range(3) for dx in range(2)):
                continue
            _rect(t, tx, ty, 2, 3, TRUNK)
            _rect(t, tx, ty, 1, 3, darken(TRUNK, 0.25))
            break
    return t


# Phase variants for the mountain — the sea's rule (SEA_PHASES below) applied
# to the board's most silhouette-dominant tile, because a range is a wall of
# identical peaks wherever one is repeated. An entry is (summits, relief seed):
# where the massif's three summits stand in the model's own VOXEL grid, as
# (x, y, height) with the tallest first, and the seed the spurs and gullies of
# the height field are keyed off (`buildings.massif`). A phase is a different
# mountain rather than the same one slid sideways, and nothing else varies —
# the mass stands on one row in every phase, so a range sits on one horizon,
# and the rock and snow are the same two ramps throughout. Phase 0 is the
# atlas column, so a board that has not adopted the sheet is unchanged.
MOUNTAIN_PHASES: tuple[tuple[tuple[tuple[int, int, int], ...], int], ...] = (
    (((6, 7, 15), (11, 4, 11), (2, 10, 10)), 21),
    (((5, 8, 15), (11, 5, 11), (3, 3, 9)), 11),
    (((4, 6, 15), (9, 10, 11), (11, 3, 10)), 17),
)

# Where the massif's front corner stands. Fixed across the phases: a ridge of
# mountains that stood on three different rows would read as peaks at three
# altitudes rather than as a range.
MOUNTAIN_GROUND = 57


# The massif's four rock faces, in the order the old painter used them: two
# sunlit, two shaded. They are one warm grey under two lights — the lit faces
# carry the sun's own warmth (S0.14, where they used to be the S0.07 of cut
# card), the shaded ones are `_shade`s of the lit face and so take the sky
# (see `_SHADE_GREY`). The massif is a voxel mass drawn off `palette.ROCK_RAMP`
# now, and the ramp is authored ON this ladder — its four upper rungs sit at
# these four values — so this is what the tile's rock is still keyed to, and
# `docs/terrain_tones.md` records it.
ROCK: tuple[RGB, RGB, RGB, RGB] = (
    _tone((166, 161, 153), 0.14),
    _tone((148, 144, 137), 0.14),
    _shade(_tone((148, 144, 137), 0.14), luminance((117, 113, 108))),
    _shade(_tone((148, 144, 137), 0.14), luminance((98, 95, 91))),
)


def _contact_shadow(tile: Image.Image, sprite: Image.Image, x0: int, y0: int) -> None:
    """The shadow a prop standing on grass drops: its own silhouette, moved
    down-right by `voxel.SHADOW_OFFSET` — the sheet's one sun — in the field's
    own dark grass rather than in a tone of its own.

    Only where the prop is not already standing, and only where the pixel that
    CAST it is inside the cell: a shadow whose caster was clipped off the tile
    is shade with nothing above it (`OneSun`).
    """
    sp = sprite.load()
    px = tile.load()
    dx, dy = SHADOW_OFFSET
    for yy in range(sprite.height):
        for xx in range(sprite.width):
            if sp[xx, yy][3] == 0:
                continue
            sx, sy = x0 + xx, y0 + yy
            tx, ty = sx + dx, sy + dy
            if not (0 <= tx < CELL and 0 <= ty < CELL):
                continue
            if 0 <= tx - x0 < sprite.width and 0 <= ty - y0 < sprite.height:
                if sp[tx - x0, ty - y0][3] != 0:
                    continue  # the prop stands on its own shadow
            px[tx, ty] = (*GRASS_DARK, 255)


def mountain(phase: int = 0) -> Image.Image:
    """A three-summit massif in the sheet's own projection: a voxel height
    field rasterised into top, up-left and down-right planes off one rock
    ramp, snow on the summits, talus at the foot.

    The tile it replaces was a front elevation — a fitted silhouette with a
    flat light/dark split and no top plane on it anywhere. See
    `buildings.massif`.
    """
    peaks, seed = MOUNTAIN_PHASES[phase]
    # The massif stands on the same clumped grass plate plains and woods are
    # drawn on: a flat-green apron around a mountain reads as a lighter cell
    # against the field it borders, which is the seam the woods plate was
    # fixed for.
    t = _grass_ground(4)
    rock = render_indexed(buildings.massif(peaks, seed), FACTIONS[0]).image
    x0 = (CELL - rock.width) // 2
    y0 = MOUNTAIN_GROUND - rock.height
    _contact_shadow(t, rock, x0, y0)
    place_in_cell(t, rock, x0, y0)
    # boulders shed onto the apron, in the field's own dark grass
    for sx, sy in ((5, 50), (56, 52), (12, 60), (44, 61)):
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
