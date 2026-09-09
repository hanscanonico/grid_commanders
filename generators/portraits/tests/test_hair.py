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
from cells import area_of, blank_cell, colours, opaque_count
from portraitgen import hair, light, palette
from portraitgen.canvas import BUST_DIVISOR, Canvas
from portraitgen.features import REFERENCE_BOX
from portraitgen import head
from portraitgen.head import Skull
from portraitgen.palette import INK

SKULL = Skull(1.0, "round", 0.0, 1.0)
# That skull is the one the styles were authored on, so it lands on the
# reference box one for one and a share of the skull is a share of this box.
LEFT, TOP, RIGHT, BOTTOM = REFERENCE_BOX
# How far a bound read off the raster may sit from the dial that drew it: a mass
# carries half the silhouette's ink outside its own path on each side, plus the
# canvas' own design-unit-to-pixel rounding step.
INK_SLACK = 5
# Design units per raster pixel: `_silhouette` reads the raster and reports the
# units the styles are authored in.
PITCH = BUST_DIVISOR
# How near the highest row a column has to reach to count as one of the curls.
CREST_BAND = 2
MANE = light.Ramp.of_material((90, 60, 40))
# The wearer the styles are measured on, and a second, darker one: the fringe
# band is the skin's own shade tone, so two skins tell whose it is.
SKIN = light.Ramp.of_material(preview_sheet.SKIN)
DARK_SKIN = head.ramp_for("dark")
NAMED = {INK, MANE.deep, MANE.shade, MANE.base, MANE.lit, MANE.rim, SKIN.shade}
# The styles that are a cap of hair rather than a scalp: `bald` has no mass for
# a lobe to lie on, and nothing over the crown to cast a fringe.
COMBED = sorted(hair.STYLES - {"bald"})
# A ramp over the pale line, and one under it, to ask the same style twice.
PLATINUM = hair.ramp_for("platinum")
# The lobe is a highlight on the mass, not a second mass beside it. A quarter
# was the bar at three times this raster; a lobe's edge rounds outward by up to
# a whole pixel all the way round on the bust's own grid, which is a couple of
# points on a small style like `short`.
LOBE_SHARE = 0.27


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


def _silhouette(cell: Canvas) -> list[tuple[float, float]]:
    """Every painted pixel, in the design units the styles are authored in."""
    pixels = cell.image.load()
    width, height = cell.image.size
    return [
        (x * cell.divisor, y * cell.divisor)
        for y in range(height)
        for x in range(width)
        if pixels[x, y][3] > 0
    ]


def _crests(pixels: list[tuple[float, float]]) -> int:
    """How many curls a top edge shows: the runs that reach its highest row.

    A run is broken by a column with nothing in it, and a column is a whole
    raster pixel — `PITCH` design units — so a crest is not counted once per
    pixel of itself.
    """
    profile: dict[float, float] = {}
    for x, y in pixels:
        profile[x] = min(y, profile.get(x, y))
    peak = min(profile.values())
    columns = sorted(x for x, y in profile.items() if y <= peak + CREST_BAND)
    return 1 + sum(1 for near, far in zip(columns, columns[1:]) if far - near > PITCH)


class Combed(unittest.TestCase):
    """A style drawn on a bare canvas, which is where a tone is still itself."""

    def drawn(self, style: str, **kwargs) -> Canvas:
        cell = blank_cell()
        kwargs.setdefault("skin", SKIN)
        hair.draw(cell, SKULL, style, MANE, **kwargs)
        return cell


class EveryStyleDraws(Combed):
    def test_every_combed_style_puts_hair_on_the_head(self):
        for style in COMBED:
            with self.subTest(style=style):
                self.assertGreater(opaque_count(self.drawn(style)), 0)

    def test_a_style_the_table_does_not_hold_raises(self):
        for call in (hair.draw, hair.front):
            with self.subTest(call=call.__name__), self.assertRaises(KeyError):
                call(blank_cell(), SKULL, "mohawk", MANE, skin=SKIN)
        with self.assertRaises(KeyError):
            hair.back(blank_cell(), SKULL, "mohawk", MANE)

    def test_the_mass_is_drawn_in_two_halves_that_add_up_to_the_whole(self):
        behind, over = blank_cell(), blank_cell()
        hair.back(behind, SKULL, "ponytail", MANE)
        hair.front(over, SKULL, "ponytail", MANE, skin=SKIN)
        self.assertGreater(opaque_count(behind), 0)
        self.assertGreater(opaque_count(over), 0)
        self.assertEqual(
            opaque_count(self.drawn("ponytail")),
            opaque_count(_composed(behind, over)),
        )


