"""Shoulders, chest, collar cut, chest treatment and the rank pip.

The mass is painted in the faction ramp's four flat tones — deep under the
collar, shade on the side away from the light, base across the chest, lit along
the upper-left run — plus the rim along that same run. No band is an alpha wash
over a fill and there is no texture fill: cloth reads by *cut*, and a single 2px
seam beats any weave, which mips into mud and spends colours.

Two vocabularies live here. The three collar cuts are silhouettes rather than
decorations — the V notches the mass, the mandarin stands a band above the
shoulder line, the double-breasted facing crosses the chest — so a bust is still
told apart at 31px, where nothing inside the outline survives. The chest
treatments are the second: thirteen of them, so the sheet's twenty-two generals
can wear one each without any being shared by more than two.

The gold is `UiTheme.AMMO`, and the rank pip is the only place a general who has
not earned it may not wear it.
"""

from __future__ import annotations

from collections.abc import Callable

from .canvas import INK_DETAIL, INK_FEATURE, INK_SILHOUETTE, Canvas, Point
from .light import Ramp
from .palette import INK, RGB, Faction

COLLAR_CUTS = frozenset({"double", "mandarin", "v"})
COLLAR_DEFAULT = "v"

# What a general carries on the chest under the collar. Thirteen over the
# sheet's twenty-two — nine worn by a pair, four by one — and no treatment may
# be worn by more than two.
CHEST_TREATMENTS = frozenset(
    {
        "bandolier",
        "boards",
        "crossbelt",
        "epaulette",
        "harness",
        "lanyard",
        "loops",
        "mapcase",
        "placket",
        "plain",
        "pouch",
        "sash",
        "scarf",
    }
)
CHEST_DEFAULT = "plain"

# UiTheme.AMMO, the one gold the portraits borrow.
GOLD: RGB = (224, 169, 46)

# The two patches the sheet's one light is measured on
# (`tests/unit/test_commander_portraits.gd`) are the outer shoulder wedges, and
# a payload dark enough to cover one of them turns a bust's light around. So a
# chest treatment is worn on the chest: nothing below the collar line reaches
# further out than this, at any zoom the roster poses at.
PAYLOAD_INBOARD = 52.0

# The uniform mass every bust rises out of, in portrait pixels: the handoff's
# shoulder path, its two quadratics cut into chamfers so the whole outline is
# one polygon the ink and the shade can both follow.
MASS: tuple[Point, ...] = (
    (12.0, 268.0),
    (12.0, 246.0),
    (22.0, 222.0),
    (48.0, 210.0),
    (66.0, 206.0),
    (154.0, 206.0),
    (172.0, 210.0),
    (198.0, 222.0),
    (208.0, 246.0),
    (208.0, 268.0),
)
# Where the rank pip sits — out on the left shoulder, the one spot all three
# collars leave clear.
PIP_AT = (64.0, 232.0)


def _ink(canvas: Canvas, points: list[Point], weight: float, *, closed: bool) -> None:
    canvas.stroke(points, weight, (*INK, 255), closed=closed)


def _stud(canvas: Canvas, at: Point, radius: float, colour: RGB) -> None:
    """A disc with its own ink ring, drawn as ink under fill rather than as a
    stroke, so a 4px stud is not a 4px ink weight."""
    x, y = at
    edge = radius + INK_DETAIL / 2.0
    canvas.ellipse((x - edge, y - edge, x + edge, y + edge), (*INK, 255))
    canvas.ellipse((x - radius, y - radius, x + radius, y + radius), (*colour, 255))


def _mass(canvas: Canvas, ramp: Ramp) -> None:
    canvas.polygon(MASS, (*ramp.base, 255))
    canvas.polygon(
        [
            (130.0, 206.0),
            (154.0, 206.0),
            (172.0, 210.0),
            (198.0, 222.0),
            (208.0, 246.0),
            (208.0, 268.0),
            (150.0, 268.0),
        ],
        (*ramp.shade, 255),
    )
    canvas.polygon(
        [(72.0, 206.0), (148.0, 206.0), (140.0, 228.0), (80.0, 228.0)],
        (*ramp.deep, 255),
    )
    canvas.polygon(
        [
            (12.0, 246.0),
            (22.0, 222.0),
            (48.0, 210.0),
            (66.0, 206.0),
            (78.0, 206.0),
            (56.0, 216.0),
            (32.0, 230.0),
            (22.0, 252.0),
        ],
        (*ramp.lit, 255),
    )
    # The rim: the kicker along the lit run, and the one seam the cloth gets.
    canvas.stroke(
        [(12.0, 246.0), (22.0, 222.0), (48.0, 210.0), (66.0, 206.0)],
        INK_DETAIL,
        (*ramp.rim, 255),
    )
    canvas.stroke(
        [(70.0, 214.0), (92.0, 238.0), (92.0, 268.0)],
        INK_DETAIL,
        (*ramp.deep, 255),
    )
    _ink(canvas, list(MASS), INK_SILHOUETTE, closed=True)


