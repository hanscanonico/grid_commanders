"""The one promise a machine cannot check for itself: the same art everywhere.

`test_determinism.py` runs the pipeline twice on one machine. That was green
while CI, on x86-64, drew Cass Orlov and Perrin Ash a pixel apart from the art
baked on an arm Mac — because Pillow's own polygon fill and wide line work their
geometry out in C, and the compilers fold a multiply and an add together on arm
but not on x86-64. A crossing that lands exactly on a pixel boundary then falls
either side of it.

So the bar here is stated over the arithmetic instead: every shape is decided in
whole numbers before Pillow sees it, and the two rows that flipped are pinned.
"""

from __future__ import annotations

import unittest
from pathlib import Path

from portraitgen import canvas, raster

PACKAGE = Path(canvas.__file__).parent

# The working-resolution quad of Cass Orlov's right-shoulder crossbelt: the one
# shape in the sheet whose edges cross a scan line at exactly half a pixel.
CROSSBELT = [(464, 621), (158, 801), (154, 807), (460, 627)]
SHEET = (660, 804)


class PillowIsNeverAskedToWorkOutAShape(unittest.TestCase):
    def test_no_module_draws_a_polygon_or_a_wide_line(self):
        for module in sorted(PACKAGE.glob("*.py")):
            with self.subTest(module=module.name):
                source = module.read_text()
                self.assertNotIn("_draw.polygon", source)
                self.assertNotIn("_draw.line", source)


class ACrossingOnAPixelBoundaryIsDecidedInWholeNumbers(unittest.TestCase):
    def test_the_crossbelt_rows_that_flipped_are_pinned(self):
        rows = {
            row: (first, last) for row, first, last in raster.spans(CROSSBELT, SHEET)
        }
        # 183.5 and 166.5 exactly: the run starts at the next whole pixel.
        self.assertEqual(rows[786], (184, 190))
        self.assertEqual(rows[796], (167, 173))

    def test_a_crossing_is_never_a_float(self):
        for row, first, last in raster.spans(CROSSBELT, SHEET):
            with self.subTest(row=row):
                self.assertIsInstance(first, int)
                self.assertIsInstance(last, int)


class TheSpansCoverWhatThePolygonCovers(unittest.TestCase):
    def test_a_rectangle_fills_every_row_between_its_corners(self):
        rows = raster.spans([(4, 6), (10, 6), (10, 9), (4, 9)], (32, 32))
        self.assertEqual(set(rows), {(y, 4, 10) for y in range(6, 10)})

    def test_a_shape_is_clipped_to_the_raster(self):
        rows = raster.spans([(-8, -4), (20, -4), (20, 40), (-8, 40)], (16, 16))
        self.assertEqual(set(rows), {(y, 0, 15) for y in range(16)})

    def test_a_path_with_no_area_draws_nothing(self):
        self.assertEqual(list(raster.spans([(5, 5)], (32, 32))), [])


class AStrokeBuildsItsOwnRectangles(unittest.TestCase):
    def test_a_segment_quad_lands_on_whole_numbers(self):
        quad = canvas.segment_quad((198, 624), (504, 804), 4)
        self.assertEqual(quad, [(196, 627), (502, 807), (506, 801), (200, 621)])

    def test_a_segment_of_no_length_has_no_quad(self):
        self.assertIsNone(canvas.segment_quad((10, 10), (10, 10), 4))


if __name__ == "__main__":
    unittest.main()
