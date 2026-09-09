"""The square the small surfaces repaint, and the jaw it must never cut.

`CommanderVisuals.FACE_REGION` is one rectangle over twenty-three poses, and the
chip drawn from it is that square painted again on a coarser grid rather than
cut out of the bust. The thing that goes quiet when the rectangle breaks is a
chin crossing its bottom edge: a square that cuts a jaw cuts it off the HUD
chip, the speech bust and the campaign brief at once.

The engine's suite holds what it can see without the ramps —
`tests/unit/test_commander_face.gd::test_face_region_fits_inside_a_portrait`
and `::test_every_general_hands_back_that_square`, plus
`test_commander_portraits.gd::test_the_whole_bust_field_is_the_art_s_own_size`
for the field measured off the rectangle. The chin is measured here, where the
roster and the skin ramps are — and where a failure is fixed by moving
geometry, never by moving the rectangle.

The rectangle is read out of the game's own source rather than typed here, the
way `test_palette_mirror.py` reads the faction themes: a rename in
`commander_visuals.gd` has to fail loudly.
"""

from __future__ import annotations

import re
import unittest
from collections import Counter

from PIL import Image

from cells import tally
from game import VISUALS, scrape
from painted import painted
from portraitgen import bust, head, roster
from portraitgen.canvas import BUST_DIVISOR, BUST_SIZE, CHIP_DIVISOR, CHIP_SIZE
from portraitgen.canvas import face_box as _face_box


# The floor and the band the sheet holds, on the bust's own grid — half the
# raster the eight-pixel floor was set on, so the floor comes down with it. The
# rebaked sheet measures 8 (Holt) to 32 (Morn) against that floor of 4.
CHIN_CLEARANCE_PX = 4
CHIN_TARGET_PX = 8

# A bust is snapped onto sixteen named tones and nothing is blended anywhere,
# so a skin pixel IS one of the skin ramp's rungs. The tolerance is what the
# quantiser can move a rung by, which is nothing.
SKIN_TOLERANCE = 0

_REGION = re.compile(r"FACE_REGION.*?Rect2i\((\d+),\s*(\d+),\s*(\d+),\s*(\d+)\)", re.S)


def _as_rect(divisor: int) -> tuple[int, int, int, int]:
    """The generator's own face box as (x, y, width, height)."""
    left, top, right, bottom = _face_box(divisor)
    return (left, top, right - left, bottom - top)


def face_region() -> tuple[int, int, int, int]:
    """`CommanderVisuals.FACE_REGION` as (x, y, width, height)."""
    return tuple(int(group) for group in scrape(VISUALS, _REGION).groups())


def is_skin(pixel: tuple[int, ...], tones: list[tuple[int, int, int]]) -> bool:
    if pixel[3] < 204:
        return False
    return any(
        max(abs(pixel[index] - tone[index]) for index in range(3)) <= SKIN_TOLERANCE
        for tone in tones
    )


def chin_row(image: Image.Image, tones: list[tuple[int, int, int]]) -> int:
    """The lowest row of the crop's middle column that is still this face.

        Public because it is the sheet's one reading of where a jaw ends, and
        `test_props` holds a prop clear of that row rather than taking a second
        opinion on it.

    The face is the one CONNECTED mass of skin in the crop: a bust is snapped
        onto sixteen tones, so a leather strap under the collar can land on the very
        rung a cheek is painted in, and a signature prop is drawn in its owner's
        skin. What tells them apart is that a brow, a jaw and the neck under them
        touch, and a strap does not — so the jaw is the bottom of the largest island
        of skin, not the lowest skin pixel anywhere.
    """
    island = _face_island(image, tones)
    return max((row for _, row in island), default=-1)


def _face_island(
    image: Image.Image, tones: list[tuple[int, int, int]]
) -> set[tuple[int, int]]:
    """The largest four-connected run of this face's own skin inside the crop."""
    x, y, width, height = face_region()
    skin = {
        (column, row)
        for row in range(y, y + height)
        for column in range(x, x + width)
        if is_skin(image.getpixel((column, row)), tones)
    }
    largest: set[tuple[int, int]] = set()
    while skin:
        island, edge = set(), [skin.pop()]
        while edge:
            column, row = edge.pop()
            island.add((column, row))
            for step in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                near = (column + step[0], row + step[1])
                if near in skin:
                    skin.remove(near)
                    edge.append(near)
        if len(island) > len(largest):
            largest = island
    return largest


def _clearance(image: Image.Image, tones: list[tuple[int, int, int]]) -> int:
    _, y, _, height = face_region()
    return y + height - 1 - chin_row(image, tones)


def skin_tones(skin: str) -> list[tuple[int, int, int]]:
    ramp = head.ramp_for(skin)
    return [ramp.deep, ramp.shade, ramp.base, ramp.lit]


class TheRectangleIsTheGameSOwn(unittest.TestCase):
    def test_the_region_is_a_square_inside_the_portrait(self):
        x, y, width, height = face_region()
        self.assertEqual((x, y, width, height), _as_rect(BUST_DIVISOR))
        self.assertEqual(width, height)
        self.assertLessEqual(x + width, BUST_SIZE[0])
        self.assertLessEqual(y + height, BUST_SIZE[1])

    def test_the_rectangle_lands_on_both_grids(self):
        """The chip is this square rasterised coarser, so a rectangle that did
        not divide by the chip grid would put a chip off the bust's own head."""
        for divisor in (BUST_DIVISOR, CHIP_DIVISOR):
            with self.subTest(divisor=divisor):
                left, top, right, bottom = _face_box(divisor)
                self.assertEqual(right - left, bottom - top)
        self.assertEqual(_as_rect(CHIP_DIVISOR)[2], CHIP_SIZE)


