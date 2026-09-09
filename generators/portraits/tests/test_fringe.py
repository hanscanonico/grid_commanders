"""The fringe rule: what a mane has to stand off, and who it moves.

`hair.mass_band` steps a style's declared rung down `hair._fallback` until the
mass stands `hair.SKIN_CONTRAST` off the skin bands it can border — the cheek in
the skin's base rung always, and the forehead the fringe lays its shade rung
across (`hair.FRINGE_BAND`) wherever the mass itself is pale. `test_contrast.py`
measures the first half over the whole painted mane; the second half was
unpinned, so this suite holds it and names the busts it moves.

What is claimed is about the **mass** rung, which is what the rule picks, and
about the tone that rung lands on once the bust is snapped onto its sixteen:
hair is given three of them, so a mass dropped to `deep` ships as whichever
allowed tone is nearest — Quill's does — and the floor has to hold there or the
rule bought nothing. It is not a claim about every tone of a mane: a lit lobe is
drawn inside the mass off the same ramp, and may come within the floor of a
fringe pixel somewhere on the crown.
"""

from __future__ import annotations

import unittest

from PIL import Image

from cells import tally
from painted import painted
from portraitgen import bust, hair, head, palette, roster
from portraitgen.canvas import CAST_TONE

# The two busts the pale half of the rule moves, and the two the cheek half
# moves on its own. Named rather than counted: the rule is worth exactly the
# faces it changes, and a widened floor that started moving a third bust would
# otherwise pass every bar in this package.
FRINGE_MOVED = {"konrad_vale", "lyra_quill"}
CHEEK_MOVED = {"iris_colt", "viktor_draeg"}


def _tones(key: str) -> set[tuple[int, ...]]:
    return {colour for _, colour in tally(painted(key).convert("RGB"))}


def _mass_tone(key: str) -> tuple[int, ...]:
    """The tone the mass reaches the raster in: the rung the rule picked, put
    through the bust's own quantiser rather than through a second opinion."""
    face = roster.FACES[key]
    ramp = hair.ramp_for(face.hair)
    picked = ramp.band(hair.mass_band(face.style, ramp, head.ramp_for(face.skin)))
    one = Image.new("RGBA", (1, 1), (*picked, 255))
    snapped = palette.quantise(one, bust.palette_of(face), shadow=CAST_TONE)
    return snapped.getpixel((0, 0))[:3]


class TheMassStandsOffTheSkinItBorders(unittest.TestCase):
    def test_every_mass_tone_is_on_its_own_bust(self):
        """The tone the mass lands on is a tone the raster carries — otherwise
        the two bars below are measuring a colour nobody painted."""
        for key in sorted(roster.FACES):
            with self.subTest(commander=key):
                self.assertIn(_mass_tone(key), _tones(key))

    def test_every_mass_clears_the_cheek(self):
        for key, face in sorted(roster.FACES.items()):
            with self.subTest(commander=key):
                cheek = head.ramp_for(face.skin).base
                self.assertGreaterEqual(
                    abs(palette.luminance(_mass_tone(key)) - palette.luminance(cheek)),
                    hair.SKIN_CONTRAST,
                )

    def test_a_pale_mass_clears_the_fringe_it_lays(self):
        pale = []
        for key, face in sorted(roster.FACES.items()):
            tone = _mass_tone(key)
            if palette.luminance(tone) <= hair.PALE_HAIR:
                continue
            pale.append(key)
            with self.subTest(commander=key):
                fringe = head.ramp_for(face.skin).band(hair.FRINGE_BAND)
                self.assertGreaterEqual(
                    abs(palette.luminance(tone) - palette.luminance(fringe)),
                    hair.SKIN_CONTRAST,
                )
        self.assertTrue(pale, "no pale mass left on the sheet — the bar is vacuous")


class TheRuleMovesExactlyTheseManes(unittest.TestCase):
    """Which busts are not wearing the rung their style names, and why."""

    def _clears(self, tone: tuple[int, ...], band: tuple[int, ...]) -> bool:
        return (
            abs(palette.luminance(tone) - palette.luminance(band)) >= hair.SKIN_CONTRAST
        )

    def test_the_rule_moves_the_four_it_is_named_for(self):
        moved = {
            key
            for key, face in roster.FACES.items()
            if hair.mass_band(
                face.style, hair.ramp_for(face.hair), head.ramp_for(face.skin)
            )
            != hair.declared_band(face.style)
        }
        self.assertEqual(moved, FRINGE_MOVED | CHEEK_MOVED)

    def test_only_quill_and_vale_are_moved_by_the_pale_half(self):
        """A bust the cheek band alone would have moved is not this rule's; a
        bust whose declared rung clears the cheek and ties with its own fringe
        is, and there are two of them."""
        for key in sorted(FRINGE_MOVED | CHEEK_MOVED):
            face = roster.FACES[key]
            declared = hair.ramp_for(face.hair).band(hair.declared_band(face.style))
            skin = head.ramp_for(face.skin)
            with self.subTest(commander=key):
                self.assertEqual(
                    key in FRINGE_MOVED,
                    self._clears(declared, skin.base)
                    and not self._clears(declared, skin.band(hair.FRINGE_BAND)),
                )


if __name__ == "__main__":
    unittest.main()
