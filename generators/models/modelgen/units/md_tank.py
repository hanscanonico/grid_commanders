"""The medium tank: the biggest slab of armour on land, a stepped turret and a very fat gun."""

from __future__ import annotations

from ..kit import RECOIL, Kit
from .land_gear import badge, track_run

HULL_TOP = 0.235
TRACK_LEN = 0.81
TRACK_H = 0.165
TRACK_W = 0.16
TRACK_Y = 0.285
TURRET_X = -0.12
GUN_Z = 0.29
GUN_R = 0.057
MUZZLE_X = 0.42
TIER_TOP = 0.382


def _running_gear(k: Kit, side: float) -> None:
    top = track_run(k, side, TRACK_LEN, TRACK_H, TRACK_W, TRACK_Y, 5, 0.056)
    y = side * TRACK_Y
    # The skirt: one heavy plate hung over the wheels' tops, so the flank reads as a wall.
    k.box((0.0, side * (TRACK_Y + TRACK_W / 2 + 0.014), 0.13), (TRACK_LEN * 0.9, 0.026, 0.08), "team", 0.01, label="skirt")
    k.box((-0.2, y, top + 0.03), (0.26, 0.115, 0.06), "team_dark", 0.014, label="bin")
    k.box((0.19, y, top + 0.012), (0.27, 0.1, 0.024), "team_dark", 0.008, label="locker")
    k.rivets([(x, side * (TRACK_Y + TRACK_W / 2 + 0.0275), 0.13) for x in (-0.3, -0.18, -0.06, 0.06, 0.18, 0.3)], (0, side, 0), 0.009)


def _hull(k: Kit) -> None:
    half_y = 0.235
    outline = [
        (-0.405, 0.09),
        (0.27, 0.09),
        (0.4, 0.155),
        (0.29, HULL_TOP),
        (-0.385, HULL_TOP),
        (-0.415, 0.175),
    ]
    k.side_profile(outline, -half_y, half_y, "team", 0.02, "hull")
    k.box((-0.335, 0, HULL_TOP + 0.012), (0.12, 0.34, 0.03), "team_dark", 0.01, label="deck")
    if k.hi:
        for i in range(5):
            k.box((-0.38 + i * 0.022, 0, HULL_TOP + 0.027), (0.011, 0.28, 0.006), "gunmetal", 0.0, label="grille")
    k.box((0.215, 0.1, HULL_TOP + 0.004), (0.1, 0.11, 0.02), "team_light", 0.008, label="hatch")
    k.box((0.285, 0.1, 0.228), (0.03, 0.08, 0.02), "glass", 0.003, label="vision")
    k.seam((0.155, 0, HULL_TOP + 0.001), (0.006, 0.44, 0.003))
    for side in (-1.0, 1.0):
        k.cyl((0.33, side * 0.19, 0.192), (0.365, side * 0.19, 0.174), 0.026, 0.024, "brass", 10, 0.004, "headlamp")
        k.rivets([(x, side * 0.215, HULL_TOP) for x in (0.17, 0.21, 0.25)], (0, 0, 1), 0.007)


def _turret(k: Kit) -> None:
    x = TURRET_X
    z = HULL_TOP
    k.box((x - 0.03, 0, z + 0.006), (0.4, 0.37, 0.024), "gunmetal", 0.006, label="ring")

    def slab(back: float, front: float, half: float, cut: float) -> list[tuple[float, float]]:
        return [
            (back, -half),
            (front - cut, -half),
            (front, -half + cut),
            (front, half - cut),
            (front - cut, half),
            (back, half),
        ]

    k.loft(
        [
            (z + 0.012, slab(-0.235, 0.17, 0.205, 0.075)),
            (z + 0.06, slab(-0.255, 0.185, 0.215, 0.08)),
            (z + 0.103, slab(-0.235, 0.145, 0.19, 0.07)),
        ],
        "team",
        0.012,
        (x, 0, 0),
        "turret",
    )
    # The upper tier, one step in on every side: the shape a round tank turret can't make.
    tier_base = z + 0.1
    k.loft(
        [
            (tier_base, slab(-0.2, 0.1, 0.13, 0.03)),
            (TIER_TOP, slab(-0.185, 0.085, 0.115, 0.025)),
        ],
        "team_light",
        0.007,
        (x, 0, 0),
        "tier",
    )
    badge(k, (x - 0.02, 0, TIER_TOP), 0.08)
    cup = (x - 0.14, 0.06)
    k.cyl((*cup, TIER_TOP - 0.004), (*cup, TIER_TOP + 0.022), 0.042, 0.038, "team", 10, 0.005, "cupola")
    k.cyl((*cup, TIER_TOP + 0.022), (*cup, TIER_TOP + 0.03), 0.027, None, "gunmetal", 10, 0.002, "cupola_hatch")
    k.box((x - 0.255, 0, z + 0.058), (0.08, 0.26, 0.078), "team_dark", 0.014, label="bustle")
    for side in (-1.0, 1.0):
        k.rivets([(x + dx, side * 0.2155, z + 0.06) for dx in (-0.2, -0.14, -0.08, -0.02, 0.04)], (0, side, 0), 0.008)


def _gun(k: Kit) -> None:
    mantlet_x = TURRET_X + 0.195
    k.box((mantlet_x, 0, GUN_Z), (0.075, 0.155, 0.108), "gunmetal", 0.018, label="mantlet")
    k.moves(k.cyl((mantlet_x + 0.02, 0, GUN_Z), (MUZZLE_X - 0.05, 0, GUN_Z), GUN_R * 1.1, GUN_R, "steel", 12, 0.002, "barrel"), RECOIL)
    k.moves(k.cyl((mantlet_x + 0.05, 0, GUN_Z), (mantlet_x + 0.085, 0, GUN_Z), GUN_R * 1.22, GUN_R * 1.22, "gunmetal", 12, 0.004, "sleeve"), RECOIL)
    # The boxy muzzle brake, wider than it is tall, so the top-down lens gets a hammerhead.
    brake_len = 0.075
    k.moves(k.box((MUZZLE_X - brake_len / 2, 0, GUN_Z), (brake_len, 0.178, 0.112), "gunmetal", 0.014, label="brake"), RECOIL)
    if k.hi:
        for side in (-1.0, 1.0):
            k.box((MUZZLE_X - brake_len / 2, side * 0.06, GUN_Z + 0.056), (0.022, 0.05, 0.004), "rubber", 0.0, label="brake_slot")
            k.box((MUZZLE_X - brake_len / 2, side * 0.089, GUN_Z), (0.022, 0.004, 0.06), "rubber", 0.0, label="brake_slot")
    k.marker("muzzle", (MUZZLE_X, 0, GUN_Z))


def build(k: Kit) -> None:
    _hull(k)
    for side in (-1.0, 1.0):
        _running_gear(k, side)
    _turret(k)
    _gun(k)
