"""The pipeline's headline promise: the same bytes on every run.

There are no seeds and no randomness here, so this is a real gate rather than a
formality — it is what catches a set iterated in insertion order, a colour mixed
from a clock, or geometry rounded by an implicit float coercion. The canvas is
held to the same bar on its own, because the busts land on it later and a drift
there would show up as 23 failures rather than one.
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from portraitgen import canvas, pipeline


def _run(out: Path) -> dict[str, bytes]:
    pipeline.generate(out, log=lambda _: None)
    return {
        p.relative_to(out).as_posix(): p.read_bytes()
        for p in sorted(out.rglob("*.png"))
    }


class TwoRunsAreOneRun(unittest.TestCase):
    def test_every_output_is_byte_identical(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            first, second = _run(Path(a)), _run(Path(b))
        self.assertEqual(sorted(first), sorted(second))
        self.assertEqual(len(first), len(pipeline.OUTPUTS))
        for name, data in first.items():
            with self.subTest(output=name):
                self.assertEqual(data, second[name])


class TheCanvasDrawsTheSamePictureTwice(unittest.TestCase):
    def _paint(self) -> canvas.Canvas:
        layer = canvas.Canvas((32, 40))
        layer.polygon([(4.0, 4.3), (28.7, 9.1), (16.2, 35.5)], (200, 60, 40, 255))
        layer.ellipse((6.5, 6.5, 20.5, 18.25), (40, 60, 200, 255))
        layer.stroke(
            [(3.0, 30.0), (12.5, 22.25), (29.0, 31.5)],
            canvas.INK_FEATURE,
            (19, 23, 27, 255),
        )
        return layer

    def test_two_paintings_resolve_to_the_same_raster(self):
        first, second = self._paint().resolve(), self._paint().resolve()
        self.assertEqual(first.size, (32, 40))
        self.assertEqual(first.tobytes(), second.tobytes())

    def test_the_cast_shadow_lands_outside_the_figure(self):
        figure = self._paint()
        sheet = canvas.Canvas((32, 40))
        sheet.cast_shadow(figure)
        under = sheet.resolve()
        sheet.compose(figure)
        self.assertNotEqual(under.tobytes(), sheet.resolve().tobytes())
        self.assertGreater(under.getchannel("A").getextrema()[1], 0)

    def test_an_ink_weight_outside_the_hierarchy_is_refused(self):
        with self.assertRaises(ValueError):
            self._paint().stroke([(0.0, 0.0), (5.0, 5.0)], 1.0, (0, 0, 0, 255))


if __name__ == "__main__":
    unittest.main()
