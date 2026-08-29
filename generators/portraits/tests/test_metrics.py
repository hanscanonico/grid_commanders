"""The style brief's bars, as measurements over the sheet the generator emits.

Each test is one numbered item of the brief — a metric (M) or a checklist line
(C) — and it is measured off `bust.paint`, the same call `pipeline.py` bakes the
committed PNGs with, so a bar that passes here passes on the art the game loads.
Nothing here is a taste judgement: the items the brief marks as a human read
(M5's legibility score, C16's no-regression) are for the review page, not for a
suite.

The busts are rendered once and kept, because six of these bars read the same
twenty-three rasters.
"""

from __future__ import annotations

import itertools
import unittest
from collections import Counter
from functools import lru_cache

from PIL import Image, ImageChops

from portraitgen import bust, features, head, light, roster, uniform
from portraitgen.canvas import PORTRAIT_SIZE, Canvas

# M2/C5: a value band is a luminance covering this much of the figure, and a
# bust owes four of them — base, shade, deep and lit.
VALUE_BANDS = 4
BAND_COVERAGE = 0.02

# M4/C4: the flat tones a raster is painted in, which is what the bar was
# written for. The 3x box downsample blends across every edge it smooths, so a
# raster carries a few hundred values whatever it is painted in; a tone is a
# colour that covers at least a thousandth of it. Raw uniques are reported by
# `test_the_raw_unique_count_is_recorded`, never gated.
MAX_TONES = 48
TONE_COVERAGE = 0.001

# M1/C9: silhouettes of the face crop at chip size, over all 253 pairs. One
# pair is over the ceiling and it is named rather than rounded away: Orlov and
# Ferrow are two buzz-cut square jaws with no headwear between them, which is a
# roster retune (a `head`, `style` or `acc` column) and not this slice's — the
# table is a transcription here. The gate is that no *other* pair joins them.
CHIP = 28
MAX_IOU = 0.90
MEAN_IOU = 0.78
OVER_THE_CEILING = (("cass_orlov", "dane_ferrow"),)

# C10: the sheet's collar budget — line officers V, staff mandarin, veterans
# double — and the four costliest powers wear the stud.
V_COLLAR_CAP = 11

# C11: no chest treatment on more than two of twenty-two.
CHEST_CAP = 2

# M8/C15: what a prop may not cross, and the raster it may not leave.
BLEED_PX = 4

# A pixel this dark is ink or something drawn in it (C13 counts dark area).
DARK_LUMINANCE = 100
OPAQUE = 128

FACE_CROP = (16, 25, 206, 215)


def _luminance(pixel: tuple[int, ...]) -> float:
    return 0.2126 * pixel[0] + 0.7152 * pixel[1] + 0.0722 * pixel[2]


def _specs() -> list[tuple[str, object]]:
    return [*sorted(roster.FACES.items()), (roster.NEUTRAL_ID, roster.NEUTRAL)]


@lru_cache(maxsize=None)
def _painted(key: str, *, cast: bool = True) -> Image.Image:
    spec = roster.NEUTRAL if key == roster.NEUTRAL_ID else roster.FACES[key]
    return bust.paint(spec, cast=cast)


@lru_cache(maxsize=None)
def _figure(key: str) -> Image.Image:
    """Where the bust differs from its own window: its silhouette."""
    spec = roster.NEUTRAL if key == roster.NEUTRAL_ID else roster.FACES[key]
    difference = ImageChops.difference(_painted(key, cast=False), bust.window(spec))
    return difference.convert("L").point(lambda level: 255 if level else 0)


def _colours(image: Image.Image) -> list[tuple[int, tuple[int, ...]]]:
    counted = image.getcolors(1 << 20)
    assert counted is not None, "the raster carries more colours than a sheet can"
    return counted


def _tones(image: Image.Image) -> list[tuple[int, ...]]:
    counted = _colours(image)
    floor = TONE_COVERAGE * sum(count for count, _ in counted)
    return [colour for count, colour in counted if count >= floor]


def _dark_area(paint) -> int:
    layer = Canvas()
    paint(layer)
    return sum(
        count
        for count, colour in _colours(layer.resolve())
        if colour[3] >= OPAQUE and _luminance(colour) <= DARK_LUMINANCE
    )


def _chip(key: str) -> list[int]:
    mask = _figure(key).crop(FACE_CROP).resize((CHIP, CHIP), Image.Resampling.BOX)
    return [1 if level >= 128 else 0 for level in mask.get_flattened_data()]