# The two bars `TheChipIsTheSameFace` holds the sheet to, argued there and
# measured on the art as it ships.
CHIP_AGREEMENT_FLOOR = 0.60
CHIP_IDENTITY_MARGIN = 0.15


def _dominant_tones(image: Image.Image, side: int) -> list[tuple[int, ...]]:
    """The bust's face box read at chip resolution: per chip texel, the tone
    that fills most of the 3x3 block of the bust that texel covers."""
    region = image.crop(_face_box(BUST_DIVISOR))
    block = region.size[0] // side
    return [
        Counter(
            region.getpixel((x * block + dx, y * block + dy))
            for dy in range(block)
            for dx in range(block)
        ).most_common(1)[0][0]
        for y in range(side)
        for x in range(side)
    ]


def agreement(chip: Image.Image, dominant: list[tuple[int, ...]]) -> float:
    """What fraction of a chip's texels carry the tone that dominates the bust
    block they stand for."""
    return sum(
        1
        for texel, tone in zip(chip.get_flattened_data(), dominant, strict=True)
        if texel == tone
    ) / len(dominant)


class TheChipIsTheSameFace(unittest.TestCase):
    """The chip is the bust's own face, measured against the shipped bust.

    A chip is not a crop of the bust — it is the whole drawing repainted on a
    grid three times coarser, so the two cannot be compared byte for byte and a
    test that recomputes `bust.chip`'s own definition measures nothing. What can
    be compared is the picture: the face box is 93px on the bust's grid and 31px
    on the chip's, so every chip texel stands for one 3x3 block of the bust, and
    a chip that is the same face carries the tone that DOMINATES its block.

    It cannot carry it everywhere. Every edge in the drawing falls somewhere
    inside a block on one grid and on a block boundary on the other, an ink
    weight that is two bust pixels is one chip texel, and the gauge sweep runs
    against a different smallest mark on each — so a third of the texels sitting
    on an edge disagreeing is the rasteriser, not a different face. Measured on
    the sheet as it ships, agreement runs 63.7% (Rhea Sol, the busiest face) to
    86.2% (the empty seat); the floor below is set at 60%, under the worst bust
    with room for the rasteriser to move an edge and over anything that is not
    this face.

    The floor alone is loose, so the bar it is paired with is an identity one,
    and that one is tight: a chip agrees with ITS OWN bust far better than with
    any other general's. The narrowest such margin on the sheet is Halden Marr
    against Gideon Holt — two Meridian faces in the same window — at 22.7
    points, and the bar is 15. A painter that branched on the divisor and drew
    another face on the chip grid loses the whole margin at once.
    """

    def setUp(self):
        self.sheet = {
            key: (bust.chip(spec), _dominant_tones(painted(key), CHIP_SIZE))
            for key, spec in bust.sheet_rows()
        }

    def test_every_chip_is_the_chip_square(self):
        for key, (chip, _) in sorted(self.sheet.items()):
            with self.subTest(commander=key):
                self.assertEqual(chip.size, (CHIP_SIZE, CHIP_SIZE))

    def test_every_chip_carries_the_tones_its_own_bust_does(self):
        for key, (chip, dominant) in sorted(self.sheet.items()):
            with self.subTest(commander=key):
                self.assertGreaterEqual(
                    agreement(chip, dominant),
                    CHIP_AGREEMENT_FLOOR,
                    f"{key}'s chip is not the face its bust draws",
                )

    def test_every_chip_reads_as_its_own_general_and_no_other(self):
        for key, (chip, dominant) in sorted(self.sheet.items()):
            with self.subTest(commander=key):
                own = agreement(chip, dominant)
                stranger = max(
                    agreement(chip, theirs)
                    for other, (_, theirs) in self.sheet.items()
                    if other != key
                )
                self.assertGreaterEqual(
                    own - stranger,
                    CHIP_IDENTITY_MARGIN,
                    f"{key}'s chip reads no more like its own bust "
                    f"({own:.3f}) than like another general's ({stranger:.3f})",
                )

    def test_no_chip_spends_a_tone_its_bust_does_not(self):
        for key, face in sorted(roster.FACES.items()):
            with self.subTest(commander=key):
                tones = {
                    colour[:3]
                    for _, colour in tally(bust.chip(face))
                    if colour[3] == 255
                }
                self.assertEqual(tones - set(bust.palette_of(face)), set())


class TheCropClearsEveryJaw(unittest.TestCase):
    """Per bust, per run: this is the hardest bar the sheet has to clear."""

    def test_every_general_s_chin_sits_above_the_crop_s_bottom_edge(self):
        for key, face in sorted(roster.FACES.items()):
            with self.subTest(commander=key):
                image = painted(key)
                tones = skin_tones(face.skin)
                self.assertGreater(chin_row(image, tones), 0, "no face on the column")
                self.assertGreaterEqual(_clearance(image, tones), CHIN_CLEARANCE_PX)

    def test_the_sheet_holds_the_band_the_shipped_busts_held(self):
        thin = {
            key: _clearance(painted(key), skin_tones(face.skin))
            for key, face in sorted(roster.FACES.items())
        }
        self.assertEqual(
            [], [f"{k}: {v}" for k, v in thin.items() if v < CHIN_TARGET_PX]
        )


if __name__ == "__main__":
    unittest.main()
