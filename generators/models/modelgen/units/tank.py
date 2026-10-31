"""The tank: a soft wedge hull on big toy tracks, a round cast turret, a fat gun."""

from __future__ import annotations

import math

from ..kit import RECOIL, TREAD, WHEEL, Kit

HULL_TOP = 0.205
TURRET_X = -0.05
TRACK_LEN = 0.74
TRACK_H = 0.15
TRACK_W = 0.135
TRACK_Y = 0.25
GUN_R = 0.036
MUZZLE_X = 0.395
EMBLEM_CENTRE = (TURRET_X + 0.035, 0.0)
EMBLEM_RADIUS = 0.082


def _running_gear(k: Kit, side: float) -> None:
    half = TRACK_LEN / 2
    y = side * TRACK_Y
    outline = [
        (-half + 0.06, 0.0),
        (half - 0.06, 0.0),
        (half, 0.055),
        (half - 0.015, TRACK_H - 0.035),
        (half - 0.06, TRACK_H),
        (-half + 0.05, TRACK_H),
        (-half, TRACK_H - 0.04),
        (-half + 0.01, 0.05),
    ]
    k.moves(k.side_profile(outline, y - TRACK_W / 2, y + TRACK_W / 2, "rubber", 0.012, "track"), TREAD)
    if k.hi:
        count = 22
        for i in range(count):
            x = -half + 0.06 + (TRACK_LEN - 0.12) * i / (count - 1)
            k.box((x, y + side * (TRACK_W / 2), 0.012), (0.018, 0.012, 0.03), "wheel", 0.0, label="tread")
    face = y + side * (TRACK_W / 2 - 0.004)
    rim = y + side * (TRACK_W / 2 + 0.012)
    wheel_r = 0.052
    for i in range(4):
        x = -0.235 + i * 0.155
        k.moves(k.cyl((x, face, 0.066), (x, rim, 0.066), wheel_r, wheel_r * 0.92, "wheel", 12, 0.005, "wheel"), WHEEL, (x, 0.066))
        cap = rim + side * 0.007
        k.moves(k.cyl((x, rim - side * 0.002, 0.066), (x, cap, 0.066), 0.022, 0.018, "gunmetal", 8, 0.002, "hub"), WHEEL, (x, 0.066))
    sprocket_x = half - 0.058
    k.moves(k.cyl((sprocket_x, face, 0.086), (sprocket_x, rim, 0.086), 0.04, 0.038, "gunmetal", 8, 0.004, "sprocket"), WHEEL, (sprocket_x, 0.086))
    idler_x = -half + 0.058
    k.moves(k.cyl((idler_x, face, 0.086), (idler_x, rim, 0.086), 0.034, 0.032, "wheel", 10, 0.004, "idler"), WHEEL, (idler_x, 0.086))
    # The fender: a soft shelf in the army's colour the lens looks down on.
    guard = TRACK_H + 0.014
    k.box((0.0, y + side * 0.002, guard), (TRACK_LEN * 0.975, TRACK_W + 0.024, 0.026), "team", 0.011, label="fender")
    top = guard + 0.013
    # What a crew straps down: one big bin aft, a smaller one, and a low locker.
    k.box((-0.2, y, top + 0.034), (0.15, 0.105, 0.068), "team_dark", 0.014, label="bin")
    k.box((-0.03, y, top + 0.024), (0.12, 0.095, 0.048), "team", 0.012, label="bin")
    k.box((0.17, y, top + 0.012), (0.2, 0.09, 0.024), "team_dark", 0.008, label="locker")
    k.rivets([(-0.2 + dx, y, top + 0.068) for dx in (-0.05, 0.05)], (0, 0, 1), 0.008)


