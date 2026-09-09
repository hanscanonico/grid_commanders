"""The one light: a fixed key direction, a per-material ramp, an AO pass.

The sheet is lit from the upper left and a mirrored pose flips geometry only, so
the direction is stated once, here, and never taken from a face's own spec.
Every material is painted out of four named flat tones — deep, shade, base, lit
— plus a rim; no band is an alpha wash over a fill, which is what keeps a
finished raster inside its colour budget.

A ramp is BUILT rather than typed out, the way the sprite sheet's own palette
builds a faction ramp: one authored value ladder, and one shared chroma shape
over every rung of it — chroma peaking in the middle, hue rotating toward the
sky in the shadow bands and toward the sun in the lit one, the shadow bands
mixed toward a single cool ambient. Six literal hexes per material drift into
the same hue at six brightnesses, which is the flattest a ramp can be.

Nothing here blurs. The occlusion band is a hard offset of a mask, because the
design system's shadows are `4px 4px 0` with zero blur and a gradient is the one
thing this style does not own.

**There is no rim band on the figure.** There was: the silhouette minus a copy
of itself stepped toward the key, in the army's own rim rung, walked one texel
in under the ink. On a 110-pixel bust that is a one-texel run of a colour the
face does not own, laid between a two-texel outline and the cheek — under the
gauge (`gauge.GAUGE`) in width and alien in hue, and what the review read as
opaque fleck halos strung along five silhouettes. The form is carried by the
four bands and the ink instead. The coat keeps a kicker because it can afford
one: `uniform` draws it as a ribbon, two texels, in a rung the army already
spends.
"""

from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache

from PIL import Image, ImageChops

from . import palette
from .canvas import Point
from .palette import RGB

# The key, in portrait space: x right, y down, so the sun sits up and to the
# left. The sprite sheet's own sun (generators/sprites) lights the board from
# the same corner.
KEY = (-0.64, -0.77)
# Which way everything the key does not reach falls — away from it, so down and
# to the right, on every bust, mirrored poses included. Derived from the key
# rather than typed beside it: one statement of where the sun is.
SHADOW_STEP: tuple[int, int] = (-1 if KEY[0] > 0 else 1, -1 if KEY[1] > 0 else 1)
# The four bands every material is painted in, plus the rim. Naming them is the
# palette discipline: a tone is chosen from a ramp, never mixed at the call.
BANDS = ("deep", "shade", "base", "lit")

# The value ladder, as multiples of the base colour's own luminance. The first
# rung is the contour the board's own ramps open on; the four after it are
# BANDS, and the rim closes the ladder at its own headroom.
_LADDER = (0.22, 0.40, 0.68, 1.00, 1.34)
# Where the lit band stops. A pale skin's own luminance is already 223, and a
# third over it is white — a forehead painted in pure white is a hole in the
# sheet rather than a plane the sun is on, and at sixteen tones it also spends
# the rung the steel wants.
_LIT_CEILING = 236.0
# The rim is the one rung that keeps most of its chroma: it is the faction's
# light tint doing the separating, so washing it toward the sun would spend
# exactly the colour it is there for.
_RIM_HEADROOM = 0.55  # of the room between the base's value and white
# How far off the face's own centre line the shade may come. C8: a boundary
# down the nose-mouth axis reads as a two-tone mask rather than as a lit head,
# so every shade shape starts this fraction of a half-width out from centre —
# outside the nose and the mouth, which is what the clearance buys.
NOSE_AXIS_CLEARANCE = 0.58

# The three face-shade geometries (C7). Which one a skull takes is its crown and
# its width, so the sheet does not wear one shade shape 22 times.
CHEEK_WEDGE, BROW_SOCKET, JAW_UNDER = "cheek_wedge", "brow_socket", "jaw_under"
SHADE_KINDS = (CHEEK_WEDGE, BROW_SOCKET, JAW_UNDER)
# A skull lifted this far is drawing its shade off a heavy brow; one this wide
# is drawing it off the jaw. Both dials are the roster's own `head` column.
CROWN_BROW = 1.0
WIDTH_JAW = 1.06

# Where each shape ends on the nose side: a horizontal run at one v, so the
# shade reads as a plane turning away from the light rather than as a line
# drawn down the face. Keyed by shape, in skull heights from the crown.
TERMINATORS: dict[str, float] = {
    CHEEK_WEDGE: 0.62,
    BROW_SOCKET: 0.46,
    JAW_UNDER: 0.74,
}

