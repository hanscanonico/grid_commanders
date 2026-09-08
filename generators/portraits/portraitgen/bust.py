"""One general, composed: the layer order a bust is painted in, and the pose.

Every module under `portraitgen/` owns one layer and none of them owns a
general; this is where a roster row becomes a picture. The order is the
handoff's own — prop behind, hair behind, uniform, head, features, hair over,
prop in front — with the backdrop under all of it and the hard cast shadow
between the two.

Two things are decided here and nowhere else.

**The pose is an affine over the figure, not a rotation of the finished sheet.**
Tilt and zoom are one matrix whose coefficients are rounded before they are
used, so no libm's cosine can move an edge by a pixel between two machines, and
it is sampled nearest on the grid the figure was drawn on. Nothing in this
pipeline blends two tones: `palette.quantise` is the one place a pixel settles,
and it settles onto a rung `palette.bust_palette` already handed this bust.

**Nothing under the gauge survives the bake.** The last thing `paint` does is
sweep the quantised raster for clusters too small to be marks (`gauge.despeckle`)
— the opaque flecks a band leaves strung along a silhouette once every pixel of
it has been rounded onto sixteen tones. What the sweep takes was never authored;
what was authored is drawn to the gauge in the first place.

**A prop stays inside the frame the pose would push it out of.** `props.py`
states its bleed line in portrait pixels, and the zoom is applied after it, so
the limit can only be kept here: a prop whose posed corner would cross the line
is walked back inside it as a whole, both layers together, before the pose.
Shoulders are meant to bleed off the sides; a signature prop cut in half by the
raster edge is the defect the review named.

**A mirrored pose flips geometry, never light.** The five mirrored rows flip
the layers that carry a face's asymmetry — the hair, the head, the features —
and nothing else: the uniform, the props and the window never turn, so the
shoulder the sheet is lit on is the same shoulder on all 23 busts. The light
inside the flipped group is pre-flipped (`head.draw(mirrored=True)`) so that it
lands on the screen's shadow side once the group is turned over.
"""

from __future__ import annotations

import math
from collections.abc import Callable
from dataclasses import dataclass

from PIL import Image

from . import backdrop, features, gauge, hair, head, light, props, roster, uniform
from .canvas import BUST_DIVISOR, CAST_TONE, CHIP_DIVISOR, Canvas, face_box
from .palette import Faction, bust_palette, faction_by_key, quantise
from .roster import EmptySeat, Face

# Which army a general wears. The faction is presentation only, and this is the
# one place the roster's rows are grouped by it: `CommanderVisuals` seats them.
FACTION_OF: dict[str, str] = {
    "alina_ward": "meridian",
    "gideon_holt": "meridian",
    "mara_voss": "meridian",
    "halden_marr": "meridian",
    "iris_colt": "meridian",
    "cass_orlov": "iron",
    "viktor_draeg": "iron",
    "konrad_vale": "iron",
    "dane_ferrow": "iron",
    "iona_vance": "iron",
    "radek_morn": "iron",
    "cassian_rook": "aurora",
    "orin_flux": "aurora",
    "perrin_ash": "aurora",
    "sera_lark": "aurora",
    "nia_rowan": "verdant",
    "tomas_reed": "verdant",
    "ines_calder": "verdant",
    "ivar_thorne": "verdant",
    "rhea_sol": "gold",
    "lyra_quill": "gold",
    "sable_wren": "gold",
}

# The pose's two anchors, in portrait pixels: the zoom is taken about the
# bottom centre, because the composition is anchored there and a chest-up crop
# has to stay anchored there, and the tilt about the head, because a bust leans
# from the neck rather than from the frame.
ZOOM_AT = (110.0, 268.0)
TILT_AT = (110.0, 168.0)
# Where a matrix coefficient is cut off. Nine places is far finer than a
# portrait pixel and far coarser than the last bit of a double, so two machines'
# trigonometry agree exactly on the number the sampler is handed.
_COEFF_PLACES = 9

Matrix = tuple[float, float, float, float, float, float]


@dataclass(frozen=True)
class Painted:
    """A finished bust and the file it is baked as."""

    id: str
    image: Image.Image


def _compose(outer: Matrix, inner: Matrix) -> Matrix:
    """`outer` applied after `inner`, as one matrix."""
    a, b, c, d, e, f = outer
    p, q, r, s, t, u = inner
    return (
        a * p + b * s,
        a * q + b * t,
        a * r + b * u + c,
        d * p + e * s,
        d * q + e * t,
        d * r + e * u + f,
    )


def _scaled_about(factor: float, at: tuple[float, float]) -> Matrix:
    return (factor, 0.0, at[0] * (1.0 - factor), 0.0, factor, at[1] * (1.0 - factor))


def _turned_about(degrees: float, at: tuple[float, float]) -> Matrix:
    radians = math.radians(degrees)
    cos = round(math.cos(radians), _COEFF_PLACES)
    sin = round(math.sin(radians), _COEFF_PLACES)
    x, y = at
    return (
        cos,
        -sin,
        x - cos * x + sin * y,
        sin,
        cos,
        y - sin * x - cos * y,
    )


