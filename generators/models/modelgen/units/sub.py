"""The sub: a whale-back sunk to its top third, a big conning tower, foam along its flanks."""

from __future__ import annotations

import math

from ..kit import Kit
from . import naval

ROLES = naval.ROLES

HULL_CENTRE = -0.03
HULL_RISE = 0.088
BOW = 0.355
PLAN = naval.Plan(0.364, 0.106, 0.23, stern=0.22, fullness=2.3, transom=0.12, stern_round=1.6)
WATER_T = -HULL_CENTRE / HULL_RISE
TOWER_X = 0.02
TOWER_TOP = 0.2
EMBLEM_X = TOWER_X + 0.035
EMBLEM_RADIUS = 0.04


def _ring(t: float, grow: float = 0.0) -> naval.Outline:
    """The hull's plan at `t` of its rise above its centre: round across, and shorter as it climbs."""
    s = math.sqrt(max(1.0 - t * t, 0.0))
    return PLAN.outline(0.5 + 0.5 * s, s, grow)


def _hull(k: Kit) -> None:
    rings = [(HULL_CENTRE + HULL_RISE * t, _ring(t)) for t in (-0.75, -0.4, 0.0, WATER_T, 0.55, 0.75, 0.9, 0.98)]
    k.loft(rings, "team", 0.0, label="hull")
    naval.wash(k, _ring(WATER_T), 0.015, 0.012, 0.364)
    if k.hi:
        _stripe(k, -0.001, 0.014, "foam")
        _stripe(k, 0.014, 0.032, "team_dark")


def _stripe(k: Kit, z0: float, z1: float, role: str) -> None:
    """A band round the round hull, just proud so the bake reads it."""
    low = _ring((z0 - HULL_CENTRE) / HULL_RISE, 0.003)
    high = _ring((z1 - HULL_CENTRE) / HULL_RISE, 0.003)
    k.loft([(z0, low), (z1, high)], role, 0.0, label="stripe")


def _casing(k: Kit) -> None:
    """The flat walkway down the whale's back, and the tail a sub is known by from above."""
    z = HULL_CENTRE + HULL_RISE
    k.box((-0.03, 0, z), (0.5, 0.05, 0.012), "team_light", 0.005, label="casing")
    k.box((-0.305, 0, 0.034), (0.052, 0.19, 0.014), "team_dark", 0.005, label="stern_plane")
    k.box((-0.31, 0, 0.056), (0.07, 0.018, 0.07), "team_dark", 0.006, taper=0.75, label="fin")
    if k.hi:
        for i in range(10):
            x = -0.25 + i * 0.05
            if abs(x - TOWER_X) > 0.15:
                k.box((x, 0, z + 0.006), (0.006, 0.046, 0.002), "team_dark", 0.0, label="slat")


def _tower(k: Kit) -> None:
    x = TOWER_X
    base = HULL_CENTRE + HULL_RISE - 0.022
    k.loft(
        [
            (base, naval.shell(0.122, 0.06, 0.05)),
            (base + 0.08, naval.shell(0.112, 0.056, 0.046)),
            (TOWER_TOP, naval.shell(0.098, 0.05, 0.04)),
        ],
        "team",
        0.012,
        (x, 0, 0),
        "tower",
    )
    k.loft(
        [
            (TOWER_TOP - 0.002, naval.shell(0.082, 0.042, 0.034)),
            (TOWER_TOP + 0.006, naval.shell(0.078, 0.039, 0.03)),
        ],
        "team_light",
        0.003,
        (x, 0, 0),
        "tower_roof",
    )
    # The periscope housing at the back of the roof, with its two masts.
    k.box((x - 0.058, 0, TOWER_TOP + 0.02), (0.06, 0.05, 0.032), "team_dark", 0.008, label="housing")
    for dx, top, r in ((-0.07, 0.3, 0.016), (-0.044, 0.272, 0.014)):
        k.cyl((x + dx, 0, TOWER_TOP + 0.03), (x + dx, 0, top), r, r * 0.8, "steel", 8, 0.002, "periscope")
    # The planes across the tower.
    k.box((x + 0.055, 0, 0.135), (0.058, 0.25, 0.018), "team_dark", 0.006, label="plane")
    for side in (-1.0, 1.0):
        k.rivets([(x + dx, side * 0.057, 0.095) for dx in (-0.075, -0.035, 0.005)], (0, side, 0), 0.007)


def build(k: Kit) -> None:
    k.cull = False
    _hull(k)
    _casing(k)
    _tower(k)
    k.marker("muzzle", (BOW, 0.0, 0.0))
    roof = TOWER_TOP + 0.006
    k.marker("emblem", (EMBLEM_X, 0.0, roof))
    k.marker("emblem_edge", (EMBLEM_X + EMBLEM_RADIUS, 0.0, roof))
