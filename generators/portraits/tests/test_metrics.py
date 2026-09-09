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

from portraitgen import bust, features, head, light, palette, props, roster, uniform
from painted import painted, specs
from portraitgen.canvas import (
    BUST_DIVISOR,
    BUST_SIZE,
    CHIP_DIVISOR,
    Canvas,
    face_box,
)

# M2/C5: a value band is a luminance covering this much of the figure, and a
# bust owes four of them — base, shade, deep and lit.
VALUE_BANDS = 4
BAND_COVERAGE = 0.02

# M4/C4: what a bust may be painted in. Sixteen, and every one of them a rung
# `palette.bust_palette` handed out — there is no downsample any more, so a
# raster carries exactly the tones it was painted in and the bar needs no
# coverage floor under it to be readable.
MAX_TONES = palette.PAINTED_TONES

# M1/C9: silhouettes of the face crop at chip size, over all 253 pairs. The
# ceiling is a plain one — a measured failure is a roster retune, not a named
# exception — and the pair that used to carry one, Orlov and Ferrow, was two
# buzz-cut square jaws with no headwear between them until Ferrow took a cap.
# Read off the chip the generator bakes, which is what a small surface draws.
MAX_IOU = 0.90
MEAN_IOU = 0.78

# C10: the sheet's collar budget — line officers V, staff mandarin, veterans
# double — and the four costliest powers wear the stud.
V_COLLAR_CAP = 11

# C11: no chest treatment on more than two of twenty-two.
CHEST_CAP = 2

# M8/C15: the raster a prop may not leave, on the bust's own grid — the bleed
# line `props` states in design units, where the rasteriser puts it.

# A pixel this dark is ink or something drawn in it (C13 counts dark area).
DARK_LUMINANCE = 100
OPAQUE = 128

FACE_CROP = face_box(BUST_DIVISOR)


def _luminance(pixel: tuple[int, ...]) -> float:
    return 0.2126 * pixel[0] + 0.7152 * pixel[1] + 0.0722 * pixel[2]


@lru_cache(maxsize=None)
def _figure(key: str) -> Image.Image:
    """Where the bust differs from its own window: its silhouette."""
    spec = roster.NEUTRAL if key == roster.NEUTRAL_ID else roster.FACES[key]
    difference = ImageChops.difference(painted(key, cast=False), bust.window(spec))
    return difference.convert("L").point(lambda level: 255 if level else 0)


def _colours(image: Image.Image) -> list[tuple[int, tuple[int, ...]]]:
    counted = image.getcolors(1 << 20)
    assert counted is not None, "the raster carries more colours than a sheet can"
    return counted


def _tones(image: Image.Image) -> list[tuple[int, ...]]:
    """The opaque tones a raster is painted in. What is not opaque is the one
    cast-shadow tone, which is a shadow rather than paint."""
    return [colour[:3] for _, colour in _colours(image) if colour[3] == 255]


def _dark_area(paint) -> int:
    layer = Canvas()
    paint(layer)
    return sum(
        count
        for count, colour in _colours(layer.resolve())
        if colour[3] >= OPAQUE and _luminance(colour) <= DARK_LUMINANCE
    )


def _chip(key: str) -> list[int]:
    """One general's silhouette at chip size, off the chip's own grid."""
    spec = roster.NEUTRAL if key == roster.NEUTRAL_ID else roster.FACES[key]
    figure = ImageChops.difference(
        bust.paint(spec, cast=False, divisor=CHIP_DIVISOR),
        bust.window(spec, divisor=CHIP_DIVISOR),
    )
    mask = figure.convert("L").crop(face_box(CHIP_DIVISOR))
    return [1 if level else 0 for level in mask.get_flattened_data()]


def _iou(first: list[int], second: list[int]) -> float:
    over = sum(1 for a, b in zip(first, second) if a and b)
    union = sum(1 for a, b in zip(first, second) if a or b)
    return over / union if union else 1.0


class TheRasterIsWhatTheGamePins(unittest.TestCase):
    """M8, first half: the bake fails loudly on a size mismatch, so it is held
    here before it can reach the engine."""

    def test_every_bust_is_the_pinned_raster(self):
        for key, _ in specs():
            with self.subTest(commander=key):
                self.assertEqual(painted(key).size, BUST_SIZE)