def pose_matrix(tilt: float, zoom: float, *, divisor: int = BUST_DIVISOR) -> Matrix:
    """The inverse map a pose is sampled through, in native pixels.

    `divisor` is the grid the figure was drawn on: the rotation terms are
    scale-free, the two translations are design units and divide onto it.

    Pillow's affine transform reads its matrix backwards — it asks, for each
    output pixel, which input pixel to take — so what is built here is the
    inverse of "scale about the bottom centre, then lean about the head".
    """
    inverse = _compose(
        _scaled_about(1.0 / zoom, ZOOM_AT), _turned_about(-tilt, TILT_AT)
    )
    a, b, c, d, e, f = inverse
    return tuple(
        round(value, _COEFF_PLACES) for value in (a, b, c / divisor, d, e, f / divisor)
    )


def _posed(figure: Canvas, tilt: float, zoom: float) -> Canvas:
    """The figure leaned and zoomed, sampled nearest at the working scale."""
    posed = figure.blank()
    posed.image = figure.image.transform(
        figure.image.size,
        Image.Transform.AFFINE,
        pose_matrix(tilt, zoom, divisor=figure.divisor),
        resample=Image.Resampling.NEAREST,
    )
    return posed


def _flipped(layer: Canvas) -> Canvas:
    """A layer turned about the raster's centre line — geometry only."""
    turned = layer.blank()
    turned.image = layer.image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    return turned


def _corners(box: tuple[int, int, int, int]) -> tuple[tuple[float, float], ...]:
    x0, y0, x1, y1 = box
    return ((x0, y0), (x1, y0), (x0, y1), (x1, y1))


def _forward(tilt: float, zoom: float) -> Matrix:
    """Where the pose sends a point, in portrait pixels."""
    return _compose(_turned_about(tilt, TILT_AT), _scaled_about(zoom, ZOOM_AT))


def _bleed_shift(
    box: tuple[int, int, int, int] | None, tilt: float, zoom: float
) -> int:
    """How far left a prop has to move to keep the bleed line once posed."""
    if box is None:
        return 0
    a, b, c, *_ = _forward(tilt, zoom)
    reach = max(a * x + b * y + c for x, y in _corners(box))
    return max(0, math.ceil((reach - props.RIGHT_LIMIT) / zoom))


def _prop_layers(
    on: Canvas, face: Face, army: Faction, cloth: light.Ramp
) -> tuple[Canvas, Canvas]:
    """The prop behind the figure and its rig in front, both walked inboard."""
    whole = on.blank()
    props.draw(whole, face.prop, army, cloth, layer="all")
    shift = _bleed_shift(_design_box(whole), *face.pose[:2])
    layers = []
    for half in ("back", "front"):
        art = on.blank()
        props.draw(art, face.prop, army, cloth, layer=half)
        layers.append(_walked(art, shift))
    return tuple(layers)


def _design_box(layer: Canvas) -> tuple[int, int, int, int] | None:
    """What a layer covers, back in design units — the space the bleed line and
    the pose are both stated in."""
    box = layer.resolve().getbbox()
    return None if box is None else tuple(edge * layer.divisor for edge in box)


def _walked(layer: Canvas, by: int) -> Canvas:
    """A layer moved left a whole number of design units."""
    if by == 0:
        return layer
    moved = layer.blank()
    moved.image.paste(layer.image, (-layer.px(by), 0))
    return moved


def _face_group(
    on: Canvas, face: Face, skin: light.Ramp, mane: light.Ramp, cloth: light.Ramp
) -> Canvas:
    """Everything above the collar: the head, its features and its hair over."""
    group = on.blank()
    head.draw(group, face.head, skin, mirrored=face.pose[2])
    features.facial_hair(group, face.head, face.facial, mane)
    hair.front(group, face.head, face.style, mane, skin=skin)
    # Headwear cut out of uniform cloth is painted in the coat's own rungs —
    # its base, and its lit rung along the key's edge (`features._CAP_LIT`).
    for worn in (face.acc, face.acc2):
        features.accessory(group, face.head, worn, tint=cloth.base, kicker=cloth.lit)
    covered = features.covered_eye(face.acc)
    features.brow(group, face.head, face.brow, mane, covered=covered)
    features.eyes(group, face.head, face.eyes, scale=face.eye, covered=covered)
    features.nose(group, face.head, face.nose, skin)
    features.mouth(group, face.head, face.mouth, eye=face.eye)
    if face.earring:
        features.earring(group, face.head)
    if face.freckles:
        features.freckles(group, face.head, skin)
    return group


def _faction(face: Face) -> Faction:
    return faction_by_key(FACTION_OF[face.id])


