"""The drawing surface every painted layer goes through.

A bust is **pixel art**: it is rasterised straight onto its native 110x134 grid,
one mark per whole pixel, with no supersample and no downsample anywhere. Every
module states its geometry in the same **design units** it always has — the
220x268 space the handoff's viewBox doubles — and this is the one place a design
unit becomes a native pixel, by `DIVISOR`.

Two grids come out of that one authoring space. The bust divides by
`BUST_DIVISOR`, the face chip a surface too small for a bust draws divides by
`CHIP_DIVISOR`: the same geometry rasterised coarser, never the bust resampled
down. A chip is therefore as hard-edged as the bust is, and both are drawn
nearest by the engine (`CommanderVisuals.ART_FILTER`).

Determinism is the reason geometry is rounded in exactly one place (`px`):
float control points coerced to ints implicitly could move an edge by a pixel
between two libms. It is the reason a stroke walks its own pixels (`_walk`)
instead of handing Pillow a width — that path decides its corners in C off a
libm `hypot`, and a diagonal landed a pixel apart on x86-64 and arm. Every
number this module gives a rasteriser is an integer on the native grid. Nothing
here reads a clock, an environment variable or a random number.

Ink is a hierarchy of three weights and nothing else, so a scar can never come
out as heavy as a jaw; `stroke` refuses any other width rather than drawing it.
At this grid the hierarchy is a ceiling rather than three distinct widths — a
silhouette is two native pixels and both lighter weights are one, which is as
many as a 110px-wide bust has room for.
"""

from __future__ import annotations

import math
from collections.abc import Iterable, Iterator

from PIL import Image, ImageDraw

from . import raster
from .palette import RGB, RGBA

# The authoring space every module's coordinates are stated in, and the two
# grids it is rasterised onto. The bust's is `CommanderVisuals.PORTRAIT_SIZE`.
DESIGN_SIZE = (220, 268)
BUST_DIVISOR = 2
CHIP_DIVISOR = 6

# The design system's three stroke weights, in design units.
INK_SILHOUETTE, INK_FEATURE, INK_DETAIL = 4.0, 3.0, 2.0
INK_WEIGHTS: tuple[float, ...] = (INK_SILHOUETTE, INK_FEATURE, INK_DETAIL)

# The hard offset shadow, in design units: one flat tone, zero blur, and one
# direction for the whole sheet — a mirrored pose flips the geometry, never the
# light.
CAST_OFFSET = (6, 6)
CAST_TONE: RGBA = (0, 0, 0, 77)
# Above this the silhouette is opaque enough to cast. A threshold rather than a
# copy of the alpha keeps the shadow a single tone.
CAST_CUTOFF = 128

Point = tuple[float, float]
Box = tuple[float, float, float, float]


# The rasteriser's own type: one place decides what a whole-pixel corner is.
Corner = raster.Corner


