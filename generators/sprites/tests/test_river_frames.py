"""The river's two time frames: the channel moves and does not boil.

The sea's own idiom (`test_sea_frames.py`) applied to a connection-keyed
family. A river's mask (`autotile.river_tile`'s `mask`) fixes the channel and
its banks — `_shape_river` and the two `_edge_pass` calls never read `frame`
— so the two gates are the same ones the sea is held to:

  no boil    outside the two glint tones the two frames are the same image
             for every one of the 16 masks, not "few pixels changed".
  the texel  one board texel is 4 atlas px at the 4:1 rung
             (`autotile.RIVER_GLINT_SLIDE`), and at a 16x16 area sample the
             pair disagrees on at least three texels, the sea's own floor.

There is no wrap/seam class the sea's suite carries: the sea slides an
isotropic dash inside one cell and has to keep it off the ring it repeats
against, where a river's arms run to the tile's own edge on purpose — a
glint reaching x=0 or x=63 is the channel continuing into the neighbour it is
connected to, not a seam. Nothing here needs `_slide_x`'s wrap because a
straight `+ RIVER_GLINT_SLIDE` never leaves the water: every arm has enough
clearance in its own band that a texel of drift lands inside the channel or
its own joint square (see the constant's own comment in `autotile.py`).

Run with `.venv/bin/python -m unittest discover tests`.
"""

from __future__ import annotations

import unittest

from PIL import Image

from spritegen import anim, autotile
from spritegen.terrain import CELL

# The two tones the flow streaks paint, and nothing else in a river cell is
# allowed to differ between frames.
GLINT_TONES = {(*autotile.WATER_LIGHT, 255), (*autotile.WATER_LIT, 255)}
TEXELS = CELL // 4  # one board texel is 4 atlas px at the 4:1 rung


def _pixels(img: Image.Image) -> list[tuple[int, ...]]:
    raw = img.convert("RGBA").tobytes()
    return [tuple(raw[i : i + 4]) for i in range(0, len(raw), 4)]


def _sample(img: Image.Image, mode: int) -> list[tuple[int, ...]]:
    return _pixels(img.convert("RGBA").resize((TEXELS, TEXELS), mode))


class NoBoil(unittest.TestCase):
    def test_only_glint_pixels_move(self):
        """Mask out the glint tones and the two frames are one image, for
        every one of the 16 connection masks."""
        for mask in range(16):
            a = _pixels(autotile.river_tile(mask, frame=0))
            b = _pixels(autotile.river_tile(mask, frame=1))
            for i, (pa, pb) in enumerate(zip(a, b)):
                if pa in GLINT_TONES or pb in GLINT_TONES:
                    continue
                self.assertEqual(
                    pa, pb, f"mask {mask} repaints the channel at {i % CELL},{i // CELL}"
                )

    def test_the_flow_neither_grows_nor_shrinks(self):
        """A slide moves the streaks; it does not paint more of them."""
        for mask in range(16):
            counts = [
                sum(1 for px in _pixels(autotile.river_tile(mask, frame=f)) if px in GLINT_TONES)
                for f in range(autotile.RIVER_FRAMES)
            ]
            self.assertEqual(counts[0], counts[1], f"mask {mask} flow count moved")


class TexelRule(unittest.TestCase):
    def test_the_frames_disagree_on_at_least_three_board_texels(self):
        for mask in range(16):
            a = _sample(autotile.river_tile(mask, frame=0), Image.BOX)
            b = _sample(autotile.river_tile(mask, frame=1), Image.BOX)
            moved = sum(1 for pa, pb in zip(a, b) if pa != pb)
            self.assertGreaterEqual(moved, 3, f"mask {mask} moves only {moved} board texels")

    def test_the_slide_is_one_whole_board_texel(self):
        self.assertEqual(autotile.RIVER_GLINT_SLIDE, 4)
        self.assertEqual(autotile.RIVER_GLINT_SLIDE, CELL // TEXELS)


class FrameAReaders(unittest.TestCase):
    def test_frame_a_is_the_sheet_the_board_already_has(self):
        """Adoption is additive: frame 0 is the old tile and the old sheet."""
        for mask in range(16):
            self.assertEqual(
                autotile.river_tile(mask, frame=0).tobytes(),
                autotile.river_tile(mask).tobytes(),
            )
        self.assertEqual(
            autotile.rivers_sheet(0).tobytes(),
            autotile.variant_sheet(autotile.river_tile).tobytes(),
        )


class Sheets(unittest.TestCase):
    def test_both_frames_carry_the_same_masks_in_the_same_order(self):
        for frame in range(autotile.RIVER_FRAMES):
            s = autotile.rivers_sheet(frame)
            self.assertEqual(s.size, (4 * (CELL + 2) + 2, 4 * (CELL + 2) + 2))
            for mask in range(16):
                x = (mask % 4) * (CELL + 2) + 2
                y = (mask // 4) * (CELL + 2) + 2
                cell = s.crop((x, y, x + CELL, y + CELL))
                self.assertEqual(
                    cell.convert("RGB").tobytes(),
                    autotile.river_tile(mask, frame=frame).convert("RGB").tobytes(),
                    f"frame {frame} cell {mask} is not mask {mask}",
                )

    def test_the_frames_are_different_sheets(self):
        self.assertNotEqual(
            autotile.rivers_sheet(0).tobytes(), autotile.rivers_sheet(1).tobytes()
        )


class Manifest(unittest.TestCase):
    def test_the_clip_names_one_sheet_per_time_frame(self):
        clip = anim.MANIFEST["clips"]["rivers"]
        self.assertEqual(clip["sheets"], list(anim.RIVER_SHEETS))
        self.assertEqual(len(anim.RIVER_SHEETS), autotile.RIVER_FRAMES)
        self.assertEqual(clip["order"], list(range(autotile.RIVER_FRAMES)))
        self.assertEqual(clip["ms_per_frame"], anim.RIVER_MS)
        self.assertEqual(clip["mode"], "loop")

    def test_the_cadence_shares_no_tick_with_the_other_four(self):
        for other in (anim.AMBIENT_MS, anim.MOVE_MS, anim.SEA_MS, anim.SHOAL_MS):
            self.assertNotEqual(anim.RIVER_MS % other, 0, f"{anim.RIVER_MS} divides {other}")
            self.assertNotEqual(other % anim.RIVER_MS, 0, f"{other} divides {anim.RIVER_MS}")


if __name__ == "__main__":
    unittest.main()
