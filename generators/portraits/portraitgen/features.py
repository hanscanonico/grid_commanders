"""Eyes, brows, nose, mouth and facial hair.

Every vocabulary here is the roster's own, and every one is a dispatch table: an
unknown key raises rather than drawing a default, which is what the GUT suite's
three "is it one the file can draw?" lints existed to catch.

The handoff drew every feature against one skull, in a 110x134 viewBox that
doubles to the 220x268 design space. Its drawing is transcribed here in portrait
pixels — its own units, doubled, over `REFERENCE_BOX`, which is where that one
skull sits on this raster — and `Frame` fits that one drawing to whatever
skull `head.outline` actually cut, so a narrow face wears narrow features
without any of them being authored twice.

Tones are flat and named: a band comes off a ramp, never off an alpha wash, and
ink is the feature and detail weights only. The silhouette weight belongs to the
outline of the bust, which is `head`'s and `hair`'s to draw.

The worn accessories are the neighbouring module's: they fit to the same `Frame`
and read the same eye line, so `accessories.py` imports this one and nothing
here imports it back.
"""

from __future__ import annotations

from collections.abc import Callable, Iterable
from dataclasses import dataclass

from . import head
from .canvas import INK_DETAIL, INK_FEATURE, Box, Canvas, Point
from .head import Skull
from .light import Ramp
from .palette import INK, RGB
from .vocab import known, pick

# The handoff's skull at width 1.0: left, top, right, bottom in portrait pixels.
REFERENCE_BOX: Box = (64.0, 82.0, 156.0, 206.0)
# The face's own landmarks in that drawing: the line the eyes sit on, how far a
# spread of 1.0 walks them apart, and the near ear's centre and radius.
EYE_LINE = 142.0
EYE_HALF = 20.0
EAR = (62.0, 144.0, 10.0)

# The default the handoff gave every face, and the dial the roster scales it by.
EYE_DEFAULT = 1.0
# Below this an eye keeps a single catchlight: two sparkles on a small eye is
# what reads as a child's avatar rather than as a general.
EYE_SINGLE_CATCHLIGHT = 0.92

# The tones a feature carries that are neither skin nor hair: two of the design
# system's own kit colours (UiTheme SLATE_700 and AMMO). What headwear spends
# beyond these is `accessories.py`'s.
SCLERA: RGB = (255, 255, 255)
IRIS: RGB = (58, 63, 69)
GOLD: RGB = (224, 169, 46)


@dataclass(frozen=True)
class Frame:
    """The handoff's face geometry fitted to one general's skull."""

    left: float
    top: float
    right: float
    bottom: float

    @classmethod
    def of(cls, skull: Skull) -> Frame:
        points = head.outline(skull)
        xs = [x for x, _ in points]
        ys = [y for _, y in points]
        return cls(min(xs), min(ys), max(xs), max(ys))

    def at(self, x: float, y: float) -> Point:
        left, top, right, bottom = REFERENCE_BOX
        return (
            self.left + (x - left) * (self.right - self.left) / (right - left),
            self.top + (y - top) * (self.bottom - self.top) / (bottom - top),
        )

    def path(self, points: Iterable[Point]) -> list[Point]:
        return [self.at(x, y) for x, y in points]

    def ellipse(self, cx: float, cy: float, rx: float, ry: float) -> Box:
        return (*self.at(cx - rx, cy - ry), *self.at(cx + rx, cy + ry))


def eye_xs(skull: Skull) -> tuple[float, float]:
    """The two eye centres, in reference pixels, walked apart by the spread."""
    half = EYE_HALF * skull.spread
    centre = (REFERENCE_BOX[0] + REFERENCE_BOX[2]) / 2.0
    return (centre - half, centre + half)


