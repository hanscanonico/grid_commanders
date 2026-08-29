"""The drawing surface every painted layer goes through.

A bust is drawn at **3x** — 660x804 — and downsampled once to the pinned
220x268 with a plain box filter. That is where the antialiasing comes from:
`ImageDraw` has none of its own, so a primitive is rasterised hard at the
working resolution and the downsample averages the edge. `BOX` at an exact
integer ratio is a straight average of nine pixels, reproducible on any machine
Pillow runs on, and it does not ring on hard ink edges the way `LANCZOS` does.
The filter is named here rather than left to a Pillow default so a release
cannot change the art.

Determinism is the reason geometry is rounded in exactly one place (`_at`):
float control points coerced to ints implicitly could move an edge by a pixel
between two libms. It is the reason a stroke builds its own rectangles
(`segment_quad`) instead of handing Pillow a width — that path decides the same
corners in C off libm, and a diagonal landed a pixel apart on x86-64 and arm.
Every number this module gives a rasteriser is an integer at the working
resolution. Nothing here reads a clock, an environment variable or a random
number.

Ink is a hierarchy of three weights and nothing else, so a scar can never come
out as heavy as a jaw; `stroke` refuses any other width rather than drawing it.
"""

from __future__ import annotations

import math
from collections.abc import Iterable

from PIL import Image, ImageDraw

from . import raster
from .palette import RGB, RGBA

# The pinned raster (CommanderVisuals.PORTRAIT_SIZE) and the factor everything
# is drawn at above it.
PORTRAIT_SIZE = (220, 268)
SUPERSAMPLE = 3
DOWNSAMPLE = Image.Resampling.BOX

# The design system's three stroke weights, in portrait pixels.
INK_SILHOUETTE, INK_FEATURE, INK_DETAIL = 4.0, 3.0, 2.0
INK_WEIGHTS: tuple[float, ...] = (INK_SILHOUETTE, INK_FEATURE, INK_DETAIL)

# The hard offset shadow, in portrait pixels: one flat tone, zero blur, and one
# direction for the whole sheet — a mirrored pose flips the geometry, never the
# light.
CAST_OFFSET = (6, 6)
CAST_TONE: RGBA = (0, 0, 0, 77)
# Above this the silhouette is opaque enough to cast. A threshold rather than a
# copy of the alpha keeps the shadow a single tone at the working resolution.
CAST_CUTOFF = 128

Point = tuple[float, float]
Box = tuple[float, float, float, float]


Corner = tuple[int, int]


def segment_quad(start: Corner, end: Corner, radius: int) -> list[Corner] | None:
    """One segment of a stroke as a rectangle on the working grid.

    Its corners are decided here rather than by passing `width` to Pillow's
    line: that path builds the same rectangle in C off a libm `hypot`, whose
    last bit is not the same on x86-64 and arm, so a diagonal came out a pixel
    apart on Linux and macOS. `math.sqrt` of an exact integer is correctly
    rounded on every platform, and the offset lands on an integer before it
    reaches a rasteriser.

    `None` for a segment of no length — the disc drawn at the vertex is the
    whole mark there.
    """
    dx, dy = end[0] - start[0], end[1] - start[1]
    span = math.sqrt(dx * dx + dy * dy)
    if span == 0.0:
        return None
    offset_x, offset_y = _grid(-dy * radius / span), _grid(dx * radius / span)
    return [
        (start[0] + offset_x, start[1] + offset_y),
        (end[0] + offset_x, end[1] + offset_y),
        (end[0] - offset_x, end[1] - offset_y),
        (start[0] - offset_x, start[1] - offset_y),
    ]


def _grid(value: float) -> int:
    """Half away from zero, so the two sides of a stroke stay symmetric."""
    return math.floor(value + 0.5) if value >= 0.0 else math.ceil(value - 0.5)