def _hull(k: Kit) -> None:
    half_y = 0.205
    outline = [
        (-0.335, 0.075),
        (0.215, 0.075),
        (0.36, 0.14),
        (0.235, HULL_TOP),
        (-0.315, HULL_TOP),
        (-0.345, 0.15),
    ]
    k.side_profile(outline, -half_y, half_y, "team", 0.02, "hull")
    # The engine deck, a raised dark block with a grille for the wash to pool in.
    k.box((-0.255, 0, HULL_TOP + 0.012), (0.13, 0.27, 0.03), "team_dark", 0.01, label="deck")
    if k.hi:
        for i in range(5):
            k.box((-0.3 + i * 0.024, 0, HULL_TOP + 0.027), (0.012, 0.22, 0.006), "gunmetal", 0.0, label="grille")
    # Driver's hatch, his vision block, and a pair of brass headlamps.
    k.box((0.175, 0.07, HULL_TOP + 0.004), (0.095, 0.1, 0.02), "team_light", 0.008, label="hatch")
    k.box((0.24, 0.07, 0.196), (0.03, 0.07, 0.02), "glass", 0.003, label="vision")
    for side in (-1.0, 1.0):
        k.cyl((0.3, side * 0.15, 0.158), (0.335, side * 0.15, 0.142), 0.026, 0.024, "brass", 10, 0.004, "headlamp")
    k.seam((0.105, 0, HULL_TOP + 0.001), (0.006, 0.38, 0.003))
    for side in (-1.0, 1.0):
        y = side * (half_y + 0.0005)
        k.rivets([(x, y, 0.13) for x in (-0.25, -0.17, -0.09, -0.01, 0.07, 0.15)], (0, side, 0), 0.008)
        k.rivets([(x, side * 0.18, HULL_TOP) for x in (0.125, 0.165, 0.205)], (0, 0, 1), 0.007)


def _turret(k: Kit) -> None:
    x = TURRET_X
    z = HULL_TOP
    # The ring it turns on, dark so the turret floats off the deck.
    k.cyl((x, 0, z - 0.005), (x, 0, z + 0.018), 0.162, 0.162, "gunmetal", 16, 0.004, "ring")

    def shell(rx: float, ry: float, nose: float) -> list[tuple[float, float]]:
        points = []
        for i in range(18):
            t = math.tau * i / 18
            cx = math.cos(t)
            points.append((rx * cx + (nose if cx > 0 else 0.0) * cx * cx, ry * math.sin(t)))
        return points

    k.loft(
        [
            (z + 0.014, shell(0.158, 0.148, 0.036)),
            (z + 0.058, shell(0.18, 0.17, 0.044)),
            (z + 0.112, shell(0.168, 0.156, 0.038)),
            (z + 0.142, shell(0.134, 0.122, 0.026)),
        ],
        "team",
        0.01,
        (x, 0, 0),
        "turret",
    )
    # The bustle at the back, with a rolled tarp strapped on top.
    k.box((x - 0.185, 0, z + 0.068), (0.09, 0.2, 0.08), "team_dark", 0.016, label="bustle")
    k.cyl((x - 0.2, -0.085, z + 0.128), (x - 0.2, 0.085, z + 0.128), 0.026, None, "canvas", 10, 0.006, "tarp")
    # The commander's cupola, a raised round with its hatch.
    top = z + 0.142
    cup = (x - 0.078, 0.062)
    k.cyl((*cup, top - 0.004), (*cup, top + 0.03), 0.054, 0.05, "team_light", 12, 0.006, "cupola")
    k.cyl((*cup, top + 0.03), (*cup, top + 0.037), 0.036, None, "gunmetal", 12, 0.002, "cupola_hatch")
    for side in (-1.0, 1.0):
        k.rivets([(x + dx, side * 0.169, z + 0.058) for dx in (-0.06, -0.02, 0.02, 0.06)], (0, side, 0), 0.007)


def _gun(k: Kit) -> None:
    z = HULL_TOP + 0.076
    mantlet_x = TURRET_X + 0.205
    k.box((mantlet_x, 0, z), (0.075, 0.13, 0.095), "gunmetal", 0.018, label="mantlet")
    k.moves(k.cyl((mantlet_x + 0.02, 0, z), (MUZZLE_X - 0.05, 0, z), GUN_R * 1.15, GUN_R, "steel", 12, 0.002, "barrel"), RECOIL)
    k.moves(k.cyl((mantlet_x + 0.055, 0, z), (mantlet_x + 0.09, 0, z), GUN_R * 1.3, GUN_R * 1.3, "gunmetal", 12, 0.004, "sleeve"), RECOIL)
    # The muzzle brake: the one thing a toy tank must have.
    k.moves(k.cyl((MUZZLE_X - 0.055, 0, z), (MUZZLE_X, 0, z), GUN_R * 1.5, GUN_R * 1.42, "gunmetal", 12, 0.005, "brake"), RECOIL)
    k.marker("muzzle", (MUZZLE_X, 0, z))


def build(k: Kit) -> None:
    _hull(k)
    for side in (-1.0, 1.0):
        _running_gear(k, side)
    _turret(k)
    _gun(k)