def ringed_ellipse(
    canvas: Canvas,
    frame: Frame,
    centre: tuple[float, float],
    radii: tuple[float, float],
    fill: RGB,
    weight: float,
) -> None:
    """A filled ellipse inside a ring of ink of one of the three weights."""
    cx, cy = centre
    rx, ry = radii
    half = weight / 2.0
    canvas.ellipse(frame.ellipse(cx, cy, rx + half, ry + half), INK)
    canvas.ellipse(frame.ellipse(cx, cy, rx - half, ry - half), fill)


# --- eyes --------------------------------------------------------------------


@dataclass(frozen=True)
class EyeShape:
    """One eye kind: its half-height, its pupil, and the marks it adds."""

    ry: float
    pupil: float
    lash: bool = False
    lid: bool = False
    closed: bool = False


_EYES: dict[str, EyeShape] = {
    "closed": EyeShape(0.0, 0.0, closed=True),
    "f": EyeShape(8.8, 4.2, lash=True),
    "lidded": EyeShape(5.2, 4.2, lid=True),
    "m": EyeShape(8.8, 4.2),
    "narrow": EyeShape(5.2, 4.2),
    "wide": EyeShape(10.8, 3.4),
}
EYE_KINDS = frozenset(_EYES)
EYE_RX = 8.2


def eyes(
    canvas: Canvas, skull: Skull, kind: str, *, scale: float, covered: int | None = None
) -> None:
    """Sclera, iris ring, pupil and the catchlights, at the roster's eye dial.

    `covered` is the socket a worn accessory hides, from `covered_eye`.
    """
    shape = pick(_EYES, kind, "eyes")
    frame = Frame.of(skull)
    for side, x in enumerate(eye_xs(skull)):
        if side == covered:
            continue
        if shape.closed:
            shut = [
                (x - 4.5 * scale, EYE_LINE),
                (x, EYE_LINE + 3.5 * scale),
                (x + 4.5 * scale, EYE_LINE),
            ]
            canvas.stroke(frame.path(shut), INK_FEATURE, INK)
            continue
        rx, ry = EYE_RX * scale, shape.ry * scale
        ringed_ellipse(canvas, frame, (x, EYE_LINE), (rx, ry), SCLERA, INK_FEATURE)
        iris = min(shape.pupil * 1.8 * scale, ry * 0.95)
        canvas.ellipse(frame.ellipse(x, EYE_LINE + 0.4 * scale, iris, iris), IRIS)
        pupil = shape.pupil * scale
        canvas.ellipse(frame.ellipse(x, EYE_LINE + 0.4 * scale, pupil, pupil), INK)
        _catchlights(canvas, frame, x, scale)
        if shape.lid:
            edge = EYE_LINE - ry * 0.3
            lid = [(x - rx, edge), (x, EYE_LINE - ry * 1.2), (x + rx, edge)]
            canvas.stroke(frame.path(lid), INK_FEATURE, INK)
        if shape.lash:
            lash = [(x - 10.0, 135.2), (x, 130.4), (x + 10.0, 135.2)]
            canvas.stroke(frame.path(lash), INK_DETAIL, INK)


def _catchlights(canvas: Canvas, frame: Frame, x: float, scale: float) -> None:
    spark = 1.8 * scale
    canvas.ellipse(
        frame.ellipse(x + 2.2 * scale, EYE_LINE - 2.0 * scale, spark, spark), SCLERA
    )
    if scale < EYE_SINGLE_CATCHLIGHT:
        return
    small = 1.1 * scale
    canvas.ellipse(
        frame.ellipse(x - 3.0 * scale, EYE_LINE + 2.8 * scale, small, small), SCLERA
    )


# --- brows -------------------------------------------------------------------


@dataclass(frozen=True)
class BrowShape:
    """A brow as three heights — outer, middle, inner — and its thickness."""

    outer: float
    middle: float
    inner: float
    half: float
    thickness: float


