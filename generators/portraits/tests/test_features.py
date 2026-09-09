"""The face's own features: every vocabulary draws, an unknown key raises.

What is worn over them — headwear, eyewear, the scar — is `test_accessories.py`.

The vocabulary *is* the dispatch table now, so these suites replace the three
GUT lints that existed only to catch a silent fallback — a name outside the
table cannot reach a default any more, it raises.

Three facts are measured rather than eyeballed: C13, the mouth's dark area
staying under the pair of eyes'; P3, an open mouth spanning 2.2 of one eye's
width, which the shipped glyph had collapsed under; and the palette, which is
checked as "only tones this module was handed" on the working canvas, where a
flat tone is still exactly itself.
"""

from __future__ import annotations

import unittest

import preview_sheet
from PIL import ImageChops
from cells import area_of, blank_cell, colours, opaque_count
from portraitgen import features, light
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
# P3: the width an open mouth owes, in eye widths.
MOUTH_SPAN = 2.2
HAIR = light.Ramp.of_material((90, 60, 40))
SKIN = light.Ramp.of_material(preview_sheet.SKIN)
# The tones a face may be painted in: the two ramps it is handed, plus the eye
# colours this module owns. Nothing else may reach the canvas.
NAMED = {
    INK,
    features.SCLERA,
    features.IRIS,
    features.GOLD,
    *(HAIR.deep, HAIR.shade, HAIR.base, HAIR.lit, HAIR.rim),
    *(SKIN.deep, SKIN.shade, SKIN.base, SKIN.lit, SKIN.rim),
}


def _box_of(cell: Canvas, tone: tuple[int, int, int]) -> tuple[int, int, int, int]:
    """Where one flat tone sits on the canvas, in that canvas's own pixels."""
    bands = [
        band.point(lambda level, want=want: 255 if level == want else 0)
        for band, want in zip(cell.image.split(), tone, strict=False)
    ]
    mask = ImageChops.multiply(ImageChops.multiply(bands[0], bands[1]), bands[2])
    box = mask.getbbox()
    assert box is not None, f"no {tone} on the canvas"
    return box


class EveryKindDraws(unittest.TestCase):
    """Not one member of a vocabulary is a name with no drawing behind it."""

    def test_every_eye_kind_draws(self):
        for kind in sorted(features.EYE_KINDS):
            with self.subTest(eyes=kind):
                cell = blank_cell()
                features.eyes(cell, SKULL, kind, scale=features.EYE_DEFAULT)
                self.assertGreater(opaque_count(cell), 0)

    def test_every_brow_kind_draws(self):
        for kind in sorted(features.BROW_KINDS):
            with self.subTest(brow=kind):
                cell = blank_cell()
                features.brow(cell, SKULL, kind, HAIR)
                self.assertGreater(opaque_count(cell), 0)

    def test_every_nose_kind_draws(self):
        for kind in sorted(features.NOSE_KINDS):
            with self.subTest(nose=kind):
                cell = blank_cell()
                features.nose(cell, SKULL, kind, SKIN)
                self.assertGreater(opaque_count(cell), 0)

    def test_every_mouth_kind_draws(self):
        for kind in sorted(features.MOUTH_KINDS):
            with self.subTest(mouth=kind):
                cell = blank_cell()
                features.mouth(cell, SKULL, kind)
                self.assertGreater(opaque_count(cell), 0)

    def test_every_facial_hair_but_none_draws(self):
        for kind in sorted(features.FACIAL_KINDS):
            with self.subTest(facial=kind):
                cell = blank_cell()
                features.facial_hair(cell, SKULL, kind, HAIR)
                drawn = opaque_count(cell)
                if kind == "none":
                    self.assertEqual(drawn, 0)
                else:
                    self.assertGreater(drawn, 0)

    def test_the_earring_and_the_freckles_draw(self):
        ear, freckled = blank_cell(), blank_cell()
        features.earring(ear, SKULL)
        features.freckles(freckled, SKULL, SKIN)
        self.assertGreater(opaque_count(ear), 0)
        self.assertGreater(opaque_count(freckled), 0)


