"""Which pixels a filled polygon covers, decided in integers.

Pillow's own polygon fill walks its scan lines in `float`: an edge's slope,
then one multiply-and-add per row. Arm compilers fold that pair into a single
fused instruction and x86-64 ones do not, so a crossing that falls exactly on a
pixel boundary rounds one way on a Mac and the other way on CI — which is how
two of the twenty-three busts came out a pixel apart on Linux while every local
regeneration was clean. A crossing is a ratio of small whole numbers, so it is
kept as one here and never becomes a float at all.

The pixel model is Pillow's, so the art already drawn does not move: a pixel is
the unit square centred on its integer coordinate, a scan line is a row of those
centres, and a run covers the centres between two crossings rounded inward. A
crossing outside the raster is clipped, which is also why the rounding needs no
rule for a negative one.
"""

from __future__ import annotations

from collections.abc import Iterator, Sequence

Corner = tuple[int, int]
# One filled row: its y, and the first and last x it covers, both inclusive.
Span = tuple[int, int, int]

# A crossing as numerator over a positive denominator.
Crossing = tuple[int, int]


def spans(corners: Sequence[Corner], size: tuple[int, int]) -> Iterator[Span]:
    """The rows a polygon fills, in scan order, clipped to a raster of `size`.

    A row may come back more than once: a horizontal edge is a run of its own,
    the way Pillow draws one, and the crossings cover it again.
    """
    if len(corners) < 2:
        return
    closed = [*corners, corners[0]]
    edges = list(zip(closed, closed[1:]))
    rows = [y for _, y in corners]
    # Pillow stops at the raster's height rather than at its last row, and that
    # bound is also what decides whether a row is the polygon's last.
    last_row = min(max(rows), size[1])
    for row in range(max(0, min(rows)), last_row + 1):
        for (x0, y0), (x1, y1) in edges:
            if y0 == y1 == row:
                yield from _clipped(row, min(x0, x1), max(x0, x1), size)
        crossings = sorted(_crossings(edges, row, last_row), key=_value)
        for start, end in zip(crossings[::2], crossings[1::2]):
            yield from _clipped(row, _round_up(start), _round_down(end), size)


def _crossings(
    edges: Sequence[tuple[Corner, Corner]], row: int, last_row: int
) -> Iterator[Crossing]:
    """Where a row meets each edge, an edge's far end counted twice.

    Counting both ends of an edge, and its lower end again on every row but the
    polygon's last, is what keeps the crossings even in number and paired the
    way the outline runs — Pillow's rule, and the reason a shared corner fills
    as one shape rather than as two that miss each other.
    """
    for (x0, y0), (x1, y1) in edges:
        if y0 == y1:
            continue
        top, bottom = (y0, y1) if y0 < y1 else (y1, y0)
        if not top <= row <= bottom:
            continue
        denominator = y1 - y0
        numerator = x0 * denominator + (row - y0) * (x1 - x0)
        crossing = (
            (numerator, denominator) if denominator > 0 else (-numerator, -denominator)
        )
        yield crossing
        if row == bottom < last_row:
            yield crossing


def _value(crossing: Crossing) -> float:
    """A crossing's place in the sort. One division of two exact whole numbers
    is correctly rounded everywhere, and two crossings of one polygon are
    further apart than a double can confuse."""
    return crossing[0] / crossing[1]


def _round_up(crossing: Crossing) -> int:
    """The first pixel centre at or after a crossing."""
    numerator, denominator = crossing
    return (2 * numerator + denominator) // (2 * denominator)


def _round_down(crossing: Crossing) -> int:
    """The last pixel centre at or before a crossing."""
    numerator, denominator = crossing
    return -((denominator - 2 * numerator) // (2 * denominator))


def _clipped(row: int, first: int, last: int, size: tuple[int, int]) -> Iterator[Span]:
    width, height = size
    first, last = max(0, first), min(width - 1, last)
    if 0 <= row < height and first <= last:
        yield (row, first, last)
