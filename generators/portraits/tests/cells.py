"""How the suites read a raster back, and the material they paint one on.

Three suites measure a layer by painting it onto a bare `Canvas()` in design
space and counting what landed — the face's features, what is worn over them,
and hair. The three counts are the same in all three, so they live here rather
than three times over. `tally` is the one place a suite turns an image into
counted colours, and the one place the `getcolors` cap being hit is an error
rather than a `None` that reads as "no colours".

A count on the working canvas is a count of what the layer asked for: a flat
tone is still exactly itself there, because no ramp has been resampled onto the
bust's grid yet.

`luminance` here is on the 0–255 scale, the one the painted rasters are read
on. Godot's own 0–1 luminance is a different number and lives with the suite
that compares against the engine (`test_geometry._godot_luminance`).
"""

from __future__ import annotations

from PIL import Image

from portraitgen.canvas import Canvas

# No raster a suite measures can carry more distinct colours than this, so a
# tally that hits the cap is a bug in the caller rather than a wider sheet.
_ALL_COLOURS = 1 << 24

# The stand-in skin the layer suites and the preview sheet build their ramp
# off. One material in one place, so a tone read off a features raster is the
# same tone a hair raster was read against.
SKIN_MATERIAL: tuple[int, int, int] = (217, 160, 102)


def tally(image: Image.Image) -> list[tuple[int, tuple[int, ...]]]:
    """Every colour in the image and how much of it there is."""
    counted = image.getcolors(_ALL_COLOURS)
    if counted is None:
        raise AssertionError("more colours than a sheet can carry")
    return counted


def luminance(pixel: tuple[int, ...]) -> float:
    """Rec. 709 luminance of a pixel, on the 0-255 scale it was read at."""
    return 0.2126 * pixel[0] + 0.7152 * pixel[1] + 0.0722 * pixel[2]


def opaque_count(canvas: Canvas) -> int:
    """How many pixels the layer painted at all."""
    return sum(count for count, pixel in tally(canvas.image) if pixel[3] > 0)


def area_of(canvas: Canvas, tone: tuple[int, int, int]) -> int:
    """How many pixels one flat tone covers."""
    return sum(count for count, pixel in tally(canvas.image) if pixel[:3] == tone)


def colours(canvas: Canvas) -> set[tuple[int, int, int]]:
    """The set of tones on the canvas, alpha ignored."""
    return {pixel[:3] for _, pixel in tally(canvas.image) if pixel[3] > 0}
