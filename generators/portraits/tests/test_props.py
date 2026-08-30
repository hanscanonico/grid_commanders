"""The props: all twenty-two draw, all twenty-two touch, all twenty-two cast.

Contact is the check this suite exists for. A prop that floats beside the bust
was the sheet's most-repeated defect, and the fix is structural rather than
per-drawing: every prop reaches the figure through a strap, a lanyard, a cable,
a perch or a sleeve, and this measures that its alpha really does meet the
figure's. The stand-in figure is the uniform mass, which is the layer a prop is
composed against.

Meeting it is the floor, not the bar. A prop that reaches the bust through a
shape detached from the object it carries still reads as a float, so the
connector is measured too: unbroken drawing from the object down to the
contact, a plane held clear of the crop the HUD chip is cut from, and an anchor
the shoulder really passes in front of.
"""

from __future__ import annotations

import unittest

from PIL import Image, ImageChops
from test_face_region import chin_row, skin_tones

from portraitgen import bust, props, roster, uniform
from portraitgen import canvas as canvas_module
from portraitgen.canvas import Canvas
from portraitgen.light import Ramp
from portraitgen.palette import faction_by_key

FACTION = faction_by_key("meridian")
RAMP = Ramp(
    deep=(74, 24, 20),
    shade=(112, 38, 32),
    base=(158, 58, 48),
    lit=(206, 92, 76),
    rim=(238, 150, 136),
)
# The head the worn props reach for, in portrait pixels: a stand-in for the
# skull the light model draws, so a pipe or a cigar can be measured against a
# jaw before there is one.
HEAD = (54.0, 84.0, 166.0, 196.0)


def _shoulders() -> Image.Image:
    canvas = Canvas()
    uniform.draw(canvas, FACTION, uniform.COLLAR_DEFAULT, RAMP)
    return canvas.silhouette()


def _figure() -> Image.Image:
    canvas = Canvas()
    uniform.draw(canvas, FACTION, uniform.COLLAR_DEFAULT, RAMP)
    canvas.ellipse(HEAD, (*RAMP.base, 255))
    return canvas.silhouette()


def _prop(key: str, *, layer: str = "all") -> Canvas:
    canvas = Canvas()
    props.draw(canvas, key, FACTION, RAMP, layer=layer)
    return canvas


