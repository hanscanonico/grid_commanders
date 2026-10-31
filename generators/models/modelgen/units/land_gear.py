"""What the land models share: track runs, tyres, the launcher truck and a raised frame."""

from __future__ import annotations

import math
from collections.abc import Callable

from mathutils import Matrix

from ..kit import TREAD, WHEEL, Kit


def badge(k: Kit, at: tuple[float, float, float], radius: float) -> None:
    """The army's badge, on a flat panel whose top is at `at`."""
    k.marker("emblem", at)
    k.marker("emblem_edge", (at[0] + radius, at[1], at[2]))


def raised(pivot: tuple[float, float], degrees: float) -> Callable[[float, float, float], tuple[float, float, float]]:
    """A frame hinged at (x, z) and raised nose up: `u` runs along it, `w` square off its top."""
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))

    def at(u: float, y: float = 0.0, w: float = 0.0) -> tuple[float, float, float]:
        return (pivot[0] + u * c - w * s, y, pivot[1] + u * s + w * c)

    return at


def track_run(k: Kit, side: float, length: float, height: float, width: float, y_mid: float, wheels: int, wheel_r: float) -> float:
    """One track with its road wheels, sprocket, idler and fender. Answers the fender's top."""
    half = length / 2
    y = side * y_mid
    outline = [
        (-half + 0.06, 0.0),
        (half - 0.06, 0.0),
        (half, 0.055),
        (half - 0.015, height - 0.035),
        (half - 0.06, height),
        (-half + 0.05, height),
        (-half, height - 0.04),
        (-half + 0.01, 0.05),
    ]
    k.moves(k.side_profile(outline, y - width / 2, y + width / 2, "rubber", 0.012, "track"), TREAD)
    if k.hi:
        count = int(length * 30)
        for i in range(count):
            x = -half + 0.06 + (length - 0.12) * i / (count - 1)
            k.box((x, y + side * (width / 2), 0.012), (0.018, 0.012, 0.03), "wheel", 0.0, label="tread")
    face = y + side * (width / 2 - 0.004)
    rim = y + side * (width / 2 + 0.012)
    cap = rim + side * 0.007
    wheel_z = wheel_r + 0.014
    span = length - 0.27
    for i in range(wheels):
        x = -span / 2 + span * i / (wheels - 1)
        k.moves(k.cyl((x, face, wheel_z), (x, rim, wheel_z), wheel_r, wheel_r * 0.92, "wheel", 12, 0.005, "wheel"), WHEEL, (x, wheel_z))
        k.moves(k.cyl((x, rim - side * 0.002, wheel_z), (x, cap, wheel_z), wheel_r * 0.42, wheel_r * 0.35, "gunmetal", 8, 0.002, "hub"), WHEEL, (x, wheel_z))
    end_z = height * 0.57
    sprocket_x = half - 0.058
    k.moves(k.cyl((sprocket_x, face, end_z), (sprocket_x, rim, end_z), 0.04, 0.038, "gunmetal", 8, 0.004, "sprocket"), WHEEL, (sprocket_x, end_z))
    idler_x = -half + 0.058
    k.moves(k.cyl((idler_x, face, end_z), (idler_x, rim, end_z), 0.034, 0.032, "wheel", 10, 0.004, "idler"), WHEEL, (idler_x, end_z))
    guard = height + 0.014
    k.box((0.0, y + side * 0.002, guard), (length * 0.975, width + 0.024, 0.026), "team", 0.011, label="fender")
    return guard + 0.013


def tyre(k: Kit, x: float, side: float, y_mid: float, radius: float, width: float) -> None:
    """A fat toy tyre and its hub, spinning about its own axle. Tread only the bake sees."""
    z = radius
    inner = side * (y_mid - width / 2)
    outer = side * (y_mid + width / 2)
    k.moves(k.cyl((x, inner, z), (x, outer, z), radius, radius * 0.95, "rubber", 14, 0.012, "tyre"), WHEEL, (x, z))
    face = outer + side * 0.012
    k.moves(k.cyl((x, outer - side * 0.004, z), (x, face, z), radius * 0.6, radius * 0.52, "wheel", 10, 0.005, "wheel_rim"), WHEEL, (x, z))
    k.moves(k.cyl((x, face - side * 0.002, z), (x, face + side * 0.008, z), radius * 0.24, radius * 0.18, "gunmetal", 6, 0.002, "hub"), WHEEL, (x, z))
    if k.hi:
        lugs = 18
        for i in range(lugs):
            t = math.tau * i / lugs
            at = (x + (radius - 0.001) * math.cos(t), side * y_mid, z + (radius - 0.001) * math.sin(t))
            lug = k.box(at, (0.012, width * 0.9, 0.012), "wheel", 0.0, label="lug")
            lug.matrix_world = lug.matrix_world @ Matrix.Rotation(-t, 4, "Y")


TRUCK_WHEEL = 0.082
TRUCK_Y = 0.218
TRUCK_TYRE_W = 0.075
CAB_BACK = 0.13
CAB_ROOF = 0.29
BED_TOP = 0.15


def truck(k: Kit) -> None:
    """Six wheels out to the cell's edge, a flat-faced cab at the front and a long bed."""
    for side in (-1.0, 1.0):
        for x in (-0.3, -0.13, 0.285):
            tyre(k, x, side, TRUCK_Y, TRUCK_WHEEL, TRUCK_TYRE_W)
    k.box((0.0, 0, 0.105), (0.84, 0.3, 0.05), "team_dark", 0.012, label="chassis")
    k.box((-0.145, 0, BED_TOP - 0.018), (0.55, 0.32, 0.036), "team", 0.012, label="bed")
    for side in (-1.0, 1.0):
        # One long mudguard over the twin rear axles, one over the front, army colour to the lens.
        k.box((-0.215, side * TRUCK_Y, 0.178), (0.36, TRUCK_TYRE_W + 0.03, 0.026), "team", 0.012, label="mudguard")
        k.box((0.285, side * TRUCK_Y, 0.178), (0.2, TRUCK_TYRE_W + 0.03, 0.026), "team", 0.012, label="mudguard")
        k.box((-0.215, side * (TRUCK_Y - 0.052), 0.155), (0.34, 0.035, 0.05), "team_dark", 0.006, label="guard_web")
    half_y = 0.178
    outline = [
        (CAB_BACK, 0.115),
        (0.415, 0.115),
        (0.42, 0.175),
        (0.335, CAB_ROOF),
        (CAB_BACK + 0.012, CAB_ROOF),
    ]
    k.side_profile(outline, -half_y, half_y, "team", 0.02, "cab")
    # The windscreen lies on the cab's slope, proud of it, so the lens sees glass.
    screen = [(0.404, 0.186), (0.413, 0.192), (0.352, 0.277), (0.343, 0.271)]
    k.side_profile(screen, -half_y + 0.03, half_y - 0.03, "glass", 0.003, "windscreen")
    for side in (-1.0, 1.0):
        k.box((0.255, side * (half_y + 0.002), 0.232), (0.12, 0.006, 0.058), "glass", 0.002, label="side_window")
        k.cyl((0.385, side * 0.135, 0.145), (0.419, side * 0.135, 0.145), 0.026, 0.024, "brass", 10, 0.004, "headlamp")
    k.box((0.405, 0, 0.108), (0.028, 0.36, 0.036), "gunmetal", 0.008, label="bumper")
