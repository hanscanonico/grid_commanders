"""Eyes, brows, nose, mouth, facial hair and the worn accessories.

Every vocabulary here is the roster's own, and every one is a dispatch table: an
unknown key raises rather than drawing a default, which is what the GUT suite's
three "is it one the file can draw?" lints existed to catch.

The handoff drew every feature against one skull, in a 110x134 viewBox that
bakes to the pinned 220x268 raster. Its drawing is transcribed here in portrait
pixels — its own units, doubled, over `REFERENCE_BOX`, which is where that one
skull sits on this raster — and `Frame` fits that one drawing to whatever
skull `head.outline` actually cut, so a narrow face wears narrow features
without any of them being authored twice.

Tones are flat and named: a band comes off a ramp, never off an alpha wash, and
ink is the feature and detail weights only. The silhouette weight belongs to the
outline of the bust, which is `head`'s and `hair`'s to draw.
"""

from __future__ import annotations

from collections.abc import Callable, Iterable
from dataclasses import dataclass

from . import head
from .canvas import INK_DETAIL, INK_FEATURE, Box, Canvas, Point
from .head import Skull
from .light import Ramp
from .palette import INK, RGB

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

# The tones features carry that are neither skin nor hair: the design system's
# own kit colours (UiTheme SLATE_700, SLATE_800 and AMMO), the handoff's goggle
# glass, and the one flesh tone a scar is cut in.
SCLERA: RGB = (255, 255, 255)
IRIS: RGB = (58, 63, 69)
KIT: RGB = (43, 47, 52)
GLASS: RGB = (188, 214, 224)
GOLD: RGB = (224, 169, 46)
SCAR: RGB = (181, 107, 90)
# The cut's own shadow side: a scar is a ribbon here, and a ribbon owes its
# edge a tone a shade under its core.
SCAR_DEEP: RGB = (126, 72, 62)

# Half a lens, squared on the eye line: what survives the mip is the square,
# not the frame drawn around it.
LENS_HALF = 14.0


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


def _eye_xs(skull: Skull) -> tuple[float, float]:
    """The two eye centres, in reference pixels, walked apart by the spread."""
    half = EYE_HALF * skull.spread
    centre = (REFERENCE_BOX[0] + REFERENCE_BOX[2]) / 2.0
    return (centre - half, centre + half)


