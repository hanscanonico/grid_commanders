"""The worn accessories: what a general has on their head, over their eyes or
across their cheek.

One vocabulary, one dispatch table (`_ACCESSORIES`), and an unknown key raises.
Split out of `features.py` because it is a layer of its own: everything here is
fitted to the same skull through `features.Frame` and drawn after the face is,
so this module reads that one and nothing there reads back.

Every painter takes a `Worn` and hands back what it added to the silhouette —
`bust.py` inks the head around that path, and the roster suite measures a
general's second accessory against it.
"""

from __future__ import annotations

from collections.abc import Callable, Iterable
from dataclasses import dataclass

from .canvas import INK_DETAIL, INK_FEATURE, Canvas, Point
from .features import EAR, EYE_LINE, Frame, eye_xs, ringed_ellipse
from .head import Skull
from .palette import INK, RGB

# What headwear spends that a face does not: the design system's SLATE_800 kit
# slate every strap and every frame is cut from, the handoff's goggle glass, and
# the one flesh tone a scar is cut in.
KIT: RGB = (43, 47, 52)
GLASS: RGB = (188, 214, 224)
SCAR: RGB = (181, 107, 90)
# The cut's own shadow side: a scar is a ribbon here, and a ribbon owes its
# edge a tone a shade under its core.
SCAR_DEEP: RGB = (126, 72, 62)

# Half a lens, squared on the eye line: what survives the mip is the square,
# not the frame drawn around it.
LENS_HALF = 14.0

_BANDANA: tuple[Point, ...] = (
    (60.0, 88.0),
    (76.0, 78.0),
    (110.0, 76.0),
    (144.0, 78.0),
    (160.0, 88.0),
    (152.0, 94.0),
    (68.0, 94.0),
)
_HEADBAND: tuple[Point, ...] = (
    (60.0, 82.0),
    (160.0, 82.0),
    (160.0, 94.0),
    (60.0, 94.0),
)
_HOOD: tuple[Point, ...] = (
    (48.0, 156.0),
    (44.0, 96.0),
    (110.0, 74.0),
    (176.0, 96.0),
    (172.0, 156.0),
    (160.0, 116.0),
    (110.0, 110.0),
    (60.0, 116.0),
)
_HOOD_LINING: tuple[Point, ...] = (
    (48.0, 156.0),
    (56.0, 122.0),
    (110.0, 112.0),
    (164.0, 122.0),
    (172.0, 156.0),
    (160.0, 116.0),
    (110.0, 110.0),
    (60.0, 116.0),
)
# The service cap: a saucer crown that overhangs its band on both sides, and a
# peak wider than either. Both are the silhouette — this is the dress cap, and
# the field cap below it is the same head with all of that taken off.
_CAP_CROWN: tuple[Point, ...] = (
    (50.0, 88.0),
    (54.0, 56.0),
    (98.0, 44.0),
    (124.0, 44.0),
    (166.0, 56.0),
    (170.0, 88.0),
)
# The rim of the crown the key lands on: a band three texels deep, walked in
# along the crown's own upper-left edge. A crown painted flat in one rung is a
# silhouette rather than a cap, and on Iron — whose cloth and whose window field
# round onto neighbouring rungs — it was the darkest chip on the sheet.
_CAP_LIT: tuple[Point, ...] = (
    (52.0, 88.0),
    (56.0, 57.0),
    (98.0, 45.0),
    (124.0, 45.0),
    (124.0, 51.0),
    (100.0, 51.0),
    (62.0, 63.0),
    (60.0, 88.0),
)
_CAP_BAND: tuple[Point, ...] = (
    (54.0, 86.0),
    (166.0, 86.0),
    (166.0, 100.0),
    (54.0, 100.0),
)
_CAP_PEAK: tuple[Point, ...] = (
    (44.0, 98.0),
    (176.0, 98.0),
    (162.0, 114.0),
    (58.0, 114.0),
)
# The soft field cap: the same band, a lower crown that slouches away from the
# key, and no peak at all. The peak is the service cap's whole silhouette, so
# leaving it off is what tells the two caps apart at chip size.
_FIELD_CROWN: tuple[Point, ...] = (
    (56.0, 92.0),
    (60.0, 76.0),
    (92.0, 66.0),
    (140.0, 68.0),
    (168.0, 78.0),
    (170.0, 92.0),
)
_FIELD_LIT: tuple[Point, ...] = (
    (58.0, 92.0),
    (62.0, 77.0),
    (93.0, 67.0),
    (122.0, 68.0),
    (122.0, 74.0),
    (96.0, 73.0),
    (69.0, 82.0),
    (66.0, 92.0),
)
_FIELD_BAND: tuple[Point, ...] = (
    (56.0, 88.0),
    (168.0, 88.0),
    (168.0, 102.0),
    (56.0, 102.0),
)
# The eyeshade: a strap and a wide brim over the brow, and no crown — so the
# hair above it stays part of the outline, which is what separates it from a
# cap. The brim stops above the brow line the eyes are read against.
_VISOR_STRAP: tuple[Point, ...] = (
    (60.0, 90.0),
    (160.0, 90.0),
    (160.0, 104.0),
    (60.0, 104.0),
)
_VISOR_BRIM: tuple[Point, ...] = (
    (42.0, 102.0),
    (178.0, 102.0),
    (158.0, 118.0),
    (62.0, 118.0),
)
_GOGGLE_STRAP: tuple[Point, ...] = (
    (60.0, 100.0),
    (160.0, 100.0),
    (160.0, 112.0),
    (60.0, 112.0),
)
_HEADSET_BAND: tuple[Point, ...] = (
    (60.0, 128.0),
    (72.0, 92.0),
    (110.0, 86.0),
    (148.0, 92.0),
    (160.0, 128.0),
)
_HEADSET_CUP: tuple[Point, ...] = (
    (52.0, 128.0),
    (68.0, 128.0),
    (68.0, 152.0),
    (52.0, 152.0),
)
# The eyepatch: a plate over the eye it covers, in reference pixels off that
# eye's centre, and the strap that lands on the ear. The plate is one flat tone
# all through: what the review read as a domino mask was the lit eye and the
# brow showing inside it, and `covered_eye` is what keeps them off it.
_PATCH_PLATE: tuple[Point, ...] = (
    (-15.0, 130.0),
    (13.0, 127.0),
    (14.0, 148.0),
    (0.0, 158.0),
    (-14.0, 151.0),
)
# One cut, run at the gauge and down the cheek rather than across the socket.
# The two cross-ticks it used to carry were four design units long — one texel
# — and three one-texel marks laid over a brow are the cluster of ink fragments
# the review found orbiting Vale's eye. A scar reads as a scar beside the eye;
# on top of it, it reads as damage to the drawing.
_SCAR_CUT: tuple[Point, ...] = ((140.0, 134.0), (148.0, 164.0))


