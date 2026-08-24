"""The sea's two time frames: the water moves and does not boil.

A phase of the sea (`terrain.SEA_PHASES`) re-salts the water base, so the
phases are SPATIAL variants and cannot be played as frames — every pixel of
the cell would repaint on the same tick, which is the boil that makes cheap
animated water read as television static. A time frame keeps the base byte
for byte and slides only the glint dashes.

That gives the two gates here:

  no boil    outside the glint tones the two frames are the same image, and
             that image is `_water_base` untouched. Not "few pixels changed"
             — none, anywhere the flow is not drawn.
  the texel  the pair has to differ by something the board can SHOW. One
             board texel is 4 atlas px at the 4:1 rung, the dash slides
             exactly that, and at a 16x16 sample of the cell the pair
             disagrees on at least three texels.

The texel sample is an AREA sample (`Image.BOX`), i.e. what the 4x4 block of
atlas pixels behind one board texel averages to. A point sample
(`Image.NEAREST`, what `measure_motion` uses on unit sprites) reads one pixel
in sixteen, and a glint is a ONE-PIXEL-tall row: whether a dash registers at
all then depends on where its row happens to fall against the sample grid,
which is a property of the frame-A art and not of the animation. Under the
point sample the three phases score 6, 2 and 4 changed texels; under the area
sample 13, 11 and 18. The area number is the one that says whether the water
moved, so it is the one gated; the point sample is held above zero so no
phase can go point-sample invisible.

Run with `.venv/bin/python -m unittest discover tests`.
"""

from __future__ import annotations

import unittest

from PIL import Image

from spritegen import anim, autotile, terrain
from spritegen.palette import mix
from spritegen.terrain import CELL, WATER, WATER_DARK

# The two tones `_glints` paints, and nothing else in a sea cell is allowed to
# differ between frames. Derived the way the painter derives them, so a change
# to the mix cannot leave this table behind.
GLINT_TONES = {
    (*mix(WATER_DARK, WATER, 0.55), 255),
    (*mix(WATER_DARK, WATER, 0.3), 255),
}
TEXELS = CELL // 4  # one board texel is 4 atlas px at the 4:1 rung


def _pixels(img: Image.Image) -> list[tuple[int, ...]]:
    raw = img.convert("RGBA").tobytes()
    return [tuple(raw[i : i + 4]) for i in range(0, len(raw), 4)]


def _sample(img: Image.Image, mode: int) -> list[tuple[int, ...]]:
    return _pixels(img.convert("RGBA").resize((TEXELS, TEXELS), mode))


class NoBoil(unittest.TestCase):
    def test_only_glint_pixels_move(self):
        """Mask out the glint tones and the two frames are one image."""
        for phase in range(len(terrain.SEA_PHASES)):
            a = _pixels(terrain.sea(phase, 0))
            b = _pixels(terrain.sea(phase, 1))
            for i, (pa, pb) in enumerate(zip(a, b)):
                if pa in GLINT_TONES or pb in GLINT_TONES:
                    continue
                self.assertEqual(
                    pa,
                    pb,
                    f"phase {phase} repaints water at {i % CELL},{i // CELL}",
                )

    def test_the_water_base_itself_is_untouched_in_both_frames(self):
        """Stronger than the pair agreeing: both frames ARE the base wherever
        no glint is drawn, so neither frame re-salted the grain."""
        for phase, (grain, _) in enumerate(terrain.SEA_PHASES):
            base = _pixels(terrain._water_base(True, grain))
            for frame in range(terrain.SEA_FRAMES):
                for i, px in enumerate(_pixels(terrain.sea(phase, frame))):
                    if px in GLINT_TONES:
                        continue
                    self.assertEqual(
                        px,
                        base[i],
                        f"phase {phase} frame {frame} moved the grain at "
                        f"{i % CELL},{i // CELL}",
                    )

    def test_the_flow_neither_grows_nor_shrinks(self):
        """A slide moves the dashes; it does not paint more of them. Equal
        glint counts also mean no dash fell off the tile at the wrap."""
        for phase in range(len(terrain.SEA_PHASES)):
            counts = [
                sum(1 for px in _pixels(terrain.sea(phase, f)) if px in GLINT_TONES)
                for f in range(terrain.SEA_FRAMES)
            ]
            self.assertEqual(counts[0], counts[1], f"phase {phase} flow count moved")


