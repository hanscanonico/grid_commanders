"""The minimum feature gauge: the smallest mark this grid is allowed to hold.

Nothing on a bust is thinner than two texels, because one texel of a detail
tone laid diagonally is not a line — it is a dotted run of specks, which is how
a monocle chain, a headset cable and a row of stitching all arrived.

The rule has an authored half and a measured one. **Authored**: a run that has
to read as a line is drawn `Canvas.ribbon` — two texels, a lit core against an
inked edge — or it is cut. That is the whole of it; a bar cannot measure it,
because quantising a band edge leaves one-texel runs down every silhouette on
the sheet. **Measured**: `despeckle` sweeps what the rasteriser left behind — a
cluster too small to hold a `GAUGE`-square and no bigger than `MAX_ORPHAN`
takes whichever tone borders it most. It invents no colour and settles to a
fixed point, so two runs of it are the same bytes.

**Nothing is a border tone, and that is the silhouette half of the sweep.** A
speck sitting off the outline is bordered mostly by the transparent ground, so
the vote hands it transparency and it is trimmed rather than recoloured — a nub
one texel wide is under the gauge whichever tone it is painted in. The sweep
cannot punch a hole in a figure by doing it: an orphan inside the silhouette has
no transparent neighbour at all, so transparency has no vote there. Both halves
are pinned by `tests/test_gauge.py`.
"""

from __future__ import annotations

from collections.abc import Iterator

from PIL import Image

from .palette import RGBA

# The smallest mark this grid holds, in native texels, square.
GAUGE = 2
# A cluster of one tone at most this large, holding no GAUGE-square of its own,
# is rasteriser residue rather than a mark — a speck of paint on the ground, or
# a pinhole of ground inside the paint. Three would take the eyes' small
# catchlight with it, which is authored and reads.
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
    """The tone that borders a cluster most, transparency included.

    Ties go to the lower tone, so the sweep decides the same way on every
    machine. The transparent ground votes like any other tone on purpose: a
    speck hanging off the outline is bordered mostly by nothing, and trimming it
    is the silhouette half of the gauge. It cannot open a hole in a figure,
    because a cluster inside the silhouette borders no transparency to vote.
    """
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

    Repainted in the transparent ground's tone where that is what borders it,
    which trims a speck off the outline instead of recolouring it.

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
