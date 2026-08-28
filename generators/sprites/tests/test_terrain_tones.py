"""The ground is lit by the same sky the armies are (docs/terrain_tones.md).

`terrain._shade` and `terrain._tone` are not decoration on top of ten literals:
they are the statement that a ground's shadow is sky-lit, that the two grounds
covering the board are off poster chroma, and that a grey has a temperature.
Typed back as literals, all three claims are invisible — so they are pinned
here, on the constants, next to the luma ladder they are not allowed to move.
"""

import colorsys
import unittest

from spritegen import palette, terrain, voxel


def hue(c) -> float:
    return colorsys.rgb_to_hsv(*[v / 255 for v in c])[0] * 360.0


def saturation(c) -> float:
    return colorsys.rgb_to_hsv(*[v / 255 for v in c])[1]


def hue_gap(a: float, b: float) -> float:
    d = abs(a - b) % 360.0
    return min(d, 360.0 - d)


SKY = hue(palette.AMBIENT)


class GroundShadowsAreSkyLit(unittest.TestCase):
    """Every _DARK is its lit tone rotated toward `palette.AMBIENT`.

    Before the 2026-08-22 pass the ten ground tones were hand-typed and the
    dark of each pair was the lit tone with the value pulled down: 2.5 degrees
    of rotation on grass, 2.8 on water, under one on sand and timber. That is
    a board lit by nothing, next to units whose every shadow rung turns into
    the sky (`RampShape.test_the_shadow_steps_sit_in_the_ambient_sky`).
    """

    # How far a chromatic ground has to turn before the turn is doing work.
    # Measured after: grass 11.1, timber 8.0, water 7.9, sand 6.0 degrees.
    MIN_SKY_PULL = 5.0
    PAIRS = (
        ("grass", "GRASS", "GRASS_DARK"),
        ("water", "WATER", "WATER_DARK"),
        ("sand", "SAND", "SAND_DARK"),
        ("timber", "TIMBER", "TIMBER_DARK"),
    )

    def test_a_chromatic_ground_turns_toward_the_sky_in_shadow(self):
        for name, lit_id, dark_id in self.PAIRS:
            lit = getattr(terrain, lit_id)
            dark = getattr(terrain, dark_id)
            with self.subTest(pair=name):
                self.assertGreaterEqual(saturation(lit), terrain._SHADE_GREY)
                pull = hue_gap(hue(lit), SKY) - hue_gap(hue(dark), SKY)
                self.assertGreaterEqual(pull, self.MIN_SKY_PULL)

    def test_a_grey_ground_takes_the_skys_own_hue_in_shadow(self):
        """Gravel sits almost opposite the sky, so it snaps rather than leans
        (`terrain._SHADE_GREY`) — a shadow on a grey may not be warmer than
        the face casting it."""
        self.assertLess(saturation(terrain.ROAD), terrain._SHADE_GREY)
        self.assertLessEqual(hue_gap(hue(terrain.ROAD_DARK), SKY), 6.0)

    def test_the_cast_shadow_is_the_sky_and_the_two_modules_agree(self):
        """`terrain.SHADOW` is AMBIENT keyed down, not a near-black literal,
        and `voxel.SHADOW` is the unit cells' copy of the same triple."""
        self.assertLessEqual(hue_gap(hue(terrain.SHADOW), SKY), 2.0)
        self.assertGreater(saturation(terrain.SHADOW), 0.25)
        self.assertEqual(terrain.SHADOW, voxel.SHADOW)
        # below any ground tone on the sheet
        self.assertLess(terrain.luminance(terrain.SHADOW), 60.0)


class GreysHaveATemperature(unittest.TestCase):
    """Rock, stone and concrete were one S0.04-0.10 neutral under both lights
    — the colour of cut card. A lit face now carries the sun's warmth and a
    shaded one is lit by AMBIENT alone."""

    MIN_LIT_CHROMA = 0.12
    MIN_SHADE_CHROMA = 0.10
    LIT = ("rock", "stone")
    SHADED = ("rock_dk", "stone_dk", "concrete_dk", "asphalt")

    def test_a_lit_grey_is_warm(self):
        for name in self.LIT:
            with self.subTest(material=name):
                c = palette.MATERIALS[name]
                self.assertGreaterEqual(saturation(c), self.MIN_LIT_CHROMA)
                self.assertLessEqual(hue(c), 70.0)  # sunward half of the wheel

    def test_a_shaded_grey_is_the_sky(self):
        for name in self.SHADED:
            with self.subTest(material=name):
                c = palette.MATERIALS[name]
                self.assertGreaterEqual(saturation(c), self.MIN_SHADE_CHROMA)
                self.assertLessEqual(hue_gap(hue(c), SKY), 8.0)

    def test_the_massif_carries_the_same_split(self):
        hi, lt, dk, deep = terrain.ROCK
        for c in (hi, lt):
            with self.subTest(face=c):
                self.assertGreaterEqual(saturation(c), self.MIN_LIT_CHROMA)
                self.assertLessEqual(hue(c), 70.0)
        for c in (dk, deep):
            with self.subTest(face=c):
                self.assertGreaterEqual(saturation(c), self.MIN_SHADE_CHROMA)
                self.assertLessEqual(hue_gap(hue(c), SKY), 8.0)


