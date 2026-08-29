"""Hair: every style is a mass with one lit lobe on it, and `bald` has neither.

The claim the module exists to make is that a hairstyle is a mass the key
catches once — not one flat hex, and not the row of alternating strand clusters
it used to be, which read as a striped awning at chip size. That is measured
here as the lobe's share of the mass, the pale ramps that refuse a lobe at all,
and the scalp that draws no fringe — plus the vocabulary sweep and the raise on
an unknown name the roster is linted by.
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
# The styles that are a cap of hair rather than a scalp: `bald` has no mass for
# a lobe to lie on, and nothing over the crown to cast a fringe.
COMBED = sorted(hair.STYLES - {"bald"})
# A ramp over the pale line, and one under it, to ask the same style twice.
PLATINUM = hair.ramp_for("platinum")
# The lobe is a highlight on the mass, not a second mass beside it.
LOBE_SHARE = 0.25


def _cell() -> Canvas:
    return Canvas(PORTRAIT_SIZE)


def _tally(cell: Canvas) -> list[tuple[int, tuple[int, int, int, int]]]:
    return cell.image.getcolors(1 << 24)


def _painted(cell: Canvas) -> int:
    return sum(count for count, pixel in _tally(cell) if pixel[3] > 0)


def _area_of(cell: Canvas, tone: tuple[int, int, int]) -> int:
    return sum(count for count, pixel in _tally(cell) if pixel[:3] == tone)


def _pixels_of(cell: Canvas, tone: tuple[int, int, int]) -> list[tuple[int, int]]:
    pixels = cell.image.load()
    width, height = cell.image.size
    return [
        (x, y)
        for y in range(height)
        for x in range(width)
        if pixels[x, y][3] > 0 and pixels[x, y][:3] == tone
    ]


def _regions(pixels: list[tuple[int, int]]) -> int:
    """How many four-connected islands a set of pixels falls into."""
    left = set(pixels)
    islands = 0
    while left:
        islands += 1
        edge = [left.pop()]
        while edge:
            x, y = edge.pop()
            for step in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                near = (x + step[0], y + step[1])
                if near in left:
                    left.discard(near)
                    edge.append(near)
    return islands


def _colours(cell: Canvas) -> set[tuple[int, int, int]]:
    return {pixel[:3] for _, pixel in _tally(cell) if pixel[3] > 0}


class Combed(unittest.TestCase):
    """A style drawn on a bare canvas, which is where a tone is still itself."""

    def drawn(self, style: str, **kwargs) -> Canvas:
        cell = _cell()
        hair.draw(cell, SKULL, style, MANE, **kwargs)
        return cell


class EveryStyleDraws(Combed):
    def test_every_combed_style_puts_hair_on_the_head(self):
        for style in COMBED:
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


class TheMassTakesOneLitLobe(Combed):
    """One flat shape where the key lands, and it stays a highlight."""

    def test_every_combed_style_carries_a_lit_lobe(self):
        for style in COMBED:
            with self.subTest(style=style):
                self.assertGreater(_area_of(self.drawn(style), MANE.lit), 0)

    def test_the_lobe_is_a_quarter_of_the_mass_at_most(self):
        for style in COMBED:
            with self.subTest(style=style):
                cell = self.drawn(style)
                share = _area_of(cell, MANE.lit) / _painted(cell)
                self.assertLessEqual(share, LOBE_SHARE)

    def test_the_lobe_is_one_shape_and_not_a_row_of_them(self):
        # The awning this replaced was N clusters, so "one" is the claim.
        for style in COMBED:
            with self.subTest(style=style):
                self.assertEqual(_regions(_pixels_of(self.drawn(style), MANE.lit)), 1)

    def test_the_crown_is_the_base_tone_under_the_one_lit_shape(self):
        # Two tones over the head and no more: a mass and the key on it. The
        # clusters took a band each, which is what striped every crown.
        for style in COMBED:
            with self.subTest(style=style):
                cell = _cell()
                hair.front(cell, SKULL, style, MANE)
                self.assertEqual(_colours(cell) - {INK}, {MANE.base, MANE.lit})

    def test_the_lobe_sits_on_the_side_the_key_is_fixed_to(self):
        # The light never moves, so the lobe belongs to the left of the mass on
        # every style, mirrored or not.
        cell = self.drawn("long")
        columns = [x for x, _ in _pixels_of(cell, MANE.lit)]
        self.assertLess(max(columns), cell.image.width / 2)

    def test_a_pale_mass_takes_no_lobe_at_all(self):
        # Over the pale line the lit band is a step off the base, so the lobe
        # stops separating the mass and starts cutting a seam through it.
        self.assertGreater(light.luminance(PLATINUM.base), hair.PALE_HAIR)
        for style in COMBED:
            with self.subTest(style=style):
                cell = _cell()
                hair.draw(cell, SKULL, style, PLATINUM)
                self.assertGreater(_painted(cell), 0)
                self.assertEqual(_area_of(cell, PLATINUM.lit), 0)


class TheFringeShadesTheForehead(Combed):
    def test_the_band_is_painted_in_the_wearers_own_skin(self):
        lit = self.drawn("bob")
        shaded = self.drawn("bob", skin=SKIN)
        self.assertEqual(_area_of(lit, SKIN.shade), 0)
        self.assertGreater(_area_of(shaded, SKIN.shade), 0)

    def test_a_scalp_has_no_fringe_to_cast_one(self):
        self.assertEqual(_area_of(self.drawn("bald", skin=SKIN), SKIN.shade), 0)

    def test_a_scalp_draws_no_fringe_pixels_of_its_own(self):
        # The two temple wisps this style used to carry read as horns on the
        # crown, so a bald head is a bald head.
        self.assertEqual(_painted(self.drawn("bald", skin=SKIN)), 0)


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
