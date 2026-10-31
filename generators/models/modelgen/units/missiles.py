"""The missile truck: two huge white missiles on a raised rail, and very little else."""

from __future__ import annotations

import math

from ..kit import Kit
from ..paint import Role
from .land_gear import BED_TOP, CAB_ROOF, badge, raised, truck

ROLES = {"ordnance": Role((0.84, 0.82, 0.74), chip=0.1, edge=0.4, wash=0.8, dust=0.2, roughness=0.5)}

HINGE = (-0.37, 0.15)
RAISE = 20.0
TILT = math.radians(RAISE)
BODY_START = 0.0
BODY_END = 0.45
TIP = 0.555
R = 0.05
LIFT = 0.072
Y = 0.082


def _missile(k: Kit, at, y: float) -> None:
    k.cyl(at(BODY_START, y, LIFT), at(BODY_END, y, LIFT), R, R, "ordnance", 12, 0.004, "body")
    k.cyl(at(BODY_END, y, LIFT), at(TIP - 0.012, y, LIFT), R, R * 0.2, "brass", 12, 0.0, "warhead")
    # The army's band round the waist, and four fat fins at the tail.
    k.cyl(at(0.3, y, LIFT), at(0.345, y, LIFT), R + 0.003, R + 0.003, "team", 12, 0.002, "band")
    for dy, dw, size in (
        (0.0, 0.05, (0.075, 0.03, 0.045)),
        (0.05, 0.0, (0.075, 0.045, 0.03)),
        (-0.05, 0.0, (0.075, 0.045, 0.03)),
    ):
        k.box(at(0.05, y + dy, LIFT + dw), size, "team_dark", 0.005, tilt=TILT, label="fin")


def _launcher(k: Kit) -> None:
    at = raised(HINGE, RAISE)
    k.box((-0.09, 0, BED_TOP + 0.03), (0.1, 0.14, 0.07), "gunmetal", 0.012, label="ram")
    k.box(at(0.24, 0, 0.012), (0.48, 0.3, 0.03), "team_dark", 0.01, tilt=TILT, label="rail")
    for u in (0.13, 0.36):
        k.box(at(u, 0, 0.04), (0.06, 0.32, 0.05), "team", 0.012, tilt=TILT, label="clamp")
    for y in (-Y, Y):
        _missile(k, at, y)
    k.marker("muzzle", at(TIP, -Y, LIFT))


def build(k: Kit) -> None:
    truck(k)
    k.box((0.24, 0, CAB_ROOF + 0.005), (0.15, 0.27, 0.014), "team_light", 0.005, label="roof")
    badge(k, (0.24, 0, CAB_ROOF + 0.012), 0.062)
    _launcher(k)
