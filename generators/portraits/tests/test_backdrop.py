"""The window field: every kind draws, none is a wash, none leaks past the frame.

What the reviews measured as an opacity band is a pair of RUNGS now — the two
under the field's own — because a bust is painted in sixteen flat tones and a
wash over a fill is not one of them. So the reading is the same reading, taken
off the ramp instead of off the alpha: a treatment is darker than the field it
lies on, and it is one of the army's own colours.
"""

from __future__ import annotations

import unittest

from cells import colours, tally
from portraitgen import backdrop
from portraitgen.canvas import Canvas
from portraitgen.palette import faction_by_key, faction_ramp, luminance

FACTION = faction_by_key("meridian")


def _painted(kind: str) -> Canvas:
    canvas = Canvas()
    backdrop.draw(canvas, kind, FACTION)
    return canvas


class EveryKindDraws(unittest.TestCase):
    def test_the_vocabulary_and_the_dispatch_table_are_one_set(self):
        for kind in sorted(backdrop.KINDS):
            with self.subTest(kind=kind):
                self.assertIsNotNone(_painted(kind).image.getbbox())

    def test_an_unknown_kind_raises_rather_than_falling_through(self):
        with self.assertRaises(KeyError):
            backdrop.draw(Canvas(), "sunburst", FACTION)

    def test_the_field_is_one_flat_tone(self):
        canvas = Canvas()
        backdrop.field(canvas, FACTION)
        tones = {colour for _, colour in tally(canvas.image)}
        rung = faction_ramp(FACTION.key)[backdrop.FIELD_SLOT]
        self.assertEqual(tones, {(0, 0, 0, 0), (*rung, 255)})


class EveryTreatmentIsABand(unittest.TestCase):
    def _treatment(self, kind: str) -> Canvas:
        canvas = Canvas()
        backdrop.treatment(canvas, kind, FACTION)
        return canvas

    def test_every_band_is_a_rung_of_the_army_s_own_ramp(self):
        allowed = {
            faction_ramp(FACTION.key)[slot]
            for slot in (backdrop.LATTICE, backdrop.ACCENT)
        }
        for kind in sorted(backdrop.KINDS):
            with self.subTest(kind=kind):
                painted = colours(self._treatment(kind))
                self.assertTrue(painted, "the treatment drew nothing")
                self.assertEqual(painted - allowed, set())

    def test_every_band_is_opaque_and_darker_than_the_field(self):
        """A treatment used to be a wash at a fifth of an alpha; the rule it
        stood for — never competing with the face — is now a value one."""
        ramp = faction_ramp(FACTION.key)
        field = luminance(ramp[backdrop.FIELD_SLOT])
        for slot in (backdrop.LATTICE, backdrop.ACCENT):
            with self.subTest(slot=slot):
                self.assertLess(luminance(ramp[slot]), field)
        for kind in sorted(backdrop.KINDS):
            with self.subTest(kind=kind):
                alphas = {colour[3] for _, colour in tally(self._treatment(kind).image)}
                self.assertEqual(alphas - {0}, {255})

    def test_nothing_is_painted_outside_the_window(self):
        x0, y0, x1, y1 = backdrop.WINDOW
        for kind in sorted(backdrop.KINDS):
            with self.subTest(kind=kind):
                canvas = self._treatment(kind)
                left, top, right, bottom = canvas.image.getbbox()
                units = canvas.divisor
                self.assertGreaterEqual(left * units, x0)
                self.assertGreaterEqual(top * units, y0)
                self.assertLessEqual(right * units, x1)
                self.assertLessEqual(bottom * units, y1)


class ThePaletteIsBounded(unittest.TestCase):
    def test_a_backdrop_is_painted_in_a_handful_of_named_tones(self):
        for kind in sorted(backdrop.KINDS):
            with self.subTest(kind=kind):
                self.assertLessEqual(len(tally(_painted(kind).image)), 8)


if __name__ == "__main__":
    unittest.main()