# Thickness is in design units and a brow tapers to 40% of it at the outer end,
# so anything under five came off the grid as a one-texel line that broke where
# it leaned. Five is the floor here for that reason, not for a drawing one.
_BROWS: dict[str, BrowShape] = {
    "angled": BrowShape(125.0, 128.5, 132.0, 11.0, 5.5),
    "cocked": BrowShape(124.0, 119.0, 124.0, 10.0, 5.0),
    "heavy": BrowShape(128.0, 131.0, 134.0, 11.0, 6.5),
    "raised": BrowShape(124.0, 119.0, 124.0, 10.0, 5.0),
    "soft": BrowShape(127.0, 123.0, 127.0, 10.0, 5.0),
}
BROW_KINDS = frozenset(_BROWS)


def brow(
    canvas: Canvas, skull: Skull, kind: str, ramp: Ramp, *, covered: int | None = None
) -> None:
    """A tapered mass per eye, in one rung of the hair ramp and no more.

    The mass used to carry a deep-tone hairline along its own top edge. A brow
    is between two and three texels thick here, so that line was one texel of a
    detail tone over a taper — and it came off the rasteriser as the string of
    ink fragments the review read over Vale's and Draeg's sockets. The shade
    rung the mass is painted in is what the hairline was there to buy.
    """
    shape = pick(_BROWS, kind, "brow")
    frame = Frame.of(skull)
    for side, x in enumerate(eye_xs(skull)):
        if side == covered:
            continue
        # `cocked` is the one brow whose halves differ: one raised, one level.
        worn = _BROWS["soft"] if kind == "cocked" and side == 1 else shape
        outward = -1.0 if side == 0 else 1.0
        outer = x + outward * worn.half
        inner = x - outward * worn.half
        top = [(outer, worn.outer), (x, worn.middle), (inner, worn.inner)]
        bottom = [
            (inner, worn.inner + worn.thickness * 0.6),
            (x, worn.middle + worn.thickness),
            (outer, worn.outer + worn.thickness * 0.4),
        ]
        canvas.polygon(frame.path([*top, *bottom]), ramp.shade)


# --- nose --------------------------------------------------------------------

# The midline every nose is built on, and how deep its underside runs: two
# texels, so the darkest mark on the face holds the gauge on its own.
NOSE_X = 110.0
NOSE_UNDERSIDE = 4.0
# Where a nose may start. It used to be drawn between 116 and 136 — the band the
# brows occupy, a good ten texels above the eye line — and what that put on
# twenty-two foreheads was a wrinkle, or a bindi, rather than a nose. It begins
# below the eyes now, and this is the floor the suite holds it to.
NOSE_TOP_FLOOR = EYE_LINE + 2.0


@dataclass(frozen=True)
class NoseShape:
    """A nose as two marks under the eye line, and no line of its own.

    A stroke down the bridge is one texel of a deep tone laid on a slope, which
    is the mark the gauge exists to refuse. What is left is what a nose is at
    this size: the plane the key does not reach, in the skin's shade rung, and
    the bar of the tip's own underside in its deep one.
    """

    top: float
    base: float
    flank: float
    wing: float


_NOSES: dict[str, NoseShape] = {
    "broad": NoseShape(top=147.0, base=156.0, flank=8.0, wing=7.0),
    "hook": NoseShape(top=145.0, base=157.0, flank=7.0, wing=5.0),
    "tick": NoseShape(top=149.0, base=155.0, flank=5.0, wing=5.0),
}
NOSE_KINDS = frozenset(_NOSES)


def nose_shape(kind: str) -> NoseShape:
    """One nose's authored geometry — where the suite that holds every nose
    under the eye line reads it, so the table itself stays this module's."""
    return pick(_NOSES, kind, "nose")