# Each shape as (u, v): u out from the face's centre in half-widths, v down
# from the crown in skull heights. Every u clears NOSE_AXIS_CLEARANCE and every
# shape opens on its terminator's two vertices. The outer u run past 1.0 on
# purpose: the caller clips them to the face's own mask, so a wedge meets the
# cheek's edge instead of stopping short of it.
_SHADE_SHAPES: dict[str, tuple[Point, ...]] = {
    CHEEK_WEDGE: (
        (0.58, 0.62),
        (1.08, 0.62),
        (1.08, 0.86),
        (0.86, 0.94),
        (0.62, 0.80),
    ),
    BROW_SOCKET: (
        (0.58, 0.46),
        (1.08, 0.46),
        (1.08, 0.16),
        (0.84, 0.12),
        (0.60, 0.28),
    ),
    JAW_UNDER: (
        (0.58, 0.74),
        (1.06, 0.74),
        (1.00, 0.92),
        (0.78, 1.00),
        (0.60, 0.86),
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
    """One material's four flat tones and its rim, over the board's own ramp.

    A material is a six-slot `palette.Ramp6` — the ladder the unit sheet and the
    terrain are painted on — and the four bands a bust paints in are a view onto
    four of its rungs. The contour rung (S0) is the window's, not the figure's,
    so it is reached through `six` rather than named a band.
    """

    six: palette.Ramp6

    @classmethod
    def of_faction(cls, key: str) -> Ramp:
        """An army's own rungs, straight off the board's palette — no ladder of
        the portraits' own between a coat and the chassis it is painted to
        match."""
        return cls(palette.faction_ramp(key))

    @property
    def deep(self) -> RGB:
        return self.six[palette.S_UNDER]

    @property
    def shade(self) -> RGB:
        return self.six[palette.S_SHADOW]

    @property
    def base(self) -> RGB:
        return self.six[palette.S_BODY]

    @property
    def lit(self) -> RGB:
        return self.six[palette.S_TOP]

    @property
    def rim(self) -> RGB:
        return self.six[palette.S_RIM]

    def band(self, name: str) -> RGB:
        """A band by name. An unknown name raises: the vocabulary is the
        dispatch table here as everywhere else in this package."""
        if name not in BANDS:
            raise KeyError(f"no band {name!r} (have {BANDS})")
        return getattr(self, name)


@lru_cache(maxsize=None)
def build_ramp(base: RGB) -> Ramp:
    """A material's rungs from its base colour, rim included.

    The ladder is this sheet's — a contour rung under four bands keyed off the
    base's own luma — and the shaper is the board's (`palette.build_ramp`), so
    a general's coat is lit by the same sun and mixed toward the same sky as
    the tank outside the window.

    **A material built here has no rim of its own: it kicks in its own lit
    rung.** Skin and hair are given four and three rungs on a sixteen-tone bust
    and a rim is not one of them, so the kicker along their shadow edge has to
    be a tone the bust already spends. It used to be the army's: a near-white
    line down an Iron general's jaw, a mint one down a Verdant general's neck —
    a hue the face does not own, laid one texel from the ink that outlines the
    same edge, which is the fleck halo the review read off five busts.

    Cached because a bust asks for the same handful of ladders on every layer
    it paints.
    """
    lum = palette.luminance(base)
    rim_target = lum + (255.0 - lum) * _RIM_HEADROOM
    ladder = (*(min(lum * step, _LIT_CEILING) for step in _LADDER), rim_target)
    six = list(palette.build_ramp(base, ladder))
    six[palette.S_RIM] = six[palette.S_TOP]
    return Ramp(tuple(six))


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
    divisor: int = 1,
    mirrored: bool = False,
) -> Image.Image:
    """The AO pass: where an occluder's own shape lands on what is under it.

    A hard offset band, not a blur — the occluder's mask stepped `depth`
    portrait pixels away from the key and intersected with the target, minus
    the occluder itself. The caller paints the target's `deep` tone through the
    mask this returns, so the band stays a named tone rather than a wash.

    `depth` is stated in design units like every other geometry in this package;
    `divisor` is the grid the two masks were drawn on (`Canvas.divisor`), which
    is what turns it into whole pixels on that grid.
    """
    step = max(1, round(depth / divisor))
    away = _step(mirrored)
    below = _shifted(occluder, away[0] * step, away[1] * step)
    return ImageChops.multiply(ImageChops.subtract(below, occluder), target)