def _collar_v(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    """The handoff's chevron: a notch cut deep into the mass."""
    canvas.polygon(
        [
            (80.0, 206.0),
            (110.0, 236.0),
            (140.0, 206.0),
            (140.0, 214.0),
            (110.0, 246.0),
            (80.0, 214.0),
        ],
        (*faction.body_dk, 255),
    )
    _ink(
        canvas,
        [(88.0, 206.0), (110.0, 228.0), (132.0, 206.0)],
        INK_FEATURE,
        closed=False,
    )


def _collar_mandarin(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    """A standing band: the one cut whose silhouette rises above the shoulders."""
    band: list[Point] = [
        (84.0, 200.0),
        (96.0, 188.0),
        (124.0, 188.0),
        (136.0, 200.0),
        (136.0, 214.0),
        (110.0, 222.0),
        (84.0, 214.0),
    ]
    canvas.polygon(band, (*faction.body_dk, 255))
    _ink(canvas, band, INK_FEATURE, closed=True)
    canvas.stroke([(110.0, 190.0), (110.0, 220.0)], INK_DETAIL, (*ramp.deep, 255))


def _collar_double(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    """A double-breasted facing, off centre, carrying its two gold buttons."""
    canvas.polygon(
        [(126.0, 206.0), (148.0, 206.0), (108.0, 268.0), (84.0, 268.0)],
        (*faction.body_dk, 255),
    )
    _ink(
        canvas,
        [(80.0, 206.0), (94.0, 222.0), (126.0, 206.0)],
        INK_FEATURE,
        closed=False,
    )
    _stud(canvas, (123.0, 222.0), 4.0, GOLD)
    _stud(canvas, (110.0, 244.0), 4.0, GOLD)


_COLLARS: dict[str, Callable[[Canvas, Faction, Ramp], None]] = {
    "double": _collar_double,
    "mandarin": _collar_mandarin,
    "v": _collar_v,
}


def _plain(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    """No payload: a breast pocket and its flap, in seam and shade alone."""
    left, right = PAYLOAD_INBOARD, PAYLOAD_INBOARD + 38.0
    canvas.polygon(
        [(left, 236.0), (right, 236.0), (right, 262.0), (left, 262.0)],
        (*ramp.shade, 255),
    )
    canvas.stroke([(left, 244.0), (right, 244.0)], INK_DETAIL, (*ramp.deep, 255))


def _sash(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    canvas.polygon(
        [(160.0, 208.0), (184.0, 220.0), (122.0, 268.0), (96.0, 268.0)],
        (*faction.body_dk, 255),
    )
    _ink(
        canvas,
        [(160.0, 208.0), (184.0, 220.0), (122.0, 268.0), (96.0, 268.0)],
        INK_DETAIL,
        closed=True,
    )


def _bandolier(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    strap: list[Point] = [
        (60.0, 208.0),
        (84.0, 208.0),
        (156.0, 268.0),
        (128.0, 268.0),
    ]
    canvas.polygon(strap, (*ramp.deep, 255))
    _ink(canvas, strap, INK_DETAIL, closed=True)
    _stud(canvas, (108.0, 240.0), 8.0, GOLD)


def _pouch(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    left, right = PAYLOAD_INBOARD, PAYLOAD_INBOARD + 42.0
    canvas.rect((left, 230.0, right, 266.0), (*ramp.deep, 255))
    canvas.rect((left, 230.0, right, 242.0), (*faction.body_dk, 255))
    _ink(
        canvas,
        [(left, 230.0), (right, 230.0), (right, 266.0), (left, 266.0)],
        INK_DETAIL,
        closed=True,
    )
    _stud(canvas, (left + 21.0, 248.0), 4.0, GOLD)


def _harness(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    """Webbing: two vertical straps off the shoulder line, carrying nothing.

    The empty chest is the point — it is the one treatment told apart by what
    is missing from it, which is what breaks it from the pouch it replaced.
    """
    for left in (PAYLOAD_INBOARD + 14.0, PAYLOAD_INBOARD + 88.0):
        right = left + 18.0
        canvas.rect((left, 206.0, right, 268.0), (*ramp.deep, 255))
        _ink(
            canvas,
            [(left, 206.0), (left, 268.0)],
            INK_DETAIL,
            closed=False,
        )
        _ink(
            canvas,
            [(right, 206.0), (right, 268.0)],
            INK_DETAIL,
            closed=False,
        )
        canvas.stroke(
            [(left + 4.0, 214.0), (left + 4.0, 268.0)],
            INK_DETAIL,
            (*ramp.shade, 255),
        )


def _mapcase(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    canvas.rect((150.0, 226.0, 186.0, 268.0), (*ramp.deep, 255))
    _ink(
        canvas,
        [(150.0, 226.0), (186.0, 226.0), (186.0, 268.0), (150.0, 268.0)],
        INK_DETAIL,
        closed=True,
    )
    canvas.stroke([(150.0, 236.0), (186.0, 236.0)], INK_DETAIL, (*faction.body_dk, 255))
    canvas.stroke([(130.0, 208.0), (166.0, 228.0)], INK_DETAIL, (*ramp.deep, 255))


def _loops(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    canvas.rect((40.0, 238.0, 152.0, 254.0), (*ramp.deep, 255))
    for i in range(6):
        canvas.rect((46.0 + i * 18.0, 232.0, 56.0 + i * 18.0, 254.0), (*GOLD, 255))
    _ink(
        canvas,
        [(40.0, 238.0), (152.0, 238.0), (152.0, 254.0), (40.0, 254.0)],
        INK_DETAIL,
        closed=True,
    )


def _boards(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    for x0, x1 in ((22.0, 66.0), (154.0, 198.0)):
        canvas.rect((x0, 214.0, x1, 228.0), (*GOLD, 255))
        _ink(
            canvas,
            [(x0, 214.0), (x1, 214.0), (x1, 228.0), (x0, 228.0)],
            INK_DETAIL,
            closed=True,
        )


def _lanyard(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    canvas.stroke(
        [(88.0, 208.0), (72.0, 246.0), (96.0, 262.0), (128.0, 240.0), (130.0, 208.0)],
        INK_DETAIL,
        (*GOLD, 255),
    )
    canvas.rect((88.0, 254.0, 104.0, 268.0), (*ramp.deep, 255))


def _epaulette(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    pad: list[Point] = [(18.0, 224.0), (70.0, 210.0), (74.0, 226.0), (24.0, 240.0)]
    canvas.polygon(pad, (*faction.body_dk, 255))
    _ink(canvas, pad, INK_DETAIL, closed=True)
    for i in range(4):
        canvas.stroke(
            [(26.0 + i * 12.0, 236.0), (30.0 + i * 12.0, 252.0)],
            INK_DETAIL,
            (*GOLD, 255),
        )


def _placket(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    canvas.rect((96.0, 220.0, 124.0, 268.0), (*faction.body_dk, 255))
    _ink(
        canvas,
        [(96.0, 220.0), (124.0, 220.0), (124.0, 268.0), (96.0, 268.0)],
        INK_DETAIL,
        closed=True,
    )
    for y in (232.0, 248.0, 264.0):
        _stud(canvas, (110.0, y), 4.0, GOLD)


def _crossbelt(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    for first, second in (
        ((66.0, 208.0), (168.0, 268.0)),
        ((154.0, 208.0), (52.0, 268.0)),
    ):
        canvas.stroke([first, second], INK_FEATURE, (*ramp.deep, 255))
    _stud(canvas, (110.0, 238.0), 7.0, GOLD)


def _scarf(canvas: Canvas, faction: Faction, ramp: Ramp) -> None:
    wrap: list[Point] = [
        (76.0, 210.0),
        (144.0, 210.0),
        (150.0, 232.0),
        (110.0, 244.0),
        (70.0, 232.0),
    ]
    canvas.polygon(wrap, (*faction.body_lt, 255))
    _ink(canvas, wrap, INK_DETAIL, closed=True)
    tail: list[Point] = [(126.0, 238.0), (150.0, 244.0), (140.0, 268.0), (118.0, 268.0)]
    canvas.polygon(tail, (*faction.body_lt, 255))
    _ink(canvas, tail, INK_DETAIL, closed=True)


_CHESTS: dict[str, Callable[[Canvas, Faction, Ramp], None]] = {
    "bandolier": _bandolier,
    "boards": _boards,
    "crossbelt": _crossbelt,
    "epaulette": _epaulette,
    "harness": _harness,
    "lanyard": _lanyard,
    "loops": _loops,
    "mapcase": _mapcase,
    "placket": _placket,
    "plain": _plain,
    "pouch": _pouch,
    "sash": _sash,
    "scarf": _scarf,
}


def chest(canvas: Canvas, treatment: str, faction: Faction, ramp: Ramp) -> None:
    """What the general carries on the chest. An unknown treatment raises."""
    if treatment not in _CHESTS:
        raise KeyError(f"no chest treatment {treatment!r} (have {sorted(_CHESTS)})")
    _CHESTS[treatment](canvas, faction, ramp)


def draw(canvas: Canvas, faction: Faction, collar: str, ramp: Ramp) -> None:
    """The uniform mass, cut at the collar. An unknown cut raises."""
    if collar not in _COLLARS:
        raise KeyError(f"no collar {collar!r} (have {sorted(_COLLARS)})")
    _mass(canvas, ramp)
    _COLLARS[collar](canvas, faction, ramp)


def pip(canvas: Canvas, ramp: Ramp) -> None:
    """The rank stud — the four costliest powers wear it, nobody else."""
    _stud(canvas, PIP_AT, 5.0, GOLD)
