"""The one light: a fixed key direction, a per-material ramp, a rim, an AO pass.

The sheet is lit from the upper left and a mirrored pose flips geometry only, so
the direction is stated once, here, and never taken from a face's own spec.
Every material is painted out of four named flat tones — deep, shade, base, lit
— plus a rim; no band is an alpha wash over a fill, which is what keeps a
finished raster inside its colour budget.

A ramp is BUILT rather than typed out, the way the sprite sheet's own
palette builds a faction ramp: one authored value ladder, and one shared chroma shape over every
rung of it — chroma peaking in the middle, hue rotating toward the sky in the
shadow bands and toward the sun in the lit one, the shadow bands mixed toward a
single cool ambient. Six literal hexes per material drift into the same hue at
six brightnesses, which is the flattest a ramp can be.

Nothing here blurs. The occlusion band and the rim band are both hard offsets of
a mask, because the design system's shadows are `4px 4px 0` with zero blur and a
gradient is the one thing this style does not own.
"""

from __future__ import annotations

import colorsys
from dataclasses import dataclass
from functools import lru_cache

from PIL import Image, ImageChops

from .canvas import Point
from .palette import RGB

# The key, in portrait space: x right, y down, so the sun sits up and to the
# left. The sprite sheet's own sun (generators/sprites) lights the board from the same corner.
KEY = (-0.64, -0.77)
# Which way everything the key does not reach falls — away from it, so down and
# to the right, on every bust, mirrored poses included. Derived from the key
# rather than typed beside it: one statement of where the sun is.
SHADOW_STEP: tuple[int, int] = (-1 if KEY[0] > 0 else 1, -1 if KEY[1] > 0 else 1)
# The four bands every material is painted in, plus the rim. Naming them is the
# palette discipline: a tone is chosen from a ramp, never mixed at the call.
BANDS = ("deep", "shade", "base", "lit")

# The sky every shadow on the sheet is lit by, and the two hues a rung may
# rotate toward. The sky is the sprite sheet's own AMBIENT — the board and the
# busts are lit by one scene, so a portrait's shadow is the board's shadow
# colour. Rotations are small on purpose: a big one turns a red faction's
# shadow purple and stops reading as the same army.
AMBIENT: RGB = (86, 112, 190)
_SKY_HUE = 225.0
_SUN_HUE = 45.0
_HUE_ARC = 14.0

# The value ladder, as multiples of the base colour's own luminance, and the
# chroma shape over it. Index order is BANDS, with the rim last.
_LADDER = (0.40, 0.68, 1.00, 1.34)
# The rim is the one rung that keeps most of its chroma: it is the faction's
# light tint doing the separating, so washing it toward the sun would spend
# exactly the colour it is there for.
_RIM_HEADROOM = 0.55  # of the room between the base's value and white
_HUE_PULL = (-1.00, -0.58, 0.0, 0.62, 0.35)
_SAT_SCALE = (1.20, 1.14, 1.0, 0.84, 0.72)
_AMBIENT_MIX = (0.26, 0.13, 0.0, 0.0, 0.0)

# How far off the face's own centre line the shade may come. C8: a boundary
# down the nose-mouth axis reads as a two-tone mask rather than as a lit head,
# so every shade shape starts this fraction of a half-width out from centre.
NOSE_AXIS_CLEARANCE = 0.30

# The three face-shade geometries (C7). Which one a skull takes is its crown and
# its width, so the sheet does not wear one shade shape 22 times.
CHEEK_WEDGE, BROW_SOCKET, JAW_UNDER = "cheek_wedge", "brow_socket", "jaw_under"
SHADE_KINDS = (CHEEK_WEDGE, BROW_SOCKET, JAW_UNDER)
# A skull lifted this far is drawing its shade off a heavy brow; one this wide
# is drawing it off the jaw. Both dials are the roster's own `head` column.
CROWN_BROW = 1.0
WIDTH_JAW = 1.06