class TheShadowIsDrawn(unittest.TestCase):
    """M3/C1: the shadow the review asked for twice and never got. One command,
    on all twenty-three: what changes when it is switched off, and where."""

    def test_the_cast_shadow_lands_outside_every_silhouette(self):
        for key, _ in specs():
            with self.subTest(commander=key):
                changed = ImageChops.difference(
                    painted(key), painted(key, cast=False)
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
        for key, _ in specs():
            with self.subTest(commander=key):
                inside = Image.composite(
                    painted(key),
                    Image.new("RGBA", BUST_SIZE, (0, 0, 0, 0)),
                    _figure(key),
                )
                histogram: Counter[int] = Counter()
                for count, colour in _colours(inside):
                    if colour[3]:
                        histogram[round(_luminance(colour))] += count
                total = sum(histogram.values())
                bands = [v for v in histogram.values() if v >= BAND_COVERAGE * total]
                self.assertGreaterEqual(len(bands), VALUE_BANDS)


class ThePaletteIsSpentPerMaterial(unittest.TestCase):
    """What the sixteen buy, material by material — the measured half of the
    README's style bar.

    The light model hands every material four bands (`light.Ramp`), but a bust
    cannot afford four of each: skin takes four rungs and the army six, which
    leaves three for hair and two for gunmetal. So the four-tone rule is the
    model's, not the emitted PNG's, and this is where that is stated in numbers
    rather than in prose — a slot added to one material has to come out of
    another, and `bust_palette` raises if the sixteen stop adding up.
    """

    BUDGET = {"skin": 4, "hair": 3, "metal": 2}

    def test_the_sixteen_are_the_ink_the_army_and_the_three_materials(self):
        spent = 1 + len(palette.faction_ramp("meridian")) + sum(self.BUDGET.values())
        self.assertEqual(spent, palette.PAINTED_TONES)

    def test_each_material_gets_the_rungs_the_budget_names(self):
        for material, slots in (
            ("skin", palette.SKIN_SLOTS),
            ("hair", palette.HAIR_SLOTS),
            ("metal", palette.METAL_SLOTS),
        ):
            with self.subTest(material=material):
                self.assertEqual(len(set(slots)), self.BUDGET[material])


class ThePaletteIsBounded(unittest.TestCase):
    """M4/C4: the tones a raster is painted in, against the brief's forty-eight."""

    def test_no_bust_is_painted_in_more_than_sixteen_tones(self):
        for key, _ in specs():
            with self.subTest(commander=key):
                self.assertLessEqual(len(_tones(painted(key))), MAX_TONES)

    def test_every_tone_is_one_the_bust_was_given(self):
        """The harder half: not "few colours" but "these colours". A pixel that
        is not a rung of this bust's own palette is a blend, and there is
        nowhere left in the pipeline for one to come from."""
        for key, spec in specs():
            with self.subTest(commander=key):
                allowed = set(bust.palette_of(spec))
                self.assertEqual(set(_tones(painted(key))) - allowed, set())

    def test_the_shadow_is_the_one_tone_that_is_neither_paint_nor_nothing(self):
        for key, _ in specs():
            with self.subTest(commander=key):
                partial = {
                    colour
                    for _, colour in _colours(painted(key))
                    if 0 < colour[3] < 255
                }
                self.assertLessEqual(len(partial), 1)


class OneLightOnEveryFace(unittest.TestCase):
    """M7/C6: the sheet is lit from one corner on all twenty-three, the five
    the pose mirrors included — a mirror turns geometry, not light.

    Read off the COAT rather than off the cheek, which is where this used to
    read it. A bust is snapped onto sixteen tones now, so a scar, a strap or a
    prop lands on the very rung a cheek is painted in and a face-wide average
    measures the general's accessories as much as the sun. The two shoulders
    are the one surface every general wears unbroken, they are exact mirrors of
    each other about the bust's centre line, and they are the patches
    `tests/unit/test_commander_portraits.gd` reads off the shipped PNGs — so
    this is that gate, per run, before the art is installed.
    """

    # The GUT suite's own two patches and floor, on the bust's own grid.
    LIT_PATCH = (11, 121, 6, 6)
    SHADED_PATCH = (93, 121, 6, 6)
    FLOOR = 2.55

    def _patch(self, key: str, patch: tuple[int, int, int, int]) -> float:
        x, y, width, height = patch
        pixels = painted(key).load()
        values = sorted(
            _luminance(pixels[column, row])
            for row in range(y, y + height)
            for column in range(x, x + width)
        )
        half = len(values) // 2
        return 0.5 * (values[half - 1] + values[half])

    def test_the_key_side_of_every_bust_is_the_lighter_one(self):
        for key, _ in specs():
            with self.subTest(commander=key):
                lit = self._patch(key, self.LIT_PATCH)
                away = self._patch(key, self.SHADED_PATCH)
                self.assertGreater(lit - away, self.FLOOR)


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

    It is a ceiling, not the fix's own proof: the geometry this replaced also
    cleared it, by 0.01 on its worst face. `TheThreeShadesKeepOffTheNose` is
    what fails when a shape moves back onto the axis.
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
        pixels = painted(key).load()
        centre, half, top, height = (
            value / BUST_DIVISOR for value in head.skull_box(face.head)
        )
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
        chips = {key: _chip(key) for key, _ in specs()}
        return [
            (_iou(chips[a], chips[b]), a, b)
            for a, b in itertools.combinations(sorted(chips), 2)
        ]

    def test_the_sheet_holds_the_mean(self):
        pairs = self._pairs()
        self.assertLessEqual(sum(p[0] for p in pairs) / len(pairs), MEAN_IOU)

    def test_no_pair_crosses_the_ceiling(self):
        over = sorted(
            (round(score, 3), a, b) for score, a, b in self._pairs() if score > MAX_IOU
        )
        self.assertEqual([], over)


class ThePropsStayInTheFrame(unittest.TestCase):
    """M8/C15, second half: a shoulder may bleed off the side; a signature prop
    may not be cut in half by the raster edge."""

    def test_every_prop_keeps_the_bleed_inside_the_raster(self):
        limit = props.RIGHT_LIMIT / BUST_DIVISOR
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
                    lambda layer, f=face: features.mouth(
                        layer, f.head, f.mouth, eye=f.eye
                    )
                )
                eyes = _dark_area(
                    lambda layer, f=face: features.eyes(
                        layer, f.head, f.eyes, scale=f.eye
                    )
                )
                self.assertLess(mouth, eyes)


if __name__ == "__main__":
    unittest.main()