def _composed(behind: Canvas, over: Canvas) -> Canvas:
    behind.compose(over)
    return behind


class TheMassTakesOneLitLobe(Combed):
    """One flat shape where the key lands, and it stays a highlight."""

    def test_every_combed_style_carries_a_lit_lobe(self):
        for style in COMBED:
            with self.subTest(style=style):
                self.assertGreater(area_of(self.drawn(style), MANE.lit), 0)

    def test_the_lobe_is_a_quarter_of_the_mass_at_most(self):
        for style in COMBED:
            with self.subTest(style=style):
                cell = self.drawn(style)
                share = area_of(cell, MANE.lit) / opaque_count(cell)
                self.assertLessEqual(share, LOBE_SHARE)

    def test_the_lobe_is_one_shape_and_not_a_row_of_them(self):
        # The awning this replaced was N clusters, so "one" is the claim.
        for style in COMBED:
            with self.subTest(style=style):
                self.assertEqual(_regions(_pixels_of(self.drawn(style), MANE.lit)), 1)

    def test_the_crown_is_one_tone_under_the_one_lit_shape(self):
        # Two hair tones over the head and no more: a mass and the key on it.
        # The clusters took a band each, which is what striped every crown. The
        # fringe's own band is the wearer's skin, not a third hair tone.
        for style in COMBED:
            with self.subTest(style=style):
                cell = blank_cell()
                hair.front(cell, SKULL, style, MANE, skin=SKIN)
                mass = MANE.band(hair.mass_band(style, MANE, SKIN))
                self.assertEqual(colours(cell) - {INK, SKIN.shade}, {mass, MANE.lit})

    def test_the_lobe_sits_on_the_side_the_key_is_fixed_to(self):
        # The light never moves, so the lobe belongs to the left of the mass on
        # every style, mirrored or not.
        cell = self.drawn("long")
        columns = [x for x, _ in _pixels_of(cell, MANE.lit)]
        self.assertLess(max(columns), cell.image.width / 2)

    def test_a_pale_mass_takes_no_lobe_at_all(self):
        # Over the pale line the lit band is a step off the base, so the lobe
        # stops separating the mass and starts cutting a seam through it.
        self.assertGreater(palette.luminance(PLATINUM.base), hair.PALE_HAIR)
        for style in COMBED:
            with self.subTest(style=style):
                cell = blank_cell()
                hair.draw(cell, SKULL, style, PLATINUM, skin=SKIN)
                self.assertGreater(opaque_count(cell), 0)
                self.assertEqual(area_of(cell, PLATINUM.lit), 0)


class TheCloudSitsLowAndBroad(Combed):
    """`curly` is one broad cloud of curls rather than a stack of them.

    Three reviews read the four ink-ringed blobs it used to carry as a
    barrister's wig, so what is measured here is the silhouette they were
    replaced by: it covers the crown, it spreads past the skull, it stops at
    the ear, and its top edge shows the curls the dial names and no more.
    """

    def cloud(self) -> list[tuple[float, float]]:
        return _silhouette(self.drawn("curly"))

    def test_the_cloud_covers_the_crown(self):
        # A crest under the crown line bares the top of the head, which reads
        # as bald rather than as low.
        self.assertLessEqual(min(y for _, y in self.cloud()), TOP)

    def test_the_cloud_spreads_wider_than_the_skull_it_sits_on(self):
        xs = [x for x, _ in self.cloud()]
        self.assertAlmostEqual(
            max(xs) - min(xs), (RIGHT - LEFT) * hair.CLOUD_WIDTH, delta=INK_SLACK
        )

    def test_the_cloud_falls_no_further_than_the_ear(self):
        self.assertAlmostEqual(
            max(y for _, y in self.cloud()),
            TOP + (BOTTOM - TOP) * hair.CLOUD_FOOT,
            delta=INK_SLACK,
        )

    def test_the_top_edge_shows_the_curls_the_dial_names(self):
        self.assertEqual(_crests(self.cloud()), hair.CLOUD_LOBES)


