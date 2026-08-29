"""Contract tests for the UI chrome: the overlay, the cursor, the icon.

The three are flat rectangles, so what is checked is what a rectangle can get
wrong — size, coverage, which colours are in the image — plus the one thing
that has no other keeper: how far the icon's two team tokens have drifted
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
    def test_it_is_five_flat_colours_on_a_transparent_ground(self):
        counts = _counts(chrome.icon())
        self.assertEqual(
            set(counts),
            {
                (0, 0, 0, 0),
                chrome.ICON_PLATE,
                chrome.ICON_GRID,
                chrome.ICON_MERIDIAN,
                chrome.ICON_AURORA,
                chrome.ICON_MARK,
            },
        )
        self.assertEqual(sum(counts.values()), chrome.ICON**2)

    def test_the_board_fits_the_plate_exactly(self):
        span = 4 * chrome.ICON_LINE + 3 * chrome.ICON_CELL
        self.assertEqual(span + 2 * chrome.ICON_INSET, chrome.ICON)

    def test_the_corners_are_cut_away(self):
        px = chrome.icon().load()
        far = chrome.ICON - 1
        for x, y in ((0, 0), (far, 0), (0, far), (far, far)):
            self.assertEqual(px[x, y][3], 0, (x, y))
        self.assertEqual(px[chrome.ICON_CORNER, 0], chrome.ICON_PLATE)

    def test_the_rules_frame_nine_cells(self):
        px = chrome.icon().load()
        mid = chrome.ICON // 2
        self.assertEqual(px[chrome.ICON_INSET, mid], chrome.ICON_GRID)
        self.assertEqual(px[mid, chrome.ICON_INSET], chrome.ICON_GRID)
        empty = chrome._cell_origin(1, 0)
        self.assertEqual(px[empty[0] + 2, empty[1] + 2], chrome.ICON_PLATE)

    def test_two_armies_sit_in_opposite_corner_cells(self):
        px = chrome.icon().load()
        counts = _counts(chrome.icon())
        token = chrome.ICON_TOKEN**2
        for (col, row), color in (
            ((0, 2), chrome.ICON_MERIDIAN),
            ((2, 0), chrome.ICON_AURORA),
        ):
            x, y = chrome._cell_origin(col, row)
            half = chrome.ICON_CELL // 2
            self.assertEqual(px[x + half, y + half], color)
            self.assertEqual(counts[color], token)

    def test_the_mark_holds_the_centre_cell(self):
        px = chrome.icon().load()
        counts = _counts(chrome.icon())
        mid = chrome.ICON // 2
        self.assertEqual(px[mid, mid], chrome.ICON_MARK)
        self.assertLessEqual(chrome.ICON_MARK_ARM, chrome.ICON_CELL)
        arms = 2 * chrome.ICON_MARK_ARM * chrome.ICON_MARK_THICK
        self.assertEqual(counts[chrome.ICON_MARK], arms - chrome.ICON_MARK_THICK**2)

    def test_nothing_is_thinner_than_a_rule(self):
        """Every feature is a multiple of the 4px rule, so the platforms' 64,
        32 and 16 all land on whole pixels."""
        for size in (
            chrome.ICON_CORNER,
            chrome.ICON_LINE,
            chrome.ICON_CELL,
            chrome.ICON_INSET,
            chrome.ICON_TOKEN,
            chrome.ICON_MARK_ARM,
            chrome.ICON_MARK_THICK,
        ):
            self.assertEqual(size % chrome.ICON_LINE, 0, size)


class ChromeDrift(unittest.TestCase):
    """The icon's team tokens against the faction rows they stand for.

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

    def test_each_token_is_its_row_to_the_eye(self):
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

    def test_the_tokens_are_opaque(self):
        for legacy, _ in self._pairs():
            self.assertEqual(legacy[3], 255)


if __name__ == "__main__":
    unittest.main()
