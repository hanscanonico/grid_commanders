"""The uniform: three cuts that differ where it counts, and twelve chest ideas.

A collar is only worth having if it changes the outline at chip size, so the two
checks here are the two the reviews asked for — the cuts differ at 31px, and no
chest treatment need be worn by more than two of the twenty-two.

The ramp is a stand-in: `light.build_ramp` lands with the light model, and this
module only ever reads the four tones and the rim off whatever it is handed.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from PIL import Image, ImageChops

from portraitgen import uniform
from portraitgen.canvas import Canvas
from portraitgen.light import Ramp
from portraitgen.palette import faction_by_key

GAME = Path(__file__).resolve().parents[3]
UI_THEME = GAME / "scenes/common/ui_theme.gd"
# `const AMMO := Color(r, g, b)` — the one gold the portraits borrow, read back
# out of the game the way the faction themes are.
_AMMO = re.compile(r"const AMMO := Color\(([^)]*)\)")

FACTION = faction_by_key("aurora")
RAMP = Ramp(
    deep=(24, 34, 58),
    shade=(38, 54, 92),
    base=(56, 78, 132),
    lit=(84, 110, 172),
    rim=(150, 176, 226),
)
# The roster is twenty-two generals and no chest treatment may be worn by more
# than two of them.
ROSTER = 22
SHARED_CAP = 2


def _uniform(collar: str) -> Canvas:
    canvas = Canvas()
    uniform.draw(canvas, FACTION, collar, RAMP)
    return canvas


class EveryCutDraws(unittest.TestCase):
    def test_the_vocabulary_and_the_dispatch_table_are_one_set(self):
        for collar in sorted(uniform.COLLAR_CUTS):
            with self.subTest(collar=collar):
                self.assertIsNotNone(_uniform(collar).image.getbbox())

    def test_the_default_cut_is_one_of_them(self):
        self.assertIn(uniform.COLLAR_DEFAULT, uniform.COLLAR_CUTS)

    def test_an_unknown_cut_raises_rather_than_falling_through(self):
        with self.assertRaises(KeyError):
            uniform.draw(Canvas(), FACTION, "shawl", RAMP)


class TheCutsAreToldApartAtChipSize(unittest.TestCase):
    """31px is where a portrait spends most of its life, so that is where the
    three cuts have to be three drawings rather than one."""

    def _chip(self, collar: str) -> Image.Image:
        canvas = _uniform(collar)
        crop = canvas.image.crop(
            tuple(round(v * canvas.scale) for v in (56, 180, 164, 260))
        )
        return crop.resize((31, 23), Image.Resampling.BOX).convert("RGB")

    def test_no_two_collars_read_the_same(self):
        chips = {collar: self._chip(collar) for collar in sorted(uniform.COLLAR_CUTS)}
        cuts = sorted(chips)
        for first in range(len(cuts)):
            for second in range(first + 1, len(cuts)):
                with self.subTest(pair=(cuts[first], cuts[second])):
                    difference = ImageChops.difference(
                        chips[cuts[first]], chips[cuts[second]]
                    )
                    moved = difference.convert("L").point(
                        lambda value: 255 if value > 12 else 0
                    )
                    self.assertGreater(moved.histogram()[255], 60)


class TheChestCarriesSomething(unittest.TestCase):
    def test_there_are_enough_treatments_to_go_round(self):
        self.assertGreaterEqual(len(uniform.CHEST_TREATMENTS), ROSTER // SHARED_CAP)

    def test_every_treatment_draws_something(self):
        for treatment in sorted(uniform.CHEST_TREATMENTS):
            with self.subTest(treatment=treatment):
                canvas = Canvas()
                uniform.chest(canvas, treatment, FACTION, RAMP)
                self.assertIsNotNone(canvas.image.getbbox())

    def test_the_default_treatment_is_one_of_them(self):
        self.assertIn(uniform.CHEST_DEFAULT, uniform.CHEST_TREATMENTS)

    def test_an_unknown_treatment_raises(self):
        with self.assertRaises(KeyError):
            uniform.chest(Canvas(), "cape", FACTION, RAMP)


class TheGoldIsTheGame(unittest.TestCase):
    """`GOLD` is `UiTheme.AMMO` restated, so it is read back out of the game.

    The engine writes a `Color` to hex by rounding, which is what the shipped
    busts' `_gold` carries; a drift here means the pip and the HUD's ammo
    readout have stopped being the same gold.
    """

    def test_the_gold_is_ui_themes_ammo(self):
        self.assertTrue(UI_THEME.is_file(), UI_THEME)
        found = _AMMO.search(UI_THEME.read_text())
        self.assertIsNotNone(found, f"no AMMO constant in {UI_THEME}")
        channels = tuple(float(v) for v in found.group(1).split(",")[:3])
        self.assertEqual(uniform.GOLD, tuple(round(v * 255.0) for v in channels))


class TheGoldIsTheRankPip(unittest.TestCase):
    def test_the_pip_is_gold_over_ink_and_nothing_else(self):
        canvas = Canvas()
        uniform.pip(canvas, RAMP)
        colours = {colour for _, colour in canvas.image.getcolors(maxcolors=1 << 16)}
        self.assertEqual(len(colours), 3, colours)
        self.assertIn((*uniform.GOLD, 255), colours)

    def test_the_pip_is_a_stud_rather_than_a_badge(self):
        canvas = Canvas()
        uniform.pip(canvas, RAMP)
        left, top, right, bottom = canvas.image.getbbox()
        self.assertLess((right - left) / canvas.scale, 16)
        self.assertLess((bottom - top) / canvas.scale, 16)


class ThePaletteIsBounded(unittest.TestCase):
    """Counted on the working canvas: the box downsample is this pipeline's
    antialiasing, so the tones authored here are what the budget is about."""

    def test_a_dressed_bust_is_painted_in_named_tones(self):
        for collar in sorted(uniform.COLLAR_CUTS):
            for treatment in sorted(uniform.CHEST_TREATMENTS):
                with self.subTest(collar=collar, treatment=treatment):
                    canvas = _uniform(collar)
                    uniform.chest(canvas, treatment, FACTION, RAMP)
                    uniform.pip(canvas, RAMP)
                    self.assertLessEqual(
                        len(canvas.image.getcolors(maxcolors=1 << 16)), 16
                    )


if __name__ == "__main__":
    unittest.main()
