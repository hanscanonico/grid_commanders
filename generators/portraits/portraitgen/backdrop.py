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
from .palette import INK, RGBA, Faction, S_CONTOUR, S_SHADOW, S_UNDER, faction_ramp

KINDS = frozenset({"bars", "burst", "grid", "halftone", "rays", "speed", "wedge"})
# Which rung of the army's ramp each part of the window is painted in. A band
# is a tone off the ramp, never an alpha wash over the field: a wash was what
# the retired bake's soft edges hid, and at sixteen tones it is a colour the
# bust does not have. The field is the shadow rung — a band under the coat
# that stands in front of it on every army, Iron included — and the two
# treatments step DOWN
# from it, so a window can only ever be darker than the general in it.
FIELD_SLOT = S_SHADOW
LATTICE, ACCENT = S_UNDER, S_CONTOUR

# The ink-bordered inner window, in portrait pixels — the handoff's 98x96 box at
# (6, 24) of its 110x134 viewBox, at the pinned raster's scale.
WINDOW = (12.0, 76.0, 208.0, 268.0)
# The star and the rays are struck about these, not about the raster's centre:
# the bust stands bottom-centre, so the burst sits behind the head and the rays
# rise out of the shoulders.
BURST_AT = (110.0, 166.0)
RAYS_AT = (110.0, 268.0)

Painter = Callable[[Canvas], None]
Band = tuple[int, Painter]

# The colour a treatment's shape is drawn in, and it is never the colour it ends
# up: `_band` flattens the whole layer to the rung it was asked for once the
# shape is down, so a painter only has to lay opaque pixels somewhere. That is
# why no painter is told which army it is drawing for.
SOLID: RGBA = (255, 255, 255, 255)


def _erase(canvas: Canvas, points: Iterable[Point]) -> None:
    """Cut a shape back out of a layer, so two bands never stack into a third."""
    hole = canvas.blank()
    hole.polygon(points, (255, 255, 255, 255))
    keep = ImageChops.invert(hole.image.getchannel("A"))
    canvas.image.putalpha(ImageChops.multiply(canvas.image.getchannel("A"), keep))


def _band(canvas: Canvas, faction: Faction, paint: Painter, slot: int) -> None:
    """Paint one treatment band: its shape, flattened onto one rung of the
    army's ramp and clipped to the window."""
    layer = canvas.blank()
    paint(layer)
    flat = layer.image.getchannel("A").point(lambda a: 255 if a >= CAST_CUTOFF else 0)
    window = Image.new("L", layer.image.size, 0)
    x0, y0, x1, y1 = (canvas.px(v) for v in WINDOW)
    ImageDraw.Draw(window).rectangle((x0, y0, x1 - 1, y1 - 1), fill=255)
    layer.image.paste((*faction_ramp(faction.key)[slot], 255), (0, 0), flat)
    layer.image.putalpha(ImageChops.multiply(flat, window))
    canvas.compose(layer)


def _grid(canvas: Canvas) -> None:
    """The strategist's lattice: a ruled grid over the whole window."""
    for i in range(9):
        canvas.rect((12.0 + i * 24.0, 76.0, 15.0 + i * 24.0, 268.0), SOLID)
        canvas.rect((12.0, 76.0 + i * 24.0, 208.0, 79.0 + i * 24.0), SOLID)


def _halftone(canvas: Canvas) -> None:
    """Dots on a staggered lattice, shrinking as they climb."""
    for row in range(8):
        y = 84.0 + row * 24.0
        radius = 8.0 - row * 0.6
        for col in range(9):
            x = 12.0 + col * 24.0 + (12.0 if row % 2 else 0.0)
            canvas.ellipse((x - radius, y - radius, x + radius, y + radius), SOLID)


def _bars_tall(canvas: Canvas) -> None:
    canvas.rect((34.0, 116.0, 60.0, 268.0), SOLID)
    canvas.rect((96.0, 88.0, 122.0, 268.0), SOLID)


def _bars_short(canvas: Canvas) -> None:
    canvas.rect((158.0, 140.0, 184.0, 268.0), SOLID)


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


def _burst(canvas: Canvas) -> None:
    """Three concentric hard stars: a rim, a punched gap, a core."""
    canvas.polygon(_star(1.0), SOLID)
    _erase(canvas, _star(0.62))
    canvas.polygon(_star(0.34), SOLID)


def _rays(canvas: Canvas) -> None:
    """Four wedges wide enough to survive decimation.

    Seven eleven-degree spokes read as one grey smear at chip size, which is
    what the reviews measured; four twenty-degree wedges on an eighteen-degree
    gap carry the same radiance and stay two-valued all the way down.
    """
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
            SOLID,
        )


def _speed(canvas: Canvas) -> None:
    """Level bands rather than a rotated comb: the hairline is what died."""
    for left, top, height in (
        (12.0, 84.0, 10.0),
        (12.0, 98.0, 4.0),
        (68.0, 110.0, 6.0),
        (12.0, 132.0, 14.0),
        (12.0, 150.0, 4.0),
        (92.0, 166.0, 6.0),
    ):
        canvas.rect((left, top, 208.0, top + height), SOLID)


def _wedge_low(canvas: Canvas) -> None:
    canvas.rect((12.0, 76.0, 208.0, 100.0), SOLID)
    canvas.rect((110.0, 126.0, 208.0, 156.0), SOLID)


def _wedge_high(canvas: Canvas) -> None:
    canvas.rect((61.0, 100.0, 208.0, 126.0), SOLID)
    canvas.rect((159.0, 156.0, 208.0, 190.0), SOLID)


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
    canvas.rect(WINDOW, (*faction_ramp(faction.key)[FIELD_SLOT], 255))


def treatment(canvas: Canvas, kind: str, faction: Faction) -> None:
    """One dramatic treatment, clipped to the window. An unknown kind raises."""
    if kind not in _TREATMENTS:
        raise KeyError(f"no backdrop {kind!r} (have {sorted(_TREATMENTS)})")
    for slot, paint in _TREATMENTS[kind]:
        _band(canvas, faction, paint, slot)


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