class AnUnknownNameRaises(unittest.TestCase):
    """The vocabulary is the dispatch table; nothing falls through to a default."""

    def test_no_drawer_answers_for_a_name_it_does_not_hold(self):
        cell = blank_cell()
        calls = (
            lambda: features.eyes(cell, SKULL, "smouldering", scale=1.0),
            lambda: features.brow(cell, SKULL, "waggled", HAIR),
            lambda: features.nose(cell, SKULL, "roman", SKIN),
            lambda: features.mouth(cell, SKULL, "pursed"),
            lambda: features.facial_hair(cell, SKULL, "muttonchops", HAIR),
        )
        for call in calls:
            with self.subTest(call=call), self.assertRaises(KeyError):
                call()


class TheNoseSitsUnderTheEyes(unittest.TestCase):
    """N1: every nose was authored at brow height and read as a forehead mark.

    Measured on the shape table rather than on the raster, because that is
    where the mistake was: three glyphs drawn between 116 and 136 on a face
    whose eyes sit on 142. The floor is the eye line plus a texel, so a nose
    can never climb back over the brows it was tangled in.
    """

    def test_no_nose_starts_at_or_above_the_eye_line(self):
        for kind in sorted(features.NOSE_KINDS):
            shape = features.nose_shape(kind)
            with self.subTest(nose=kind):
                self.assertGreaterEqual(shape.top, features.NOSE_TOP_FLOOR)
                self.assertGreater(shape.base, shape.top)

    def test_every_nose_clears_the_mouth_it_sits_over(self):
        for kind in sorted(features.NOSE_KINDS):
            shape = features.nose_shape(kind)
            with self.subTest(nose=kind):
                self.assertLess(
                    shape.base + features.NOSE_UNDERSIDE, features.MOUTH_CEILING
                )


class TheMouthCannotOutrankTheEyes(unittest.TestCase):
    """C13: an open mouth is a mouth, not a second eye socket.

    Measured against the pair, which is the checklist's own wording and what
    `test_metrics.py` holds every bust to. A mouth two and a fifth eyes wide
    (P3) carries a lip line longer than one eye's whole ring, so a one-eye bar
    here would have capped the *size* C13 explicitly does not cap."""

    def _both_eyes(self) -> int:
        cell = blank_cell()
        features.eyes(cell, SKULL, "m", scale=features.EYE_DEFAULT)
        return opaque_count(cell)

    def test_every_mouth_is_darker_in_less_area_than_the_eyes(self):
        eyes = self._both_eyes()
        for kind in sorted(features.MOUTH_KINDS):
            with self.subTest(mouth=kind):
                cell = blank_cell()
                features.mouth(cell, SKULL, kind)
                self.assertLess(area_of(cell, INK), eyes)


class AnOpenMouthOutspansTheEyes(unittest.TestCase):
    """P3: an open mouth is at least 2.2 eye widths — the whole family had
    collapsed into one small glyph, which is what C13's cap on the mouth's dark
    *area* is not allowed to cost.

    Both widths are read off the working canvas, where a flat tone is still
    itself and an edge has not been averaged into the skin."""

    def _mouth_width(self, kind: str, dial: float) -> int:
        cell = blank_cell()
        features.mouth(cell, SKULL, kind, eye=dial)
        left, _, right, _ = cell.image.getbbox()
        return right - left

    def _eye_width(self, dial: float) -> int:
        """One eye, measured across the line it is widest on."""
        cell = blank_cell()
        features.eyes(cell, SKULL, "m", scale=dial)
        midline, line = (
            round(value * PIXELS_PER_UNIT)
            for value in FRAME.at(features.MOUTH_X, features.EYE_LINE)
        )
        left, _, right, _ = cell.image.crop((0, line, midline, line + 1)).getbbox()
        return right - left

    def test_every_open_mouth_spans_two_and_a_fifth_eyes(self):
        for kind in sorted(features.OPEN_MOUTH_KINDS):
            for dial in (0.85, features.EYE_DEFAULT, 1.06):
                with self.subTest(mouth=kind, eye=dial):
                    self.assertGreaterEqual(
                        self._mouth_width(kind, dial),
                        MOUTH_SPAN * self._eye_width(dial),
                    )

    def test_every_open_mouth_carries_one_light_mark(self):
        """Teeth on three of them, the lit lower lip on the fourth: what an
        open mouth may not be is a dark hole with nothing bright in it."""
        for kind in sorted(features.OPEN_MOUTH_KINDS):
            with self.subTest(mouth=kind):
                cell = blank_cell()
                features.mouth(cell, SKULL, kind)
                self.assertGreater(area_of(cell, features.SCLERA), 0)


