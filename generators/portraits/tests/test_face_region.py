"""The crop the small surfaces draw, and the jaw it must never cut.

`CommanderVisuals.FACE_REGION` is one rectangle over twenty-three poses, and the
thing that goes quiet when it breaks is a chin crossing its bottom edge: a crop
that cuts a jaw cuts it off the HUD chip, the speech bust and the campaign brief
at once. This is `tests/unit/test_commander_face.gd::test_the_crop_clears_every_jaw`,
rehosted here because the roster and the skin ramps live in this package now —
and because a failure is fixed by moving geometry, never by moving the
rectangle, which is what a gate beside the generator makes easy.

The rectangle is read out of the game's own source rather than typed here, the
way `test_palette_mirror.py` reads the faction themes: a rename in
`commander_visuals.gd` has to fail loudly.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from PIL import Image

from portraitgen import bust, head, roster

GAME = Path(__file__).resolve().parents[3]
VISUALS = GAME / "scenes/common/commander_visuals.gd"

# The shipped busts measured 12 (Quill) to 21 (Morn) against a floor of 8. The
# floor is the GUT suite's own; the target is the band the sheet has held.
CHIN_CLEARANCE_PX = 8
CHIN_TARGET_PX = 12

# How far off one of a general's own skin tones a pixel may be and still be
# their face. The busts are painted in flat named tones, so the only pixels
# that drift are the downsample's own edge blends, which are not the chin.
SKIN_TOLERANCE = 14

_REGION = re.compile(r"FACE_REGION.*?Rect2i\((\d+),\s*(\d+),\s*(\d+),\s*(\d+)\)", re.S)


def face_region() -> tuple[int, int, int, int]:
    """`CommanderVisuals.FACE_REGION` as (x, y, width, height)."""
    found = _REGION.search(VISUALS.read_text())
    assert found is not None, "FACE_REGION is not where this test looks for it"
    return tuple(int(group) for group in found.groups())


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

    A column rather than the whole bottom row, for the GUT suite's own reason: a
    signature prop is drawn in its owner's skin, so a row-wide scan measures the
    props instead of the jaw.
    """
    x, y, width, height = face_region()
    column = x + width // 2
    rows = [
        row
        for row in range(y, y + height)
        if is_skin(image.getpixel((column, row)), tones)
    ]
    return rows[-1] if rows else -1


def _clearance(image: Image.Image, tones: list[tuple[int, int, int]]) -> int:
    _, y, _, height = face_region()
    return y + height - 1 - chin_row(image, tones)


def skin_tones(skin: str) -> list[tuple[int, int, int]]:
    ramp = head.ramp_for(skin)
    return [ramp.deep, ramp.shade, ramp.base, ramp.lit]


class TheRectangleIsTheGameSOwn(unittest.TestCase):
    def test_the_region_is_a_square_inside_the_portrait(self):
        x, y, width, height = face_region()
        self.assertEqual((x, y, width, height), (16, 25, 190, 190))
        self.assertEqual(width, height)
        self.assertLessEqual(x + width, 220)
        self.assertLessEqual(y + height, 268)


class TheCropClearsEveryJaw(unittest.TestCase):
    """Per bust, per run: this is the hardest bar the sheet has to clear."""

    def test_every_general_s_chin_sits_above_the_crop_s_bottom_edge(self):
        for key, face in sorted(roster.FACES.items()):
            with self.subTest(commander=key):
                image = bust.paint(face)
                tones = skin_tones(face.skin)
                self.assertGreater(chin_row(image, tones), 0, "no face on the column")
                self.assertGreaterEqual(_clearance(image, tones), CHIN_CLEARANCE_PX)

    def test_the_sheet_holds_the_band_the_shipped_busts_held(self):
        thin = {
            key: _clearance(bust.paint(face), skin_tones(face.skin))
            for key, face in sorted(roster.FACES.items())
        }
        self.assertEqual(
            [], [f"{k}: {v}" for k, v in thin.items() if v < CHIN_TARGET_PX]
        )


if __name__ == "__main__":
    unittest.main()