# Each shape as (u, v): u out from the face's centre in half-widths, v down
# from the crown in skull heights. Every u clears NOSE_AXIS_CLEARANCE.
_SHADE_SHAPES: dict[str, tuple[Point, ...]] = {
    CHEEK_WEDGE: (
        (1.00, 0.28),
        (0.98, 0.62),
        (0.60, 0.86),
        (0.34, 0.70),
        (0.52, 0.44),
        (0.74, 0.30),
    ),
    BROW_SOCKET: (
        (1.00, 0.14),
        (1.00, 0.46),
        (0.44, 0.54),
        (0.30, 0.40),
        (0.52, 0.30),
        (0.80, 0.16),
    ),
    JAW_UNDER: (
        (0.96, 0.50),
        (0.86, 0.80),
        (0.46, 0.94),
        (0.32, 0.74),
        (0.62, 0.62),
        (0.84, 0.52),
    ),
}
# The one shape on the key side: the forehead and cheekbone the light catches.
# It is a single band rather than a mirror of the shade, so the two sides of a
# face are never the same drawing.
_LIGHT_SHAPE: tuple[Point, ...] = (
    (-0.94, 0.20),
    (-0.34, 0.14),
    (-0.40, 0.34),
    (-0.72, 0.56),
    (-0.92, 0.44),
)


@dataclass(frozen=True)
class Ramp:
    """One material's four flat tones and its rim."""

    deep: RGB
    shade: RGB
    base: RGB
    lit: RGB
    rim: RGB

    def band(self, name: str) -> RGB:
        """A band by name. An unknown name raises: the vocabulary is the
        dispatch table here as everywhere else in this package."""
        if name not in BANDS:
            raise KeyError(f"no band {name!r} (have {BANDS})")
        return getattr(self, name)


def luminance(colour: RGB) -> float:
    """Rec. 601 luma, the scale the ladder is authored on."""
    return 0.299 * colour[0] + 0.587 * colour[1] + 0.114 * colour[2]


def _clamp8(value: float) -> int:
    return max(0, min(255, int(round(value))))


