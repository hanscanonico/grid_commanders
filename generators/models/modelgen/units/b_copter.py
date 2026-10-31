"""The gunship: a narrow stepped-canopy body, long stub wings of rocket pods and a chin gun."""

from __future__ import annotations

from ..kit import Kit
from .aircraft import AIR_ROLES, Wing, fin, fuselage, rounded_plan, skids, wings

ROLES = AIR_ROLES
HUB = (0.0, 0.0, 0.3)
ROTOR_HUB_DROP = 0.01
CHIN_GUN = (0.26, 0.0, 0.035)
CHIN_GUN_LENGTH = 0.14
STUB = Wing(0.05, 0.285, 0.075, 0.03, -0.085, -0.075)
STUB_Z = (0.128, 0.168)
DECK_Z = 0.245
EMBLEM = (-0.105, 0.0)
EMBLEM_RADIUS = 0.05


def _body(k: Kit) -> None:
    fuselage(
        k,
        [
            (0.34, 0.095, 0.022, 0.024),
            (0.315, 0.098, 0.048, 0.044),
            (0.27, 0.104, 0.068, 0.058),
            (0.2, 0.115, 0.084, 0.07),
            (0.05, 0.125, 0.098, 0.088),
            (-0.1, 0.13, 0.092, 0.088),
            (-0.19, 0.142, 0.068, 0.066),
            (-0.26, 0.155, 0.048, 0.048),
            (-0.4, 0.17, 0.036, 0.036),
        ],
    )
    # The light nose, a cap over the tip.
    fuselage(
        k,
        [
            (0.347, 0.095, 0.02, 0.022),
            (0.335, 0.096, 0.04, 0.037),
            (0.305, 0.1, 0.06, 0.052),
            (0.288, 0.102, 0.06, 0.052),
        ],
        "bone",
        label="nose",
    )
    # The stepped canopy: the gunner low in front, the pilot raised behind.
    k.ellipsoid((0.195, 0, 0.165), (0.08, 0.056, 0.052), "glass", 8, 14, "gunner")
    k.ellipsoid((0.075, 0, 0.212), (0.078, 0.064, 0.056), "glass", 8, 14, "pilot")
    # The engine deck the mast stands on, narrow enough for the far wing to show past it.
    k.loft(
        [
            (0.2, rounded_plan(0.02, -0.19, 0.068, 0.04, 0.035)),
            (DECK_Z, rounded_plan(0.01, -0.18, 0.06, 0.035, 0.03)),
        ],
        "team_dark",
        0.012,
        label="deck",
    )
    k.cyl((HUB[0], 0, DECK_Z - 0.01), (HUB[0], 0, HUB[2] - ROTOR_HUB_DROP), 0.038, 0.028, "gunmetal", 10, 0.004, "mast")
    k.marker("emblem", (EMBLEM[0], EMBLEM[1], DECK_Z))
    k.marker("emblem_edge", (EMBLEM[0] + EMBLEM_RADIUS, EMBLEM[1], DECK_Z))
    if k.hi:
        for x in (-0.03, -0.17):
            k.seam((x, 0, DECK_Z + 0.001), (0.005, 0.1, 0.003))


def _armament(k: Kit) -> None:
    wings(k, STUB, *STUB_Z, "team", 0.014, cap_y=0.245, label="stub")
    for side in (-1.0, 1.0):
        for y_abs in (0.135, 0.205):
            y = side * y_abs
            x0 = 0.1
            k.cyl((x0, y, 0.108), (x0 - 0.2, y, 0.108), 0.032, 0.032, "steel", 10, 0.006, "pod")
            k.cyl((x0 + 0.024, y, 0.108), (x0, y, 0.108), 0.014, 0.032, "brass", 10, 0.002, "warhead")
    # The chin gun in its ball.
    k.ellipsoid(CHIN_GUN, (0.034, 0.034, 0.034), "gunmetal", 5, 10, "chin_ball")
    end = CHIN_GUN[0] + CHIN_GUN_LENGTH
    k.cyl(CHIN_GUN, (end - 0.02, 0, CHIN_GUN[2]), 0.017, 0.015, "steel", 10, 0.002, "chin_gun")
    k.cyl((end - 0.028, 0, CHIN_GUN[2]), (end, 0, CHIN_GUN[2]), 0.021, 0.02, "gunmetal", 10, 0.004, "chin_brake")
    k.marker("muzzle", (end, 0, CHIN_GUN[2]))


def _tail(k: Kit) -> None:
    fin(k, (-0.33, 0.165), (-0.372, 0.305), (-0.415, 0.305), (-0.415, 0.165), thick=0.036)
    # The tail rotor, a disc on the fin's near side.
    k.cyl((-0.362, -0.018, 0.232), (-0.362, -0.03, 0.232), 0.05, 0.05, "steel", 12, 0.003, "tail_rotor")
    k.cyl((-0.362, -0.03, 0.232), (-0.362, -0.038, 0.232), 0.018, 0.014, "gunmetal", 8, 0.002, "tail_hub")
    wings(k, Wing(0.03, 0.12, -0.27, -0.3, -0.34, -0.345), 0.15, 0.178, "team", 0.01, label="tail_stab")


def build(k: Kit) -> None:
    k.cull = False
    skids(k, 0.1, 0.18, -0.17, 0.055)
    _body(k)
    _armament(k)
    _tail(k)
