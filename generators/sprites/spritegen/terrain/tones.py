"""The tone vocabulary every terrain tile is drawn out of: the ground colours
under their value ceilings, and the cell-sized helpers that fill and stamp a
64px tile."""

from __future__ import annotations

from PIL import Image

from ..palette import (
    AMBIENT,
    RGB,
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
from ..palette import luminance as _luminance_601
from ..voxel import place_in_cell

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

# The engine script's original hues, revalued under the ceiling above. The hues are the
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


def _rect(img: Image.Image, x0: int, y0: int, w: int, h: int, c: RGB) -> None:
    px = img.load()
    for yy in range(max(0, y0), min(CELL, y0 + h)):
        for xx in range(max(0, x0), min(CELL, x0 + w)):
            px[xx, yy] = (*c, 255)


def _paste_prop(tile: Image.Image, prop: Image.Image, cx: int, bottom: int) -> None:
    place_in_cell(tile, prop, cx - prop.width // 2, bottom - prop.height)
