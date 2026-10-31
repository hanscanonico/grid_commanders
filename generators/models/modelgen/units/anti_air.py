"""The anti-air: a tracked hull under a raised mount, four guns fanned skyward, and a radar dish."""

from __future__ import annotations

import math

from ..kit import RECOIL, Kit
from .land_gear import badge, raised, track_run

TRACK_LEN = 0.7
TRACK_H = 0.125
TRACK_W = 0.14
TRACK_Y = 0.222
HULL_TOP = 0.17
MOUNT_X = -0.065
PIVOT = (MOUNT_X + 0.01, 0.235)
ELEVATION = 40.0
GUN_ENDS = 0.24
GUN_RS = 0.021


def _hull(k: Kit) -> None:
    half_y = 0.185
    outline = [
        (-0.33, 0.08),
        (0.2, 0.08),
        (0.345, 0.125),
        (0.26, HULL_TOP),
        (-0.31, HULL_TOP),
        (-0.34, 0.13),
    ]
    k.side_profile(outline, -half_y, half_y, "team", 0.02, "hull")
    # Forward of the guns' tips: the badge's patch paints anything facing up above it.
    k.box((0.19, 0, HULL_TOP + 0.007), (0.13, 0.25, 0.016), "team_light", 0.006, label="deck_panel")
    badge(k, (0.19, 0, HULL_TOP + 0.015), 0.058)
    for side in (-1.0, 1.0):
        k.cyl((0.29, side * 0.14, 0.145), (0.335, side * 0.14, 0.128), 0.027, 0.025, "brass", 10, 0.004, "headlamp")
    k.box((-0.27, 0, HULL_TOP + 0.012), (0.1, 0.27, 0.03), "team_dark", 0.01, label="deck")


def _mount(k: Kit) -> None:
    x = MOUNT_X
    z = HULL_TOP
    # A big round turntable, then a tall fork: this mount stands up off the hull.
    k.cyl((x, 0, z - 0.004), (x, 0, z + 0.016), 0.17, 0.17, "gunmetal", 16, 0.004, "ring")
    k.cyl((x, 0, z + 0.014), (x, 0, z + 0.04), 0.162, 0.148, "team", 16, 0.012, "table")
    for side in (-1.0, 1.0):
        y = side * 0.155
        k.side_profile(
            [(x - 0.09, z + 0.036), (x + 0.09, z + 0.036), (x + 0.06, PIVOT[1] + 0.03), (x - 0.05, PIVOT[1] + 0.03)],
            y - 0.022,
            y + 0.022,
            "team",
            0.014,
            "fork",
        )
    k.box((x, 0, z + 0.05), (0.11, 0.22, 0.03), "gunmetal", 0.008, label="pedestal")


def _guns(k: Kit) -> None:
    at = raised(PIVOT, ELEVATION)
    # One breech block in the army's light tone holds all four: at the board it's a single mass.
    k.box(at(0.0), (0.13, 0.27, 0.075), "team_light", 0.016, tilt=math.radians(ELEVATION), label="breech")
    for y, w in ((-0.1, 0.0), (-0.035, 0.012), (0.035, 0.012), (0.1, 0.0)):
        k.moves(
            k.cyl(at(0.04, y, w), at(GUN_ENDS - 0.03, y, w), GUN_RS * 1.05, GUN_RS, "steel", 8, 0.002, "barrel"), RECOIL
        )
        k.moves(
            k.cyl(
                at(GUN_ENDS - 0.04, y, w),
                at(GUN_ENDS, y, w),
                GUN_RS * 1.35,
                GUN_RS * 1.25,
                "gunmetal",
                8,
                0.003,
                "flash_hider",
            ),
            RECOIL,
        )
    k.marker("muzzle", at(GUN_ENDS, -0.035, 0.012))


def _radar(k: Kit) -> None:
    x = -0.255
    base = HULL_TOP + 0.026
    k.cyl((x, 0, base - 0.004), (x, 0, base + 0.05), 0.024, 0.02, "gunmetal", 8, 0.003, "mast")
    k.cyl((x, 0, base + 0.04), (x, 0, base + 0.1), 0.022, 0.082, "team_light", 14, 0.008, "dish")
    k.cyl((x, 0, base + 0.095), (x, 0, base + 0.108), 0.02, 0.012, "brass", 8, 0.002, "feed")


def build(k: Kit) -> None:
    _hull(k)
    for side in (-1.0, 1.0):
        top = track_run(k, side, TRACK_LEN, TRACK_H, TRACK_W, TRACK_Y, 4, 0.046)
        k.box((0.16, side * TRACK_Y, top + 0.013), (0.22, 0.09, 0.026), "team_dark", 0.008, label="locker")
    _mount(k)
    _guns(k)
    _radar(k)
