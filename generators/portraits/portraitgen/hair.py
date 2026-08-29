"""Hair: a mass silhouette with one flat lit lobe off the hair ramp.

A style is the mass plus the single shape the key catches on it. It used to be
N alternating strand clusters, and at chip size a row of them read as a striped
awning rather than as hair — so the mass now takes one lobe, on the lit side,
and nothing else.

The masses are the handoff's own, transcribed in portrait pixels (its units,
doubled, over `features.REFERENCE_BOX` like every other feature) and fitted to
the general's skull by `features.Frame`, so hair and the face it sits on can
never be cut to two different heads. Where the lobe lies is decided by the
light, not by a roll: the key is fixed upper left, so it sits on that side of
the mass on every bust.

The mass is drawn in two halves because the head is painted between them: `back`
is the fall behind the skull, `front` the fringe and the crown over it. `draw`
paints both onto one layer.
"""

from __future__ import annotations

from dataclasses import dataclass

from . import light
from .canvas import INK_SILHOUETTE, Canvas, Point
from .features import Frame
from .head import Skull
from .light import Ramp
from .palette import INK, RGB

# The hair colours the roster picks from: the handoff's seven, plus `steel`.
# Steel is grey a rung darker, and it exists because grey over a pale face is
# the sheet's contrast floor — the one general who wears both needs a ramp of
# his own rather than everyone else's grey moved down to meet him.
HAIR_BASES: dict[str, RGB] = {
    "auburn": (140, 74, 47),
    "black": (38, 38, 38),
    "blonde": (224, 184, 76),
    "brown": (90, 60, 40),
    "darkbrown": (51, 37, 26),
    "grey": (189, 189, 189),
    "platinum": (231, 224, 204),
    "steel": (165, 165, 165),
}
HAIR_COLOURS = frozenset(HAIR_BASES)

Mass = tuple[Point, ...]
Blob = tuple[float, float, float]


@dataclass(frozen=True)
class Lobe:
    """The one shape the key catches on a mass: a span at a top, and its drop."""

    x0: float
    x1: float
    top: float
    fall: float
    lean: float = 0.0


@dataclass(frozen=True)
class Style:
    """One hairstyle: what falls behind the head, what covers it, and the lobe."""

    front: tuple[Mass, ...] = ()
    back: tuple[Mass, ...] = ()
    blobs: tuple[Blob, ...] = ()
    lobe: Lobe | None = None
    fringe: Mass = ()


_CAP: Mass = (
    (60.0, 136.0),
    (56.0, 76.0),
    (110.0, 72.0),
    (164.0, 76.0),
    (160.0, 136.0),
    (160.0, 112.0),
    (110.0, 108.0),
    (60.0, 112.0),
)
_FRINGE_BAND: Mass = ((66.0, 116.0), (110.0, 110.0), (154.0, 116.0), (110.0, 126.0))

