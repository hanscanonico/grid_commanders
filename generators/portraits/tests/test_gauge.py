"""The minimum feature gauge, as a bar over the sheet the generator emits.

The review this suite came out of read the same defect off eight busts under
three names — a dotted headset cable, a dotted monocle chain, a row of
stitching that had become ticks, and opaque fleck halos strung along five
silhouettes. All four are one thing: a mark thinner than a texel. `portraitgen.
gauge` is the rule, and this is where it stops being prose.

The bar that matters is the last one: **no bust holds an orphan cluster.** It is
measured off `bust.paint`, the call `pipeline.py` bakes the committed PNGs with,
so a stroke authored under the gauge in some future edit fails here rather than
shipping as noise.
"""

from __future__ import annotations

import unittest

from PIL import Image

from painted import painted
from portraitgen import bust, gauge
from portraitgen.canvas import BUST_DIVISOR, CHIP_DIVISOR, Canvas

INK = (19, 23, 27, 255)
CORE = (224, 169, 46, 255)


def _orphans(image: Image.Image) -> list[list[tuple[int, int]]]:
    pixels = list(image.get_flattened_data())
    return [
        cells
        for cells in gauge.clusters(pixels, image.size)
        if gauge.is_orphan(cells)
        and pixels[cells[0][1] * image.size[0] + cells[0][0]][3]
    ]


class TheSweepKnowsWhatAMarkIs(unittest.TestCase):
    def test_a_lone_pixel_is_an_orphan(self):
        self.assertTrue(gauge.is_orphan([(4, 4)]))

    def test_a_pair_is_an_orphan(self):
        self.assertTrue(gauge.is_orphan([(4, 4), (5, 4)]))

    def test_a_gauge_square_is_a_mark(self):
        block = [(4, 4), (5, 4), (4, 5), (5, 5)]
        self.assertTrue(gauge.holds_gauge(block))
        self.assertFalse(gauge.is_orphan(block))

    def test_a_three_cell_l_is_a_mark_and_holds_no_gauge_square(self):
        """Why `MAX_ORPHAN` may not be raised to three without the gauge term:
        a catchlight-sized L is over the bound, and nothing else says it is a
        mark."""
        ell = [(4, 4), (5, 4), (4, 5)]
        self.assertFalse(gauge.holds_gauge(ell))
        self.assertFalse(gauge.is_orphan(ell))

    def test_a_run_longer_than_the_orphan_bound_is_a_mark(self):
        run = [(x, 4) for x in range(6)]
        self.assertFalse(gauge.holds_gauge(run))
        self.assertFalse(gauge.is_orphan(run))

    def test_a_diagonal_staircase_is_one_cluster_and_not_noise(self):
        """Four-connectivity would call every step of an inked edge a speck."""
        layer = Canvas((40, 40), 1)
        layer.stroke([(4.0, 4.0), (30.0, 20.0)], 2.0, INK)
        self.assertEqual(_orphans(layer.resolve()), [])


class TheSweepRepaintsFromTheBorder(unittest.TestCase):
    def test_a_speck_takes_the_tone_around_it(self):
        layer = Canvas((40, 40), 1)
        layer.fill(CORE)
        layer.rect((10.0, 10.0, 11.0, 11.0), INK)
        swept = gauge.despeckle(layer.resolve())
        self.assertEqual(swept.getpixel((10, 10)), CORE)

    def test_the_sweep_has_settled_when_it_returns(self):
        for key, _ in bust.sheet_rows():
            with self.subTest(commander=key):
                once = painted(key)
                self.assertEqual(gauge.despeckle(once).tobytes(), once.tobytes())

    def test_the_sweep_invents_no_tone(self):
        for key, spec in bust.sheet_rows():
            with self.subTest(commander=key):
                allowed = {(*tone, 255) for tone in bust.palette_of(spec)}
                tones = {
                    colour
                    for _, colour in painted(key).getcolors(1 << 16)
                    if colour[3] == 255
                }
                self.assertEqual(tones - allowed, set())