class GroundChroma(unittest.TestCase):
    """79% of a map's pixels are grass or water; at S0.60/S0.71 they were a
    poster, and left the five armies nothing to be the colourful thing on.
    Ceilings, not targets — `GroundSeparation` is the floor under them."""

    def test_the_two_grounds_that_cover_the_board_are_off_poster_chroma(self):
        self.assertLessEqual(saturation(terrain.GRASS), 0.53)
        self.assertLessEqual(saturation(terrain.WATER), 0.62)
        self.assertLessEqual(saturation(terrain.WATER_LIGHT), 0.43)


class TonesKeepTheirAuthoredValue(unittest.TestCase):
    """The whole pass is safe only because it moves hue and chroma at constant
    LUMA: every ceiling, every movement-cost step and `palette.GROUND_BAND` is
    a rule about value. This is that ladder, to a third of a luma."""

    LADDER = {
        "GRASS": 157.7,
        "GRASS_DARK": 128.4,
        "ROAD": 142.2,
        "ROAD_DARK": 111.3,
        "TIMBER": 124.0,
        "TIMBER_DARK": 93.1,
        "WATER": 131.6,
        "WATER_DARK": 102.1,
        "WATER_LIGHT": 167.9,
        "SAND": 165.7,
        "SAND_DARK": 139.0,
        "SNOW": 173.3,
        "WILDFLOWER": 166.2,
        "SHADOW": 18.0,
    }
    ROCK_LADDER = (161.5, 144.3, 113.5, 95.3)
    MATERIAL_LADDER = {
        "rock": 142.3,
        "rock_dk": 106.3,
        "stone": 154.3,
        "stone_dk": 118.3,
        "concrete": 173.8,
        "concrete_dk": 137.8,
        "asphalt": 115.5,
    }

    def test_the_ground_tones_sit_where_they_were_authored(self):
        for name, want in self.LADDER.items():
            with self.subTest(tone=name):
                got = terrain.luminance(getattr(terrain, name))
                self.assertAlmostEqual(got, want, delta=0.35)

    def test_the_massif_and_the_greys_sit_where_they_were_authored(self):
        for c, want in zip(terrain.ROCK, self.ROCK_LADDER):
            with self.subTest(face=c):
                self.assertAlmostEqual(terrain.luminance(c), want, delta=0.35)
        for name, want in self.MATERIAL_LADDER.items():
            with self.subTest(material=name):
                got = terrain.luminance(palette.MATERIALS[name])
                self.assertAlmostEqual(got, want, delta=0.45)

    def test_the_helpers_key_a_tone_onto_a_value_they_are_given(self):
        """`_tone` and `_shade` are only allowed to move hue and chroma — the
        luma is an argument, and it is hit within rounding.

        In gamut, that is: a saturated blue shaded at L166 has nowhere left to
        put the luma and lands a full step short. No tone on the sheet is
        asked for that (`test_the_ground_tones_sit_where_they_were_authored`
        is the ladder as shipped), so the probes stay under the shoal's sand.
        """
        for probe in ((108, 181, 73), (63, 143, 220), (150, 120, 87), (146, 142, 133)):
            for want in (40.0, 93.1, 128.4):
                with self.subTest(probe=probe, value=want):
                    shaded = terrain._shade(probe, want)
                    self.assertAlmostEqual(terrain.luminance(shaded), want, delta=0.6)
                    keyed = terrain._tone(probe, 0.4, want)
                    self.assertAlmostEqual(terrain.luminance(keyed), want, delta=0.6)
            with self.subTest(probe=probe, value="own"):
                self.assertAlmostEqual(
                    terrain.luminance(terrain._tone(probe, 0.3)),
                    terrain.luminance(probe),
                    delta=0.6,
                )


if __name__ == "__main__":
    unittest.main()
