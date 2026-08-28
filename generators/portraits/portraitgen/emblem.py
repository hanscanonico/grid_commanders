"""The four 64x64 faction emblems: hollow diamond, diamond, star, pennant.

Board marks are outlined, not blurred, and these are board marks: each emblem is
a couple of Manhattan diamonds and bands, drawn **at 1x with integer geometry**
rather than through the supersampled canvas the busts use. That is a decision,
not an oversight — the shapes are axis-aligned and 45-degree, so a supersample
buys nothing but a soft edge, and drawing them the way
the retired GDScript bake's `_draw_emblem` did keeps the committed PNGs pixel
for pixel what they already are.
"""

from __future__ import annotations

from PIL import Image

from .palette import INK, RGB, faction_by_key

SIZE = 64  # CommanderVisuals.EMBLEM_PX
_CENTRE = SIZE // 2


def draw(key: str) -> Image.Image:
    """One faction's emblem, on a transparent field."""
    faction = faction_by_key(key)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    _SHAPES[key](img, faction.body)
    return img


def _hollow_diamond(img: Image.Image, colour: RGB) -> None:
    _diamond(img, _CENTRE, _CENTRE, 26, INK)
    _diamond(img, _CENTRE, _CENTRE, 21, colour)
    _diamond(img, _CENTRE, _CENTRE, 11, INK)


def _solid_diamond(img: Image.Image, colour: RGB) -> None:
    _diamond(img, _CENTRE, _CENTRE, 26, INK)
    _diamond(img, _CENTRE, _CENTRE, 21, colour)


def _four_point_star(img: Image.Image, colour: RGB) -> None:
    _diamond(img, _CENTRE, _CENTRE, 27, INK)
    _diamond(img, _CENTRE, _CENTRE, 22, colour)
    _band(img, _CENTRE - 3, 6, 6, 52, colour)
    _band(img, 6, _CENTRE - 3, 52, 6, colour)


def _pennant(img: Image.Image, colour: RGB) -> None:
    _band(img, 18, 8, 6, 48, INK)
    for y in range(10, 40):
        for x in range(24, 54):
            if x - 24 < 30 - abs(y - 22):
                img.putpixel((x, y), (*colour, 255))


# The shape each army wears. A key with no shape is a faction nobody drew, so
# this raises rather than falling through to a default.
_SHAPES = {
    "meridian": _hollow_diamond,
    "iron": _solid_diamond,
    "aurora": _four_point_star,
    "verdant": _pennant,
}


def _band(img: Image.Image, x: int, y: int, w: int, h: int, colour: RGB) -> None:
    for py in range(max(0, y), min(SIZE, y + h)):
        for px in range(max(0, x), min(SIZE, x + w)):
            img.putpixel((px, py), (*colour, 255))


def _diamond(img: Image.Image, cx: int, cy: int, r: int, colour: RGB) -> None:
    for y in range(max(0, cy - r), min(SIZE, cy + r + 1)):
        for x in range(max(0, cx - r), min(SIZE, cx + r + 1)):
            if abs(x - cx) + abs(y - cy) <= r:
                img.putpixel((x, y), (*colour, 255))


__all__ = ["SIZE", "draw"]