@dataclass(frozen=True)
class Worn:
    """What a headwear painter is handed.

    One object rather than five parameters: only the two caps spend `kicker` —
    the faction cloth's lit rung — and the other nine painters were carrying it
    down their signatures to ignore it.
    """

    canvas: Canvas
    frame: Frame
    skull: Skull
    tint: RGB
    kicker: RGB

    def path(self, points: Iterable[Point]) -> list[Point]:
        """`points` fitted to this general's own skull."""
        return self.frame.path(points)

    def fill(self, path: Iterable[Point], colour: RGB) -> None:
        self.canvas.polygon(path, colour)

    def ink(self, path: Iterable[Point], *, closed: bool = True) -> None:
        self.canvas.stroke(path, INK_FEATURE, INK, closed=closed)

    def piece(self, points: tuple[Point, ...], colour: RGB) -> list[Point]:
        """One flat mass of cloth, outlined — what most of headwear is made of.

        Returns the path, because what a painter hands back is what it added to
        the silhouette.
        """
        path = self.path(points)
        self.fill(path, colour)
        self.ink(path)
        return path


def _worn(points: tuple[Point, ...]) -> Callable[[Worn], list[Point]]:
    """A piece of headwear that is nothing but one mass in faction cloth."""

    def draw(worn: Worn) -> list[Point]:
        return worn.piece(points, worn.tint)

    return draw


def _hood(worn: Worn) -> list[Point]:
    path = worn.path(_HOOD)
    worn.fill(path, worn.tint)
    worn.fill(worn.path(_HOOD_LINING), KIT)
    worn.ink(path)
    return path


def _crown(worn: Worn, mass: tuple[Point, ...], lit: tuple[Point, ...]) -> list[Point]:
    """A cap crown: `mass` in faction cloth, with `lit` — the part of it the key
    lands on — carried in the coat's lit rung."""
    path = worn.path(mass)
    worn.fill(path, worn.tint)
    worn.fill(worn.path(lit), worn.kicker)
    worn.ink(path)
    return path


def _cap(worn: Worn) -> list[Point]:
    """A service cap: a crown in faction cloth over a kit band and a peak.

    The peak is what makes it a cap rather than a hat at chip size — a straight
    dark bar over the brow, wider than the band it hangs off.
    """
    crown = _crown(worn, _CAP_CROWN, _CAP_LIT)
    for piece in (_CAP_BAND, _CAP_PEAK):
        worn.piece(piece, KIT)
    return crown


