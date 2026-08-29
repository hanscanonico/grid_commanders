"""What the face wears: every vocabulary draws, an unknown key raises.

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
from PIL import Image
from portraitgen import features, light
from portraitgen.canvas import PORTRAIT_SIZE, SUPERSAMPLE, Canvas
from portraitgen.head import Skull
from portraitgen.palette import INK

SKULL = Skull(1.0, "round", 0.0, 1.0)
FRAME = features.Frame.of(SKULL)
# P3: the width an open mouth owes, in eye widths.
MOUTH_SPAN = 2.2
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
    """C13: an open mouth is a mouth, not a second eye socket.

    Measured against the pair, which is the checklist's own wording and what
    `test_metrics.py` holds every bust to. A mouth two and a fifth eyes wide
    (P3) carries a lip line longer than one eye's whole ring, so a one-eye bar
    here would have capped the *size* C13 explicitly does not cap."""

    def _both_eyes(self) -> int:
        cell = _cell()
        features.eyes(cell, SKULL, "m", scale=features.EYE_DEFAULT)
        return _painted(cell)

    def test_every_mouth_is_darker_in_less_area_than_the_eyes(self):
        eyes = self._both_eyes()
        for kind in sorted(features.MOUTH_KINDS):
            with self.subTest(mouth=kind):
                cell = _cell()
                features.mouth(cell, SKULL, kind)
                self.assertLess(_area_of(cell, INK), eyes)


class AnOpenMouthOutspansTheEyes(unittest.TestCase):
    """P3: an open mouth is at least 2.2 eye widths — the whole family had
    collapsed into one small glyph, which is what C13's cap on the mouth's dark
    *area* is not allowed to cost.

    Both widths are read off the working canvas, where a flat tone is still
    itself and an edge has not been averaged into the skin."""

    def _mouth_width(self, kind: str, dial: float) -> int:
        cell = _cell()
        features.mouth(cell, SKULL, kind, eye=dial)
        left, _, right, _ = cell.image.getbbox()
        return right - left

    def _eye_width(self, dial: float) -> int:
        """One eye, measured across the line it is widest on."""
        cell = _cell()
        features.eyes(cell, SKULL, "m", scale=dial)
        midline, line = (
            round(value * SUPERSAMPLE)
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

    def test_every_open_mouth_bares_a_band_of_teeth(self):
        for kind in sorted(features.OPEN_MOUTH_KINDS):
            with self.subTest(mouth=kind):
                cell = _cell()
                features.mouth(cell, SKULL, kind)
                self.assertGreater(_area_of(cell, features.SCLERA), 0)


class TheEyepatchIsAPatchAndNotAMask(unittest.TestCase):
    """P4a: a plate with a lit eye showing inside it is a domino mask. The
    patch is one flat tone, and the socket it covers is not drawn at all."""

    def _patch(self) -> Canvas:
        cell = _cell()
        features.accessory(cell, SKULL, "eyepatch")
        return cell

    def test_the_patch_and_its_strap_are_one_tone(self):
        self.assertEqual(_colours(self._patch()), {INK})

    def test_the_strap_lands_on_the_ear(self):
        """P4a: a plate with no strap is a sticker. It is anchored where it
        would be worn, so the ear is where the stroke has to end."""
        ear_x, ear_y, radius = features.EAR
        x, y = (
            round(value * SUPERSAMPLE)
            for value in FRAME.at(ear_x + radius, ear_y - radius)
        )
        anchor = self._patch().image.crop((x - 1, y - 1, x + 2, y + 2))
        self.assertEqual(anchor.getcolors(), [(9, (*INK, 255))])

    def test_the_eyepatch_is_the_one_accessory_that_covers_a_socket(self):
        covering = {
            kind
            for kind in features.ACCESSORY_KINDS
            if features.covered_eye(kind) is not None
        }
        self.assertEqual(covering, {"eyepatch"})

    def test_a_covered_socket_draws_neither_eye_nor_brow(self):
        covered = features.covered_eye("eyepatch")
        for paint in (
            lambda cell, hide: features.eyes(
                cell, SKULL, "wide", scale=1.06, covered=hide
            ),
            lambda cell, hide: features.brow(cell, SKULL, "heavy", HAIR, covered=hide),
        ):
            with self.subTest(paint=paint):
                both, one = _cell(), _cell()
                paint(both, None)
                paint(one, covered)
                self.assertLess(_painted(one), _painted(both))

    def test_no_tone_lighter_than_the_patch_is_drawn_inside_it(self):
        covered = features.covered_eye("eyepatch")
        face = self._patch()
        features.brow(face, SKULL, "heavy", HAIR, covered=covered)
        features.eyes(face, SKULL, "wide", scale=1.06, covered=covered)
        inside = Image.new("RGBA", face.image.size, (0, 0, 0, 0))
        inside.paste(face.image, mask=self._patch().image.getchannel("A"))
        self.assertEqual(
            {pixel[:3] for _, pixel in inside.getcolors(1 << 24) if pixel[3] > 0},
            {INK},
        )


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
