"""What the light model and the head module owe: size, one sun, four bands.

Everything here is measured off `preview_sheet.bust`, the stand-in a reviewer
looks at, so the picture the suite holds to the bar is the picture a human saw.
The roster, the uniform, the hair and the features are other slices'; a
stand-in is a skull, a neck, a shoulder block and a flat field.

The light checks are the shipped sheet's own. `test_commander_portraits.gd`
measures one patch on the lit shoulder against one on the shaded shoulder and
demands a floor between them; the same two rectangles and the same floor are
read here, in Python, off the same 220x268 raster — which is what keeps "every
bust is lit from the sheet's side" one claim rather than two.

Colours are counted with `getcolors`, never `getdata`: the dependency pin's
ceiling is the release that removes `getdata`.
"""

from __future__ import annotations

import dataclasses
import unittest

from PIL import Image, ImageChops
from preview_sheet import FIELD, ROW, SKIN, bust

from portraitgen import head, light
from portraitgen.canvas import PORTRAIT_SIZE, Canvas
from portraitgen.palette import faction_by_key

# tests/unit/test_commander_portraits.gd's own patches and floor: the widest
# margin the shoulders offer, and a bar a sheet with no shade at all fails.
LIT_PATCH = (22, 242, 12, 12)
SHADED_PATCH = (186, 242, 12, 12)
SHADE_FLOOR = 0.01

# The style brief's palette bar (M4/C4). It counts the flat tones a raster is
# painted in, so the measure is a colour's coverage: the 3x box downsample
# blends across every edge it smooths, and an edge blend is not a tone.
MAX_TONES = 48
TONE_COVERAGE = 0.001

_ALL_COLOURS = 1 << 20


def _colours(image: Image.Image) -> list[tuple[int, tuple[int, ...]]]:
    counted = image.getcolors(_ALL_COLOURS)
    assert counted is not None, "the raster carries more colours than a sheet can"
    return counted


def _luminance(pixel: tuple[int, ...]) -> float:
    """Godot's `Color.get_luminance`, which is what the GUT test reads."""
    red, green, blue = (channel / 255.0 for channel in pixel[:3])
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def _mean_luminance(image: Image.Image, patch: tuple[int, int, int, int]) -> float:
    x, y, width, height = patch
    counted = _colours(image.crop((x, y, x + width, y + height)))
    total = sum(count * _luminance(colour) for count, colour in counted)
    return total / float(sum(count for count, _ in counted))


def _skin_ramp() -> light.Ramp:
    return light.build_ramp(SKIN, rim_hue=faction_by_key("meridian").body_lt)


def _tones(ramp: light.Ramp) -> set[tuple[int, ...]]:
    return {(*tone, 255) for tone in dataclasses.astuple(ramp)}


def _skull_box(skull: head.Skull) -> tuple[int, int, int, int]:
    points = head.outline(skull)
    xs, ys = [x for x, _ in points], [y for _, y in points]
    return (int(min(xs)), int(min(ys)), int(max(xs)), int(max(ys)))


class TheRasterIsThePinnedOne(unittest.TestCase):
    def test_a_bust_resolves_to_the_portrait_size(self):
        self.assertEqual(bust(ROW[0][1]).size, PORTRAIT_SIZE)
        self.assertEqual(PORTRAIT_SIZE, (220, 268))

    def test_a_head_covers_a_head_s_worth_of_the_frame(self):
        for name, skull in ROW:
            with self.subTest(skull=name):
                layer = Canvas()
                head.draw(layer, skull, _skin_ramp())
                opaque = sum(
                    count for count, level in _colours(layer.silhouette()) if level
                )
                share = opaque / float(PORTRAIT_SIZE[0] * PORTRAIT_SIZE[1] * 9)
                self.assertGreater(share, 0.05)
                self.assertLess(share, 0.30)


