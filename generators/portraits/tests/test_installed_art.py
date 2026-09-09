"""The art the game actually loads, measured on the files under `assets/`.

Every other bar in this package reads `bust.paint` in memory. That proves the
generator, not the install: a bust rebaked with a stale generator, a chip
written at the wrong divisor and a file the roster no longer names would all
pass a suite that never opens a PNG. `make portraits-snapshot` compares a fresh
generation against these same files, so the two together say the installed art
is both current and inside the rules — but the snapshot alone would happily
match a generation that broke every one of them.

Read out of the repo the way `test_face_region.py` reads
`commander_visuals.gd`: the game's tree is three levels up, and a file missing
from it is a failure rather than a skip.
"""

from __future__ import annotations

import unittest
from pathlib import Path

from PIL import Image

from game import GAME
from portraitgen import bust, emblem, palette, roster
from portraitgen.canvas import BUST_SIZE, CAST_TONE, CHIP_SIZE

INSTALLED = GAME / "assets/portraits"

BUSTS = INSTALLED / "commanders"
FACES = INSTALLED / "faces"
EMBLEMS = INSTALLED / "factions"

# Which spec each installed drawing is of. The empty seat ships like everybody
# else, which is why it is in the roster's own list here rather than special.
SPECS = {**roster.FACES, roster.NEUTRAL_ID: roster.NEUTRAL}


def _opened(path: Path) -> Image.Image:
    if not path.is_file():
        raise AssertionError(f"{path} is not installed — run `make portraits`")
    return Image.open(path).convert("RGBA")


def _counted(image: Image.Image) -> list[tuple[int, tuple[int, ...]]]:
    counted = image.getcolors(1 << 16)
    if counted is None:
        raise AssertionError("more colours than a portrait can carry")
    return counted


def _opaque(image: Image.Image) -> set[tuple[int, ...]]:
    return {colour[:3] for _, colour in _counted(image) if colour[3] == 255}


def _partial(image: Image.Image) -> set[tuple[int, ...]]:
    """Every tone that is neither paint nor nothing."""
    return {colour for _, colour in _counted(image) if 0 < colour[3] < 255}


class TheInstalledSheetIsTheWholeRoster(unittest.TestCase):
    def test_every_general_has_a_bust_and_a_chip_and_no_one_else_does(self):
        for directory in (BUSTS, FACES):
            with self.subTest(directory=directory.name):
                self.assertEqual(
                    sorted(p.stem for p in directory.glob("*.png")), sorted(SPECS)
                )

    def test_every_army_has_an_emblem_and_the_empty_seat_has_none(self):
        self.assertEqual(
            sorted(p.stem for p in EMBLEMS.glob("*.png")), sorted(palette.EMBLEM_KEYS)
        )


class TheInstalledFilesAreTheRightShape(unittest.TestCase):
    def test_every_bust_is_the_bust_grid(self):
        for key in sorted(SPECS):
            with self.subTest(commander=key):
                self.assertEqual(_opened(BUSTS / f"{key}.png").size, BUST_SIZE)

    def test_every_chip_is_the_chip_square(self):
        for key in sorted(SPECS):
            with self.subTest(commander=key):
                self.assertEqual(
                    _opened(FACES / f"{key}.png").size, (CHIP_SIZE, CHIP_SIZE)
                )

    def test_every_emblem_is_the_badge_square(self):
        for key in sorted(palette.EMBLEM_KEYS):
            with self.subTest(faction=key):
                self.assertEqual(
                    _opened(EMBLEMS / f"{key}.png").size, (emblem.SIZE, emblem.SIZE)
                )


class TheInstalledArtIsInsideItsPalette(unittest.TestCase):
    """Sixteen tones per bust, each one a rung `bust.palette_of` handed out —
    measured on the file rather than on the raster the generator held."""

    def test_no_installed_drawing_spends_more_than_sixteen_tones(self):
        for key in sorted(SPECS):
            for directory in (BUSTS, FACES):
                with self.subTest(commander=key, drawing=directory.name):
                    tones = _opaque(_opened(directory / f"{key}.png"))
                    self.assertLessEqual(len(tones), palette.PAINTED_TONES)

    def test_no_installed_drawing_spends_a_tone_its_palette_does_not(self):
        for key, spec in sorted(SPECS.items()):
            allowed = set(bust.palette_of(spec))
            for directory in (BUSTS, FACES):
                with self.subTest(commander=key, drawing=directory.name):
                    tones = _opaque(_opened(directory / f"{key}.png"))
                    self.assertEqual(tones - allowed, set())

    def test_an_emblem_is_its_army_s_body_rung_and_ink(self):
        for key in sorted(palette.EMBLEM_KEYS):
            with self.subTest(faction=key):
                allowed = {palette.INK, palette.faction_by_key(key).body}
                self.assertEqual(
                    _opaque(_opened(EMBLEMS / f"{key}.png")) - allowed, set()
                )


class TheInstalledArtCarriesOneShadowTone(unittest.TestCase):
    """A bust is flat paint over one hard cast shadow. Anything else part-way
    transparent is a blend, which is what this pipeline exists not to make."""

    def test_the_only_tone_that_is_not_paint_is_the_cast_shadow(self):
        for key in sorted(SPECS):
            for directory in (BUSTS, FACES):
                with self.subTest(commander=key, drawing=directory.name):
                    self.assertLessEqual(
                        _partial(_opened(directory / f"{key}.png")), {CAST_TONE}
                    )

    def test_every_general_stands_over_one(self):
        """The bar above passes an art file with no shadow in it at all, so the
        tone is asked for as well. The empty seat is out: it is a silhouette on
        a barred field with no figure to cast."""
        for key in sorted(roster.FACES):
            with self.subTest(commander=key):
                self.assertIn(CAST_TONE, _partial(_opened(BUSTS / f"{key}.png")))

    def test_an_emblem_casts_nothing(self):
        for key in sorted(palette.EMBLEM_KEYS):
            with self.subTest(faction=key):
                self.assertEqual(_partial(_opened(EMBLEMS / f"{key}.png")), set())


if __name__ == "__main__":
    unittest.main()