_STYLES: dict[str, Style] = {
    # A scalp, and nothing else: the two temple wisps this style used to carry
    # broke the crown's silhouette and read as horns at chip size.
    "bald": Style(),
    "bob": Style(
        front=(
            (
                (60.0, 124.0),
                (58.0, 82.0),
                (110.0, 78.0),
                (162.0, 82.0),
                (160.0, 124.0),
                (146.0, 98.0),
                (110.0, 96.0),
                (74.0, 98.0),
            ),
        ),
        back=(
            (
                (56.0, 140.0),
                (48.0, 76.0),
                (110.0, 72.0),
                (172.0, 76.0),
                (164.0, 140.0),
                (164.0, 188.0),
                (148.0, 180.0),
                (160.0, 132.0),
                (110.0, 124.0),
                (60.0, 132.0),
                (72.0, 180.0),
                (56.0, 188.0),
            ),
        ),
        lobe=Lobe(66.0, 104.0, 84.0, 24.0),
        fringe=_FRINGE_BAND,
    ),
    "braid": Style(
        front=(
            (
                (62.0, 124.0),
                (60.0, 84.0),
                (110.0, 80.0),
                (160.0, 84.0),
                (158.0, 124.0),
                (144.0, 100.0),
                (110.0, 98.0),
                (76.0, 100.0),
            ),
        ),
        back=(
            _CAP,
            (
                (62.0, 128.0),
                (40.0, 148.0),
                (48.0, 188.0),
                (52.0, 212.0),
                (66.0, 208.0),
                (56.0, 176.0),
                (76.0, 144.0),
            ),
        ),
        blobs=((56.0, 170.0, 9.0), (60.0, 194.0, 9.0)),
        lobe=Lobe(68.0, 104.0, 86.0, 20.0),
        fringe=_FRINGE_BAND,
    ),
    "bun": Style(
        front=(
            (
                (62.0, 124.0),
                (60.0, 88.0),
                (110.0, 84.0),
                (160.0, 88.0),
                (158.0, 124.0),
                (144.0, 104.0),
                (110.0, 104.0),
                (76.0, 104.0),
            ),
        ),
        blobs=((110.0, 74.0, 18.0),),
        lobe=Lobe(70.0, 106.0, 90.0, 18.0),
        fringe=_FRINGE_BAND,
    ),
    "buzz": Style(
        front=(
            (
                (66.0, 120.0),
                (68.0, 90.0),
                (110.0, 86.0),
                (152.0, 90.0),
                (154.0, 120.0),
                (140.0, 102.0),
                (110.0, 100.0),
                (80.0, 102.0),
            ),
        ),
        lobe=Lobe(76.0, 110.0, 92.0, 12.0),
    ),
    "curly": Style(
        front=(
            (
                (64.0, 124.0),
                (68.0, 108.0),
                (152.0, 108.0),
                (156.0, 124.0),
                (140.0, 112.0),
                (110.0, 112.0),
                (80.0, 112.0),
            ),
        ),
        blobs=(
            (76.0, 100.0, 16.0),
            (100.0, 90.0, 17.0),
            (124.0, 90.0, 17.0),
            (146.0, 102.0, 16.0),
        ),
        lobe=Lobe(74.0, 108.0, 88.0, 18.0),
        fringe=_FRINGE_BAND,
    ),
    "hood": Style(
        front=(
            (
                (54.0, 150.0),
                (44.0, 90.0),
                (110.0, 76.0),
                (176.0, 90.0),
                (166.0, 150.0),
                (156.0, 114.0),
                (110.0, 106.0),
                (64.0, 114.0),
            ),
        ),
        lobe=Lobe(68.0, 106.0, 90.0, 22.0),
        fringe=_FRINGE_BAND,
    ),
    "long": Style(
        front=(
            (
                (64.0, 120.0),
                (68.0, 88.0),
                (110.0, 84.0),
                (152.0, 88.0),
                (156.0, 120.0),
                (140.0, 100.0),
                (120.0, 104.0),
                (112.0, 88.0),
                (94.0, 100.0),
                (80.0, 96.0),
                (80.0, 116.0),
            ),
        ),
        back=(
            (
                (54.0, 144.0),
                (44.0, 72.0),
                (110.0, 68.0),
                (176.0, 72.0),
                (166.0, 144.0),
                (172.0, 236.0),
                (144.0, 220.0),
                (160.0, 136.0),
                (110.0, 128.0),
                (60.0, 136.0),
                (76.0, 220.0),
                (48.0, 236.0),
            ),
        ),
        lobe=Lobe(64.0, 106.0, 80.0, 32.0, lean=3.0),
        fringe=_FRINGE_BAND,
    ),
    "ponytail": Style(
        front=(
            (
                (62.0, 124.0),
                (60.0, 84.0),
                (110.0, 80.0),
                (160.0, 84.0),
                (158.0, 124.0),
                (144.0, 100.0),
                (110.0, 98.0),
                (80.0, 98.0),
                (80.0, 116.0),
            ),
        ),
        back=(
            _CAP,
            (
                (156.0, 108.0),
                (196.0, 120.0),
                (192.0, 176.0),
                (184.0, 200.0),
                (168.0, 196.0),
                (184.0, 156.0),
                (164.0, 128.0),
            ),
        ),
        lobe=Lobe(68.0, 106.0, 84.0, 22.0),
        fringe=_FRINGE_BAND,
    ),
    "short": Style(
        front=(
            (
                (62.0, 124.0),
                (60.0, 84.0),
                (110.0, 80.0),
                (160.0, 84.0),
                (158.0, 124.0),
                (148.0, 96.0),
                (110.0, 94.0),
                (72.0, 96.0),
            ),
        ),
        lobe=Lobe(70.0, 108.0, 86.0, 18.0),
        fringe=_FRINGE_BAND,
    ),
    "sidepart": Style(
        front=(
            (
                (62.0, 122.0),
                (60.0, 84.0),
                (110.0, 80.0),
                (160.0, 84.0),
                (158.0, 118.0),
                (150.0, 98.0),
                (104.0, 98.0),
                (100.0, 92.0),
                (88.0, 104.0),
            ),
        ),
        lobe=Lobe(64.0, 100.0, 86.0, 18.0, lean=4.0),
        fringe=_FRINGE_BAND,
    ),
    "spiky": Style(
        front=(
            (
                (62.0, 122.0),
                (68.0, 88.0),
                (82.0, 108.0),
                (92.0, 82.0),
                (104.0, 106.0),
                (116.0, 82.0),
                (128.0, 106.0),
                (140.0, 86.0),
                (152.0, 110.0),
                (158.0, 122.0),
                (140.0, 104.0),
                (110.0, 104.0),
                (80.0, 104.0),
            ),
        ),
        lobe=Lobe(74.0, 108.0, 92.0, 14.0),
    ),
}
STYLES = frozenset(_STYLES)