def _iou(first: list[int], second: list[int]) -> float:
    over = sum(1 for a, b in zip(first, second) if a and b)
    union = sum(1 for a, b in zip(first, second) if a or b)
    return over / union if union else 1.0


class TheRasterIsWhatTheGamePins(unittest.TestCase):
    """M8, first half: the bake fails loudly on a size mismatch, so it is held
    here before it can reach the engine."""

    def test_every_bust_is_the_pinned_raster(self):
        for key, _ in _specs():
            with self.subTest(commander=key):
                self.assertEqual(_painted(key).size, PORTRAIT_SIZE)


class TheShadowIsDrawn(unittest.TestCase):
    """M3/C1: the shadow the review asked for twice and never got. One command,
    on all twenty-three: what changes when it is switched off, and where."""

    def test_the_cast_shadow_lands_outside_every_silhouette(self):
        for key, _ in _specs():
            with self.subTest(commander=key):
                changed = ImageChops.difference(
                    _painted(key), _painted(key, cast=False)
                ).convert("L")
                outside = ImageChops.multiply(
                    changed.point(lambda level: 255 if level else 0),
                    _figure(key).point(lambda level: 255 - level),
                )
                self.assertIsNotNone(outside.getbbox())


class FourValueBands(unittest.TestCase):
    """M2/C5: a fill and one darkened copy of it is two bands; this sheet is
    painted in four."""

    def test_every_bust_carries_four_bands_inside_its_silhouette(self):
        for key, _ in _specs():
            with self.subTest(commander=key):
                inside = Image.composite(
                    _painted(key),
                    Image.new("RGBA", PORTRAIT_SIZE, (0, 0, 0, 0)),
                    _figure(key),
                )
                histogram: Counter[int] = Counter()
                for count, colour in _colours(inside):
                    if colour[3]:
                        histogram[round(_luminance(colour))] += count
                total = sum(histogram.values())
                bands = [v for v in histogram.values() if v >= BAND_COVERAGE * total]
                self.assertGreaterEqual(len(bands), VALUE_BANDS)


class ThePaletteIsBounded(unittest.TestCase):
    """M4/C4: the tones a raster is painted in, against the brief's forty-eight."""

    def test_no_bust_is_painted_in_more_than_forty_eight_tones(self):
        for key, _ in _specs():
            with self.subTest(commander=key):
                self.assertLessEqual(len(_tones(_painted(key))), MAX_TONES)

    def test_the_raw_unique_count_is_recorded(self):
        """Not a bar — the shipped sheet ran 528 to 2,877 and the number is
        worth having in the log, so it is printed. What is gated is the tone
        count above."""
        counts = {key: len(_colours(_painted(key))) for key, _ in _specs()}
        self.assertEqual(len(counts), len(roster.FACES) + 1)
        low, high = min(counts, key=counts.get), max(counts, key=counts.get)
        print(
            f"raw unique RGBA per raster: {counts[low]} ({low}) "
            f"to {counts[high]} ({high})"
        )


class OneLightOnEveryFace(unittest.TestCase):
    """M7/C6: the key side of a face outreads the shadow side on all twenty-two,
    including the five the pose mirrors — a mirror turns geometry, not light.

    The eye band is left out for the reason the brief gives: an eyepatch is a
    black rectangle over one third and it broke this gate before."""

    EYE_BAND = (0.35, 0.62)

    def _skin(self, key: str, face) -> list[tuple[int, int, tuple[int, ...]]]:
        ramp = head.ramp_for(face.skin)
        tones = (ramp.deep, ramp.shade, ramp.base, ramp.lit)
        crop = _painted(key).crop(FACE_CROP)
        pixels = crop.load()
        width, height = crop.size
        return [
            (x, y, pixels[x, y])
            for y in range(height)
            for x in range(width)
            if pixels[x, y][3] >= 204
            and any(
                max(abs(pixels[x, y][i] - tone[i]) for i in range(3)) <= 14
                for tone in tones
            )
        ]

    def test_the_key_side_of_every_face_is_the_lighter_one(self):
        for key, face in sorted(roster.FACES.items()):
            with self.subTest(commander=key):
                skin = self._skin(key, face)
                xs = [x for x, _, _ in skin]
                ys = [y for _, y, _ in skin]
                third = (max(xs) - min(xs)) // 3
                low = min(ys) + self.EYE_BAND[0] * (max(ys) - min(ys))
                high = min(ys) + self.EYE_BAND[1] * (max(ys) - min(ys))

                def mean(x0: float, x1: float) -> float:
                    band = [
                        _luminance(pixel)
                        for x, y, pixel in skin
                        if x0 <= x < x1 and not low <= y <= high
                    ]
                    return sum(band) / len(band)

                self.assertGreater(
                    mean(min(xs), min(xs) + third), mean(max(xs) - third, max(xs))
                )