def nose(canvas: Canvas, skull: Skull, kind: str, ramp: Ramp) -> None:
    """The shadow plane beside the bridge, and the bar under the tip."""
    shape = nose_shape(kind)
    frame = Frame.of(skull)
    # The light is fixed upper-left, so the plane the nose turns away from it is
    # the one to its right; it is a flat band of the skin's own shade tone.
    plane = [
        (NOSE_X, shape.top),
        (NOSE_X + shape.flank, shape.base),
        (NOSE_X, shape.base),
    ]
    canvas.polygon(frame.path(plane), ramp.shade)
    canvas.polygon(
        frame.path(
            [
                (NOSE_X - shape.wing, shape.base),
                (NOSE_X + shape.wing, shape.base),
                (NOSE_X + shape.wing, shape.base + NOSE_UNDERSIDE),
                (NOSE_X - shape.wing, shape.base + NOSE_UNDERSIDE),
            ]
        ),
        ramp.deep,
    )


# --- mouth -------------------------------------------------------------------


def _stroked(
    points: tuple[Point, ...], weight: float
) -> Callable[[Canvas, Frame], None]:
    def draw(canvas: Canvas, frame: Frame) -> None:
        canvas.stroke(frame.path(points), weight, INK)

    return draw


def _clench(canvas: Canvas, frame: Frame) -> None:
    canvas.stroke(frame.path([(97.0, 170.0), (123.0, 170.0)]), INK_FEATURE, INK)
    for corner in (((97.6, 170.0), (95.2, 175.0)), ((122.4, 170.0), (124.8, 175.0))):
        canvas.stroke(frame.path(corner), INK_DETAIL, INK)


_MOUTHS: dict[str, Callable[[Canvas, Frame], None]] = {
    "clench": _clench,
    "neutral": _stroked(((98.0, 171.0), (122.0, 171.0)), INK_FEATURE),
    "smile": _stroked(((95.0, 166.0), (110.0, 176.0), (125.0, 166.0)), INK_FEATURE),
    "smirk": _stroked(((97.0, 172.0), (112.0, 175.0), (125.0, 166.0)), INK_FEATURE),
    "stern": _stroked(((98.0, 172.0), (110.0, 169.0), (122.0, 173.0)), INK_FEATURE),
    "wry": _stroked(((94.0, 170.0), (110.0, 172.0), (126.0, 164.0)), INK_FEATURE),
}

# The face's midline, and what an open mouth is wide in: the review reads a
# mouth in eye widths, so it is drawn in them — a general whose eyes are
# dialled up gets the wider mouth that holds the ratio.
MOUTH_X = 110.0
MOUTH_EYE_SPAN = 2.5


# P10: the bared band of teeth spans this share of the mouth's inner width at
# most, and each open mouth bares it its own way — one white block worn by
# seven busts is what the band had become.
TEETH_WIDTH = 0.6
# A snarl bares its upper row alone, and an open mouth bares no teeth at all:
# it is a dark cavity read by the lit lip along the bottom of it.
UPPER_ROW = 0.34
NOTHING_BARED = 0.0
LIT_LIP = 2.0


@dataclass(frozen=True)
class OpenMouth:
    """An open mouth as three heights — the lip line, the corners, the lower
    lip — how wide and how deep into the opening the bared band of teeth runs,
    and how far one side of the lip curls, which is the whole of a snarl."""

    top: float
    corner: float
    bottom: float
    bared: float
    teeth: float = 1.0
    curl: float = 0.0


_OPEN: dict[str, OpenMouth] = {
    "grin": OpenMouth(163.5, 166.5, 175.5, TEETH_WIDTH * 0.6),
    "laugh": OpenMouth(162.5, 165.5, 178.5, TEETH_WIDTH),
    "open": OpenMouth(163.0, 166.5, 173.0, NOTHING_BARED),
    "snarl": OpenMouth(163.5, 166.5, 175.0, TEETH_WIDTH, UPPER_ROW, curl=4.5),
}
OPEN_MOUTH_KINDS = frozenset(_OPEN)
MOUTH_KINDS = frozenset(_MOUTHS) | OPEN_MOUTH_KINDS
# The highest row a mouth reaches, an open one's lip line: the ceiling a nose's
# own underside has to end above, so the two never run into one mass.
MOUTH_CEILING = min(shape.top for shape in _OPEN.values())