class Canvas:
    """An RGBA layer at `scale` times the portrait raster.

    Every coordinate it takes is in portrait pixels; the canvas is the only
    place they become working-resolution integers.
    """

    def __init__(
        self, size: tuple[int, int] = PORTRAIT_SIZE, scale: int = SUPERSAMPLE
    ) -> None:
        self.size = size
        self.scale = scale
        self.image = Image.new("RGBA", (size[0] * scale, size[1] * scale), (0, 0, 0, 0))
        self._draw = ImageDraw.Draw(self.image)

    def _at(self, value: float) -> int:
        return round(value * self.scale)

    def _points(self, points: Iterable[Point]) -> list[tuple[int, int]]:
        return [(self._at(x), self._at(y)) for x, y in points]

    def _box(self, box: Box) -> tuple[int, int, int, int]:
        x0, y0, x1, y1 = box
        return (self._at(x0), self._at(y0), self._at(x1) - 1, self._at(y1) - 1)

    def fill(self, colour: RGB | RGBA) -> None:
        self._draw.rectangle((0, 0, *self.image.size), fill=colour)

    def rect(self, box: Box, colour: RGB | RGBA) -> None:
        self._draw.rectangle(self._box(box), fill=colour)

    def polygon(self, points: Iterable[Point], colour: RGB | RGBA) -> None:
        self._fill(self._points(points), colour)

    def _fill(self, corners: list[raster.Corner], colour: RGB | RGBA) -> None:
        """A polygon already at the working resolution, painted as the rows
        `raster` says it covers."""
        rows = list(raster.spans(corners, self.image.size))
        if not rows:
            return
        left = min(first for _, first, _ in rows)
        top = min(row for row, _, _ in rows)
        width = max(last for _, _, last in rows) - left + 1
        height = max(row for row, _, _ in rows) - top + 1
        mask = bytearray(width * height)
        for row, first, last in rows:
            at = (row - top) * width + first - left
            mask[at : at + last - first + 1] = b"\xff" * (last - first + 1)
        self.image.paste(
            colour, (left, top), Image.frombytes("L", (width, height), bytes(mask))
        )

    def ellipse(self, box: Box, colour: RGB | RGBA) -> None:
        self._draw.ellipse(self._box(box), fill=colour)

    def stroke(
        self,
        points: Iterable[Point],
        weight: float,
        colour: RGB | RGBA,
        *,
        closed: bool = False,
    ) -> None:
        """A path in one of the three ink weights, rounded at its joints."""
        if weight not in INK_WEIGHTS:
            raise ValueError(
                f"ink weight {weight} is none of {INK_WEIGHTS} — "
                "silhouette, feature and detail are the whole hierarchy"
            )
        path = self._points(points)
        if closed:
            path = [*path, path[0]]
        radius = self._at(weight) // 2
        for start, end in zip(path, path[1:]):
            quad = segment_quad(start, end, radius)
            if quad is not None:
                self._fill(quad, colour)
        # One disc per vertex: it rounds every joint between segments and caps
        # the two ends, which would otherwise be square.
        for x, y in path:
            self._draw.ellipse(
                (x - radius, y - radius, x + radius, y + radius), fill=colour
            )

    def compose(self, other: Canvas) -> None:
        """Stack another layer of the same scale over this one."""
        if other.image.size != self.image.size:
            raise ValueError(f"layer {other.image.size} over {self.image.size}")
        self.image.alpha_composite(other.image)

    def silhouette(self) -> Image.Image:
        """This layer's own outline as a one-bit mask."""
        return self.image.getchannel("A").point(
            lambda a: 255 if a >= CAST_CUTOFF else 0
        )

    def cast_shadow(
        self,
        figure: Canvas,
        *,
        offset: tuple[int, int] = CAST_OFFSET,
        tone: RGBA = CAST_TONE,
    ) -> None:
        """Draw `figure`'s silhouette into this layer, offset and flat."""
        layer = Image.new("RGBA", self.image.size, (0, 0, 0, 0))
        layer.paste(
            Image.new("RGBA", self.image.size, tone),
            (self._at(offset[0]), self._at(offset[1])),
            figure.silhouette(),
        )
        self.image.alpha_composite(layer)

    def resolve(self) -> Image.Image:
        """The finished raster: one box downsample to the pinned size."""
        return self.image.resize(self.size, DOWNSAMPLE)