class NoFaceWearsAHalfMask(unittest.TestCase):
    """C7/C8: the face shade is a shape on a cheek, not one step down the
    nose-mouth axis.

    Read off the pixels rather than off `_SHADE_SHAPES`, because the shade a
    face ends up wearing is the polygon clipped by its own skull and then drawn
    over by hair, a brow and a nose. A column of the skull box counts as shaded
    when `SHADED_COLUMN` of its skin is shade or deep; the mask is a half mask
    when those columns are all on one side of the centre line, the side's inner
    column sits within `MIDLINE_CLEARANCE` of it, and it owns more than
    `SHADE_SHARE_CAP` of the band. The eye band is left out for the reason
    `OneLightOnEveryFace` leaves it out.
    """

    SHADED_COLUMN = 0.30
    SHADE_SHARE_CAP = 0.32
    MIDLINE_CLEARANCE = 0.35
    ONE_SIDED = 0.9
    EYE_BAND = (0.35, 0.62)
    COLUMN_FLOOR = 4

    def _shaded_columns(self, key: str, face) -> tuple[dict[int, float], float, float]:
        ramp = head.ramp_for(face.skin)
        dark = (ramp.deep, ramp.shade)
        tones = (*dark, ramp.base, ramp.lit)
        pixels = _painted(key).load()
        centre, half, top, height = head.skull_box(face.head)
        low = top + self.EYE_BAND[0] * height
        high = top + self.EYE_BAND[1] * height
        shares: dict[int, float] = {}
        for x in range(round(centre - half), round(centre + half) + 1):
            skin = [
                next(
                    (
                        tone
                        for tone in tones
                        if max(abs(pixels[x, y][i] - tone[i]) for i in range(3)) <= 14
                    ),
                    None,
                )
                for y in range(round(top), round(top + height) + 1)
                if not low <= y <= high and pixels[x, y][3] >= 204
            ]
            band = [tone for tone in skin if tone is not None]
            if len(band) >= self.COLUMN_FLOOR:
                shares[x] = sum(tone in dark for tone in band) / len(band)
        return shares, centre, half

    def test_no_shade_is_one_sided_against_the_centre_line(self):
        for key, face in sorted(roster.FACES.items()):
            with self.subTest(commander=key):
                shares, centre, half = self._shaded_columns(key, face)
                shaded = [x for x, s in shares.items() if s >= self.SHADED_COLUMN]
                if not shaded:
                    continue
                side = max(
                    (
                        [x for x in shaded if x < centre],
                        [x for x in shaded if x >= centre],
                    ),
                    key=len,
                )
                one_sided = len(side) / len(shaded)
                inner = min(abs(x - centre) for x in side) / half
                share = sum(shares.values()) / len(shares)
                self.assertFalse(
                    share > self.SHADE_SHARE_CAP
                    and one_sided > self.ONE_SIDED
                    and inner < self.MIDLINE_CLEARANCE,
                    f"half mask: share {share:.2f}, one-sided {one_sided:.2f}, "
                    f"inner edge {inner:.2f} of a half-width off centre",
                )


class TheThreeShadesKeepOffTheNose(unittest.TestCase):
    """C7: each geometry ends on a horizontal run, out past the nose.

    The numbers are spelled here rather than read off `light`, so the bar the
    review set is stated in the suite and a shape moved back onto the axis
    fails rather than moving the bar with it."""

    PLACEMENT = {"centre": 110.0, "half": 46.0, "top": 82.0, "height": 124.0}
    # The terminator is a run, not a corner: this much of a half-width of it.
    MIN_RUN = 0.4
    # How far out from the centre line the nearest vertex of a shade may sit.
    INNER_CLEARANCE = 0.58

    def test_every_shape_terminates_horizontally_at_its_own_height(self):
        for kind, v in light.TERMINATORS.items():
            with self.subTest(shade=kind):
                y = self.PLACEMENT["top"] + v * self.PLACEMENT["height"]
                run = [
                    x for x, py in light.face_shade(kind, **self.PLACEMENT) if py == y
                ]
                self.assertEqual(len(run), 2)
                self.assertGreater(
                    max(run) - min(run), self.MIN_RUN * self.PLACEMENT["half"]
                )

    def test_no_shade_reaches_the_nose_mouth_axis(self):
        clearance = (
            self.PLACEMENT["centre"] + self.INNER_CLEARANCE * self.PLACEMENT["half"]
        )
        for kind in light.SHADE_KINDS:
            with self.subTest(shade=kind):
                shape = light.face_shade(kind, **self.PLACEMENT)
                self.assertGreaterEqual(min(x for x, _ in shape), clearance)

    def test_every_shape_names_a_terminator(self):
        self.assertEqual(sorted(light.TERMINATORS), sorted(light.SHADE_KINDS))


