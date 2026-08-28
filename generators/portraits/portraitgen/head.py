"""The skull, the neck and the ear — the geometry every other layer hangs off.

A head is four dials, exactly the `head` column of the roster:
`[width, jaw, crown, spread]`. Width scales the skull about its own centre, the
jaw names its lower half, the crown lifts the top of it, and the spread walks
the eyes apart for the features layer to read.

The numbers are the handoff's own, in portrait pixels. The handoff authored a
110x134 viewBox with its origin at y -14, and the pinned raster is 220x268 —
exactly two pixels per unit — so a handoff x is `2x` here and a handoff y is
`2(y + 14)`. Nothing is re-authored in the move; the skull a general is drawn
on is the skull they were drawn on.

Curves are flattened here, at a fixed number of steps, because a quadratic is a
polynomial and a polynomial is the same on every machine. `canvas.py` is still
the one place a coordinate becomes an integer.
"""

from __future__ import annotations

from dataclasses import dataclass

from PIL import Image, ImageChops

from . import light
from .canvas import INK_FEATURE, INK_SILHOUETTE, Canvas, Point
from .light import Ramp
from .palette import INK, RGB

# The jaw a skull is cut with. An unknown jaw raises: the vocabulary is the
# dispatch table, so nothing falls through to a default.
JAWS = frozenset({"round", "square", "tapered"})

# The five skins the roster picks from, as the handoff wrote them. They live
# beside the head because the head is what paints skin; `light.build_ramp`
# turns one into the four tones a face is painted in.
SKIN_BASES: dict[str, RGB] = {
    "dark": (138, 90, 60),
    "light": (242, 201, 160),
    "medium": (217, 160, 102),
    "pale": (246, 220, 194),
    "tan": (198, 134, 66),
}

# The face table's own HEAD_DEFAULT, column for column.
HEAD_DEFAULT: tuple[float, str, float, float] = (1.0, "round", 0.0, 1.0)

# The centre of the skull: every head, ear and eye is placed against it, and a
# general's width scales about it.
HEAD_CX = 110.0
# The skull, in portrait pixels: its sides, the cheekbone the top curve lands
# on, where the jaw takes over, the chin, and the unlifted crown.
SKULL_LEFT, SKULL_RIGHT = 64.0, 156.0
CHEEK_Y, JAW_Y, CHIN_Y, CROWN_Y = 132.0, 148.0, 206.0, 82.0
# A crown dial is in handoff units and the raster is two pixels to one.
CROWN_PX = 2.0

# The neck the head sits on, and the ear set into its side.
NECK_LEFT, NECK_RIGHT = 94.0, 126.0
NECK_TOP, NECK_BOTTOM, NECK_BULGE = 180.0, 208.0, 218.0
EAR_LEFT, EAR_RIGHT, EAR_Y, EAR_R = 62.0, 158.0, 144.0, 10.0

# How far the head's own shape falls onto what is under it — the jaw onto the
# neck and the skull onto the ear behind it are one band — in portrait pixels.
# The hair fringe and the collar are the same pass at their own layers.
JAW_DEPTH = 5.0
# The rim band, and how far in under the silhouette ink it sits.
RIM_WEIGHT = 2.5
RIM_INSET = INK_SILHOUETTE / 2.0

# Steps a quadratic is flattened into. Twelve is under a portrait pixel per
# step on the longest curve here at the working supersample.
_CURVE_STEPS = 12


@dataclass(frozen=True)
class Skull:
    """One general's head: width 0.86-1.14, a jaw, crown -3..3, spread 0.9-1.1."""

    width: float
    jaw: str
    crown: float
    spread: float

    def __post_init__(self) -> None:
        if self.jaw not in JAWS:
            raise KeyError(f"no jaw {self.jaw!r} (have {sorted(JAWS)})")


def _hx(x: float, width: float) -> float:
    """A skull x, scaled about the head's centre — the one place width lands."""
    return HEAD_CX + (x - HEAD_CX) * width


def _quad(start: Point, control: Point, end: Point) -> list[Point]:
    """A quadratic flattened to points, `start` excluded (the caller holds it)."""
    points: list[Point] = []
    for step in range(1, _CURVE_STEPS + 1):
        t = step / _CURVE_STEPS
        inv = 1.0 - t
        points.append(
            (
                inv * inv * start[0] + 2 * inv * t * control[0] + t * t * end[0],
                inv * inv * start[1] + 2 * inv * t * control[1] + t * t * end[1],
            )
        )
    return points


def _jaw_points(skull: Skull, left: float, right: float) -> list[Point]:
    """The lower half of the skull, from the cheekbone down, right side first."""
    width = skull.width
    start, chin = (right, JAW_Y), (HEAD_CX, CHIN_Y)
    if skull.jaw == "square":
        corner_r, bend_r = (_hx(148.0, width), 188.0), (_hx(140.0, width), 204.0)
        corner_l, bend_l = (_hx(80.0, width), 188.0), (_hx(72.0, width), 204.0)
        return [
            corner_r,
            *_quad(corner_r, bend_r, chin),
            *_quad(chin, bend_l, corner_l),
            (left, JAW_Y),
        ]
    if skull.jaw == "tapered":
        return [
            *_quad(start, (_hx(152.0, width), 188.0), chin),
            *_quad(chin, (_hx(68.0, width), 188.0), (left, JAW_Y)),
        ]
    return [
        *_quad(start, (right, 196.0), chin),
        *_quad(chin, (left, 196.0), (left, JAW_Y)),
    ]


