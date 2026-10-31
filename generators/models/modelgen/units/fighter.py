"""The fighter: a fat dart on a big delta, a bubble canopy and two canted fins."""

from __future__ import annotations

from ..kit import Kit
from .aircraft import AIR_ROLES, Wing, fin, fuselage, wings

ROLES = AIR_ROLES
NOSE_X = 0.342
NOSE_Z = 0.075
WING_Z = (0.06, 0.112)
WING = Wing(0.06, 0.33, 0.16, -0.17, -0.29, -0.27)
STAB = Wing(0.06, 0.165, -0.27, -0.355, -0.385, -0.405)
EMBLEM = (-0.135, -0.178)
EMBLEM_RADIUS = 0.06


def _body(k: Kit) -> None:
    fuselage(
        k,
        [
            (NOSE_X - 0.03, 0.077, 0.018, 0.02),
            (0.285, 0.08, 0.036, 0.038),
            (0.24, 0.084, 0.056, 0.058),
            (0.17, 0.088, 0.072, 0.074),
            (0.08, 0.092, 0.08, 0.085),
            (-0.08, 0.092, 0.082, 0.09),
            (-0.24, 0.09, 0.074, 0.082),
            (-0.33, 0.088, 0.06, 0.066),
        ],
    )
    # The livery band behind the nose, and the cannon's snout at its tip.
    fuselage(
        k,
        [
            (0.255, 0.083, 0.052, 0.054),
            (0.25, 0.083, 0.054, 0.056),
            (0.205, 0.087, 0.069, 0.071),
            (0.2, 0.087, 0.066, 0.068),
        ],
        "bone",
        label="band",
    )
    k.cyl((NOSE_X - 0.045, 0, 0.0775), (NOSE_X, 0, NOSE_Z), 0.019, 0.009, "gunmetal", 10, 0.002, "snout")
    k.marker("muzzle", (NOSE_X, 0, NOSE_Z))
    # A dark collar so the glass sits in something, then the bubble itself.
    k.ellipsoid((0.085, 0, 0.15), (0.122, 0.064, 0.044), "team_dark", label="canopy_rim")
    k.ellipsoid((0.1, 0, 0.16), (0.1, 0.054, 0.052), "glass", label="canopy")
    # The spine and the shoulder intakes.
    fuselage(
        k,
        [(0.0, 0.158, 0.012, 0.016), (-0.05, 0.16, 0.02, 0.032), (-0.2, 0.15, 0.02, 0.03), (-0.3, 0.125, 0.008, 0.016)],
        label="spine",
    )
    for side in (-1.0, 1.0):
        k.box((-0.015, side * 0.088, 0.09), (0.18, 0.05, 0.068), "team_dark", 0.018, label="intake")
        k.box((0.074, side * 0.09, 0.09), (0.012, 0.036, 0.046), "gunmetal", 0.003, label="intake_mouth")
    # The nozzle, dark and open.
    k.cyl((-0.31, 0, 0.088), (-0.402, 0, 0.088), 0.058, 0.05, "gunmetal", 12, 0.006, "nozzle")
    k.cyl((-0.402, 0, 0.088), (-0.406, 0, 0.088), 0.038, 0.038, "rubber", 12, 0.0, "nozzle_mouth")


def _wings(k: Kit) -> None:
    wings(k, WING, *WING_Z, "team", 0.018, cap_y=0.272)
    wings(k, STAB, 0.078, 0.11, "team", 0.012, label="stab")
    top = WING_Z[1]
    if k.hi:
        for side in (-1.0, 1.0):
            k.seam((-0.235, side * 0.17, top + 0.001), (0.006, 0.18, 0.003))
            k.seam((-0.135, side * 0.078, top + 0.001), (0.2, 0.006, 0.003))
            k.rivets([(-0.255, side * y, top) for y in (0.1, 0.14, 0.18, 0.22, 0.26)], (0, 0, 1), 0.006)
    k.marker("emblem", (EMBLEM[0], EMBLEM[1], top))
    k.marker("emblem_edge", (EMBLEM[0] + EMBLEM_RADIUS, EMBLEM[1], top))


def _fins(k: Kit) -> None:
    for side in (-1.0, 1.0):
        fin(k, (-0.19, 0.135), (-0.305, 0.292), (-0.375, 0.292), (-0.33, 0.135), side * 0.06, cant=12.0)


def build(k: Kit) -> None:
    k.cull = False
    _body(k)
    _wings(k)
    _fins(k)