def _mouth_half(eye: float) -> float:
    """Half an open mouth's width, in reference pixels, at one eye dial."""
    return MOUTH_EYE_SPAN * (EYE_RX * eye + INK_FEATURE / 2.0) - INK_FEATURE / 2.0


def _lips(shape: OpenMouth, half: float) -> tuple[Point, ...]:
    return (
        (MOUTH_X - half, shape.corner - shape.curl * 0.7),
        (MOUTH_X - half * 0.6, shape.top - shape.curl),
        (MOUTH_X + half * 0.6, shape.top),
        (MOUTH_X + half, shape.corner),
        (MOUTH_X + half * 0.55, shape.bottom),
        (MOUTH_X - half * 0.55, shape.bottom),
    )


def _inside(shape: OpenMouth, half: float, y: float) -> float:
    """How wide the opening still is at one height, inside its own lip."""
    closing = max((y - shape.corner) / (shape.bottom - shape.corner), 0.0)
    return half * (1.0 - 0.45 * closing) - INK_FEATURE / 2.0


def _teeth(shape: OpenMouth, half: float) -> tuple[Point, ...]:
    """The bared band, hung off the upper lip and inset from both corners."""
    top = shape.top + INK_FEATURE / 2.0
    bottom = top + shape.teeth * (shape.bottom - shape.top - INK_FEATURE)
    band = shape.bared * (half - INK_FEATURE / 2.0)
    close = min(band, _inside(shape, half, bottom))
    return (
        (MOUTH_X - band, top),
        (MOUTH_X + band, top),
        (MOUTH_X + close, bottom),
        (MOUTH_X - close, bottom),
    )


def _lower_lip(shape: OpenMouth, half: float) -> tuple[Point, ...]:
    """The lit lip a mouth that bares no teeth is read by instead."""
    edge = _inside(shape, half, shape.bottom)
    bottom = shape.bottom - INK_FEATURE / 2.0
    return (
        (MOUTH_X - edge, bottom - LIT_LIP),
        (MOUTH_X + edge, bottom - LIT_LIP),
        (MOUTH_X + edge, bottom),
        (MOUTH_X - edge, bottom),
    )


def _opened(canvas: Canvas, frame: Frame, shape: OpenMouth, half: float) -> None:
    """A wide mouth: the lip, and the one light thing inside it.

    C13 caps the dark area rather than the size, so a mouth that bares teeth is
    an outline around them rather than a filled hole — and what it bares is what
    tells the four apart: a laugh the whole band, a grin under two thirds of its
    width, a snarl the upper row, an open mouth a dark cavity and a lit lip.
    """
    lips = _lips(shape, half)
    if shape.bared > NOTHING_BARED:
        canvas.polygon(frame.path(_teeth(shape, half)), SCLERA)
    else:
        canvas.polygon(frame.path(lips), INK)
        canvas.polygon(frame.path(_lower_lip(shape, half)), SCLERA)
    canvas.stroke(frame.path(lips), INK_FEATURE, INK, closed=True)


def mouth(canvas: Canvas, skull: Skull, kind: str, *, eye: float = EYE_DEFAULT) -> None:
    """The mouth can never outrank the eyes: its dark area stays the smaller."""
    frame = Frame.of(skull)
    if kind in _OPEN:
        _opened(canvas, frame, _OPEN[kind], _mouth_half(eye))
        return
    _MOUTHS[known(kind, MOUTH_KINDS, "mouth")](canvas, frame)


# --- facial hair -------------------------------------------------------------