def _fieldcap(worn: Worn) -> list[Point]:
    """A soft field cap: a slouched crown over a kit band, and nothing else."""
    crown = _crown(worn, _FIELD_CROWN, _FIELD_LIT)
    worn.piece(_FIELD_BAND, KIT)
    return crown


def _visor(worn: Worn) -> list[Point]:
    """An eyeshade: a kit strap carrying a brim in the general's own cloth."""
    worn.piece(_VISOR_STRAP, KIT)
    return worn.piece(_VISOR_BRIM, worn.tint)


def _goggles(worn: Worn) -> list[Point]:
    path = worn.piece(_GOGGLE_STRAP, KIT)
    for x in eye_xs(worn.skull):
        ringed_ellipse(
            worn.canvas, worn.frame, (x, 106.0), (13.0, 13.0), GLASS, INK_FEATURE
        )
    return path


def _glasses(worn: Worn) -> list[Point]:
    """P17: two squares at the feature weight, and no bridge between them.

    A bridge is the one part of a pair of glasses the mip cannot hold, and it
    was what joined the two lenses into a single grey smear at chip size."""
    for x in eye_xs(worn.skull):
        lens = (
            (x - LENS_HALF, EYE_LINE - LENS_HALF),
            (x + LENS_HALF, EYE_LINE - LENS_HALF),
            (x + LENS_HALF, EYE_LINE + LENS_HALF),
            (x - LENS_HALF, EYE_LINE + LENS_HALF),
        )
        worn.ink(worn.path(lens))
    return []


def _eyepatch(worn: Worn) -> list[Point]:
    x = eye_xs(worn.skull)[0]
    ear_x, ear_y, radius = EAR
    outer_x, outer_y = _PATCH_PLATE[0]
    strap = [(x + outer_x + 2.0, outer_y + 3.0), (ear_x + radius, ear_y - radius)]
    worn.ink(worn.path(strap), closed=False)
    worn.fill(worn.path([(x + dx, y) for dx, y in _PATCH_PLATE]), INK)
    return []


def _scar(worn: Worn) -> list[Point]:
    worn.canvas.ribbon(worn.path(_SCAR_CUT), SCAR, SCAR_DEEP)
    return []


def _headset(worn: Worn) -> list[Point]:
    band = worn.path(_HEADSET_BAND)
    worn.ink(band, closed=False)
    cup = worn.piece(_HEADSET_CUP, worn.tint)
    worn.canvas.ribbon(
        worn.path([(56.0, 148.0), (48.0, 166.0), (80.0, 170.0)]), KIT, INK
    )
    ringed_ellipse(
        worn.canvas, worn.frame, (82.0, 169.0), (4.8, 4.8), worn.tint, INK_DETAIL
    )
    return [*band, *cup]


def _unworn(worn: Worn) -> list[Point]:
    """A general who wears nothing: the one kind that draws nothing."""
    return []


_ACCESSORIES: dict[str, Callable[[Worn], list[Point]]] = {
    "bandana": _worn(_BANDANA),
    "cap": _cap,
    "eyepatch": _eyepatch,
    "fieldcap": _fieldcap,
    "glasses": _glasses,
    "goggles": _goggles,
    "headband": _worn(_HEADBAND),
    "headset": _headset,
    "hood": _hood,
    "none": _unworn,
    "scar": _scar,
    "visor": _visor,
}
ACCESSORY_KINDS = frozenset(_ACCESSORIES)
# Which of the two sockets a worn accessory hides. An eyepatch is the only one
# that hides anything, and it covers the eye and the brow over it: a patch with
# either drawn on top of it is the mask the review named, not a patch.
_COVERS_EYE: dict[str, int] = {"eyepatch": 0}


def covered_eye(kind: str) -> int | None:
    """The socket the worn accessory hides — `eyes` and `brow` skip it."""
    return _COVERS_EYE.get(kind)


def accessory(
    canvas: Canvas, skull: Skull, kind: str, *, tint: RGB = KIT, kicker: RGB = KIT
) -> list[Point]:
    """Draw the worn accessory; returns what it added to the silhouette.

    `tint` is the general's faction colour for the pieces the handoff cut out of
    uniform cloth — a bandana, a headband, a hood, a headset cup. `kicker` is
    that cloth's lit rung, which the two caps catch the key on. Both default to
    the kit slate — the module answers for every key on its own, and a crown
    handed no kicker is the flat one it was before.
    """
    return _ACCESSORIES[kind](Worn(canvas, Frame.of(skull), skull, tint, kicker))
