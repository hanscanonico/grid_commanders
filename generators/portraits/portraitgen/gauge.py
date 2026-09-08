"""The minimum feature gauge: the smallest mark this grid is allowed to hold.

A bust is 110 pixels wide and the board it sits beside draws nothing thinner
than two texels. Every stroke in this package is authored in design units and
divided onto the grid by `canvas.px`, so a detail the handoff drew at 220 can
come out one texel across — and one texel of a detail tone, laid diagonally, is
not a line. It is a dotted run of specks: a monocle chain, a headset cable, a
row of stitching and a scatter of freckles all arrived that way.

`GAUGE` is the answer, and it has two halves.

**Authored**: a run that has to read as a line is drawn `Canvas.ribbon` rather
than `Canvas.stroke` — two texels, a lit core against an inked edge — or it is
cut. There is no third option, and nothing in this package draws a detail tone
one texel wide on purpose any more.

**Measured**: `despeckle` sweeps what the rasteriser left behind. Quantising a
finished raster onto sixteen tones rounds an edge pixel by pixel, and a band
that grazes a silhouette comes back as opaque flecks strung along it — the
halo the review read as anti-aliasing residue. A cluster of one tone small
enough to hold no `GAUGE`-square of its own, and no bigger than `MAX_ORPHAN`
pixels, is that residue; it is repainted in whatever tone borders it most.

Nothing here is a filter. There is no blur, no threshold on a distance and no
new colour: an orphan takes a tone already touching it, so a despeckled raster
is painted in the same sixteen the quantiser handed it, and two runs of it are
the same bytes.
"""

from __future__ import annotations

from collections.abc import Iterator

from PIL import Image

from .palette import RGBA

# The smallest mark this grid holds, in native texels, square.
GAUGE = 2
# An opaque cluster of one tone at most this large, holding no GAUGE-square of
# its own, is rasteriser residue rather than a mark. Three would take the
# eyes' small catchlight with it, which is authored and reads.
MAX_ORPHAN = 2

# How many times the sweep may run before the raster has to have settled.
PASSES = 8

# The eight steps a cluster grows by. Four-connectivity would cut a diagonal
# staircase — the ordinary shape of an inked edge here — into a string of
# single pixels and call every one of them noise.
_STEPS = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1))

Cell = tuple[int, int]


def clusters(pixels: list[RGBA], size: tuple[int, int]) -> Iterator[list[Cell]]:
    """Every maximal run of one tone, in raster order of its first pixel."""
    width, height = size
    seen = bytearray(width * height)
    for start in range(width * height):
        if seen[start]:
            continue
        tone = pixels[start]
        seen[start] = 1
        cells = [(start % width, start // width)]
        frontier = [cells[0]]
        while frontier:
            x, y = frontier.pop()
            for dx, dy in _STEPS:
                nx, ny = x + dx, y + dy
                if not (0 <= nx < width and 0 <= ny < height):
                    continue
                at = ny * width + nx
                if seen[at] or pixels[at] != tone:
                    continue
                seen[at] = 1
                cells.append((nx, ny))
                frontier.append((nx, ny))
        yield cells


def holds_gauge(cells: list[Cell]) -> bool:
    """Whether a cluster contains a whole `GAUGE` x `GAUGE` block of itself."""
    filled = set(cells)
    span = range(GAUGE)
    return any(
        all((x + dx, y + dy) in filled for dx in span for dy in span) for x, y in cells
    )


def is_orphan(cells: list[Cell]) -> bool:
    """Whether a cluster is under the gauge in both of its terms."""
    return len(cells) <= MAX_ORPHAN and not holds_gauge(cells)


def _border_tone(
    cells: list[Cell], pixels: list[RGBA], size: tuple[int, int]
) -> RGBA | None:
    """The tone that borders a cluster most. Ties go to the lower tone, so the
    sweep decides the same way on every machine."""
    width, height = size
    inside = set(cells)
    tally: dict[RGBA, int] = {}
    for x, y in cells:
        for dx, dy in _STEPS:
            nx, ny = x + dx, y + dy
            if not (0 <= nx < width and 0 <= ny < height) or (nx, ny) in inside:
                continue
            tone = pixels[ny * width + nx]
            tally[tone] = tally.get(tone, 0) + 1
    if not tally:
        return None
    return min(tally, key=lambda tone: (-tally[tone], tone))


def _swept(pixels: list[RGBA], size: tuple[int, int]) -> list[RGBA]:
    """One pass: every orphan repainted by the tone that borders it most.

    Read off one snapshot and written into another, so a cluster is judged
    against the raster the pass was handed rather than against the pass's own
    half-finished work — which is what keeps the result independent of the
    order the clusters come out in.
    """
    swept = list(pixels)
    width, _ = size
    for cells in clusters(pixels, size):
        if not is_orphan(cells):
            continue
        tone = _border_tone(cells, pixels, size)
        if tone is None:
            continue
        for x, y in cells:
            swept[y * width + x] = tone
    return swept


def despeckle(image: Image.Image) -> Image.Image:
    """The finished raster with every orphan cluster repainted by its border.

    Swept to a fixed point rather than once: repainting a speck can leave the
    pixel that was holding it beside its own neighbours orphaned in turn, and
    "no orphan survives the bake" is only worth measuring if it is true. The
    bound is there because a sweep that has not settled in `PASSES` is a bug in
    the rule, not a raster to keep grinding.
    """
    pixels: list[RGBA] = list(image.get_flattened_data())
    for _ in range(PASSES):
        swept = _swept(pixels, image.size)
        if swept == pixels:
            break
        pixels = swept
    else:
        raise ValueError(f"despeckle did not settle in {PASSES} passes")
    out = Image.new("RGBA", image.size)
    out.putdata(pixels)
    return out
