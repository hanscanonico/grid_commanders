"""A working canvas, and the four ways the suites read one back.

Three suites measure a layer by painting it onto a bare design-space canvas and
counting what landed — the face's features, what is worn over them, and hair.
The canvas and the three counts are the same in all three, so they live here
rather than three times over.

Every count is taken on the working canvas, where a flat tone is still exactly
itself: no ramp has been resampled onto the bust's grid yet, so a tone this
module reports is a tone the layer asked for.
"""

from __future__ import annotations

from portraitgen.canvas import DESIGN_SIZE, Canvas


def blank_cell() -> Canvas:
    """A bare canvas in design space, on the bust's own divisor."""
    return Canvas(DESIGN_SIZE)


def _tally(canvas: Canvas) -> list[tuple[int, tuple[int, int, int, int]]]:
    """Every colour on the canvas and how much of it there is."""
    return canvas.image.getcolors(1 << 24)


def opaque_count(canvas: Canvas) -> int:
    """How many pixels the layer painted at all."""
    return sum(count for count, pixel in _tally(canvas) if pixel[3] > 0)


def area_of(canvas: Canvas, tone: tuple[int, int, int]) -> int:
    """How many pixels one flat tone covers."""
    return sum(count for count, pixel in _tally(canvas) if pixel[:3] == tone)


def colours(canvas: Canvas) -> set[tuple[int, int, int]]:
    """The set of tones on the canvas, alpha ignored."""
    return {pixel[:3] for _, pixel in _tally(canvas) if pixel[3] > 0}