class TheSilhouettesAreDistinct(unittest.TestCase):
    """M1/C9: the squint test, as arithmetic — every pair of face crops at chip
    size, which is where twenty-three identical outlines used to show."""

    def _pairs(self) -> list[tuple[float, str, str]]:
        chips = {key: _chip(key) for key, _ in _specs()}
        return [
            (_iou(chips[a], chips[b]), a, b)
            for a, b in itertools.combinations(sorted(chips), 2)
        ]

    def test_the_sheet_holds_the_mean(self):
        pairs = self._pairs()
        self.assertLessEqual(sum(p[0] for p in pairs) / len(pairs), MEAN_IOU)

    def test_no_new_pair_crosses_the_ceiling(self):
        over = tuple(sorted((a, b) for score, a, b in self._pairs() if score > MAX_IOU))
        self.assertEqual(over, OVER_THE_CEILING)


class ThePropsStayInTheFrame(unittest.TestCase):
    """M8/C15, second half: a shoulder may bleed off the side; a signature prop
    may not be cut in half by the raster edge."""

    def test_every_prop_keeps_the_bleed_inside_the_raster(self):
        limit = PORTRAIT_SIZE[0] - BLEED_PX
        for key, face in sorted(roster.FACES.items()):
            with self.subTest(commander=key, prop=face.prop):
                box = bust.prop_art(face).getbbox()
                self.assertIsNotNone(box, "a signature prop drew nothing")
                self.assertLessEqual(box[2], limit)


class TheCostumeBudget(unittest.TestCase):
    """C10 and C11: the sheet wears three collar cuts and twelve chest
    treatments, and neither column may collapse onto one row's copy."""

    def test_the_v_collar_is_worn_by_no_more_than_eleven(self):
        worn = Counter(face.collar for face in roster.FACES.values())
        self.assertLessEqual(worn["v"], V_COLLAR_CAP)

    def test_all_three_cuts_are_on_the_sheet(self):
        worn = Counter(face.collar for face in roster.FACES.values())
        self.assertEqual(sorted(worn), sorted(uniform.COLLAR_CUTS))

    def test_no_chest_treatment_is_shared_by_more_than_two(self):
        worn = Counter(face.chest for face in roster.FACES.values())
        self.assertEqual([], [c for c, n in worn.items() if n > CHEST_CAP])

    def test_every_chest_treatment_is_one_the_uniform_can_wear(self):
        for key, face in sorted(roster.FACES.items()):
            with self.subTest(commander=key):
                self.assertIn(face.chest, uniform.CHEST_TREATMENTS)


class TheMouthCannotOutrankTheEyes(unittest.TestCase):
    """C13: an open mouth that reads as a second eye socket is the regression
    the review named, so the dark area is measured rather than eyeballed.

    A shut eye is a stroke rather than an area, so the one general drawn with
    her eyes closed is not in the comparison — the rule is about a mouth
    outranking an open pair of eyes, and Quill has none to outrank."""

    def test_every_mouth_is_darker_in_less_area_than_the_pair_of_eyes(self):
        open_eyed = {
            key: face for key, face in roster.FACES.items() if face.eyes != "closed"
        }
        for key, face in sorted(open_eyed.items()):
            with self.subTest(commander=key):
                mouth = _dark_area(
                    lambda layer, f=face: features.mouth(layer, f.head, f.mouth)
                )
                eyes = _dark_area(
                    lambda layer, f=face: features.eyes(
                        layer, f.head, f.eyes, scale=f.eye
                    )
                )
                self.assertLess(mouth, eyes)


if __name__ == "__main__":
    unittest.main()