# How deep the fringe's own shadow sits on the forehead: one flat band of the
# skin's shade tone, hard-edged like every other band on the sheet. The design
# system takes no blur, so this is a painted band rather than a softened alpha.
FRINGE_BAND = "shade"

# Above this luma a hair ramp's lit band is already within a step of the base,
# so the lobe stops reading as a highlight and starts cutting a seam through the
# mass — grey, platinum and blonde crowns all lost their edge to it. Those
# masses take the base tone whole.
PALE_HAIR = 150.0
# How far the lobe draws in at its foot, as a share of its own span: the shape
# is a crown highlight tapering down the mass, not a rectangle on it.
_LOBE_TAPER = 0.22


def ramp_for(colour: str) -> Ramp:
    """The four tones a hair colour is painted in."""
    return light.build_ramp(HAIR_BASES[colour])


def draw(
    canvas: Canvas, skull: Skull, style: str, ramp: Ramp, *, skin: Ramp | None = None
) -> None:
    """The mass and the shape the key catches on it. An unknown style raises."""
    back(canvas, skull, style, ramp)
    front(canvas, skull, style, ramp, skin=skin)


def back(canvas: Canvas, skull: Skull, style: str, ramp: Ramp) -> None:
    """What falls behind the head — painted before the skull is."""
    frame = Frame.of(skull)
    for mass in _STYLES[style].back:
        _mass(canvas, frame, mass, ramp.shade)


def front(
    canvas: Canvas, skull: Skull, style: str, ramp: Ramp, *, skin: Ramp | None = None
) -> None:
    """The fringe, the crown and the lit lobe — painted over the head.

    `skin` is the wearer's own ramp: the fringe casts a flat band of its shade
    tone on the forehead, and a shadow on skin has to be a skin tone.
    """
    spec = _STYLES[style]
    frame = Frame.of(skull)
    if skin is not None and spec.fringe:
        canvas.polygon(frame.path(spec.fringe), skin.shade)
    for x, y, radius in spec.blobs:
        canvas.ellipse(frame.ellipse(x, y, radius, radius), ramp.base)
        canvas.stroke(_ring(frame, x, y, radius), INK_SILHOUETTE, INK, closed=True)
    for mass in spec.front:
        _mass(canvas, frame, mass, ramp.base)
    if spec.lobe is not None and light.luminance(ramp.base) <= PALE_HAIR:
        canvas.polygon(frame.path(_lobe(spec.lobe)), ramp.lit)


def _mass(canvas: Canvas, frame: Frame, mass: Mass, tone: RGB) -> None:
    path = frame.path(mass)
    canvas.polygon(path, tone)
    canvas.stroke(path, INK_SILHOUETTE, INK, closed=True)


def _ring(frame: Frame, cx: float, cy: float, radius: float) -> list[Point]:
    """A blob's outline as an octagon, so it takes the silhouette's own ink."""
    step = radius * 0.7071
    corners = (
        (cx + radius, cy),
        (cx + step, cy + step),
        (cx, cy + radius),
        (cx - step, cy + step),
        (cx - radius, cy),
        (cx - step, cy - step),
        (cx, cy - radius),
        (cx + step, cy - step),
    )
    return frame.path(corners)


def _lobe(lobe: Lobe) -> Mass:
    """The lit shape as one tapered quad, in the reference box's own units."""
    draw_in = (lobe.x1 - lobe.x0) * _LOBE_TAPER
    foot = lobe.top + lobe.fall
    return (
        (lobe.x0, lobe.top),
        (lobe.x1, lobe.top),
        (lobe.x1 + lobe.lean - draw_in, foot),
        (lobe.x0 + lobe.lean + draw_in, foot),
    )