def native_size(size: tuple[int, int], divisor: int) -> tuple[int, int]:
    """The raster a design-space rectangle is drawn on, rounded up so nothing
    authored inside it falls off the last row."""
    return (-(-size[0] // divisor), -(-size[1] // divisor))


BUST_SIZE = native_size(DESIGN_SIZE, BUST_DIVISOR)

# The head's own rectangle, in design units, and the one statement of it on this
# side of the pipeline: `CommanderVisuals.FACE_REGION` is the same square on the
# bust's grid and `tests/test_face_region.py` reads it back out of the game's
# code. Its origin and its side are multiples of both divisors, so the chip a
# small surface draws is this square rasterised coarser rather than resampled.
FACE_REGION = (18, 30, 186, 186)


def face_box(divisor: int) -> tuple[int, int, int, int]:
    """`FACE_REGION` on one of the grids, as a crop box (left, top, right,
    bottom). An origin or a side that does not divide is a mistake in the
    rectangle, not a rounding to make quietly."""
    for value in FACE_REGION:
        if value % divisor:
            raise ValueError(f"face region {FACE_REGION} does not divide by {divisor}")
    left, top, width, height = (value // divisor for value in FACE_REGION)
    return (left, top, left + width, top + height)


CHIP_SIZE = FACE_REGION[2] // CHIP_DIVISOR


def pen(weight: float, divisor: int) -> int:
    """An ink weight as a whole number of pixels on one grid, never below one.

    Stated here rather than inside the canvas because a measurement of a
    stroke — the suites', and a caller sizing a gap beside one — has to be able
    to ask what the pen actually is at this size.
    """
    return max(1, int(weight // divisor))


def _walk(start: Corner, end: Corner) -> Iterator[Corner]:
    """The whole pixels a segment passes through, in whole numbers.

    Bresenham, so the line is the same line on every machine: `segment_quad`'s
    rectangle is a fair stroke at three times the size and a smear at one, and
    a float slope is the platform difference this package was bitten by.
    """
    x0, y0 = start
    x1, y1 = end
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    step_x = 1 if x0 < x1 else -1
    step_y = 1 if y0 < y1 else -1
    error = dx + dy
    while True:
        yield (x0, y0)
        if (x0, y0) == (x1, y1):
            return
        doubled = 2 * error
        if doubled >= dy:
            error += dy
            x0 += step_x
        if doubled <= dx:
            error += dx
            y0 += step_y


class Canvas:
    """An RGBA layer on one of the native grids.

    Every coordinate it takes is in design units; the canvas is the only place
    they become native-grid integers.
    """

    def __init__(
        self, size: tuple[int, int] = DESIGN_SIZE, divisor: int = BUST_DIVISOR
    ) -> None:
        self.size = size
        self.divisor = divisor
        self.image = Image.new("RGBA", native_size(size, divisor), (0, 0, 0, 0))
        self._draw = ImageDraw.Draw(self.image)

    @property
    def scale(self) -> float:
        """Design units to native pixels, for the light bands stated in design
        units at their call sites."""
        return 1.0 / self.divisor

    def blank(self) -> Canvas:
        """An empty layer on this canvas's own grid."""
        return Canvas(self.size, self.divisor)

    def px(self, value: float) -> int:
        """A design-unit coordinate as a whole pixel on this grid: half away
        from zero, so a shape and its mirror round the same way."""
        quotient = value / self.divisor
        return (
            math.floor(quotient + 0.5) if quotient >= 0.0 else math.ceil(quotient - 0.5)
        )

    def _points(self, points: Iterable[Point]) -> list[Corner]:
        return [(self.px(x), self.px(y)) for x, y in points]

    def _box(self, box: Box) -> tuple[int, int, int, int]:
        x0, y0, x1, y1 = box
        left, top = self.px(x0), self.px(y0)
        return (left, top, max(left, self.px(x1) - 1), max(top, self.px(y1) - 1))

    def _pen(self, weight: float) -> int:
        return pen(weight, self.divisor)

    def fill(self, colour: RGB | RGBA) -> None:
        self._draw.rectangle((0, 0, *self.image.size), fill=colour)

    def rect(self, box: Box, colour: RGB | RGBA) -> None:
        self._draw.rectangle(self._box(box), fill=colour)

    def polygon(self, points: Iterable[Point], colour: RGB | RGBA) -> None:
        self._fill(self._points(points), colour)

    def _fill(self, corners: list[Corner], colour: RGB | RGBA) -> None:
        """A polygon already on the native grid, painted as the rows `raster`
        says it covers."""
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
        """A disc, down to the one pixel a disc becomes at this size.

        Pillow draws nothing at all for a box with no width or height, which is
        how a catchlight, a freckle and a stud all went missing when the grid
        halved. A mark small enough to round to a single pixel is that pixel.
        """
        left, top, right, bottom = self._box(box)
        if right == left or bottom == top:
            self._draw.rectangle((left, top, right, bottom), fill=colour)
            return
        self._draw.ellipse((left, top, right, bottom), fill=colour)

    def stroke(
        self,
        points: Iterable[Point],
        weight: float,
        colour: RGB | RGBA,
        *,
        closed: bool = False,
    ) -> None:
        """A path in one of the three ink weights, stamped pixel by pixel."""
        if weight not in INK_WEIGHTS:
            raise ValueError(
                f"ink weight {weight} is none of {INK_WEIGHTS} — "
                "silhouette, feature and detail are the whole hierarchy"
            )
        path = self._points(points)
        if closed:
            path = [*path, path[0]]
        pen = self._pen(weight)
        offset = (pen - 1) // 2
        for start, end in zip(path, path[1:]):
            for x, y in _walk(start, end):
                self._draw.rectangle(
                    (
                        x - offset,
                        y - offset,
                        x - offset + pen - 1,
                        y - offset + pen - 1,
                    ),
                    fill=colour,
                )

    def compose(self, other: Canvas) -> None:
        """Stack another layer of the same grid over this one."""
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
            (self.px(offset[0]), self.px(offset[1])),
            figure.silhouette(),
        )
        self.image.alpha_composite(layer)

    def resolve(self) -> Image.Image:
        """The finished raster, as it stands. Nothing is resampled — what was
        drawn is what the file carries — and it is a copy, so a caller holding
        one does not watch it change under the next layer composed on.
        """
        return self.image.copy()
