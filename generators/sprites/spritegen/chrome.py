"""The UI chrome: the range overlay, the board cursor, the project icon.

These three are not board sprites — nothing here is a voxel model on a tile —
but they are art the game ships, and until this module they were the one art
the engine drew for itself, out of a second palette nothing compared against
the first. They are flat rectangles, so they are stated as rectangles.

The two team squares on the icon and the two grounds under them keep the hues
the engine script drew them with, which are a step off `palette.FACTIONS` and
`terrain.tones` — a recolour is an art change and this module is not one. The
distance is measured rather than described: `ChromeDrift` in `test_chrome.py`
holds each legacy hue within a stated tolerance of the row it stands for, so
the two palettes can drift no further without a test saying so.
"""

from __future__ import annotations

from PIL import Image

RGBA = tuple[int, int, int, int]

TILE = 16
ICON = 128

# The overlay is white and the scene modulates it: blue for movement range,
# red for threat. The border is the darker half of the two so a lit cell has
# an edge without a second sprite.
OVERLAY_FILL: RGBA = (255, 255, 255, 86)
OVERLAY_EDGE: RGBA = (255, 255, 255, 127)

# The cursor is four corner brackets, each a 6x2 arm along the tile's edge and
# a 2x6 arm down it, dropped one pixel onto their own shadow.
CURSOR_INK: RGBA = (255, 255, 255, 255)
CURSOR_SHADOW: RGBA = (12, 12, 12, 229)
BRACKET_LONG, BRACKET_SHORT = 6, 2
SHADOW_OFFSET = (1, 1)

# The icon is the board in miniature: a crossroads on grass with one army in
# each far corner. See the module header on these four hues.
ICON_GRASS: RGBA = (120, 200, 80, 255)
ICON_ROAD: RGBA = (201, 184, 132, 255)
ICON_MERIDIAN: RGBA = (216, 74, 60, 255)
ICON_AURORA: RGBA = (60, 100, 216, 255)
ICON_ROAD_WIDTH = 16
ICON_MARGIN, ICON_SQUARE = 14, 28


def _fill(img: Image.Image, box: tuple[int, int, int, int], color: RGBA) -> None:
    """Paint a rectangle, clipped to the image, overwriting what is under it —
    the chrome is opaque layers, not blended ones."""
    x, y, w, h = box
    x0, y0 = max(x, 0), max(y, 0)
    x1, y1 = min(x + w, img.width), min(y + h, img.height)
    if x1 > x0 and y1 > y0:
        img.paste(color, (x0, y0, x1, y1))


def _blank(size: int) -> Image.Image:
    return Image.new("RGBA", (size, size), (0, 0, 0, 0))


def overlay() -> Image.Image:
    """The translucent range tile the scene modulates."""
    img = _blank(TILE)
    _fill(img, (0, 0, TILE, TILE), OVERLAY_EDGE)
    _fill(img, (1, 1, TILE - 2, TILE - 2), OVERLAY_FILL)
    return img


def _brackets() -> tuple[tuple[int, int, int, int], ...]:
    far = TILE - BRACKET_LONG
    arms = []
    for left in (True, False):
        for top in (True, False):
            x, y = (0 if left else far), (0 if top else far)
            arms.append(
                (x, 0 if top else TILE - BRACKET_SHORT, BRACKET_LONG, BRACKET_SHORT)
            )
            arms.append(
                (0 if left else TILE - BRACKET_SHORT, y, BRACKET_SHORT, BRACKET_LONG)
            )
    return tuple(arms)


def cursor() -> Image.Image:
    """The grid cursor: white brackets over their own drop shadow."""
    img = _blank(TILE)
    dx, dy = SHADOW_OFFSET
    for x, y, w, h in _brackets():
        _fill(img, (x + dx, y + dy, w, h), CURSOR_SHADOW)
    for arm in _brackets():
        _fill(img, arm, CURSOR_INK)
    return img


def icon() -> Image.Image:
    """The project icon: a crossroads with two armies facing across it."""
    img = _blank(ICON)
    _fill(img, (0, 0, ICON, ICON), ICON_GRASS)
    mid = (ICON - ICON_ROAD_WIDTH) // 2
    _fill(img, (mid, 0, ICON_ROAD_WIDTH, ICON), ICON_ROAD)
    _fill(img, (0, mid, ICON, ICON_ROAD_WIDTH), ICON_ROAD)
    far = ICON - ICON_MARGIN - ICON_SQUARE
    _fill(img, (ICON_MARGIN, ICON_MARGIN, ICON_SQUARE, ICON_SQUARE), ICON_MERIDIAN)
    _fill(img, (far, far, ICON_SQUARE, ICON_SQUARE), ICON_AURORA)
    return img
