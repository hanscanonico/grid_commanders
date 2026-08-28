"""The window field: every kind draws, none is a wash, none leaks past the frame.

The opacity band is the one the reviews measured — brighter than 0.26 and the
backdrop starts competing with the face — so it is checked as a property of the
pixels rather than trusted to the constants. The colour count is read off the
**working** canvas, before the downsample: the box filter is where this pipeline
gets its antialiasing, so blends at an edge are the AA and the authored tones
are what the palette budget is about.
"""

from __future__ import annotations

import unittest

from portraitgen import backdrop
from portraitgen.canvas import Canvas
from portraitgen.palette import faction_by_key

FACTION = faction_by_key("meridian")


def _painted(kind: str) -> Canvas:
    canvas = Canvas()
    backdrop.draw(canvas, kind, FACTION)
    return canvas


class EveryKindDraws(unittest.TestCase):
    def test_the_vocabulary_and_the_dispatch_table_are_one_set(self):
        for kind in sorted(backdrop.KINDS):
            with self.subTest(kind=kind):
                self.assertIsNotNone(_painted(kind).image.getbbox())

    def test_an_unknown_kind_raises_rather_than_falling_through(self):
        with self.assertRaises(KeyError):
            backdrop.draw(Canvas(), "sunburst", FACTION)

    def test_the_field_is_one_flat_tone(self):
        canvas = Canvas()
        backdrop.field(canvas, FACTION)
        colours = {colour for _, colour in canvas.image.getcolors(maxcolors=1 << 16)}
        self.assertEqual(colours, {(0, 0, 0, 0), (*FACTION.body_dk, 255)})


class EveryTreatmentIsABand(unittest.TestCase):
    def _treatment(self, kind: str) -> Canvas:
        canvas = Canvas()
        backdrop.treatment(canvas, kind, FACTION)
        return canvas

    def test_no_pixel_leaves_the_opacity_band(self):
        low, high = backdrop.OPACITY_BAND
        floor, ceiling = round(low * 255), round(high * 255)
        for kind in sorted(backdrop.KINDS):
            with self.subTest(kind=kind):
                alphas = {
                    colour[3]
                    for _, colour in self._treatment(kind).image.getcolors(
                        maxcolors=1 << 16
                    )
                }
                self.assertTrue(alphas - {0}, "the treatment drew nothing")
                for alpha in sorted(alphas - {0}):
                    self.assertGreaterEqual(alpha, floor)
                    self.assertLessEqual(alpha, ceiling)

    def test_nothing_is_painted_outside_the_window(self):
        x0, y0, x1, y1 = backdrop.WINDOW
        for kind in sorted(backdrop.KINDS):
            with self.subTest(kind=kind):
                canvas = self._treatment(kind)
                left, top, right, bottom = canvas.image.getbbox()
                scale = canvas.scale
                self.assertGreaterEqual(left / scale, x0)
                self.assertGreaterEqual(top / scale, y0)
                self.assertLessEqual(right / scale, x1)
                self.assertLessEqual(bottom / scale, y1)


class ThePaletteIsBounded(unittest.TestCase):
    def test_a_backdrop_is_painted_in_a_handful_of_named_tones(self):
        for kind in sorted(backdrop.KINDS):
            with self.subTest(kind=kind):
                colours = _painted(kind).image.getcolors(maxcolors=1 << 16)
                self.assertLessEqual(len(colours), 8)


if __name__ == "__main__":
    unittest.main()
