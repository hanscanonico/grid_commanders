"""The signature props: one per general, each touching the bust and casting.

A prop never floats. The five shouldered ones are drawn behind the figure and
carried by a rig drawn in front of it — five props, five different rigs, because
one repeated diagonal band was the loudest shared mark on the contact sheet. The
rest reach the bust themselves: a bowl resting on the collar, a cable running
down to the shoulder, a lanyard hung off the neckline, a bird's feet on the
shoulder board, or a **sleeve** rising out of the hem to a cuff. The sleeve is
why there is no hand here: a bare flesh disc under an object is the one contact
the reviews rejected outright.

Every prop casts the same hard shadow — one flat tone, no blur, down and to the
right — so it stands off what is behind it under the sheet's one light. Nothing
breaks the frame closer than four pixels to the raster's right edge.

The tones are the shipped drawings' own: steel, wood, tobacco, paper, the
design system's slate, and `UiTheme.AMMO` gold. A prop takes its accent from the
general's faction rather than declaring a hue of its own.
"""

from __future__ import annotations

from collections.abc import Callable, Iterable

from .canvas import INK_DETAIL, INK_FEATURE, INK_SILHOUETTE, Canvas, Point
from .light import Ramp
from .palette import INK, RGB, Faction

PROPS = frozenset(
    {
        "anchor",
        "axe",
        "baton",
        "book",
        "card",
        "cigar",
        "coins",
        "compass",
        "dagger",
        "drone",
        "falcon",
        "hammer",
        "helm",
        "ledger",
        "medal",
        "pipe",
        "plane",
        "radio",
        "sabre",
        "scales",
        "whistle",
        "wrench",
    }
)
# The props worn on a shoulder, which the strap crosses in front of.
SHOULDERED = frozenset({"anchor", "axe", "hammer", "sabre", "wrench"})
# Which half of the figure a call paints: the object behind it, the rig in front
# of it, or — for a preview or a test — both at once.
LAYERS = frozenset({"all", "back", "front"})

# The hard offset shadow every prop drops, in portrait pixels: pure black, no
# blur, down and to the right, the same direction the bust's own cast runs.
PROP_CAST = (2, 2)
PROP_CAST_TONE = (0, 0, 0, 64)

# The four pixels of bleed the raster needs on the right, and the x no prop may
# cross because of it.
RIGHT_BLEED = 4.0
RIGHT_LIMIT = 220.0 - RIGHT_BLEED

STEEL: RGB = (170, 179, 187)
STEEL_LIT: RGB = (207, 214, 221)
SLATE: RGB = (43, 47, 52)
WOOD: RGB = (140, 90, 48)
TOBACCO: RGB = (122, 74, 43)
PAPER: RGB = (242, 234, 216)
GOLD: RGB = (224, 169, 46)


def _ink(canvas: Canvas, points: Iterable[Point], weight: float) -> None:
    canvas.stroke(list(points), weight, (*INK, 255), closed=True)


def _shape(
    canvas: Canvas,
    points: Iterable[Point],
    colour: RGB,
    weight: float = INK_FEATURE,
) -> None:
    """A filled shape and its own outline — the whole drawing grammar here."""
    path = list(points)
    canvas.polygon(path, (*colour, 255))
    _ink(canvas, path, weight)


def _box(x0: float, y0: float, x1: float, y1: float) -> list[Point]:
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def _disc(canvas: Canvas, at: Point, radius: float, colour: RGB) -> None:
    """A disc with an ink ring, drawn as ink under fill so a small stud is not
    an ink weight of its own."""
    x, y = at
    edge = radius + INK_DETAIL / 2.0
    canvas.ellipse((x - edge, y - edge, x + edge, y + edge), (*INK, 255))
    canvas.ellipse((x - radius, y - radius, x + radius, y + radius), (*colour, 255))


def _sleeve(canvas: Canvas, cuff: Point, faction: Faction, ramp: Ramp) -> None:
    """The arm a held prop is held by: cloth out of the hem, never a flesh disc."""
    x, y = cuff
    _shape(
        canvas,
        [
            (x - 26.0, 268.0),
            (x - 17.0, y + 8.0),
            (x + 17.0, y + 8.0),
            (x + 26.0, 268.0),
        ],
        ramp.shade,
    )
    _shape(canvas, _box(x - 19.0, y - 2.0, x + 19.0, y + 10.0), ramp.deep, INK_DETAIL)


def _cord(canvas: Canvas, first: Point, second: Point, colour: RGB) -> None:
    """One rope of a lanyard: ink under a lighter core, so a cord thin enough to
    read as rope still carries the sheet's outline."""
    canvas.stroke([first, second], INK_FEATURE, (*INK, 255))
    canvas.stroke([first, second], INK_DETAIL, (*colour, 255))


# --- the five shouldered objects, drawn behind the figure ---------------------