def _mix(a: RGB, b: RGB, t: float) -> RGB:
    return tuple(_clamp8(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _rotate(hue: float, pull: float) -> float:
    if pull == 0.0:
        return hue
    target = _SKY_HUE if pull < 0 else _SUN_HUE
    delta = ((target - hue + 180.0) % 360.0) - 180.0
    step = min(abs(delta), abs(pull) * _HUE_ARC)
    return hue + (step if delta >= 0 else -step)


def _at_luminance(colour: RGB, target: float) -> RGB:
    """Re-key a colour to an exact luma, keeping its chroma as long as it can:
    scale first, and wash toward white only once a channel is pinned."""
    lum = luminance(colour)
    if lum <= 0.0:
        return (_clamp8(target), _clamp8(target), _clamp8(target))
    ceiling = lum * 255.0 / max(colour)
    if target <= ceiling:
        return tuple(_clamp8(c * target / lum) for c in colour)
    pinned = _mix((0, 0, 0), colour, 255.0 / max(colour))
    return _mix(pinned, (255, 255, 255), (target - ceiling) / (255.0 - ceiling))


def _shape(base: RGB, slot: int, target: float) -> RGB:
    """One rung: the base's hue and chroma shaped for `slot`, keyed to
    `target` luma. Pure — one base always gives one rung."""
    hue, sat, _ = colorsys.rgb_to_hsv(*(c / 255.0 for c in base))
    red, green, blue = colorsys.hsv_to_rgb(
        (_rotate(hue * 360.0, _HUE_PULL[slot]) % 360.0) / 360.0,
        min(1.0, sat * _SAT_SCALE[slot]),
        1.0,
    )
    chroma = (_clamp8(red * 255), _clamp8(green * 255), _clamp8(blue * 255))
    if _AMBIENT_MIX[slot] > 0.0:
        chroma = _mix(
            chroma, _at_luminance(AMBIENT, luminance(chroma)), _AMBIENT_MIX[slot]
        )
    return _at_luminance(chroma, target)


@lru_cache(maxsize=None)
def build_ramp(base: RGB, *, rim_hue: RGB | None = None) -> Ramp:
    """A material's four tones from its base colour, rim included.

    Values step on a fixed ladder and chroma rotates toward the sky in shadow
    and toward the sun in light. `rim_hue` is the faction's light tint where a
    material takes the sheet's rim rather than its own; it is re-keyed to the
    rim's value, so a rim is the faction's colour at the light's brightness and
    never a second hue in the palette. Cached because a bust asks for the same
    handful of ladders on every layer it paints.
    """
    lum = luminance(base)
    tones = [_shape(base, slot, lum * step) for slot, step in enumerate(_LADDER)]
    rim_target = lum + (255.0 - lum) * _RIM_HEADROOM
    rim = _shape(rim_hue if rim_hue is not None else base, len(_LADDER), rim_target)
    return Ramp(*tones, rim)


def shade_kind(crown: float, width: float) -> str:
    """Which of the three face-shade geometries a skull takes (C7).

    A lifted crown means a brow to cast from; a wide skull means a jaw to cast
    under. Everything else takes the cheek wedge.
    """
    if crown >= CROWN_BROW:
        return BROW_SOCKET
    if width >= WIDTH_JAW:
        return JAW_UNDER
    return CHEEK_WEDGE


def _placed(
    shape: tuple[Point, ...], *, centre: float, half: float, top: float, height: float
) -> list[Point]:
    return [(centre + u * half, top + v * height) for u, v in shape]


def face_shade(
    kind: str, *, centre: float, half: float, top: float, height: float
) -> list[Point]:
    """The shadow-side shade shape, in portrait pixels.

    `kind` is one of SHADE_KINDS; an unknown one raises rather than falling
    through to a default.
    """
    if kind not in _SHADE_SHAPES:
        raise KeyError(f"no face shade {kind!r} (have {SHADE_KINDS})")
    return _placed(
        _SHADE_SHAPES[kind], centre=centre, half=half, top=top, height=height
    )


def face_light(*, centre: float, half: float, top: float, height: float) -> list[Point]:
    """The band the key catches: the forehead and cheekbone on the light side."""
    return _placed(_LIGHT_SHAPE, centre=centre, half=half, top=top, height=height)


def _shifted(mask: Image.Image, dx: int, dy: int) -> Image.Image:
    moved = Image.new("L", mask.size, 0)
    moved.paste(mask, (dx, dy))
    return moved


def _step(mirrored: bool) -> tuple[int, int]:
    """Which way the light falls for a layer, in that layer's own x.

    A layer the pose is about to mirror is drawn with its light pre-flipped in
    x, so the band lands on the screen's shadow side once the layer is turned
    over. The sun itself never moves; this is the flip a mirror owes it.
    """
    return (-SHADOW_STEP[0] if mirrored else SHADOW_STEP[0], SHADOW_STEP[1])


def occlusion(
    occluder: Image.Image,
    target: Image.Image,
    *,
    depth: float,
    scale: int = 1,
    mirrored: bool = False,
) -> Image.Image:
    """The AO pass: where an occluder's own shape lands on what is under it.

    A hard offset band, not a blur — the occluder's mask stepped `depth`
    portrait pixels away from the key and intersected with the target, minus
    the occluder itself. The caller paints the target's `deep` tone through the
    mask this returns, so the band stays a named tone rather than a wash.

    `scale` is the working supersample the two masks were drawn at, so `depth`
    is stated in portrait pixels at every call site.
    """
    step = max(1, round(depth * scale))
    away = _step(mirrored)
    below = _shifted(occluder, away[0] * step, away[1] * step)
    return ImageChops.multiply(ImageChops.subtract(below, occluder), target)


def rim_light(
    silhouette: Image.Image,
    ramp: Ramp,
    *,
    weight: float,
    inset: float = 0.0,
    scale: int = 1,
    mirrored: bool = False,
) -> Image.Image:
    """The kicker along the shadow-side silhouette run, as an RGBA layer.

    The band is the silhouette minus a copy of itself stepped toward the key,
    which leaves exactly the run the key does not reach — the lower-right edge,
    on every bust, because the light never mirrors with the pose. `inset` walks
    the band in under the ink that outlines the same edge, so the rim reads as
    light on the form rather than as a second outline.
    """
    step = max(1, round(weight * scale))
    walked = round(inset * scale)
    away = _step(mirrored)
    outer = _shifted(silhouette, -away[0] * walked, -away[1] * walked)
    inner = _shifted(outer, -away[0] * step, -away[1] * step)
    band = ImageChops.subtract(outer, inner)
    layer = Image.new("RGBA", silhouette.size, (0, 0, 0, 0))
    layer.paste(Image.new("RGBA", silhouette.size, (*ramp.rim, 255)), (0, 0), band)
    return layer
