"""The contact sheet the snapshot gate writes when a sheet has changed."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from diff_sheet import GUTTER_PX, build_sheet, cell_grid, write_diff_sheet
from PIL import Image


def _sheet(colour: tuple[int, int, int, int], size=(128, 96)) -> Image.Image:
    return Image.new("RGBA", size, colour)


def _one_moved_pixel(base: Image.Image, at=(70, 10)) -> Image.Image:
    after = base.copy()
    after.putpixel(at, (255, 255, 255, 255))
    return after


class CellGrid(unittest.TestCase):
    def test_units_atlas_is_a_grid_of_tall_cells(self):
        self.assertEqual(cell_grid((1152, 480)), (64, 96))

    def test_terrain_atlas_is_a_grid_of_square_cells(self):
        self.assertEqual(cell_grid((896, 320)), (64, 64))

    def test_a_single_cell_is_not_a_grid(self):
        self.assertIsNone(cell_grid((64, 96)))

    def test_an_odd_size_is_not_a_grid(self):
        self.assertIsNone(cell_grid((100, 70)))


class Sheet(unittest.TestCase):
    def test_it_is_three_panels_of_the_cropped_region(self):
        before = _sheet((10, 20, 30, 255))
        sheet, pixels, cells = build_sheet(before, _one_moved_pixel(before), (64, 96))
        self.assertEqual(pixels, 1)
        self.assertEqual(cells, 1)
        self.assertEqual(sheet.height % 96, 0)
        scale = sheet.height // 96
        self.assertEqual(sheet.width, 3 * 64 * scale + 2 * GUTTER_PX)

    def test_the_diff_panel_marks_the_pixel_that_moved(self):
        before = _sheet((10, 20, 30, 255))
        sheet, _, _ = build_sheet(before, _one_moved_pixel(before), (64, 96))
        scale = sheet.height // 96
        panel_w = 64 * scale
        marked = sheet.getpixel((2 * (panel_w + GUTTER_PX) + 6 * scale, 10 * scale + 1))
        self.assertEqual(marked, (255, 0, 200, 255))

    def test_an_ungridded_sheet_crops_to_the_changed_pixels(self):
        before = _sheet((10, 20, 30, 255), size=(100, 70))
        sheet, pixels, cells = build_sheet(
            before, _one_moved_pixel(before, at=(50, 50)), None
        )
        self.assertEqual((pixels, cells), (1, 0))
        self.assertLess(sheet.height, 70 * 8)

    def test_identical_images_have_no_sheet_to_draw(self):
        before = _sheet((10, 20, 30, 255))
        with self.assertRaises(ValueError):
            build_sheet(before, before.copy(), (64, 96))


class WrittenSheet(unittest.TestCase):
    def test_it_writes_a_png_and_counts_what_moved(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            base = _sheet((10, 20, 30, 255))
            base.save(out / "baseline.png")
            _one_moved_pixel(base).save(out / "generated.png")
            report = write_diff_sheet(
                out / "generated.png",
                out / "baseline.png",
                Path("autotiles/units_atlas.png"),
                out / "sheets",
            )
            self.assertTrue(report.path.exists())
            self.assertEqual(report.path.name, "autotiles_units_atlas_diff.png")
            self.assertEqual((report.pixels, report.cells), (1, 1))
            self.assertIn(str(report.path), report.note(out / "baseline.png"))
            self.assertIn("1 pixels in 1 cells", report.note(out / "baseline.png"))


if __name__ == "__main__":
    unittest.main()