class TheGroundVotesLikeAnyOtherTone(unittest.TestCase):
    """The silhouette half of the sweep: a speck off the outline is trimmed
    rather than recoloured, and no orphan inside a figure can be."""

    def test_a_nub_off_the_outline_is_trimmed(self):
        layer = Canvas((40, 40), 1)
        layer.rect((10.0, 10.0, 20.0, 20.0), CORE)
        # One inked pixel hanging off the right edge, so five of its eight
        # neighbours are the transparent ground and three are the block.
        layer.rect((20.0, 15.0, 21.0, 16.0), INK)
        swept = gauge.despeckle(layer.resolve())
        self.assertEqual(swept.getpixel((20, 15))[3], 0)
        self.assertEqual(swept.getpixel((19, 15)), CORE)

    def test_an_orphan_inside_the_paint_is_recoloured_and_not_erased(self):
        layer = Canvas((40, 40), 1)
        layer.rect((10.0, 10.0, 20.0, 20.0), CORE)
        layer.rect((15.0, 15.0, 16.0, 16.0), INK)
        swept = gauge.despeckle(layer.resolve())
        self.assertEqual(swept.getpixel((15, 15)), CORE)

    def test_the_sweep_opens_no_hole_in_a_shipped_bust(self):
        """A transparent pixel with eight opaque neighbours would be a puncture,
        which is the failure a transparency vote could make and does not."""
        for key, _ in bust.sheet_rows():
            with self.subTest(commander=key):
                image = painted(key)
                width, height = image.size
                pixels = list(image.get_flattened_data())
                holes = [
                    (x, y)
                    for y in range(1, height - 1)
                    for x in range(1, width - 1)
                    if pixels[y * width + x][3] == 0
                    and all(
                        pixels[(y + dy) * width + x + dx][3] == 255
                        for dx in (-1, 0, 1)
                        for dy in (-1, 0, 1)
                        if (dx, dy) != (0, 0)
                    )
                ]
                self.assertEqual(holes, [])


class NothingUnderTheGaugeSurvivesTheBake(unittest.TestCase):
    """The bar. An opaque cluster of one tone no bigger than `MAX_ORPHAN` is
    not a mark this grid can draw."""

    def test_no_bust_holds_an_orphan_cluster(self):
        for key, _ in bust.sheet_rows():
            with self.subTest(commander=key):
                self.assertEqual(_orphans(painted(key)), [])


class ARibbonIsTwoTexelsOnEitherGrid(unittest.TestCase):
    """The authored half of the gauge: what `stroke` cannot draw wide enough,
    `ribbon` draws as a core against an edge."""

    def _widths(self, divisor: int) -> set[int]:
        layer = Canvas((80, 80), divisor)
        layer.ribbon([(20.0, 10.0), (20.0, 70.0)], CORE, INK)
        image = layer.resolve()
        rows = range(layer.px(20.0), layer.px(60.0))
        return {
            sum(1 for x in range(image.width) if image.getpixel((x, y))[3])
            for y in rows
        }

    def test_a_ribbon_covers_the_gauge_on_the_bust_grid(self):
        self.assertEqual(self._widths(BUST_DIVISOR), {gauge.GAUGE})

    def test_a_ribbon_covers_the_gauge_on_the_chip_grid(self):
        self.assertEqual(self._widths(CHIP_DIVISOR), {gauge.GAUGE})

    def test_a_stroke_at_the_detail_weight_does_not(self):
        """Which is the whole reason the ribbon exists."""
        layer = Canvas((80, 80), BUST_DIVISOR)
        layer.stroke([(20.0, 10.0), (20.0, 70.0)], 2.0, CORE)
        image = layer.resolve()
        row = layer.px(40.0)
        self.assertEqual(
            sum(1 for x in range(image.width) if image.getpixel((x, row))[3]), 1
        )


if __name__ == "__main__":
    unittest.main()
