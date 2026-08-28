"""Hair: a mass silhouette plus tapered strand clusters off the hair ramp.

A style is not a flat shape — it is the mass, then N clusters placed on a fixed
sequence over it, each taking its own band from the ramp. That is what turns a
single dark hex into hair.

The masses are the handoff's own, transcribed in portrait pixels (its units,
doubled, over `features.REFERENCE_BOX` like every other feature) and fitted to
the general's skull by `features.Frame`, so hair and the face it sits on can
never be cut to two different heads. Which band a cluster takes is decided by
where it lies, not by a roll: the light is fixed upper left, so the clusters on
that side are the lit ones on every bust.

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

# The seven hair colours the roster picks from, as the handoff wrote them.
HAIR_BASES: dict[str, RGB] = {
    "auburn": (140, 74, 47),
    "black": (38, 38, 38),
    "blonde": (224, 184, 76),
    "brown": (90, 60, 40),
    "darkbrown": (51, 37, 26),
    "grey": (189, 189, 189),
    "platinum": (231, 224, 204),
}
HAIR_COLOURS = frozenset(HAIR_BASES)

Mass = tuple[Point, ...]
Blob = tuple[float, float, float]


@dataclass(frozen=True)
class Comb:
    """Where a style's strand clusters fall: a span, a drop and a count."""

    x0: float
    x1: float
    top: float
    fall: float
    count: int
    lean: float = 0.0


@dataclass(frozen=True)
class Style:
    """One hairstyle: what falls behind the head, what covers it, and the comb."""

    front: tuple[Mass, ...] = ()
    back: tuple[Mass, ...] = ()
    blobs: tuple[Blob, ...] = ()
    comb: Comb | None = None
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
    "bald": Style(
        front=(
            ((68.0, 88.0), (88.0, 70.0), (80.0, 80.0), (80.0, 92.0)),
            ((152.0, 88.0), (132.0, 70.0), (140.0, 80.0), (140.0, 92.0)),
        )
    ),
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
        comb=Comb(64.0, 156.0, 84.0, 22.0, 7),
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
        comb=Comb(66.0, 154.0, 86.0, 18.0, 6),
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
        comb=Comb(68.0, 152.0, 90.0, 16.0, 6),
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
        comb=Comb(74.0, 146.0, 92.0, 10.0, 8),
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
        comb=Comb(72.0, 148.0, 96.0, 14.0, 5),
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
        comb=Comb(70.0, 150.0, 92.0, 18.0, 5),
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
        comb=Comb(62.0, 158.0, 80.0, 30.0, 8, lean=4.0),
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
        comb=Comb(66.0, 154.0, 84.0, 20.0, 7),
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
        comb=Comb(70.0, 150.0, 86.0, 16.0, 7),
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
        comb=Comb(90.0, 154.0, 86.0, 14.0, 6, lean=6.0),
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
        comb=Comb(76.0, 144.0, 94.0, 12.0, 6),
    ),
}
STYLES = frozenset(_STYLES)

# How deep the fringe's own shadow sits on the forehead: one flat band of the
# skin's shade tone, hard-edged like every other band on the sheet. The design
# system takes no blur, so this is a painted band rather than a softened alpha.
FRINGE_BAND = "shade"


def ramp_for(colour: str) -> Ramp:
    """The four tones a hair colour is painted in."""
    return light.build_ramp(HAIR_BASES[colour])


def draw(
    canvas: Canvas, skull: Skull, style: str, ramp: Ramp, *, skin: Ramp | None = None
) -> None:
    """The mass and its clusters. An unknown style raises."""
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
    """The fringe, the crown and the strand clusters — painted over the head.

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
    if spec.comb is not None:
        _clusters(canvas, frame, spec.comb, ramp)


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


def _clusters(canvas: Canvas, frame: Frame, comb: Comb, ramp: Ramp) -> None:
    """Tapered quads across the mass, each taking the band its place is lit in."""
    span = comb.x1 - comb.x0
    half = span / (comb.count * 1.15)
    for index in range(comb.count):
        share = index / (comb.count - 1) if comb.count > 1 else 0.0
        x = comb.x0 + span * share
        tip = x + comb.lean
        quad = (
            (x - half, comb.top),
            (x + half, comb.top),
            (tip + half * 0.3, comb.top + comb.fall),
            (tip - half * 0.3, comb.top + comb.fall),
        )
        canvas.polygon(frame.path(quad), _band(ramp, share, index))


def _band(ramp: Ramp, share: float, index: int) -> RGB:
    """Which tone a cluster takes: where it lies, one step darker on the odds.

    The light never moves, so the left of the mass is always the lit side.
    """
    order = (ramp.lit, ramp.base, ramp.shade, ramp.deep)
    step = 0 if share < 0.3 else 1 if share < 0.6 else 2
    return order[step + index % 2]
