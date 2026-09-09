"""What a general wears over the face: headwear, eyewear and the scar.

The face's own vocabularies are `test_features.py`; this suite is the layer
drawn after them, and it measures three things rather than eyeballing them:
P13/P16, the three hats being told apart by what each leaves off; P17, a pair of
glasses being two squares with no bridge between them, the bridge having been a
grey smear at chip size; and P4a, the eyepatch covering its socket instead of
lighting an eye inside a domino mask.
"""

from __future__ import annotations

import unittest

from PIL import Image
from cells import blank_cell, colours, opaque_count
from portraitgen import accessories, features, light
from portraitgen.canvas import BUST_DIVISOR, INK_FEATURE, Canvas, pen
from portraitgen.head import Skull
from portraitgen.palette import INK

# Design units to raster pixels: a measurement stated in the geometry's own
# units, read off the raster the bust is drawn on.
PIXELS_PER_UNIT = 1.0 / BUST_DIVISOR
# What the feature weight actually draws on this grid, which is what a gap
# beside it or a ring drawn in it measures against.
FEATURE_PEN = pen(INK_FEATURE, BUST_DIVISOR)

SKULL = Skull(1.0, "round", 0.0, 1.0)
FRAME = features.Frame.of(SKULL)
HAIR = light.Ramp.of_material((90, 60, 40))
# The tones an untinted accessory may spend: the ink, the kit slate every strap
# and frame is cut from, the goggle glass and the scar's two. Nothing else may
# reach the canvas.
NAMED = {
    INK,
    accessories.KIT,
    accessories.GLASS,
    accessories.SCAR,
    accessories.SCAR_DEEP,
}


def _ink_run(cell: Canvas, y: int) -> int:
    """How thick the first stroke along one row of the working canvas is."""
    band = cell.image.crop((0, y, cell.image.width, y + 1)).get_flattened_data()
    row = [pixel[:3] for pixel in band]
    start = row.index(INK)
    run = 0
    while start + run < len(row) and row[start + run] == INK:
        run += 1
    return run


class EveryKindDraws(unittest.TestCase):
    """Not one member of the vocabulary is a name with no drawing behind it, and
    the dispatch table answers for nothing outside it."""

    def test_every_accessory_but_none_draws(self):
        for kind in sorted(accessories.ACCESSORY_KINDS):
            with self.subTest(accessory=kind):
                cell = blank_cell()
                accessories.accessory(cell, SKULL, kind)
                drawn = opaque_count(cell)
                if kind == "none":
                    self.assertEqual(drawn, 0)
                else:
                    self.assertGreater(drawn, 0)

    def test_no_accessory_answers_for_a_name_it_does_not_hold(self):
        with self.assertRaises(KeyError):
            accessories.accessory(blank_cell(), SKULL, "monocle")

    def test_headwear_hands_back_what_it_added_to_the_silhouette(self):
        cell = blank_cell()
        self.assertEqual(accessories.accessory(cell, SKULL, "glasses"), [])
        self.assertGreater(len(accessories.accessory(cell, SKULL, "bandana")), 2)

    def test_no_tone_reaches_the_canvas_that_was_not_named(self):
        for kind in sorted(accessories.ACCESSORY_KINDS):
            with self.subTest(accessory=kind):
                cell = blank_cell()
                accessories.accessory(cell, SKULL, kind)
                self.assertEqual(colours(cell) - NAMED, set())


class TheHeadwearIsToldApartByWhatItLeavesOff(unittest.TestCase):
    """P13/P16: three hats over one skull, and each is the shape the two others
    are not — a peak, a bare brow, a bare crown."""

    def _box(self, kind: str) -> tuple[float, float, float, float]:
        cell = blank_cell()
        accessories.accessory(cell, SKULL, kind)
        box = cell.image.getbbox()
        if box is None:
            raise AssertionError(f"{kind} drew nothing")
        return tuple(value * cell.divisor for value in box)

    def test_the_service_cap_hangs_a_peak_the_field_cap_has_not_got(self):
        self.assertGreater(self._box("cap")[3] - self._box("fieldcap")[3], 8.0)

    def test_the_service_cap_is_the_wider_hat(self):
        cap, field = self._box("cap"), self._box("fieldcap")
        self.assertLess(cap[0], field[0])
        self.assertGreater(cap[2], field[2])

    def test_the_field_cap_sits_lower_on_the_skull(self):
        self.assertGreater(self._box("fieldcap")[1], self._box("cap")[1])

    def test_the_visor_carries_no_crown(self):
        self.assertGreater(self._box("visor")[1], self._box("cap")[1] + 20.0)

    def test_no_hat_comes_down_over_the_eyes(self):
        line = FRAME.at(0.0, features.EYE_LINE)[1]
        for kind in ("cap", "fieldcap", "visor"):
            with self.subTest(accessory=kind):
                self.assertLess(self._box(kind)[3], line)


