"""Contract tests for the UI chrome: the overlay, the cursor, the icon.

The three are flat rectangles, so what is checked is what a rectangle can get
wrong — size, coverage, which colours are in the image — plus the one thing
that has no other keeper: how far the icon's two team squares have drifted
from the faction rows they stand for.
"""

from __future__ import annotations

import colorsys
import unittest

from spritegen import chrome
from spritegen.palette import faction_by_key


def _counts(img):
    return dict((c[1], c[0]) for c in img.getcolors(1 << 16))


class Overlay(unittest.TestCase):
    def test_is_a_tile_of_two_whites(self):
        counts = _counts(chrome.overlay())
        self.assertEqual(set(counts), {chrome.OVERLAY_FILL, chrome.OVERLAY_EDGE})
        self.assertEqual(sum(counts.values()), chrome.TILE**2)

    def test_the_edge_is_a_one_pixel_ring(self):
        counts = _counts(chrome.overlay())
        ring = chrome.TILE**2 - (chrome.TILE - 2) ** 2
        self.assertEqual(counts[chrome.OVERLAY_EDGE], ring)

    def test_the_border_is_the_denser_half(self):
        """The scene modulates one texture, so the cell's edge has to come out
        of the alpha rather than out of a second sprite."""
        self.assertGreater(chrome.OVERLAY_EDGE[3], chrome.OVERLAY_FILL[3])


class Cursor(unittest.TestCase):
    def test_four_corners_and_nothing_between_them(self):
        px = chrome.cursor().load()
        mid = chrome.TILE // 2
        self.assertEqual(px[0, 0], chrome.CURSOR_INK)
        self.assertEqual(px[chrome.TILE - 1, chrome.TILE - 1], chrome.CURSOR_INK)
        self.assertEqual(px[mid, mid][3], 0)

    def test_every_bracket_is_two_arms(self):
        self.assertEqual(len(chrome._brackets()), 8)
        for x, y, w, h in chrome._brackets():
            self.assertEqual(
                sorted((w, h)), [chrome.BRACKET_SHORT, chrome.BRACKET_LONG]
            )
            self.assertTrue(0 <= x and x + w <= chrome.TILE)
            self.assertTrue(0 <= y and y + h <= chrome.TILE)

    def test_the_shadow_is_under_the_ink(self):
        """The drop shadow is offset into the tile, so no white arm is eaten by
        the shadow drawn after it."""
        counts = _counts(chrome.cursor())
        self.assertEqual(
            set(counts) - {(0, 0, 0, 0)}, {chrome.CURSOR_INK, chrome.CURSOR_SHADOW}
        )
        arms = 8 * chrome.BRACKET_LONG * chrome.BRACKET_SHORT
        self.assertEqual(counts[chrome.CURSOR_INK], arms - 4 * chrome.BRACKET_SHORT**2)


class Icon(unittest.TestCase):
    def test_two_armies_face_across_a_crossroads(self):
        counts = _counts(chrome.icon())
        square = chrome.ICON_SQUARE**2
        self.assertEqual(counts[chrome.ICON_MERIDIAN], square)
        self.assertEqual(counts[chrome.ICON_AURORA], square)
        self.assertEqual(sum(counts.values()), chrome.ICON**2)

    def test_the_roads_cross_at_the_centre(self):
        px = chrome.icon().load()
        mid = chrome.ICON // 2
        self.assertEqual(px[mid, mid], chrome.ICON_ROAD)
        self.assertEqual(px[mid, 2], chrome.ICON_ROAD)
        self.assertEqual(px[2, mid], chrome.ICON_ROAD)
        self.assertEqual(px[2, 2], chrome.ICON_GRASS)


class ChromeDrift(unittest.TestCase):
    """The icon's team squares against the faction rows they stand for.

    They are not the same colour: the icon keeps the hues the engine script
    drew it with, one step off `CommanderVisuals` (meridian db4a3b, aurora
    3865d8). Recolouring is an art change and not this module's to make, so the
    drift is pinned instead — the same colour to the eye, and no further apart
    than it is today without a test being edited.
    """

    DRIFT = 4  # per channel, out of 255
    HUE_DRIFT = 2.0  # degrees

    def _pairs(self):
        return (
            (chrome.ICON_MERIDIAN, faction_by_key("meridian")),
            (chrome.ICON_AURORA, faction_by_key("aurora")),
        )

    def test_each_square_is_its_row_to_the_eye(self):
        for legacy, fac in self._pairs():
            for channel, (a, b) in enumerate(zip(legacy[:3], fac.body)):
                self.assertLessEqual(abs(a - b), self.DRIFT, f"{fac.key} ch{channel}")

    def test_the_hues_agree(self):
        for legacy, fac in self._pairs():
            hues = [
                colorsys.rgb_to_hsv(*(c / 255.0 for c in rgb))[0] * 360.0
                for rgb in (legacy[:3], fac.body)
            ]
            self.assertLessEqual(abs(hues[0] - hues[1]), self.HUE_DRIFT, fac.key)

    def test_the_squares_are_opaque(self):
        for legacy, _ in self._pairs():
            self.assertEqual(legacy[3], 255)


if __name__ == "__main__":
    unittest.main()