def _painted_rows(canvas: Canvas) -> set[int]:
    """Which portrait rows a layer puts ink on."""
    mask = canvas.silhouette()
    width = mask.width
    lit = mask.get_flattened_data()
    return {index // width // canvas.scale for index, value in enumerate(lit) if value}


def _area(mask: Image.Image) -> int:
    """A one-bit mask's painted area, in portrait pixels."""
    return sum(1 for value in mask.get_flattened_data() if value) // Canvas().scale ** 2


class EveryPropDraws(unittest.TestCase):
    def test_the_vocabulary_and_the_dispatch_table_are_one_set(self):
        for key in sorted(props.PROPS):
            with self.subTest(prop=key):
                self.assertIsNotNone(_prop(key).image.getbbox())

    def test_an_unknown_prop_raises_rather_than_falling_through(self):
        with self.assertRaises(KeyError):
            props.draw(Canvas(), "halberd", FACTION, RAMP)

    def test_an_unknown_layer_raises(self):
        with self.assertRaises(KeyError):
            props.draw(Canvas(), "book", FACTION, RAMP, layer="middle")


class EveryPropTouchesTheBust(unittest.TestCase):
    def test_no_prop_floats(self):
        """Silhouette against silhouette: a prop whose *shadow* is all that
        reaches the bust is exactly the float this measures."""
        figure = _figure()
        for key in sorted(props.PROPS):
            with self.subTest(prop=key):
                overlap = ImageChops.multiply(_prop(key).silhouette(), figure)
                self.assertIsNotNone(overlap.getbbox(), "the prop meets nothing")


class TheConnectorIsDrawn(unittest.TestCase):
    """Touching is not enough: the run from the object to the figure has to be
    drawn. An object hanging clear of its own strap reaches the bust through a
    detached second shape, which is the float the reviews kept naming — so the
    measure is that a prop crosses every row of its own span."""

    def test_no_prop_skips_a_row_of_its_own_span(self):
        for key in sorted(props.PROPS):
            with self.subTest(prop=key):
                painted = _painted_rows(_prop(key))
                span = range(min(painted), max(painted) + 1)
                self.assertEqual([], [row for row in span if row not in painted])


class ThePlaneRidesTheShoulder(unittest.TestCase):
    """Perrin Ash's model plane, held up beside the jaw, crossed the crop the
    HUD chip and the speech bust are cut from."""

    def test_the_prop_clears_the_face_crop_s_chin_row(self):
        face = roster.FACES["perrin_ash"]
        chin = chin_row(bust.paint(face), skin_tones(face.skin))
        top = bust.prop_art(face).getbbox()[1]
        self.assertGreater(top, chin)


class TheAnchorHangsBehindTheShoulder(unittest.TestCase):
    """Halden Marr's anchor read as a bib because none of it was occluded: an
    object the figure passes in front of has depth, one laid on the chest is a
    decal."""

    HIDDEN_PX = 500

    def test_the_shank_runs_behind_the_shoulder(self):
        behind = _prop("anchor", layer="back").silhouette()
        self.assertGreaterEqual(
            _area(ImageChops.multiply(behind, _shoulders())), self.HIDDEN_PX
        )


class TheScalesHangPlumb(unittest.TestCase):
    """Iona Vance's scales sat off to one side of the chest, which reads as an
    object laid on her rather than hung from her collar. A balance hangs plumb:
    its beam straddles the midline the collar closes on."""

    OFF_MIDLINE_PX = 6

    def test_the_beam_is_centred_on_the_bust_midline(self):
        left, _, right, _ = _prop("scales").silhouette().getbbox()
        scale = Canvas().scale
        centre = (left + right) / 2 / scale
        midline = canvas_module.PORTRAIT_SIZE[0] / 2
        self.assertLessEqual(abs(centre - midline), self.OFF_MIDLINE_PX)


class TheCigarClearsTheMouth(unittest.TestCase):
    """Cass Orlov's cigar crossed the mouth line, and a dark bar laid over a
    lip is a moustache. Every row it paints has to sit under that line, and the
    lit tip has to be the sheet's one gold."""

    def test_the_stem_starts_below_the_mouth_line(self):
        top = _prop("cigar").image.getbbox()[1] / Canvas().scale
        self.assertGreater(top, props.MOUTH_LINE)

    def test_the_tip_carries_an_ember(self):
        colours = {colour for _, colour in _prop("cigar").image.getcolors(1 << 16)}
        self.assertIn((*props.GOLD, 255), colours)


class TheHammerClearsTheTopOfTheFrame(unittest.TestCase):
    """Radek Morn's hammer head was cut flat by the first row of the portrait,
    which reads as a crop accident. It is the head's own edge that has to clear
    the frame, so this is measured on the hammer rather than on every prop:
    Ivar Thorne's axe leaves the same edge on a diagonal, which reads as an
    object continuing past the frame instead of one sliced off by it."""

    def test_the_head_stops_short_of_the_first_row(self):
        top = bust.prop_art(roster.FACES["radek_morn"]).getbbox()[1]
        self.assertGreater(top, 0)


class EveryPropCasts(unittest.TestCase):
    def test_the_shadow_lands_outside_the_prop(self):
        for key in sorted(props.PROPS):
            with self.subTest(prop=key):
                canvas = _prop(key)
                painted = canvas.image.getchannel("A")
                without = ImageChops.subtract(painted, canvas.silhouette())
                self.assertIsNotNone(without.getbbox(), "nothing changed off the prop")

    def test_the_shadow_is_one_flat_tone(self):
        canvas = _prop("book")
        colours = {colour for _, colour in canvas.image.getcolors(maxcolors=1 << 16)}
        self.assertIn(props.PROP_CAST_TONE, colours)


class ThePropsBorrowTheUniformsGold(unittest.TestCase):
    def test_there_is_one_gold_on_the_sheet(self):
        self.assertEqual(props.GOLD, uniform.GOLD)


class TheFrameIsRespected(unittest.TestCase):
    def test_a_right_breaking_prop_keeps_its_bleed(self):
        for key in sorted(props.PROPS):
            with self.subTest(prop=key):
                canvas = _prop(key)
                right = canvas.image.getbbox()[2] / canvas.scale
                self.assertLessEqual(right, props.RIGHT_LIMIT)


class AShoulderedPropIsCarried(unittest.TestCase):
    def test_the_object_is_behind_and_the_rig_is_in_front(self):
        for key in sorted(props.SHOULDERED):
            with self.subTest(prop=key):
                behind = _prop(key, layer="back").image
                in_front = _prop(key, layer="front").image
                self.assertIsNotNone(behind.getbbox())
                self.assertIsNotNone(in_front.getbbox())
                self.assertIsNotNone(ImageChops.difference(behind, in_front).getbbox())

    def test_no_two_shouldered_generals_wear_the_same_rig(self):
        rigs = {
            key: _prop(key, layer="front").image for key in sorted(props.SHOULDERED)
        }
        carried = sorted(rigs)
        for first in range(len(carried)):
            for second in range(first + 1, len(carried)):
                pair = (carried[first], carried[second])
                with self.subTest(pair=pair):
                    difference = ImageChops.difference(rigs[pair[0]], rigs[pair[1]])
                    self.assertIsNotNone(difference.getbbox())

    def test_only_a_shouldered_prop_has_a_back_layer(self):
        for key in sorted(props.PROPS - props.SHOULDERED):
            with self.subTest(prop=key):
                self.assertIsNone(_prop(key, layer="back").image.getbbox())


if __name__ == "__main__":
    unittest.main()
