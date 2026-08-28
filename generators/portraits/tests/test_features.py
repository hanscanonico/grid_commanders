"""What the face wears: every vocabulary draws, an unknown key raises.

The vocabulary *is* the dispatch table now, so these suites replace the three
GUT lints that existed only to catch a silent fallback — a name outside the
table cannot reach a default any more, it raises.

Two facts are measured rather than eyeballed: C13, the mouth's dark area staying
under one eye's, which the shipped `open` mouth broke by reading as a second eye
socket; and the palette, which is checked as "only tones this module was handed"
on the working canvas, where a flat tone is still exactly itself.
"""

from __future__ import annotations

import unittest

import preview_sheet
from portraitgen import features, light
from portraitgen.canvas import PORTRAIT_SIZE, Canvas
from portraitgen.head import Skull
from portraitgen.palette import INK

SKULL = Skull(1.0, "round", 0.0, 1.0)
HAIR = light.build_ramp((90, 60, 40))
SKIN = light.build_ramp(preview_sheet.SKIN)
# The tones a face may be painted in: the two ramps it is handed, plus the kit
# colours the module owns. Nothing else may reach the canvas.
NAMED = {
    INK,
    features.SCLERA,
    features.IRIS,
    features.KIT,
    features.GLASS,
    features.GOLD,
    features.SCAR,
    *(HAIR.deep, HAIR.shade, HAIR.base, HAIR.lit, HAIR.rim),
    *(SKIN.deep, SKIN.shade, SKIN.base, SKIN.lit, SKIN.rim),
}


def _cell() -> Canvas:
    return Canvas(PORTRAIT_SIZE)


def _tally(cell: Canvas) -> list[tuple[int, tuple[int, int, int, int]]]:
    """Every colour on the working canvas and how much of it there is."""
    return cell.image.getcolors(1 << 24)


def _painted(cell: Canvas) -> int:
    return sum(count for count, pixel in _tally(cell) if pixel[3] > 0)


def _area_of(cell: Canvas, tone: tuple[int, int, int]) -> int:
    return sum(count for count, pixel in _tally(cell) if pixel[:3] == tone)


def _colours(cell: Canvas) -> set[tuple[int, int, int]]:
    return {pixel[:3] for _, pixel in _tally(cell) if pixel[3] > 0}


class EveryKindDraws(unittest.TestCase):
    """Not one member of a vocabulary is a name with no drawing behind it."""

    def test_every_eye_kind_draws(self):
        for kind in sorted(features.EYE_KINDS):
            with self.subTest(eyes=kind):
                cell = _cell()
                features.eyes(cell, SKULL, kind, scale=features.EYE_DEFAULT)
                self.assertGreater(_painted(cell), 0)

    def test_every_brow_kind_draws(self):
        for kind in sorted(features.BROW_KINDS):
            with self.subTest(brow=kind):
                cell = _cell()
                features.brow(cell, SKULL, kind, HAIR)
                self.assertGreater(_painted(cell), 0)

    def test_every_nose_kind_draws(self):
        for kind in sorted(features.NOSE_KINDS):
            with self.subTest(nose=kind):
                cell = _cell()
                features.nose(cell, SKULL, kind, SKIN)
                self.assertGreater(_painted(cell), 0)

    def test_every_mouth_kind_draws(self):
        for kind in sorted(features.MOUTH_KINDS):
            with self.subTest(mouth=kind):
                cell = _cell()
                features.mouth(cell, SKULL, kind)
                self.assertGreater(_painted(cell), 0)

    def test_every_facial_hair_but_none_draws(self):
        for kind in sorted(features.FACIAL_KINDS):
            with self.subTest(facial=kind):
                cell = _cell()
                features.facial_hair(cell, SKULL, kind, HAIR)
                drawn = _painted(cell)
                if kind == "none":
                    self.assertEqual(drawn, 0)
                else:
                    self.assertGreater(drawn, 0)

    def test_every_accessory_but_none_draws(self):
        for kind in sorted(features.ACCESSORY_KINDS):
            with self.subTest(accessory=kind):
                cell = _cell()
                features.accessory(cell, SKULL, kind)
                drawn = _painted(cell)
                if kind == "none":
                    self.assertEqual(drawn, 0)
                else:
                    self.assertGreater(drawn, 0)

    def test_the_earring_and_the_freckles_draw(self):
        ear, freckled = _cell(), _cell()
        features.earring(ear, SKULL)
        features.freckles(freckled, SKULL, SKIN)
        self.assertGreater(_painted(ear), 0)
        self.assertGreater(_painted(freckled), 0)

    def test_headwear_hands_back_what_it_added_to_the_silhouette(self):
        cell = _cell()
        self.assertEqual(features.accessory(cell, SKULL, "glasses"), [])
        self.assertGreater(len(features.accessory(cell, SKULL, "bandana")), 2)