class TheGlassesAreTwoSquaresAndNoBridge(unittest.TestCase):
    """P17: a bridge is the part of a pair of glasses the chip grid cannot hold
    — it is thinner than one of its texels, and it joined the two lenses into one
    grey smear at chip size. Two squares at the feature weight survive it; the
    bridge is gone."""

    def _worn(self) -> Canvas:
        cell = blank_cell()
        accessories.accessory(cell, SKULL, "glasses")
        return cell

    def test_nothing_is_drawn_between_the_two_lenses(self):
        """Both rings are cropped off, so only a bridge can be left in it."""
        worn = self._worn().image
        left, top, right, bottom = worn.getbbox()
        lens = round(self._lens_side() * PIXELS_PER_UNIT)
        self.assertIsNone(worn.crop((left + lens, top, right - lens, bottom)).getbbox())

    def _lens_side(self) -> float:
        return 2 * accessories.LENS_HALF + INK_FEATURE

    def test_each_lens_is_a_square_ring_at_the_feature_weight(self):
        _, top, _, bottom = self._worn().image.getbbox()
        self.assertAlmostEqual(
            bottom - top, round(self._lens_side() * PIXELS_PER_UNIT), delta=1
        )
        self.assertEqual(_ink_run(self._worn(), (top + bottom) // 2), FEATURE_PEN)


class TheEyepatchIsAPatchAndNotAMask(unittest.TestCase):
    """P4a: a plate with a lit eye showing inside it is a domino mask. The
    patch is one flat tone, and the socket it covers is not drawn at all."""

    def _patch(self) -> Canvas:
        cell = blank_cell()
        accessories.accessory(cell, SKULL, "eyepatch")
        return cell

    def test_the_patch_and_its_strap_are_one_tone(self):
        self.assertEqual(colours(self._patch()), {INK})

    def test_the_strap_lands_on_the_ear(self):
        """P4a: a plate with no strap is a sticker. It is anchored where it
        would be worn, so the ear is where the stroke has to end — a pixel of
        the strap's own ink inside the ear's own square, which at a one-pixel
        pen is the whole of what "ends here" can mean."""
        ear_x, ear_y, radius = features.EAR
        x, y = (
            round(value * PIXELS_PER_UNIT)
            for value in FRAME.at(ear_x + radius, ear_y - radius)
        )
        anchor = self._patch().image.crop((x - 1, y - 1, x + 2, y + 2))
        self.assertIn((*INK, 255), [colour for _, colour in anchor.getcolors()])

    def test_the_eyepatch_is_the_one_accessory_that_covers_a_socket(self):
        covering = {
            kind
            for kind in accessories.ACCESSORY_KINDS
            if accessories.covered_eye(kind) is not None
        }
        self.assertEqual(covering, {"eyepatch"})

    def test_a_covered_socket_draws_neither_eye_nor_brow(self):
        covered = accessories.covered_eye("eyepatch")
        for paint in (
            lambda cell, hide: features.eyes(
                cell, SKULL, "wide", scale=1.06, covered=hide
            ),
            lambda cell, hide: features.brow(cell, SKULL, "heavy", HAIR, covered=hide),
        ):
            with self.subTest(paint=paint):
                both, one = blank_cell(), blank_cell()
                paint(both, None)
                paint(one, covered)
                self.assertLess(opaque_count(one), opaque_count(both))

    def test_no_tone_lighter_than_the_patch_is_drawn_inside_it(self):
        covered = accessories.covered_eye("eyepatch")
        face = self._patch()
        features.brow(face, SKULL, "heavy", HAIR, covered=covered)
        features.eyes(face, SKULL, "wide", scale=1.06, covered=covered)
        inside = Image.new("RGBA", face.image.size, (0, 0, 0, 0))
        inside.paste(face.image, mask=self._patch().image.getchannel("A"))
        self.assertEqual(
            {pixel[:3] for _, pixel in inside.getcolors(1 << 24) if pixel[3] > 0},
            {INK},
        )


if __name__ == "__main__":
    unittest.main()