class TexelRule(unittest.TestCase):
    def test_the_frames_disagree_on_at_least_three_board_texels(self):
        for phase in range(len(terrain.SEA_PHASES)):
            a = _sample(terrain.sea(phase, 0), Image.BOX)
            b = _sample(terrain.sea(phase, 1), Image.BOX)
            moved = sum(1 for pa, pb in zip(a, b) if pa != pb)
            self.assertGreaterEqual(
                moved, 3, f"phase {phase} moves only {moved} board texels"
            )

    def test_no_phase_is_invisible_to_a_point_sample(self):
        for phase in range(len(terrain.SEA_PHASES)):
            a = _sample(terrain.sea(phase, 0), Image.NEAREST)
            b = _sample(terrain.sea(phase, 1), Image.NEAREST)
            moved = sum(1 for pa, pb in zip(a, b) if pa != pb)
            self.assertGreater(moved, 0, f"phase {phase} moves no sampled texel")


class Seam(unittest.TestCase):
    def test_the_slide_stays_off_the_shared_border_ring(self):
        """The outer ring is what a cell shares with the cell it repeats
        against; a dash pushed into it by the slide would be a seam against a
        neighbour holding a different phase (the rule `_tuft_at` keeps)."""
        ring = terrain._GLINT_RING
        for phase in range(len(terrain.SEA_PHASES)):
            for frame in range(terrain.SEA_FRAMES):
                px = terrain.sea(phase, frame).convert("RGBA").load()
                for y in range(CELL):
                    for x in range(CELL):
                        edge = min(x, y, CELL - 1 - x, CELL - 1 - y) < ring
                        if edge and px[x, y] in GLINT_TONES:
                            self.fail(
                                f"phase {phase} frame {frame} glints on the "
                                f"border ring at {x},{y}"
                            )

    def test_the_slide_is_one_whole_board_texel(self):
        self.assertEqual(terrain.SEA_GLINT_SLIDE, 4)
        self.assertEqual(terrain.SEA_GLINT_SLIDE, CELL // TEXELS)


class Sheets(unittest.TestCase):
    def test_frame_a_is_the_sheet_the_board_already_has(self):
        """Adoption is additive: frame 0 is the old tile and the old sheet."""
        self.assertEqual(
            autotile.sea_sheet(0).tobytes(), autotile.sea_sheet().tobytes()
        )
        self.assertEqual(terrain.sea(0, 0).tobytes(), terrain.sea().tobytes())

    def test_both_frames_carry_the_same_columns_in_the_same_order(self):
        """A cell keeps its phase across frames — the board swaps sheets, it
        does not rehash — so column p of frame B has to be phase p."""
        for frame in range(terrain.SEA_FRAMES):
            s = autotile.sea_sheet(frame)
            phases = len(terrain.SEA_PHASES)
            self.assertEqual(s.size, (phases * (CELL + 2) + 2, CELL + 4))
            for phase in range(phases):
                x = phase * (CELL + 2) + 2
                column = s.crop((x, 2, x + CELL, 2 + CELL))
                self.assertEqual(
                    column.convert("RGB").tobytes(),
                    terrain.sea(phase, frame).convert("RGB").tobytes(),
                    f"frame {frame} column {phase} is not phase {phase}",
                )

    def test_the_frames_are_different_sheets(self):
        self.assertNotEqual(
            autotile.sea_sheet(0).tobytes(), autotile.sea_sheet(1).tobytes()
        )


class Manifest(unittest.TestCase):
    def test_the_clip_names_one_sheet_per_time_frame(self):
        clip = anim.MANIFEST["clips"]["sea"]
        self.assertEqual(clip["sheets"], list(anim.SEA_SHEETS))
        self.assertEqual(len(anim.SEA_SHEETS), terrain.SEA_FRAMES)
        self.assertEqual(clip["order"], list(range(terrain.SEA_FRAMES)))
        self.assertEqual(clip["ms_per_frame"], anim.SEA_MS)
        self.assertEqual(clip["mode"], "loop")

    def test_the_sea_beats_slower_than_the_ambient_clip(self):
        """Water is the slow motion on the board, and the two clips must not
        share a beat or the whole frame turns over on one tick."""
        self.assertGreater(anim.SEA_MS, anim.AMBIENT_MS)
        self.assertNotEqual(anim.SEA_MS % anim.AMBIENT_MS, 0)


if __name__ == "__main__":
    unittest.main()
