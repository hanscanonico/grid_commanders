"""The props: all twenty-two draw, all twenty-two touch, all twenty-two cast.

Contact is the check this suite exists for. A prop that floats beside the bust
was the sheet's most-repeated defect, and the fix is structural rather than
per-drawing: every prop reaches the figure through a strap, a lanyard, a cable,
a perch or a sleeve, and this measures that its alpha really does meet the
figure's. The stand-in figure is the uniform mass, which is the layer a prop is
composed against.
"""

from __future__ import annotations

import unittest

from PIL import Image, ImageChops

from portraitgen import props, uniform
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


def _figure() -> Image.Image:
    canvas = Canvas()
    uniform.draw(canvas, FACTION, uniform.COLLAR_DEFAULT, RAMP)
    canvas.ellipse(HEAD, (*RAMP.base, 255))
    return canvas.image.getchannel("A")


def _prop(key: str, *, layer: str = "all") -> Canvas:
    canvas = Canvas()
    props.draw(canvas, key, FACTION, RAMP, layer=layer)
    return canvas


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
        figure = _figure()
        for key in sorted(props.PROPS):
            with self.subTest(prop=key):
                overlap = ImageChops.multiply(_prop(key).image.getchannel("A"), figure)
                self.assertIsNotNone(overlap.getbbox(), "the prop meets nothing")


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