class TheBaredTeethAreFourGlyphsAndNotOne(unittest.TestCase):
    """P10: seven busts wore one wide white block, which is a sameness of its
    own. The band is capped at `TEETH_WIDTH` of the mouth's inner width and
    each open mouth bares it its own way, so a laugh, a grin, a snarl and an
    open mouth are four marks at chip size rather than one."""

    def _mouth(self, kind: str) -> Canvas:
        cell = blank_cell()
        features.mouth(cell, SKULL, kind)
        return cell

    def _opening(self, kind: str) -> tuple[int, int]:
        """The width and height inside the lip, which is what the cap is of."""
        left, top, right, bottom = self._mouth(kind).image.getbbox()
        lip = 2 * FEATURE_PEN
        return (right - left - lip, bottom - top - lip)

    def _bared(self, kind: str) -> tuple[int, int]:
        left, top, right, bottom = _box_of(self._mouth(kind), features.SCLERA)
        return (right - left, bottom - top)

    def test_no_open_mouth_bares_more_than_three_fifths_of_its_width(self):
        """The cap, to the raster pixel the band's own edge rounds to."""
        self.assertLessEqual(features.TEETH_WIDTH, 0.6)
        for kind in sorted(features.OPEN_MOUTH_KINDS):
            with self.subTest(mouth=kind):
                self.assertLessEqual(
                    self._bared(kind)[0],
                    features.TEETH_WIDTH * self._opening(kind)[0] + 1,
                )

    def test_a_grin_bares_a_narrower_band_than_a_laugh(self):
        self.assertLess(self._bared("grin")[0], self._bared("laugh")[0])

    def test_a_snarl_bares_its_upper_row_alone(self):
        self.assertLess(self._bared("snarl")[1], self._opening("snarl")[1] / 2)

    def test_an_open_mouth_is_a_dark_cavity_with_a_lit_lip(self):
        cell = self._mouth("open")
        left, top, right, _ = cell.image.getbbox()
        under_the_lip = (
            (left + right) // 2,
            top + FEATURE_PEN + 1,
        )
        self.assertEqual(cell.image.getpixel(under_the_lip)[:3], INK)
        self.assertLessEqual(
            self._bared("open")[1], round(features.LIT_LIP * PIXELS_PER_UNIT) + 1
        )


class TheFaceIsPaintedInNamedTones(unittest.TestCase):
    """A band is a tone off a ramp: no feature mixes one of its own."""

    def _whole_face(self) -> Canvas:
        cell = blank_cell()
        features.facial_hair(cell, SKULL, "beard", HAIR)
        features.brow(cell, SKULL, "heavy", HAIR)
        features.eyes(cell, SKULL, "m", scale=features.EYE_DEFAULT)
        features.nose(cell, SKULL, "hook", SKIN)
        features.mouth(cell, SKULL, "stern")
        features.earring(cell, SKULL)
        features.freckles(cell, SKULL, SKIN)
        return cell

    def test_no_tone_reaches_the_canvas_that_was_not_named(self):
        self.assertEqual(colours(self._whole_face()) - NAMED, set())

    def test_a_whole_face_stays_inside_the_colour_budget(self):
        self.assertLessEqual(len(colours(self._whole_face())), 48)


class TheEyeDialIsTheOneNumberThatSizesAnEye(unittest.TestCase):
    def _at(self, scale: float) -> Canvas:
        cell = blank_cell()
        features.eyes(cell, SKULL, "m", scale=scale)
        return cell

    def test_a_smaller_dial_draws_a_smaller_eye(self):
        self.assertLess(opaque_count(self._at(0.82)), opaque_count(self._at(1.06)))

    def _white(self, scale: float) -> int:
        return area_of(self._at(scale), features.SCLERA)

    def test_the_second_catchlight_goes_out_below_the_threshold(self):
        # A hair either side of the threshold: the eye is the same size, so the
        # white that disappears is the second sparkle and nothing else.
        below = self._white(features.EYE_SINGLE_CATCHLIGHT - 0.001)
        self.assertLess(below, self._white(features.EYE_SINGLE_CATCHLIGHT))


if __name__ == "__main__":
    unittest.main()