class TheBobHemsInAnArc(Combed):
    """`bob` is painted a band down its ramp and ends at the chin.

    Platinum's base and a pale face are one value, so the mass takes the shade
    band — the contrast floor is met without renaming the colour. The hem is
    an arc for the other half of the same reading: two square corners at the
    jaw are a curtain, not a bob.
    """

    def test_the_mass_takes_the_band_under_its_own_base(self):
        cell = self.drawn("bob")
        self.assertEqual(hair.declared_band("bob"), "shade")
        self.assertGreater(area_of(cell, MANE.shade), 0)
        self.assertEqual(area_of(cell, MANE.base), 0)

    def test_the_hem_falls_to_the_chin(self):
        self.assertAlmostEqual(
            max(y for _, y in _silhouette(self.drawn("bob"))),
            TOP + (BOTTOM - TOP) * hair.BOB_HEM,
            delta=INK_SLACK,
        )

    def test_the_hems_own_corners_are_rounded_off(self):
        fall = [(x, y) for x, y in _silhouette(self.drawn("bob")) if y > BOTTOM - 60]
        bottom = max(y for _, y in fall)
        hem = [x for x, y in fall if y >= bottom - CREST_BAND]
        self.assertGreater(min(hem), min(x for x, _ in fall) + INK_SLACK)
        self.assertLess(max(hem), max(x for x, _ in fall) - INK_SLACK)


class TheFringeShadesTheForehead(Combed):
    def test_the_band_is_painted_in_the_wearers_own_skin(self):
        # The same style on two faces: each casts its own skin's shade tone and
        # neither casts the other's.
        self.assertNotEqual(SKIN.shade, DARK_SKIN.shade)
        pale, dark = self.drawn("bob"), self.drawn("bob", skin=DARK_SKIN)
        self.assertGreater(area_of(pale, SKIN.shade), 0)
        self.assertEqual(area_of(pale, DARK_SKIN.shade), 0)
        self.assertGreater(area_of(dark, DARK_SKIN.shade), 0)
        self.assertEqual(area_of(dark, SKIN.shade), 0)

    def test_a_scalp_has_no_fringe_to_cast_one(self):
        self.assertEqual(area_of(self.drawn("bald", skin=SKIN), SKIN.shade), 0)

    def test_a_scalp_draws_no_fringe_pixels_of_its_own(self):
        # The two temple wisps this style used to carry read as horns on the
        # crown, so a bald head is a bald head.
        self.assertEqual(opaque_count(self.drawn("bald", skin=SKIN)), 0)


class HairIsPaintedInNamedTones(Combed):
    def test_no_tone_reaches_the_canvas_that_was_not_named(self):
        for style in sorted(hair.STYLES):
            with self.subTest(style=style):
                self.assertEqual(colours(self.drawn(style)) - NAMED, set())

    def test_a_style_stays_inside_the_colour_budget(self):
        for style in sorted(hair.STYLES):
            with self.subTest(style=style):
                self.assertLessEqual(len(colours(self.drawn(style))), 48)


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

    def test_steel_stays_the_rung_of_grey_it_was_forked_to_be(self):
        # `steel` exists only because grey over a pale face sat on the contrast
        # floor, so it is worth nothing unless it stays a band below grey.
        self.assertLessEqual(
            hair.HAIR_BASES["steel"][0], hair.HAIR_BASES["grey"][0] - 20
        )

    def test_a_colour_the_table_does_not_hold_raises(self):
        with self.assertRaises(KeyError):
            hair.ramp_for("chartreuse")


if __name__ == "__main__":
    unittest.main()
