"""P9: hair has to be a different value from the face it sits on.

The review's own reading — pale hair over pale skin reads as one mass at chip
size, where the ink outline between them is the first thing the coarser grid
drops. It is measured off the finished bust rather than off the two ramps,
because what a general's hair is *painted* in is the ramp clipped by a style, a
fringe and a piece of headwear, and that is what a player sees.

A floor with no exceptions list: a bust that cannot clear it is a roster retune
(a skin rung, a hair colour) and not a name in a tuple here.
"""

from __future__ import annotations

import statistics
import unittest

from cells import luminance
from painted import figure, painted
from portraitgen import hair, head, roster

# The luminance the hair mass and the skin's base band must differ by. Below
# this the two read as one shape once the chip grid drops the outline between
# them.
MIN_CONTRAST = 30.0
# How near a painted pixel must be to a named tone to count as that tone, and
# how opaque it must be to count at all — the same tolerances the other
# measurements over the sheet use.
TONE_TOLERANCE = 14
OPAQUE = 204


def _is(pixel: tuple[int, ...], tone: tuple[int, ...]) -> bool:
    return max(abs(pixel[i] - tone[i]) for i in range(3)) <= TONE_TOLERANCE


def _hair_luminance(key: str) -> float:
    """The median luminance of everything painted in the general's hair ramp."""
    ramp = hair.ramp_for(roster.FACES[key].hair)
    tones = (ramp.deep, ramp.shade, ramp.base, ramp.lit)
    image = painted(key)
    pixels = image.load()
    mask = figure(key).load()
    width, height = image.size
    mass = [
        luminance(pixels[x, y])
        for y in range(height)
        for x in range(width)
        if mask[x, y]
        and pixels[x, y][3] >= OPAQUE
        and any(_is(pixels[x, y], tone) for tone in tones)
    ]
    if not mass:
        raise AssertionError(f"{key} has no hair mass to measure")
    return statistics.median(mass)


class TheHairStandsOffTheFace(unittest.TestCase):
    """C9's problem one layer in: two shapes of one value are one shape."""

    def test_every_bust_carries_the_contrast_floor(self):
        for key, face in sorted(roster.FACES.items()):
            with self.subTest(commander=key, hair=face.hair, skin=face.skin):
                skin = luminance(head.ramp_for(face.skin).base)
                self.assertGreaterEqual(abs(_hair_luminance(key) - skin), MIN_CONTRAST)


if __name__ == "__main__":
    unittest.main()