def _general(on: Canvas, face: Face) -> Canvas:
    """One general's figure, unposed: the five layers and which of them turn."""
    army = _faction(face)
    cloth = _cloth(army)
    skin = light.build_ramp(head.SKIN_BASES[face.skin])
    mane = hair.ramp_for(face.hair)

    behind_prop, front_prop = _prop_layers(on, face, army, cloth)
    figure = on.blank()
    figure.compose(behind_prop)

    behind = on.blank()
    hair.back(behind, face.head, face.style, mane)

    dress = on.blank()
    uniform.draw(dress, army, face.collar, cloth)
    uniform.chest(dress, face.chest, army, cloth)
    if face.pip:
        uniform.pip(dress, cloth)

    above = _face_group(on, face, skin, mane, cloth)
    if face.pose[2]:
        behind, above = _flipped(behind), _flipped(above)

    figure.compose(behind)
    figure.compose(dress)
    figure.compose(above)
    figure.compose(front_prop)
    return figure


def _empty_seat(on: Canvas, seat: EmptySeat) -> Canvas:
    """The seat nobody holds: the shared skull, in slate, with no face on it.

    Deliberately featureless — an empty seat has to read as a choice rather
    than as a bust that failed to render — so it is the one figure that names
    no hair, no expression and no prop.
    """
    army = faction_by_key("neutral")
    cloth = _cloth(army)
    figure = on.blank()
    uniform.draw(figure, army, uniform.COLLAR_DEFAULT, cloth)
    uniform.chest(figure, uniform.CHEST_DEFAULT, army, cloth)
    head.draw(figure, seat.head, cloth)
    return figure


def _army_of(spec: Face | EmptySeat) -> Faction:
    return _faction(spec) if isinstance(spec, Face) else faction_by_key("neutral")


def _cloth(army: Faction) -> light.Ramp:
    """The rungs an army's coat is painted in — the board's own, so a general
    and their armour are the same red."""
    return light.Ramp.of_faction(army.key)


def palette_of(spec: Face | EmptySeat) -> tuple[tuple[int, int, int], ...]:
    """The sixteen tones this bust is painted in, before a pixel is drawn."""
    army = _army_of(spec)
    if isinstance(spec, Face):
        skin = light.build_ramp(head.SKIN_BASES[spec.skin]).six
        mane = hair.ramp_for(spec.hair).six
    else:
        skin = mane = _cloth(army).six
    return bust_palette(army.key, skin, mane)


def paint(
    spec: Face | EmptySeat, *, cast: bool = True, divisor: int = BUST_DIVISOR
) -> Image.Image:
    """One finished bust, on its own grid and in its own sixteen tones.

    `cast=False` is the same bust with the hard offset shadow left off, which
    is how "the shadow was drawn" is measured: the difference between the two
    is the shadow and nothing else. `divisor` is which grid it lands on: the
    bust's, or the coarser one a face chip is cut from.
    """
    tilt, zoom, _ = spec.pose

    sheet = Canvas(divisor=divisor)
    backdrop.draw(sheet, spec.bg, _army_of(spec))
    figure = _posed(
        _general(sheet, spec) if isinstance(spec, Face) else _empty_seat(sheet, spec),
        tilt,
        zoom,
    )
    if cast:
        sheet.cast_shadow(figure)
    sheet.compose(figure)
    return gauge.despeckle(
        quantise(sheet.resolve(), palette_of(spec), shadow=CAST_TONE)
    )


def chip(spec: Face | EmptySeat) -> Image.Image:
    """The face a surface too small for a bust draws.

    The same drawing, rasterised on the chip grid and cut to the head's own
    square — never the bust resampled, which is the softness this bake exists
    to end. `CommanderVisuals.face_for` loads exactly this file.
    """
    return paint(spec, divisor=CHIP_DIVISOR).crop(face_box(CHIP_DIVISOR))


def prop_art(face: Face) -> Image.Image:
    """A general's prop alone, posed — what the frame-safety bleed is read off."""
    army = _faction(face)
    cloth = _cloth(army)
    art = Canvas()
    for half in _prop_layers(art, face, army, cloth):
        art.compose(half)
    return _posed(art, *face.pose[:2]).resolve()


def window(spec: Face | EmptySeat, *, divisor: int = BUST_DIVISOR) -> Image.Image:
    """The bust's backdrop alone — the field the figure is measured against."""
    sheet = Canvas(divisor=divisor)
    backdrop.draw(sheet, spec.bg, _army_of(spec))
    return quantise(sheet.resolve(), palette_of(spec), shadow=CAST_TONE)


def _sheet(art: Callable[[Face | EmptySeat], Image.Image]) -> list[Painted]:
    """Every seat the sheet carries, in roster order and the empty one last."""
    rows = [*sorted(roster.FACES.items()), (roster.NEUTRAL_ID, roster.NEUTRAL)]
    return [Painted(key, art(spec)) for key, spec in rows]


def busts() -> list[Painted]:
    """Every bust the sheet carries, the empty seat last."""
    return _sheet(paint)


def chips() -> list[Painted]:
    """Every face chip the sheet carries, the empty seat last."""
    return _sheet(chip)
