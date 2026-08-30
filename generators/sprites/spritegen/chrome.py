"""The UI chrome: the range overlay, the board cursor, the project icon.

These three are not board sprites — nothing here is a voxel model on a tile —
but they are art the game ships, and until this module they were the one art
the engine drew for itself, out of a second palette nothing compared against
the first. They are flat rectangles, so they are stated as rectangles.

The icon's two team tokens keep the hues the engine script drew them with,
which are a step off `palette.FACTIONS` — a recolour is an art change and this
module is not one. The
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

# The icon is the command table: a dark plate ruled into a 3x3 board, one army
# in each far corner and the gold mark on the cell between them. See the module
# header on the two team hues.
ICON_PLATE: RGBA = (26, 30, 36, 255)
ICON_GRID: RGBA = (72, 84, 96, 255)
ICON_MERIDIAN: RGBA = (216, 74, 60, 255)
ICON_AURORA: RGBA = (60, 100, 216, 255)
ICON_MARK: RGBA = (224, 169, 46, 255)
# Every measure is a multiple of the 8px rule, so all four platform sizes —
# 128, 64, 32 and the 16 the desktop shrinks to — land on whole pixels: a rule
# is one pixel at 16, a cell is four, the mark's arms two.
ICON_CORNER = 8
ICON_LINE, ICON_CELL = 8, 32
ICON_INSET = (ICON - (4 * ICON_LINE + 3 * ICON_CELL)) // 2
ICON_TOKEN = 32
ICON_MARK_ARM, ICON_MARK_THICK = 32, 16


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


def _cell_origin(col: int, row: int) -> tuple[int, int]:
    """The top-left of a board cell: the inset, then a rule and a cell per step."""
    step = ICON_LINE + ICON_CELL
    return (ICON_INSET + ICON_LINE + col * step, ICON_INSET + ICON_LINE + row * step)


def _plate(img: Image.Image) -> None:
    """The dark table the board is ruled onto."""
    _fill(img, (0, 0, ICON, ICON), ICON_PLATE)


def _round(img: Image.Image) -> None:
    """Cut the four corners away so the icon reads as rounded. Last, because
    the board fills the plate and its frame reaches the corners."""
    for x in (0, ICON - ICON_CORNER):
        for y in (0, ICON - ICON_CORNER):
            _fill(img, (x, y, ICON_CORNER, ICON_CORNER), (0, 0, 0, 0))


def _rules(img: Image.Image) -> None:
    """Four rules each way: the board's frame and the two lines inside it."""
    span = 4 * ICON_LINE + 3 * ICON_CELL
    for step in range(4):
        offset = ICON_INSET + step * (ICON_LINE + ICON_CELL)
        _fill(img, (ICON_INSET, offset, span, ICON_LINE), ICON_GRID)
        _fill(img, (offset, ICON_INSET, ICON_LINE, span), ICON_GRID)


def _token(img: Image.Image, col: int, row: int, color: RGBA) -> None:
    x, y = _cell_origin(col, row)
    pad = (ICON_CELL - ICON_TOKEN) // 2
    _fill(img, (x + pad, y + pad, ICON_TOKEN, ICON_TOKEN), color)


def _mark(img: Image.Image) -> None:
    """The gold crosshair on the centre cell — the objective both armies want."""
    mid = ICON // 2
    long, short = ICON_MARK_ARM // 2, ICON_MARK_THICK // 2
    _fill(img, (mid - long, mid - short, ICON_MARK_ARM, ICON_MARK_THICK), ICON_MARK)
    _fill(img, (mid - short, mid - long, ICON_MARK_THICK, ICON_MARK_ARM), ICON_MARK)


def icon() -> Image.Image:
    """The project icon: two armies across a ruled table, the mark between them."""
    img = _blank(ICON)
    _plate(img)
    _rules(img)
    _token(img, 0, 2, ICON_MERIDIAN)
    _token(img, 2, 0, ICON_AURORA)
    _mark(img)
    _round(img)
    return img