_BEARD: tuple[Point, ...] = (
    (66.0, 148.0),
    (70.0, 190.0),
    (110.0, 206.0),
    (150.0, 190.0),
    (154.0, 148.0),
    (140.0, 176.0),
    (110.0, 176.0),
    (80.0, 176.0),
)
_STUBBLE: tuple[Point, ...] = (
    (70.0, 164.0),
    (74.0, 190.0),
    (110.0, 204.0),
    (146.0, 190.0),
    (150.0, 164.0),
    (140.0, 184.0),
    (110.0, 192.0),
    (80.0, 184.0),
)
_MUSTACHE: tuple[Point, ...] = (
    (92.0, 158.0),
    (110.0, 154.0),
    (128.0, 158.0),
    (128.0, 166.0),
    (110.0, 164.0),
    (92.0, 166.0),
)
# The band the light leaves under it, as a band rather than as a line: the
# lower edge used to be a one-texel run of the deep tone along a shallow
# diagonal, which is the smudge the review read on Vale's lip.
_MUSTACHE_SHADE: tuple[Point, ...] = (
    (92.0, 162.0),
    (110.0, 160.0),
    (128.0, 162.0),
    (128.0, 166.0),
    (110.0, 164.0),
    (92.0, 166.0),
)
# The band the light leaves along a beard's shadow side, and the one it lights.
_BEARD_DEEP: tuple[Point, ...] = (
    (140.0, 176.0),
    (150.0, 190.0),
    (110.0, 206.0),
    (110.0, 196.0),
)
_BEARD_LIT: tuple[Point, ...] = (
    (66.0, 148.0),
    (80.0, 176.0),
    (86.0, 176.0),
    (74.0, 152.0),
)


def _beard(canvas: Canvas, frame: Frame, ramp: Ramp) -> None:
    canvas.polygon(frame.path(_BEARD), ramp.base)
    canvas.polygon(frame.path(_BEARD_DEEP), ramp.deep)
    canvas.polygon(frame.path(_BEARD_LIT), ramp.lit)


def _stubble(canvas: Canvas, frame: Frame, ramp: Ramp) -> None:
    # Stubble reads by how little of the jaw it covers, not by transparency —
    # a wash would put a fifth tone on a four-tone material.
    canvas.polygon(frame.path(_STUBBLE), ramp.shade)


def _mustache(canvas: Canvas, frame: Frame, ramp: Ramp) -> None:
    canvas.polygon(frame.path(_MUSTACHE), ramp.base)
    canvas.polygon(frame.path(_MUSTACHE_SHADE), ramp.shade)


def _bare(canvas: Canvas, frame: Frame, ramp: Ramp) -> None:
    """A clean-shaven general: the one kind that draws nothing."""


_FACIAL: dict[str, Callable[[Canvas, Frame, Ramp], None]] = {
    "beard": _beard,
    "mustache": _mustache,
    "none": _bare,
    "stubble": _stubble,
}
FACIAL_KINDS = frozenset(_FACIAL)


def facial_hair(canvas: Canvas, skull: Skull, kind: str, ramp: Ramp) -> None:
    pick(_FACIAL, kind, "facial hair")(canvas, Frame.of(skull), ramp)


def earring(canvas: Canvas, skull: Skull) -> None:
    x, y, radius = EAR
    frame = Frame.of(skull)
    ringed_ellipse(canvas, frame, (x, y + radius + 3.0), (3.8, 3.8), GOLD, INK_DETAIL)


# A freckle at the gauge: a square of skin shade, one per cheek, on the cheek
# proper — three design units in from the eye centre, toward the nose, and well
# below it. Three dots of a texel and a half apiece — what this drew — quantise
# into a scatter of specks rather than into freckles.
FRECKLE_INSET = 3.0
FRECKLE_Y = 159.0
FRECKLE_HALF = 2.2


def freckles(canvas: Canvas, skull: Skull, ramp: Ramp) -> None:
    frame = Frame.of(skull)
    for side, x in enumerate(eye_xs(skull)):
        inward = 1.0 if side == 0 else -1.0
        centre = x + inward * FRECKLE_INSET
        canvas.rect(
            (
                *frame.at(centre - FRECKLE_HALF, FRECKLE_Y - FRECKLE_HALF),
                *frame.at(centre + FRECKLE_HALF, FRECKLE_Y + FRECKLE_HALF),
            ),
            ramp.shade,
        )
