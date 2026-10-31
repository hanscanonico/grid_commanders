"""The rocket truck: a broad, stepped launcher box of many tubes, ribbed along its top."""

from __future__ import annotations

import math

from ..kit import Kit
from .land_gear import BED_TOP, CAB_ROOF, badge, raised, truck

HINGE = (-0.39, 0.152)
RAISE = 15.0
TILT = math.radians(RAISE)
LOW_LEN = 0.485
LOW_W = 0.355
LOW_H = 0.062
HIGH_LEN = 0.385
HIGH_W = 0.3
HIGH_H = 0.05
TUBE_R = 0.029


def _tubes(k: Kit, at, length: float, width: float, base: float, count: int, r: float) -> None:
    pitch = width / count
    for i in range(count):
        y = -width / 2 + pitch * (i + 0.5)
        k.cyl(at(0.012, y, base), at(length - 0.012, y, base), r, r, "team_light", 8, 0.003, "tube")
        k.cyl(
            at(length - 0.022, y, base),
            at(length + 0.006, y, base),
            r * 1.1,
            r * 1.1,
            "gunmetal",
            8,
            0.003,
            "tube_mouth",
        )
        k.cyl(at(length + 0.002, y, base), at(length + 0.042, y, base), r * 0.82, r * 0.3, "brass", 6, 0.002, "nose")


def _launcher(k: Kit) -> None:
    at = raised(HINGE, RAISE)
    # The cradle under it, chunky and dark.
    k.box((-0.09, 0, BED_TOP + 0.03), (0.12, 0.2, 0.07), "gunmetal", 0.012, label="cradle")
    k.box(at(LOW_LEN / 2, 0, LOW_H / 2), (LOW_LEN, LOW_W, LOW_H), "team_dark", 0.016, tilt=TILT, label="low_box")
    _tubes(k, at, LOW_LEN, LOW_W - 0.03, LOW_H + 0.006, 4, TUBE_R)
    back = 0.012
    origin = at(back, 0, LOW_H + 0.024)
    high = raised((origin[0], origin[2]), RAISE)
    k.box(
        high(HIGH_LEN / 2, 0, HIGH_H / 2 - 0.004),
        (HIGH_LEN, HIGH_W, HIGH_H),
        "team_dark",
        0.014,
        tilt=TILT,
        label="high_box",
    )
    _tubes(k, high, HIGH_LEN, HIGH_W - 0.03, HIGH_H + 0.002, 3, TUBE_R)
    k.marker("muzzle", high(HIGH_LEN + 0.042, 0, HIGH_H + 0.002))
    if k.hi:
        for u in (0.12, 0.28):
            k.box(at(u, 0, LOW_H + 0.002), (0.018, LOW_W + 0.004, 0.012), "steel", 0.0, tilt=TILT, label="strap")


def build(k: Kit) -> None:
    truck(k)
    k.box((0.24, 0, CAB_ROOF + 0.005), (0.15, 0.27, 0.014), "team_light", 0.005, label="roof")
    badge(k, (0.24, 0, CAB_ROOF + 0.012), 0.062)
    _launcher(k)