def outline(skull: Skull) -> list[Point]:
    """The skull's silhouette, in portrait pixels, before the pose transform."""
    left, right = _hx(SKULL_LEFT, skull.width), _hx(SKULL_RIGHT, skull.width)
    top = CROWN_Y - skull.crown * CROWN_PX
    start = (left, CHEEK_Y)
    crown = [
        start,
        *_quad(start, (left, top), (HEAD_CX, top)),
        *_quad((HEAD_CX, top), (right, top), (right, CHEEK_Y)),
        (right, JAW_Y),
    ]
    return crown + _jaw_points(skull, left, right)


def neck(skull: Skull) -> list[Point]:
    """A neck as wide as the skull it carries."""
    left, right = _hx(NECK_LEFT, skull.width), _hx(NECK_RIGHT, skull.width)
    return [
        (left, NECK_TOP),
        (left, NECK_BOTTOM),
        *_quad((left, NECK_BOTTOM), (HEAD_CX, NECK_BULGE), (right, NECK_BOTTOM)),
        (right, NECK_TOP),
    ]


def ears(skull: Skull) -> tuple[tuple[float, float, float, float], ...]:
    """The two ears, as boxes: an ear is as big as the skull it is set into."""
    radius = EAR_R * skull.width
    return tuple(
        (
            _hx(x, skull.width) - radius,
            EAR_Y - radius,
            _hx(x, skull.width) + radius,
            EAR_Y + radius,
        )
        for x in (EAR_LEFT, EAR_RIGHT)
    )


def _skull_box(skull: Skull) -> tuple[float, float, float, float]:
    """Centre, half-width, crown and height — what a shade shape is placed on."""
    half = (_hx(SKULL_RIGHT, skull.width) - _hx(SKULL_LEFT, skull.width)) / 2.0
    top = CROWN_Y - skull.crown * CROWN_PX
    return (HEAD_CX, half, top, CHIN_Y - top)


def _mask_of(canvas: Canvas, points: list[Point]) -> Image.Image:
    layer = Canvas(canvas.size, canvas.scale)
    layer.polygon(points, (255, 255, 255, 255))
    return layer.silhouette()


def _flat(canvas: Canvas, tone: RGB) -> Image.Image:
    return Image.new("RGBA", canvas.image.size, (*tone, 255))


def ramp_for(skin: str) -> Ramp:
    """The four tones a skin tone is painted in."""
    return light.build_ramp(SKIN_BASES[skin])


def draw(canvas: Canvas, skull: Skull, ramp: Ramp, *, mirrored: bool = False) -> None:
    """Paint the head, the neck and the ear in the skin ramp's four bands.

    Order is the light's: the parts behind the face first, each inked as it is
    laid down, then the face, then the two bands the key writes on it, then
    what the head occludes, then the rim inside the ink. The two bands and the
    occlusion are painted through the face's own mask, so a shade can never
    run off the cheek onto the field. Nothing here is a wash over a fill —
    every mark is one of the ramp's named tones.

    `mirrored` pre-flips the light for a layer the pose is about to turn over:
    the two bands are placed on the other side of the face and the occlusion
    and the rim step the other way in x, so that once the group is flipped they
    land on the screen's shadow side like every unmirrored bust's.
    """
    skin = Canvas(canvas.size, canvas.scale)
    skin.polygon(neck(skull), ramp.shade)
    skin.stroke(neck(skull), INK_FEATURE, (*INK, 255))
    for box in ears(skull):
        skin.ellipse(_grown(box, INK_FEATURE), (*INK, 255))
        skin.ellipse(box, ramp.shade)

    face = outline(skull)
    skin.polygon(face, ramp.base)
    face_mask = _mask_of(skin, face)
    centre, half, top, height = _skull_box(skull)
    placement = {
        "centre": centre,
        "half": -half if mirrored else half,
        "top": top,
        "height": height,
    }
    kind = light.shade_kind(skull.crown, skull.width)
    bands = (
        (light.face_light(**placement), ramp.lit),
        (light.face_shade(kind, **placement), ramp.shade),
    )
    for points, tone in bands:
        band = ImageChops.multiply(_mask_of(skin, points), face_mask)
        skin.image.paste(_flat(skin, tone), (0, 0), band)

    under_jaw = light.occlusion(
        face_mask,
        skin.silhouette(),
        depth=JAW_DEPTH,
        scale=canvas.scale,
        mirrored=mirrored,
    )
    skin.image.paste(_flat(skin, ramp.deep), (0, 0), under_jaw)

    skin.stroke(face, INK_SILHOUETTE, (*INK, 255), closed=True)
    skin.image.alpha_composite(
        light.rim_light(
            skin.silhouette(),
            ramp,
            weight=RIM_WEIGHT,
            inset=RIM_INSET,
            scale=canvas.scale,
            mirrored=mirrored,
        )
    )
    canvas.compose(skin)


def _grown(
    box: tuple[float, float, float, float], by: float
) -> tuple[float, float, float, float]:
    """A box widened all round, which is how an ear wears its contour: an ink
    disc under the skin one, showing as a ring of exactly one ink weight."""
    x0, y0, x1, y1 = box
    return (x0 - by, y0 - by, x1 + by, y1 + by)
