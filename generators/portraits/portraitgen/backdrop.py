"""The window field behind a bust: a flat faction field, a treatment, the frame.

The field is one flat faction tone rather than a gradient — the design system
allows a single radial on the menu and nothing else, and a field that ramps
spends colours the raster does not have.

Every treatment is hard lattice or band geometry held inside the 0.20-0.26
opacity band; brighter and it starts competing with the face. Rays, speed lines
and the soft wedge are the three the reviews measured as dying at chip size, so
they are rebuilt here as banded equivalents rather than retired: four wide
wedges instead of seven thin spokes, level bands instead of a rotated hairline
comb, and a staircase instead of a lit diagonal.

A treatment is painted opaque on its own layer, flattened to **one** alpha and
masked to the window. That is what keeps it a band and not a wash: two crossing
grid rules or two overlapping wedges composite to one value rather than to a
third, and a shape may be authored past the frame without leaking onto the
mount around it.
"""

from __future__ import annotations

import math
from collections.abc import Callable, Iterable

from PIL import Image, ImageChops, ImageDraw

from .canvas import CAST_CUTOFF, INK_SILHOUETTE, Canvas, Point
from .palette import INK, RGBA, Faction

KINDS = frozenset({"bars", "burst", "grid", "halftone", "rays", "speed", "wedge"})
# The band a treatment is drawn at, over the faction field.
OPACITY_BAND = (0.20, 0.26)
# The two opacities inside it: the lattice itself, and the second value a
# treatment lays beside it. A treatment's two bands never overlap.
LATTICE, ACCENT = 0.24, 0.20

# The ink-bordered inner window, in portrait pixels — the handoff's 98x96 box at
# (6, 24) of its 110x134 viewBox, at the pinned raster's scale.
WINDOW = (12.0, 76.0, 208.0, 268.0)
# The star and the rays are struck about these, not about the raster's centre:
# the bust stands bottom-centre, so the burst sits behind the head and the rays
# rise out of the shoulders.
BURST_AT = (110.0, 166.0)
RAYS_AT = (110.0, 268.0)

Painter = Callable[[Canvas, Faction], None]
Band = tuple[float, Painter]


def _tone(faction: Faction) -> RGBA:
    """The one colour a treatment is drawn in; the band supplies its value."""
    return (*faction.body_lt, 255)


def _erase(canvas: Canvas, points: Iterable[Point]) -> None:
    """Cut a shape back out of a layer, so two bands never stack into a third."""
    hole = Canvas(canvas.size, canvas.scale)
    hole.polygon(points, (255, 255, 255, 255))
    keep = ImageChops.invert(hole.image.getchannel("A"))
    canvas.image.putalpha(ImageChops.multiply(canvas.image.getchannel("A"), keep))


def _band(canvas: Canvas, faction: Faction, paint: Painter, opacity: float) -> None:
    """Paint one treatment band: opaque, then flattened to a single alpha."""
    layer = Canvas(canvas.size, canvas.scale)
    paint(layer, faction)
    value = round(opacity * 255)
    flat = layer.image.getchannel("A").point(lambda a: value if a >= CAST_CUTOFF else 0)
    window = Image.new("L", layer.image.size, 0)
    x0, y0, x1, y1 = (round(v * canvas.scale) for v in WINDOW)
    ImageDraw.Draw(window).rectangle((x0, y0, x1 - 1, y1 - 1), fill=255)
    layer.image.putalpha(ImageChops.multiply(flat, window))
    canvas.compose(layer)


def _grid(canvas: Canvas, faction: Faction) -> None:
    """The strategist's lattice: a ruled grid over the whole window."""
    tone = _tone(faction)
    for i in range(9):
        canvas.rect((12.0 + i * 24.0, 76.0, 15.0 + i * 24.0, 268.0), tone)
        canvas.rect((12.0, 76.0 + i * 24.0, 208.0, 79.0 + i * 24.0), tone)


def _halftone(canvas: Canvas, faction: Faction) -> None:
    """Dots on a staggered lattice, shrinking as they climb."""
    tone = _tone(faction)
    for row in range(8):
        y = 84.0 + row * 24.0
        radius = 8.0 - row * 0.6
        for col in range(9):
            x = 12.0 + col * 24.0 + (12.0 if row % 2 else 0.0)
            canvas.ellipse((x - radius, y - radius, x + radius, y + radius), tone)


def _bars_tall(canvas: Canvas, faction: Faction) -> None:
    canvas.rect((34.0, 116.0, 60.0, 268.0), _tone(faction))
    canvas.rect((96.0, 88.0, 122.0, 268.0), _tone(faction))