class AnUnknownNameRaises(unittest.TestCase):
    """The vocabulary is the dispatch table; nothing falls through to a default."""

    def test_no_drawer_answers_for_a_name_it_does_not_hold(self):
        cell = _cell()
        calls = (
            lambda: features.eyes(cell, SKULL, "smouldering", scale=1.0),
            lambda: features.brow(cell, SKULL, "waggled", HAIR),
            lambda: features.nose(cell, SKULL, "roman", SKIN),
            lambda: features.mouth(cell, SKULL, "pursed"),
            lambda: features.facial_hair(cell, SKULL, "muttonchops", HAIR),
            lambda: features.accessory(cell, SKULL, "monocle"),
        )
        for call in calls:
            with self.subTest(call=call), self.assertRaises(KeyError):
                call()


class TheMouthCannotOutrankTheEyes(unittest.TestCase):
    """C13: an open mouth is a mouth, not a second eye socket."""

    def _one_eye(self) -> int:
        cell = _cell()
        features.eyes(cell, SKULL, "m", scale=features.EYE_DEFAULT)
        return _painted(cell) // 2

    def test_every_mouth_is_darker_in_less_area_than_one_eye(self):
        eye = self._one_eye()
        for kind in sorted(features.MOUTH_KINDS):
            with self.subTest(mouth=kind):
                cell = _cell()
                features.mouth(cell, SKULL, kind)
                self.assertLess(_area_of(cell, INK), eye)

    def test_the_open_mouth_carries_its_white_band(self):
        cell = _cell()
        features.mouth(cell, SKULL, "open")
        self.assertGreater(_area_of(cell, features.SCLERA), 0)


class TheFaceIsPaintedInNamedTones(unittest.TestCase):
    """A band is a tone off a ramp: no feature mixes one of its own."""

    def _whole_face(self) -> Canvas:
        cell = _cell()
        features.facial_hair(cell, SKULL, "beard", HAIR)
        features.brow(cell, SKULL, "heavy", HAIR)
        features.eyes(cell, SKULL, "m", scale=features.EYE_DEFAULT)
        features.nose(cell, SKULL, "hook", SKIN)
        features.mouth(cell, SKULL, "stern")
        features.accessory(cell, SKULL, "goggles")
        features.earring(cell, SKULL)
        features.freckles(cell, SKULL, SKIN)
        return cell

    def test_no_tone_reaches_the_canvas_that_was_not_named(self):
        self.assertEqual(_colours(self._whole_face()) - NAMED, set())

    def test_a_whole_face_stays_inside_the_colour_budget(self):
        self.assertLessEqual(len(_colours(self._whole_face())), 48)


class TheEyeDialIsTheOneNumberThatSizesAnEye(unittest.TestCase):
    def _at(self, scale: float) -> Canvas:
        cell = _cell()
        features.eyes(cell, SKULL, "m", scale=scale)
        return cell

    def test_a_smaller_dial_draws_a_smaller_eye(self):
        self.assertLess(_painted(self._at(0.82)), _painted(self._at(1.06)))

    def _white(self, scale: float) -> int:
        return _area_of(self._at(scale), features.SCLERA)

    def test_the_second_catchlight_goes_out_below_the_threshold(self):
        # A hair either side of the threshold: the eye is the same size, so the
        # white that disappears is the second sparkle and nothing else.
        below = self._white(features.EYE_SINGLE_CATCHLIGHT - 0.001)
        self.assertLess(below, self._white(features.EYE_SINGLE_CATCHLIGHT))


if __name__ == "__main__":
    unittest.main()