def _ringed_ellipse(
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
    shape = _EYES[kind]
    frame = Frame.of(skull)
    for side, x in enumerate(_eye_xs(skull)):
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
        _ringed_ellipse(canvas, frame, (x, EYE_LINE), (rx, ry), SCLERA, INK_FEATURE)
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
    shape = _BROWS[kind]
    frame = Frame.of(skull)
    for side, x in enumerate(_eye_xs(skull)):
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


def nose(canvas: Canvas, skull: Skull, kind: str, ramp: Ramp) -> None:
    """The shadow plane beside the bridge, and the bar under the tip."""
    shape = _NOSES[kind]
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
    _MOUTHS[kind](canvas, frame)


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
    _FACIAL[kind](canvas, Frame.of(skull), ramp)


# --- accessories -------------------------------------------------------------

_BANDANA: tuple[Point, ...] = (
    (60.0, 88.0),
    (76.0, 78.0),
    (110.0, 76.0),
    (144.0, 78.0),
    (160.0, 88.0),
    (152.0, 94.0),
    (68.0, 94.0),
)
_HEADBAND: tuple[Point, ...] = (
    (60.0, 82.0),
    (160.0, 82.0),
    (160.0, 94.0),
    (60.0, 94.0),
)
_HOOD: tuple[Point, ...] = (
    (48.0, 156.0),
    (44.0, 96.0),
    (110.0, 74.0),
    (176.0, 96.0),
    (172.0, 156.0),
    (160.0, 116.0),
    (110.0, 110.0),
    (60.0, 116.0),
)
_HOOD_LINING: tuple[Point, ...] = (
    (48.0, 156.0),
    (56.0, 122.0),
    (110.0, 112.0),
    (164.0, 122.0),
    (172.0, 156.0),
    (160.0, 116.0),
    (110.0, 110.0),
    (60.0, 116.0),
)
# The service cap: a saucer crown that overhangs its band on both sides, and a
# peak wider than either. Both are the silhouette — this is the dress cap, and
# the field cap below it is the same head with all of that taken off.
_CAP_CROWN: tuple[Point, ...] = (
    (50.0, 88.0),
    (54.0, 56.0),
    (98.0, 44.0),
    (124.0, 44.0),
    (166.0, 56.0),
    (170.0, 88.0),
)
# The rim of the crown the key lands on: a band three texels deep, walked in
# along the crown's own upper-left edge. A crown painted flat in one rung is a
# silhouette rather than a cap, and on Iron — whose cloth and whose window field
# round onto neighbouring rungs — it was the darkest chip on the sheet.
_CAP_LIT: tuple[Point, ...] = (
    (52.0, 88.0),
    (56.0, 57.0),
    (98.0, 45.0),
    (124.0, 45.0),
    (124.0, 51.0),
    (100.0, 51.0),
    (62.0, 63.0),
    (60.0, 88.0),
)
_CAP_BAND: tuple[Point, ...] = (
    (54.0, 86.0),
    (166.0, 86.0),
    (166.0, 100.0),
    (54.0, 100.0),
)
_CAP_PEAK: tuple[Point, ...] = (
    (44.0, 98.0),
    (176.0, 98.0),
    (162.0, 114.0),
    (58.0, 114.0),
)
# The soft field cap: the same band, a lower crown that slouches away from the
# key, and no peak at all. The peak is the service cap's whole silhouette, so
# leaving it off is what tells the two caps apart at chip size.
_FIELD_CROWN: tuple[Point, ...] = (
    (56.0, 92.0),
    (60.0, 76.0),
    (92.0, 66.0),
    (140.0, 68.0),
    (168.0, 78.0),
    (170.0, 92.0),
)
_FIELD_LIT: tuple[Point, ...] = (
    (58.0, 92.0),
    (62.0, 77.0),
    (93.0, 67.0),
    (122.0, 68.0),
    (122.0, 74.0),
    (96.0, 73.0),
    (69.0, 82.0),
    (66.0, 92.0),
)
_FIELD_BAND: tuple[Point, ...] = (
    (56.0, 88.0),
    (168.0, 88.0),
    (168.0, 102.0),
    (56.0, 102.0),
)
# The eyeshade: a strap and a wide brim over the brow, and no crown — so the
# hair above it stays part of the outline, which is what separates it from a
# cap. The brim stops above the brow line the eyes are read against.
_VISOR_STRAP: tuple[Point, ...] = (
    (60.0, 90.0),
    (160.0, 90.0),
    (160.0, 104.0),
    (60.0, 104.0),
)
_VISOR_BRIM: tuple[Point, ...] = (
    (42.0, 102.0),
    (178.0, 102.0),
    (158.0, 118.0),
    (62.0, 118.0),
)
_GOGGLE_STRAP: tuple[Point, ...] = (
    (60.0, 100.0),
    (160.0, 100.0),
    (160.0, 112.0),
    (60.0, 112.0),
)
_HEADSET_BAND: tuple[Point, ...] = (
    (60.0, 128.0),
    (72.0, 92.0),
    (110.0, 86.0),
    (148.0, 92.0),
    (160.0, 128.0),
)
_HEADSET_CUP: tuple[Point, ...] = (
    (52.0, 128.0),
    (68.0, 128.0),
    (68.0, 152.0),
    (52.0, 152.0),
)
# The eyepatch: a plate over the eye it covers, in reference pixels off that
# eye's centre, and the strap that lands on the ear. The plate is one flat tone
# all through: what the review read as a domino mask was the lit eye and the
# brow showing inside it, and `covered_eye` is what keeps them off it.
_PATCH_PLATE: tuple[Point, ...] = (
    (-15.0, 130.0),
    (13.0, 127.0),
    (14.0, 148.0),
    (0.0, 158.0),
    (-14.0, 151.0),
)
# One cut, run at the gauge and down the cheek rather than across the socket.
# The two cross-ticks it used to carry were four design units long — one texel
# — and three one-texel marks laid over a brow are the cluster of ink fragments
# the review found orbiting Vale's eye. A scar reads as a scar beside the eye;
# on top of it, it reads as damage to the drawing.
_SCAR_CUT: tuple[Point, ...] = ((140.0, 134.0), (148.0, 164.0))


def _worn(points: tuple[Point, ...]) -> Callable[..., list[Point]]:
    """A piece of headwear: one flat mass of cloth, outlined."""

    def draw(
        canvas: Canvas, frame: Frame, skull: Skull, tint: RGB, kicker: RGB
    ) -> list[Point]:
        path = frame.path(points)
        canvas.polygon(path, tint)
        canvas.stroke(path, INK_FEATURE, INK, closed=True)
        return path

    return draw


def _hood(
    canvas: Canvas, frame: Frame, skull: Skull, tint: RGB, kicker: RGB
) -> list[Point]:
    path = frame.path(_HOOD)
    canvas.polygon(path, tint)
    canvas.polygon(frame.path(_HOOD_LINING), KIT)
    canvas.stroke(path, INK_FEATURE, INK, closed=True)
    return path


def _cap(
    canvas: Canvas, frame: Frame, skull: Skull, tint: RGB, kicker: RGB
) -> list[Point]:
    """A service cap: a crown in faction cloth over a kit band and a peak.

    The peak is what makes it a cap rather than a hat at chip size — a straight
    dark bar over the brow, wider than the band it hangs off.
    """
    crown = frame.path(_CAP_CROWN)
    canvas.polygon(crown, tint)
    canvas.polygon(frame.path(_CAP_LIT), kicker)
    canvas.stroke(crown, INK_FEATURE, INK, closed=True)
    for piece in (_CAP_BAND, _CAP_PEAK):
        path = frame.path(piece)
        canvas.polygon(path, KIT)
        canvas.stroke(path, INK_FEATURE, INK, closed=True)
    return crown


def _fieldcap(
    canvas: Canvas, frame: Frame, skull: Skull, tint: RGB, kicker: RGB
) -> list[Point]:
    """A soft field cap: a slouched crown over a kit band, and nothing else."""
    crown = frame.path(_FIELD_CROWN)
    canvas.polygon(crown, tint)
    canvas.polygon(frame.path(_FIELD_LIT), kicker)
    canvas.stroke(crown, INK_FEATURE, INK, closed=True)
    band = frame.path(_FIELD_BAND)
    canvas.polygon(band, KIT)
    canvas.stroke(band, INK_FEATURE, INK, closed=True)
    return crown


def _visor(
    canvas: Canvas, frame: Frame, skull: Skull, tint: RGB, kicker: RGB
) -> list[Point]:
    """An eyeshade: a kit strap carrying a brim in the general's own cloth."""
    strap = frame.path(_VISOR_STRAP)
    canvas.polygon(strap, KIT)
    canvas.stroke(strap, INK_FEATURE, INK, closed=True)
    brim = frame.path(_VISOR_BRIM)
    canvas.polygon(brim, tint)
    canvas.stroke(brim, INK_FEATURE, INK, closed=True)
    return brim


def _goggles(
    canvas: Canvas, frame: Frame, skull: Skull, tint: RGB, kicker: RGB
) -> list[Point]:
    path = frame.path(_GOGGLE_STRAP)
    canvas.polygon(path, KIT)
    canvas.stroke(path, INK_FEATURE, INK, closed=True)
    for x in _eye_xs(skull):
        _ringed_ellipse(canvas, frame, (x, 106.0), (13.0, 13.0), GLASS, INK_FEATURE)
    return path


def _glasses(
    canvas: Canvas, frame: Frame, skull: Skull, tint: RGB, kicker: RGB
) -> list[Point]:
    """P17: two squares at the feature weight, and no bridge between them.

    A bridge is the one part of a pair of glasses the mip cannot hold, and it
    was what joined the two lenses into a single grey smear at chip size."""
    for x in _eye_xs(skull):
        lens = (
            (x - LENS_HALF, EYE_LINE - LENS_HALF),
            (x + LENS_HALF, EYE_LINE - LENS_HALF),
            (x + LENS_HALF, EYE_LINE + LENS_HALF),
            (x - LENS_HALF, EYE_LINE + LENS_HALF),
        )
        canvas.stroke(frame.path(lens), INK_FEATURE, INK, closed=True)
    return []


def _eyepatch(
    canvas: Canvas, frame: Frame, skull: Skull, tint: RGB, kicker: RGB
) -> list[Point]:
    x = _eye_xs(skull)[0]
    ear_x, ear_y, radius = EAR
    outer_x, outer_y = _PATCH_PLATE[0]
    canvas.stroke(
        frame.path(
            [(x + outer_x + 2.0, outer_y + 3.0), (ear_x + radius, ear_y - radius)]
        ),
        INK_FEATURE,
        INK,
    )
    canvas.polygon(frame.path([(x + dx, y) for dx, y in _PATCH_PLATE]), INK)
    return []


def _scar(
    canvas: Canvas, frame: Frame, skull: Skull, tint: RGB, kicker: RGB
) -> list[Point]:
    canvas.ribbon(frame.path(_SCAR_CUT), SCAR, SCAR_DEEP)
    return []


def _headset(
    canvas: Canvas, frame: Frame, skull: Skull, tint: RGB, kicker: RGB
) -> list[Point]:
    band = frame.path(_HEADSET_BAND)
    canvas.stroke(band, INK_FEATURE, INK)
    cup = frame.path(_HEADSET_CUP)
    canvas.polygon(cup, tint)
    canvas.stroke(cup, INK_FEATURE, INK, closed=True)
    canvas.ribbon(frame.path([(56.0, 148.0), (48.0, 166.0), (80.0, 170.0)]), KIT, INK)
    _ringed_ellipse(canvas, frame, (82.0, 169.0), (4.8, 4.8), tint, INK_DETAIL)
    return [*band, *cup]


def _unworn(
    canvas: Canvas, frame: Frame, skull: Skull, tint: RGB, kicker: RGB
) -> list[Point]:
    """A general who wears nothing: the one kind that draws nothing."""
    return []


_ACCESSORIES: dict[str, Callable[[Canvas, Frame, Skull, RGB, RGB], list[Point]]] = {
    "bandana": _worn(_BANDANA),
    "cap": _cap,
    "eyepatch": _eyepatch,
    "fieldcap": _fieldcap,
    "glasses": _glasses,
    "goggles": _goggles,
    "headband": _worn(_HEADBAND),
    "headset": _headset,
    "hood": _hood,
    "none": _unworn,
    "scar": _scar,
    "visor": _visor,
}
ACCESSORY_KINDS = frozenset(_ACCESSORIES)
# Which of the two sockets a worn accessory hides. An eyepatch is the only one
# that hides anything, and it covers the eye and the brow over it: a patch with
# either drawn on top of it is the mask the review named, not a patch.
_COVERS_EYE: dict[str, int] = {"eyepatch": 0}


def covered_eye(kind: str) -> int | None:
    """The socket the worn accessory hides — `eyes` and `brow` skip it."""
    return _COVERS_EYE.get(kind)


def accessory(
    canvas: Canvas, skull: Skull, kind: str, *, tint: RGB = KIT, kicker: RGB = KIT
) -> list[Point]:
    """Draw the worn accessory; returns what it added to the silhouette.

    `tint` is the general's faction colour for the pieces the handoff cut out of
    uniform cloth — a bandana, a headband, a hood, a headset cup. `kicker` is
    that cloth's lit rung, which the two caps catch the key on. Both default to
    the kit slate — the module answers for every key on its own, and a crown
    handed no kicker is the flat one it was before.
    """
    return _ACCESSORIES[kind](canvas, Frame.of(skull), skull, tint, kicker)


def earring(canvas: Canvas, skull: Skull) -> None:
    x, y, radius = EAR
    frame = Frame.of(skull)
    _ringed_ellipse(canvas, frame, (x, y + radius + 3.0), (3.8, 3.8), GOLD, INK_DETAIL)


# A freckle at the gauge: a square of skin shade, one per cheek, out where the
# cheekbone turns. Three dots of a texel and a half apiece — what this drew —
# quantise into a scatter of specks rather than into freckles.
FRECKLE_AT = (-3.0, 159.0)
FRECKLE_HALF = 2.2


def freckles(canvas: Canvas, skull: Skull, ramp: Ramp) -> None:
    frame = Frame.of(skull)
    dx, dy = FRECKLE_AT
    for side, x in enumerate(_eye_xs(skull)):
        outward = -1.0 if side == 0 else 1.0
        canvas.rect(
            (
                *frame.at(x + outward * dx - FRECKLE_HALF, dy - FRECKLE_HALF),
                *frame.at(x + outward * dx + FRECKLE_HALF, dy + FRECKLE_HALF),
            ),
            ramp.shade,
        )