def _bars_short(canvas: Canvas, faction: Faction) -> None:
    canvas.rect((158.0, 140.0, 184.0, 268.0), _tone(faction))


def _star(scale: float) -> list[Point]:
    """A twenty-point star about `BURST_AT`, at `scale` of full size."""
    points: list[Point] = []
    for i in range(20):
        angle = math.radians(i * 18.0 - 9.0)
        radius = (44.0 if i % 2 else 88.0) * scale
        points.append(
            (
                BURST_AT[0] + radius * math.cos(angle),
                BURST_AT[1] + radius * math.sin(angle),
            )
        )
    return points


def _burst(canvas: Canvas, faction: Faction) -> None:
    """Three concentric hard stars: a rim, a punched gap, a core."""
    tone = _tone(faction)
    canvas.polygon(_star(1.0), tone)
    _erase(canvas, _star(0.62))
    canvas.polygon(_star(0.34), tone)


def _rays(canvas: Canvas, faction: Faction) -> None:
    """Four wedges wide enough to survive decimation.

    Seven eleven-degree spokes read as one grey smear at chip size, which is
    what the reviews measured; four twenty-degree wedges on an eighteen-degree
    gap carry the same radiance and stay two-valued all the way down.
    """
    tone = _tone(faction)
    for degrees in (-162.0, -124.0, -86.0, -48.0):
        first, second = math.radians(degrees), math.radians(degrees + 20.0)
        canvas.polygon(
            [
                RAYS_AT,
                (
                    RAYS_AT[0] + 300.0 * math.cos(first),
                    RAYS_AT[1] + 300.0 * math.sin(first),
                ),
                (
                    RAYS_AT[0] + 300.0 * math.cos(second),
                    RAYS_AT[1] + 300.0 * math.sin(second),
                ),
            ],
            tone,
        )


def _speed(canvas: Canvas, faction: Faction) -> None:
    """Level bands rather than a rotated comb: the hairline is what died."""
    tone = _tone(faction)
    for left, top, height in (
        (12.0, 84.0, 10.0),
        (12.0, 98.0, 4.0),
        (68.0, 110.0, 6.0),
        (12.0, 132.0, 14.0),
        (12.0, 150.0, 4.0),
        (92.0, 166.0, 6.0),
    ):
        canvas.rect((left, top, 208.0, top + height), tone)


def _wedge_low(canvas: Canvas, faction: Faction) -> None:
    tone = _tone(faction)
    canvas.rect((12.0, 76.0, 208.0, 100.0), tone)
    canvas.rect((110.0, 126.0, 208.0, 156.0), tone)


def _wedge_high(canvas: Canvas, faction: Faction) -> None:
    tone = _tone(faction)
    canvas.rect((61.0, 100.0, 208.0, 126.0), tone)
    canvas.rect((159.0, 156.0, 208.0, 190.0), tone)


_TREATMENTS: dict[str, tuple[Band, ...]] = {
    "bars": ((LATTICE, _bars_tall), (ACCENT, _bars_short)),
    "burst": ((LATTICE, _burst),),
    "grid": ((LATTICE, _grid),),
    "halftone": ((LATTICE, _halftone),),
    "rays": ((LATTICE, _rays),),
    "speed": ((LATTICE, _speed),),
    "wedge": ((LATTICE, _wedge_low), (ACCENT, _wedge_high)),
}


def field(canvas: Canvas, faction: Faction) -> None:
    """The window's flat faction field — one tone, no gradient."""
    canvas.rect(WINDOW, (*faction.body_dk, 255))


def treatment(canvas: Canvas, kind: str, faction: Faction) -> None:
    """One dramatic treatment, clipped to the window. An unknown kind raises."""
    if kind not in _TREATMENTS:
        raise KeyError(f"no backdrop {kind!r} (have {sorted(_TREATMENTS)})")
    for opacity, paint in _TREATMENTS[kind]:
        _band(canvas, faction, paint, opacity)


def frame(canvas: Canvas) -> None:
    """The ink window border, at the silhouette weight."""
    x0, y0, x1, y1 = WINDOW
    canvas.stroke(
        [(x0, y0), (x1, y0), (x1, y1), (x0, y1)],
        INK_SILHOUETTE,
        (*INK, 255),
        closed=True,
    )


def draw(canvas: Canvas, kind: str, faction: Faction) -> None:
    """The field, the treatment and the ink window border. Unknown kinds raise."""
    field(canvas, faction)
    treatment(canvas, kind, faction)
    frame(canvas)
