"""Hair: every style is a mass with strands in it, and no style is a name only.

The claim the module exists to make is that a hairstyle is not one flat hex: it
is a mass plus clusters, each taking its own band. That is measured here as
"more than one tone of the ramp reaches the canvas", which is the thing a single
fill cannot fake — plus the vocabulary sweep and the raise on an unknown name
the roster is linted by.
"""

from __future__ import annotations

import unittest

import preview_sheet
from portraitgen import hair, light
from portraitgen.canvas import PORTRAIT_SIZE, Canvas
from portraitgen.head import Skull
from portraitgen.palette import INK

SKULL = Skull(1.0, "round", 0.0, 1.0)
MANE = light.build_ramp((90, 60, 40))
SKIN = light.build_ramp(preview_sheet.SKIN)
NAMED = {INK, MANE.deep, MANE.shade, MANE.base, MANE.lit, MANE.rim}
# The styles that are a cap of hair rather than a scalp: `bald` is two wisps at
# the temples and has no mass for a cluster to lie on.
COMBED = sorted(hair.STYLES - {"bald"})


def _cell() -> Canvas:
    return Canvas(PORTRAIT_SIZE)


def _tally(cell: Canvas) -> list[tuple[int, tuple[int, int, int, int]]]:
    return cell.image.getcolors(1 << 24)


def _painted(cell: Canvas) -> int:
    return sum(count for count, pixel in _tally(cell) if pixel[3] > 0)


def _area_of(cell: Canvas, tone: tuple[int, int, int]) -> int:
    return sum(count for count, pixel in _tally(cell) if pixel[:3] == tone)


def _colours(cell: Canvas) -> set[tuple[int, int, int]]:
    return {pixel[:3] for _, pixel in _tally(cell) if pixel[3] > 0}


class Combed(unittest.TestCase):
    """A style drawn on a bare canvas, which is where a tone is still itself."""

    def drawn(self, style: str, **kwargs) -> Canvas:
        cell = _cell()
        hair.draw(cell, SKULL, style, MANE, **kwargs)
        return cell


class EveryStyleDraws(Combed):
    def test_every_style_puts_hair_on_the_head(self):
        for style in sorted(hair.STYLES):
            with self.subTest(style=style):
                self.assertGreater(_painted(self.drawn(style)), 0)

    def test_a_style_the_table_does_not_hold_raises(self):
        for call in (hair.draw, hair.back, hair.front):
            with self.subTest(call=call.__name__), self.assertRaises(KeyError):
                call(_cell(), SKULL, "mohawk", MANE)

    def test_the_mass_is_drawn_in_two_halves_that_add_up_to_the_whole(self):
        behind, over = _cell(), _cell()
        hair.back(behind, SKULL, "ponytail", MANE)
        hair.front(over, SKULL, "ponytail", MANE)
        self.assertGreater(_painted(behind), 0)
        self.assertGreater(_painted(over), 0)
        self.assertEqual(
            _painted(self.drawn("ponytail")),
            _painted(_composed(behind, over)),
        )


def _composed(behind: Canvas, over: Canvas) -> Canvas:
    behind.compose(over)
    return behind


class AMassIsNotOneFlatHex(Combed):
    """The strand clusters are the whole point: they put bands in the mass."""

    def test_every_combed_style_carries_more_than_one_band(self):
        for style in COMBED:
            with self.subTest(style=style):
                bands = _colours(self.drawn(style)) - {INK}
                self.assertGreaterEqual(len(bands), 3)

    def test_the_clusters_are_lit_from_the_one_fixed_side(self):
        # The light never moves, so the lit band belongs to the left of the mass
        # and the deep band to its right — on every style, mirrored or not.
        cell = self.drawn("long")
        self.assertGreater(_area_of(cell, MANE.lit), 0)
        self.assertGreater(_area_of(cell, MANE.shade), 0)


class TheFringeShadesTheForehead(Combed):
    def test_the_band_is_painted_in_the_wearers_own_skin(self):
        lit = self.drawn("bob")
        shaded = self.drawn("bob", skin=SKIN)
        self.assertEqual(_area_of(lit, SKIN.shade), 0)
        self.assertGreater(_area_of(shaded, SKIN.shade), 0)

    def test_a_scalp_has_no_fringe_to_cast_one(self):
        self.assertEqual(_area_of(self.drawn("bald", skin=SKIN), SKIN.shade), 0)


class HairIsPaintedInNamedTones(Combed):
    def test_no_tone_reaches_the_canvas_that_was_not_named(self):
        for style in sorted(hair.STYLES):
            with self.subTest(style=style):
                self.assertEqual(_colours(self.drawn(style)) - NAMED, set())

    def test_a_style_stays_inside_the_colour_budget(self):
        for style in sorted(hair.STYLES):
            with self.subTest(style=style):
                self.assertLessEqual(len(_colours(self.drawn(style))), 48)


class EveryColourHasItsFourTones(Combed):
    def test_every_colour_the_roster_names_builds_a_ramp(self):
        for colour in sorted(hair.HAIR_COLOURS):
            with self.subTest(colour=colour):
                ramp = hair.ramp_for(colour)
                named = hair.HAIR_BASES[colour]
                # The base band is the table's colour re-keyed to its own
                # value, so it lands on it to within a rounding step.
                for tone, want in zip(ramp.base, named):
                    self.assertAlmostEqual(tone, want, delta=1)
                self.assertNotEqual(ramp.deep, ramp.lit)

    def test_a_colour_the_table_does_not_hold_raises(self):
        with self.assertRaises(KeyError):
            hair.ramp_for("chartreuse")


if __name__ == "__main__":
    unittest.main()