class OneSun(unittest.TestCase):
    """The sheet is lit from one corner and a pose never turns the light."""

    def test_the_lit_shoulder_outreads_the_shaded_one(self):
        for name, skull in ROW:
            with self.subTest(skull=name):
                image = bust(skull)
                delta = _mean_luminance(image, LIT_PATCH) - _mean_luminance(
                    image, SHADED_PATCH
                )
                self.assertGreater(delta, SHADE_FLOOR)

    def test_the_face_is_lighter_on_the_key_side(self):
        """C6: skin-only left third against right third, same sign on each."""
        tones = _tones(_skin_ramp())
        for name, skull in ROW:
            with self.subTest(skull=name):
                left, top, right, bottom = _skull_box(skull)
                third = (right - left) // 3
                image = bust(skull)
                bands = [
                    _skin_luminance(image.crop((x0, top, x1, bottom)), tones)
                    for x0, x1 in ((left, left + third), (right - third, right))
                ]
                self.assertGreater(bands[0], bands[1])

    def test_the_cast_shadow_changes_pixels_outside_the_silhouette(self):
        """C1: the shadow is drawn, and it lands on the field, not on the bust."""
        for name, skull in ROW:
            with self.subTest(skull=name):
                shadowed, bare = bust(skull), bust(skull, cast=False)
                changed = _nonzero(ImageChops.difference(shadowed, bare))
                bare_field = Image.new("RGBA", bare.size, (*FIELD, 255))
                outside = _nonzero(ImageChops.difference(bare, bare_field), invert=True)
                landed = ImageChops.multiply(changed, outside)
                self.assertGreater(landed.getextrema()[1], 0)


def _nonzero(image: Image.Image, *, invert: bool = False) -> Image.Image:
    """A difference image as a one-bit mask — where it differs, or where it
    does not."""
    hit, miss = (0, 255) if invert else (255, 0)
    return image.convert("L").point(lambda level: hit if level else miss)


def _skin_luminance(patch: Image.Image, tones: set[tuple[int, ...]]) -> float:
    counted = [(n, c) for n, c in _colours(patch) if c in tones]
    return sum(n * _luminance(c) for n, c in counted) / float(
        sum(n for n, _ in counted)
    )


class FourFlatBands(unittest.TestCase):
    def test_every_band_of_the_ramp_is_painted(self):
        ramp = _skin_ramp()
        painted = {colour: count for count, colour in _colours(bust(ROW[0][1]))}
        for band in (*light.BANDS, "rim"):
            with self.subTest(band=band):
                self.assertIn((*getattr(ramp, band), 255), painted)

    def test_the_bands_climb_in_value_and_none_of_them_repeats(self):
        ramp = _skin_ramp()
        values = [light.luminance(ramp.band(band)) for band in light.BANDS]
        self.assertEqual(values, sorted(values))
        self.assertEqual(len(set(values)), len(light.BANDS))

    def test_a_raster_is_painted_in_at_most_forty_eight_tones(self):
        for name, skull in ROW:
            with self.subTest(skull=name):
                counted = _colours(bust(skull))
                floor = TONE_COVERAGE * sum(count for count, _ in counted)
                tones = [colour for count, colour in counted if count >= floor]
                self.assertLessEqual(len(tones), MAX_TONES)


class TheVocabularyIsTheDispatchTable(unittest.TestCase):
    def test_a_jaw_outside_the_vocabulary_raises(self):
        with self.assertRaises(KeyError):
            head.Skull(1.0, "lantern", 0.0, 1.0)

    def test_a_face_shade_outside_the_vocabulary_raises(self):
        with self.assertRaises(KeyError):
            light.face_shade("cheekbone", **_PLACEMENT)

    def test_a_band_outside_the_ramp_raises(self):
        with self.assertRaises(KeyError):
            _skin_ramp().band("highlight")

    def test_every_jaw_and_every_shade_geometry_draws_something(self):
        for jaw in sorted(head.JAWS):
            with self.subTest(jaw=jaw):
                self.assertGreater(len(head.outline(head.Skull(1.0, jaw, 0.0, 1.0))), 3)
        for kind in light.SHADE_KINDS:
            with self.subTest(shade=kind):
                self.assertGreater(len(light.face_shade(kind, **_PLACEMENT)), 3)

    def test_the_three_geometries_are_the_three_a_skull_can_ask_for(self):
        asked = {
            light.shade_kind(crown, width)
            for crown in (-3.0, 0.0, 3.0)
            for width in (0.86, 1.0, 1.14)
        }
        self.assertEqual(asked, set(light.SHADE_KINDS))


_PLACEMENT = {"centre": 110.0, "half": 46.0, "top": 82.0, "height": 124.0}


class NoBoundaryDownTheNose(unittest.TestCase):
    """C8: a shade that bisects the face reads as a mask, not as a head."""

    def test_every_shade_shape_clears_the_centre_line(self):
        for kind in light.SHADE_KINDS:
            with self.subTest(shade=kind):
                shape = light.face_shade(kind, **_PLACEMENT)
                nearest = min(x for x, _ in shape)
                clearance = light.NOSE_AXIS_CLEARANCE * _PLACEMENT["half"]
                self.assertGreaterEqual(nearest, _PLACEMENT["centre"] + clearance)


if __name__ == "__main__":
    unittest.main()
