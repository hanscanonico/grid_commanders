"""The bomber: a barrel of a fuselage under the widest wing in the air, four pods, a tall tail."""

from __future__ import annotations

from ..kit import Kit
from .aircraft import AIR_ROLES, Wing, fin, fuselage, wings

ROLES = AIR_ROLES
WING_Z = (0.122, 0.178)
WING = Wing(0.09, 0.412, 0.17, -0.05, -0.15, -0.19)
TAIL = Wing(0.05, 0.195, -0.25, -0.335, -0.395, -0.405)
PODS = (0.185, 0.315)
POD_Z = 0.15
POD_R = 0.046
BOMB_BAY = (-0.2, 0.0, 0.02)
EMBLEM = (-0.1, -0.25)
EMBLEM_RADIUS = 0.058


def _body(k: Kit) -> None:
    fuselage(
        k,
        [
            (0.385, 0.104, 0.056, 0.062),
            (0.35, 0.107, 0.088, 0.096),
            (0.29, 0.11, 0.102, 0.112),
            (0.14, 0.114, 0.11, 0.124),
            (-0.1, 0.116, 0.11, 0.124),
            (-0.26, 0.126, 0.09, 0.1),
            (-0.35, 0.15, 0.056, 0.062),
            (-0.405, 0.168, 0.024, 0.028),
        ],
        sides=16,
    )
    # The livery band behind the cockpit.
    fuselage(
        k,
        [
            (0.232, 0.113, 0.102, 0.114),
            (0.228, 0.113, 0.11, 0.122),
            (0.188, 0.114, 0.112, 0.126),
            (0.184, 0.114, 0.106, 0.118),
        ],
        "bone",
        label="band",
        sides=16,
    )
    # The glazed nose a bomb-aimer looks out of, and the cockpit above it, standing well proud.
    k.ellipsoid((0.362, 0, 0.106), (0.054, 0.086, 0.08), "glass", 8, 16, "bomb_aimer")
    k.ellipsoid((0.285, 0, 0.19), (0.088, 0.074, 0.04), "team_dark", 8, 16, "cockpit_rim")
    k.ellipsoid((0.296, 0, 0.198), (0.072, 0.062, 0.041), "glass", 8, 16, "cockpit")
    # The bomb bay: a dark belly, its doors seamed.
    k.box((-0.14, 0, 0.014), (0.26, 0.12, 0.028), "gunmetal", 0.006, label="bay")
    k.marker("muzzle", BOMB_BAY)
    if k.hi:
        for x in (-0.04, -0.14, -0.24):
            k.seam((x, 0, 0.001), (0.006, 0.12, 0.004))
        k.seam((-0.14, 0, 0.001), (0.26, 0.006, 0.004))
    # A dorsal blister behind the wing.
    k.ellipsoid((-0.165, 0, 0.207), (0.05, 0.042, 0.03), "glass", 6, 14, "blister")


def _wings(k: Kit) -> None:
    wings(k, WING, *WING_Z, "team", 0.02, cap_y=0.36)
    top = WING_Z[1]
    for side in (-1.0, 1.0):
        for y_abs in PODS:
            y = side * y_abs
            front = WING.lead(y_abs) + 0.085
            back = front - 0.17
            k.cyl((front - 0.012, y, POD_Z), (back, y, POD_Z), POD_R, POD_R * 0.8, "team_dark", 12, 0.008, "pod")
            k.cyl(
                (front + 0.006, y, POD_Z),
                (front - 0.016, y, POD_Z),
                POD_R * 0.86,
                POD_R * 1.04,
                "bone",
                12,
                0.005,
                "pod_lip",
            )
            k.cyl(
                (front + 0.007, y, POD_Z),
                (front + 0.012, y, POD_Z),
                POD_R * 0.58,
                POD_R * 0.46,
                "gunmetal",
                10,
                0.0,
                "pod_mouth",
            )
        if k.hi:
            k.seam((-0.155, side * 0.235, top + 0.001), (0.006, 0.28, 0.003))
            k.rivets([(-0.165, side * y, top) for y in (0.12, 0.17, 0.22, 0.27, 0.32)], (0, 0, 1), 0.006)
    k.marker("emblem", (EMBLEM[0], EMBLEM[1], top))
    k.marker("emblem_edge", (EMBLEM[0] + EMBLEM_RADIUS, EMBLEM[1], top))


def _tail(k: Kit) -> None:
    wings(k, TAIL, 0.165, 0.2, "team", 0.012, label="tail")
    fin(k, (-0.2, 0.2), (-0.33, 0.318), (-0.395, 0.318), (-0.385, 0.2), thick=0.042, bevel=0.012)


def build(k: Kit) -> None:
    k.cull = False
    _body(k)
    _wings(k)
    _tail(k)
