"""The shoal's two time frames: the foam edge shimmers and the shore does not.

The sea's own idiom (`test_sea_frames.py`) applied to the surf line instead of
the open water. `_draw_shore`'s `slide` offsets only the coordinate
`_foam_run` reads to decide SNOW/foam-mix — the depth `d` that draws the
sand/water boundary itself never sees it — so a shoal's waterline is fixed by
its mask alone and only the scallop cut into the surf band moves.

Same two gates as the sea and the river:

  no boil    outside the two foam tones the two frames are the same image
             for every one of the 16 masks.
  the texel  one board texel is 4 atlas px at the 4:1 rung
             (`autotile.SHOAL_FOAM_SLIDE`), and at a 16x16 area sample the
             pair disagrees on at least three texels.

No wrap/seam class either, for the reason `test_river_frames.py` gives: the
foam band is read off `d`, which the slide never touches, so there is no
region the slide could ever push a pixel into that `d` had not already
allowed.

Run with `.venv/bin/python -m unittest discover tests`.
"""

from __future__ import annotations

import unittest

from PIL import Image

from spritegen import anim, autotile
from spritegen.palette import mix
from spritegen.terrain import CELL, SNOW, WATER

# The two tones `_draw_shore` paints for foam, and nothing else in a shoal
# cell is allowed to differ between frames.
GLINT_TONES = {(*SNOW, 255), (*mix(WATER, SNOW, 0.55), 255)}
TEXELS = CELL // 4  # one board texel is 4 atlas px at the 4:1 rung


def _pixels(img: Image.Image) -> list[tuple[int, ...]]:
    raw = img.convert("RGBA").tobytes()
    return [tuple(raw[i : i + 4]) for i in range(0, len(raw), 4)]


def _sample(img: Image.Image, mode: int) -> list[tuple[int, ...]]:
    return _pixels(img.convert("RGBA").resize((TEXELS, TEXELS), mode))


class NoBoil(unittest.TestCase):
    def test_only_foam_pixels_move(self):
        """Mask out the foam tones and the two frames are one image, for
        every one of the 16 connection masks."""
        for mask in range(16):
            a = _pixels(autotile.shoal_tile(mask, frame=0))
            b = _pixels(autotile.shoal_tile(mask, frame=1))
            for i, (pa, pb) in enumerate(zip(a, b)):
                if pa in GLINT_TONES or pb in GLINT_TONES:
                    continue
                self.assertEqual(
                    pa, pb, f"mask {mask} repaints the shore at {i % CELL},{i // CELL}"
                )


class TexelRule(unittest.TestCase):
    def test_the_frames_disagree_on_at_least_three_board_texels(self):
        for mask in range(16):
            a = _sample(autotile.shoal_tile(mask, frame=0), Image.BOX)
            b = _sample(autotile.shoal_tile(mask, frame=1), Image.BOX)
            moved = sum(1 for pa, pb in zip(a, b) if pa != pb)
            self.assertGreaterEqual(
                moved, 3, f"mask {mask} moves only {moved} board texels"
            )

    def test_the_slide_is_one_whole_board_texel(self):
        self.assertEqual(autotile.SHOAL_FOAM_SLIDE, 4)
        self.assertEqual(autotile.SHOAL_FOAM_SLIDE, CELL // TEXELS)


class FrameAReaders(unittest.TestCase):
    def test_frame_a_is_the_sheet_the_board_already_has(self):
        """Adoption is additive: frame 0 is the old tile and the old sheet."""
        for mask in range(16):
            self.assertEqual(
                autotile.shoal_tile(mask, frame=0).tobytes(),
                autotile.shoal_tile(mask).tobytes(),
            )
        self.assertEqual(
            autotile.shoals_sheet(0).tobytes(),
            autotile.variant_sheet(autotile.shoal_tile).tobytes(),
        )


class Sheets(unittest.TestCase):
    def test_both_frames_carry_the_same_masks_in_the_same_order(self):
        for frame in range(autotile.SHOAL_FRAMES):
            s = autotile.shoals_sheet(frame)
            self.assertEqual(s.size, (4 * (CELL + 2) + 2, 4 * (CELL + 2) + 2))
            for mask in range(16):
                x = (mask % 4) * (CELL + 2) + 2
                y = (mask // 4) * (CELL + 2) + 2
                cell = s.crop((x, y, x + CELL, y + CELL))
                self.assertEqual(
                    cell.convert("RGB").tobytes(),
                    autotile.shoal_tile(mask, frame=frame).convert("RGB").tobytes(),
                    f"frame {frame} cell {mask} is not mask {mask}",
                )

    def test_the_frames_are_different_sheets(self):
        self.assertNotEqual(
            autotile.shoals_sheet(0).tobytes(), autotile.shoals_sheet(1).tobytes()
        )


class Manifest(unittest.TestCase):
    def test_the_clip_names_one_sheet_per_time_frame(self):
        clip = anim.MANIFEST["clips"]["shoals"]
        self.assertEqual(clip["sheets"], list(anim.SHOAL_SHEETS))
        self.assertEqual(len(anim.SHOAL_SHEETS), autotile.SHOAL_FRAMES)
        self.assertEqual(clip["order"], list(range(autotile.SHOAL_FRAMES)))
        self.assertEqual(clip["ms_per_frame"], anim.SHOAL_MS)
        self.assertEqual(clip["mode"], "loop")

    def test_the_cadence_shares_no_tick_with_the_other_four(self):
        for other in (anim.AMBIENT_MS, anim.MOVE_MS, anim.SEA_MS, anim.RIVER_MS):
            self.assertNotEqual(
                anim.SHOAL_MS % other, 0, f"{anim.SHOAL_MS} divides {other}"
            )
            self.assertNotEqual(
                other % anim.SHOAL_MS, 0, f"{other} divides {anim.SHOAL_MS}"
            )


if __name__ == "__main__":
    unittest.main()