def _sabre_back(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _shape(
        canvas,
        [(164.0, 220.0), (190.0, 92.0), (202.0, 98.0), (176.0, 224.0)],
        STEEL_LIT,
    )
    canvas.stroke([(156.0, 208.0), (186.0, 220.0)], INK_SILHOUETTE, (*INK, 255))


def _wrench_back(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _shape(
        canvas, [(160.0, 220.0), (178.0, 138.0), (194.0, 142.0), (176.0, 224.0)], STEEL
    )
    _shape(
        canvas,
        [
            (172.0, 144.0),
            (164.0, 116.0),
            (186.0, 108.0),
            (200.0, 116.0),
            (196.0, 134.0),
            (182.0, 130.0),
            (180.0, 142.0),
        ],
        STEEL,
    )


def _anchor_back(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _shape(canvas, _box(166.0, 96.0, 182.0, 222.0), STEEL)
    _shape(canvas, _box(150.0, 114.0, 198.0, 128.0), STEEL)
    _ink(
        canvas,
        [(174.0, 68.0), (190.0, 84.0), (174.0, 100.0), (158.0, 84.0)],
        INK_SILHOUETTE,
    )
    _shape(
        canvas,
        [
            (152.0, 152.0),
            (158.0, 198.0),
            (174.0, 208.0),
            (192.0, 198.0),
            (198.0, 152.0),
            (186.0, 158.0),
            (182.0, 188.0),
            (174.0, 194.0),
            (166.0, 188.0),
            (164.0, 158.0),
        ],
        STEEL,
    )


def _axe_back(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _shape(canvas, [(172.0, 206.0), (178.0, 60.0), (192.0, 62.0), (186.0, 208.0)], WOOD)
    _shape(
        canvas,
        [
            (166.0, 64.0),
            (188.0, 54.0),
            (198.0, 88.0),
            (188.0, 116.0),
            (166.0, 108.0),
            (176.0, 96.0),
            (178.0, 82.0),
        ],
        STEEL_LIT,
    )


def _hammer_back(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _shape(canvas, [(162.0, 68.0), (180.0, 68.0), (176.0, 208.0), (158.0, 208.0)], WOOD)
    _shape(canvas, _box(146.0, 42.0, 194.0, 76.0), STEEL)
    canvas.rect((180.0, 44.0, 192.0, 74.0), (*SLATE, 255))


# --- what carries them, drawn in front ---------------------------------------


def _sabre_front(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _shape(
        canvas,
        [(160.0, 210.0), (184.0, 222.0), (142.0, 268.0), (116.0, 256.0)],
        faction.body_dk,
        INK_DETAIL,
    )
    _disc(canvas, (152.0, 238.0), 7.0, GOLD)


def _wrench_front(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _shape(
        canvas,
        [(144.0, 204.0), (180.0, 216.0), (168.0, 246.0), (132.0, 234.0)],
        faction.body_dk,
        INK_DETAIL,
    )
    _shape(canvas, _box(146.0, 218.0, 164.0, 234.0), SLATE, INK_DETAIL)


def _anchor_front(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _cord(canvas, (164.0, 208.0), (126.0, 268.0), faction.body_dk)
    _cord(canvas, (178.0, 216.0), (140.0, 268.0), faction.body_dk)


def _axe_front(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _shape(
        canvas,
        [(160.0, 208.0), (178.0, 218.0), (146.0, 268.0), (126.0, 258.0)],
        faction.body_dk,
        INK_DETAIL,
    )
    _shape(
        canvas,
        [(138.0, 218.0), (148.0, 204.0), (186.0, 236.0), (176.0, 252.0)],
        faction.body_dk,
        INK_DETAIL,
    )
    _disc(canvas, (156.0, 230.0), 7.0, GOLD)


def _hammer_front(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _shape(
        canvas,
        [(164.0, 212.0), (188.0, 228.0), (130.0, 268.0), (112.0, 250.0)],
        faction.body_dk,
        INK_DETAIL,
    )
    for start, end in (
        ((156.0, 224.0), (144.0, 244.0)),
        ((138.0, 240.0), (126.0, 258.0)),
    ):
        canvas.stroke([start, end], INK_DETAIL, (*INK, 255))


# --- the worn props, which reach the bust on their own ------------------------


def _pipe(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    canvas.stroke(
        [(122.0, 168.0), (140.0, 190.0), (150.0, 200.0)], INK_FEATURE, (*WOOD, 255)
    )
    _disc(canvas, (152.0, 208.0), 10.0, WOOD)


def _cigar(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _shape(
        canvas,
        [(116.0, 164.0), (148.0, 154.0), (152.0, 166.0), (120.0, 176.0)],
        TOBACCO,
    )
    _disc(canvas, (152.0, 160.0), 4.0, faction.body_lt)


def _medal(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _shape(canvas, _box(26.0, 218.0, 64.0, 232.0), GOLD, INK_DETAIL)
    _shape(canvas, _box(156.0, 218.0, 194.0, 232.0), GOLD, INK_DETAIL)
    _shape(
        canvas,
        [(70.0, 212.0), (88.0, 212.0), (85.0, 230.0), (73.0, 230.0)],
        faction.body,
    )
    _disc(canvas, (79.0, 240.0), 9.0, GOLD)


def _drone(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    canvas.stroke(
        [(164.0, 112.0), (176.0, 162.0), (168.0, 214.0)], INK_DETAIL, (*SLATE, 255)
    )
    _shape(canvas, _box(142.0, 90.0, 160.0, 96.0), faction.body_lt, INK_DETAIL)
    _shape(canvas, _box(168.0, 90.0, 186.0, 96.0), faction.body_lt, INK_DETAIL)
    _shape(canvas, _box(150.0, 96.0, 178.0, 114.0), SLATE)
    _disc(canvas, (172.0, 105.0), 3.0, faction.body_lt)


def _falcon(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _shape(
        canvas,
        [
            (152.0, 158.0),
            (140.0, 178.0),
            (144.0, 204.0),
            (164.0, 212.0),
            (176.0, 192.0),
            (172.0, 166.0),
        ],
        WOOD,
    )
    canvas.stroke([(148.0, 178.0), (154.0, 198.0)], INK_DETAIL, (*INK, 255))
    _disc(canvas, (166.0, 150.0), 11.0, PAPER)
    _shape(canvas, [(176.0, 146.0), (190.0, 152.0), (176.0, 158.0)], GOLD, INK_DETAIL)
    _disc(canvas, (168.0, 147.0), 2.0, INK)


def _helm(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _shape(
        canvas,
        [
            (34.0, 268.0),
            (30.0, 226.0),
            (50.0, 208.0),
            (74.0, 208.0),
            (90.0, 226.0),
            (86.0, 268.0),
        ],
        STEEL,
    )
    canvas.stroke(
        [(34.0, 224.0), (60.0, 206.0), (86.0, 224.0)],
        INK_SILHOUETTE,
        (*faction.body, 255),
    )
    canvas.stroke([(60.0, 212.0), (60.0, 268.0)], INK_DETAIL, (*SLATE, 255))


def _scales(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _shape(canvas, _box(52.0, 196.0, 62.0, 268.0), STEEL)
    _shape(canvas, _box(28.0, 188.0, 96.0, 198.0), STEEL)
    for x in (36.0, 88.0):
        canvas.stroke([(x, 196.0), (x, 214.0)], INK_DETAIL, (*INK, 255))
    _shape(canvas, [(22.0, 214.0), (50.0, 214.0), (36.0, 230.0)], GOLD, INK_DETAIL)
    _shape(canvas, [(74.0, 214.0), (102.0, 214.0), (88.0, 230.0)], GOLD, INK_DETAIL)
    _disc(canvas, (57.0, 186.0), 5.0, GOLD)


def _whistle(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _cord(canvas, (94.0, 208.0), (104.0, 242.0), GOLD)
    _cord(canvas, (126.0, 208.0), (118.0, 242.0), GOLD)
    _shape(canvas, [(78.0, 244.0), (96.0, 240.0), (96.0, 256.0), (78.0, 252.0)], GOLD)
    _shape(canvas, _box(96.0, 238.0, 128.0, 258.0), GOLD)
    _disc(canvas, (114.0, 248.0), 3.0, INK)


# --- the held props: a sleeve and an object ----------------------------------


def _baton(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _sleeve(canvas, (74.0, 226.0), faction, ramp)
    _shape(
        canvas,
        [(44.0, 240.0), (154.0, 200.0), (158.0, 212.0), (48.0, 252.0)],
        WOOD,
        INK_DETAIL,
    )
    _disc(canvas, (48.0, 246.0), 6.0, GOLD)
    _disc(canvas, (156.0, 206.0), 6.0, GOLD)


def _card(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _sleeve(canvas, (158.0, 232.0), faction, ramp)
    _shape(canvas, _box(140.0, 178.0, 176.0, 226.0), PAPER)
    _shape(
        canvas,
        [(158.0, 190.0), (168.0, 202.0), (158.0, 214.0), (148.0, 202.0)],
        faction.body,
        INK_DETAIL,
    )


def _book(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _sleeve(canvas, (56.0, 238.0), faction, ramp)
    _shape(
        canvas,
        [
            (20.0, 214.0),
            (48.0, 204.0),
            (76.0, 214.0),
            (76.0, 246.0),
            (48.0, 236.0),
            (20.0, 246.0),
        ],
        PAPER,
    )
    canvas.stroke([(48.0, 206.0), (48.0, 238.0)], INK_DETAIL, (*INK, 255))


def _dagger(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _sleeve(canvas, (168.0, 226.0), faction, ramp)
    _shape(canvas, [(174.0, 138.0), (184.0, 196.0), (158.0, 196.0)], STEEL_LIT)
    _shape(canvas, _box(160.0, 196.0, 180.0, 214.0), WOOD, INK_DETAIL)


def _plane(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _sleeve(canvas, (150.0, 234.0), faction, ramp)
    _shape(
        canvas, [(118.0, 198.0), (146.0, 186.0), (178.0, 200.0), (146.0, 210.0)], PAPER
    )
    _shape(
        canvas,
        [(138.0, 188.0), (152.0, 168.0), (160.0, 172.0), (152.0, 194.0)],
        faction.body,
        INK_DETAIL,
    )
    _shape(
        canvas,
        [(120.0, 196.0), (110.0, 184.0), (116.0, 202.0)],
        faction.body,
        INK_DETAIL,
    )


def _radio(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _sleeve(canvas, (150.0, 232.0), faction, ramp)
    canvas.stroke(
        [(146.0, 168.0), (132.0, 132.0), (142.0, 110.0)], INK_DETAIL, (*INK, 255)
    )
    _shape(canvas, _box(134.0, 166.0, 168.0, 214.0), SLATE)
    for y in (176.0, 184.0):
        canvas.stroke([(140.0, y), (162.0, y)], INK_DETAIL, (*PAPER, 255))


def _coins(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _sleeve(canvas, (158.0, 238.0), faction, ramp)
    _disc(canvas, (166.0, 204.0), 10.0, GOLD)
    _disc(canvas, (188.0, 186.0), 10.0, GOLD)
    _disc(canvas, (150.0, 178.0), 10.0, GOLD)


def _compass(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _sleeve(canvas, (72.0, 242.0), faction, ramp)
    _disc(canvas, (56.0, 208.0), 24.0, PAPER)
    _ink(
        canvas, [(56.0, 190.0), (74.0, 208.0), (56.0, 226.0), (38.0, 208.0)], INK_DETAIL
    )
    _shape(
        canvas, [(56.0, 190.0), (63.0, 208.0), (56.0, 214.0)], faction.body, INK_DETAIL
    )
    _shape(canvas, [(56.0, 226.0), (49.0, 208.0), (56.0, 214.0)], STEEL, INK_DETAIL)


def _ledger(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    _sleeve(canvas, (76.0, 246.0), faction, ramp)
    _shape(canvas, _box(24.0, 206.0, 76.0, 248.0), PAPER)
    _shape(canvas, _box(64.0, 216.0, 82.0, 232.0), STEEL, INK_DETAIL)
    for y in (216.0, 224.0, 232.0):
        canvas.stroke([(32.0, y), (56.0, y)], INK_DETAIL, (*SLATE, 255))


_BACK: dict[str, Callable[[Canvas, Faction, Ramp], None]] = {
    "anchor": _anchor_back,
    "axe": _axe_back,
    "hammer": _hammer_back,
    "sabre": _sabre_back,
    "wrench": _wrench_back,
}

_FRONT: dict[str, Callable[[Canvas, Faction, Ramp], None]] = {
    "anchor": _anchor_front,
    "axe": _axe_front,
    "baton": _baton,
    "book": _book,
    "card": _card,
    "cigar": _cigar,
    "coins": _coins,
    "compass": _compass,
    "dagger": _dagger,
    "drone": _drone,
    "falcon": _falcon,
    "hammer": _hammer_front,
    "helm": _helm,
    "ledger": _ledger,
    "medal": _medal,
    "pipe": _pipe,
    "plane": _plane,
    "radio": _radio,
    "sabre": _sabre_front,
    "scales": _scales,
    "whistle": _whistle,
    "wrench": _wrench_front,
}


def draw(
    canvas: Canvas,
    key: str,
    faction: Faction,
    ramp: Ramp,
    *,
    layer: str = "all",
) -> None:
    """The prop, behind the figure, with its rig in front. Unknown keys raise.

    `layer` is which half the painter wants: the bust is drawn between `back`
    and `front`, and `all` paints both onto one surface for a preview.
    """
    if key not in PROPS:
        raise KeyError(f"no prop {key!r} (have {sorted(PROPS)})")
    if layer not in LAYERS:
        raise KeyError(f"no prop layer {layer!r} (have {sorted(LAYERS)})")
    art = Canvas(canvas.size, canvas.scale)
    if layer in ("all", "back") and key in _BACK:
        _BACK[key](art, faction, ramp)
    if layer in ("all", "front"):
        _FRONT[key](art, faction, ramp)
    canvas.cast_shadow(art, offset=PROP_CAST, tone=PROP_CAST_TONE)
    canvas.compose(art)
