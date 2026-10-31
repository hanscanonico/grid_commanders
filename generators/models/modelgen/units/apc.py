"""The APC: a long, low armoured boat on short tracks, its bay open to the sky and full of crew."""

from __future__ import annotations

from ..kit import Kit
from .land_gear import badge, track_run

TRACK_LEN = 0.78
TRACK_H = 0.115
TRACK_W = 0.13
TRACK_Y = 0.235
HULL_HALF = 0.2
FLOOR = 0.115
RIM = 0.19
CAB_BACK = 0.1
CAB_ROOF = 0.255
BAY_BACK = -0.385


def _hull(k: Kit) -> None:
    lower = [
        (-0.395, 0.07),
        (0.26, 0.07),
        (0.395, 0.125),
        (0.36, FLOOR + 0.02),
        (-0.395, FLOOR + 0.02),
    ]
    k.side_profile(lower, -HULL_HALF, HULL_HALF, "team", 0.012, "lower_hull")
    # The bay: a dark floor, a thick wall on three sides, the army's colour all along its top.
    bay_len = CAB_BACK - BAY_BACK
    bay_x = (CAB_BACK + BAY_BACK) / 2
    k.box((bay_x, 0, FLOOR + 0.022), (bay_len, HULL_HALF * 2 - 0.03, 0.012), "gunmetal", 0.0, label="floor")
    wall = 0.045
    height = RIM - FLOOR
    for side in (-1.0, 1.0):
        k.box(
            (bay_x, side * (HULL_HALF - wall / 2 + 0.002), FLOOR + height / 2),
            (bay_len, wall, height),
            "team",
            0.012,
            label="wall",
        )
        k.rivets(
            [(x, side * (HULL_HALF - wall / 2 + 0.002), RIM) for x in (-0.31, -0.2, -0.09, 0.02)], (0, 0, 1), 0.009
        )
    k.box(
        (BAY_BACK + wall / 2, 0, FLOOR + height / 2),
        (wall, HULL_HALF * 2 - 0.02, height),
        "team_dark",
        0.012,
        label="stern_door",
    )
    k.box((BAY_BACK - 0.002, 0, 0.13), (0.02, 0.2, 0.09), "team_dark", 0.006, label="ramp")


def _cab(k: Kit) -> None:
    half_y = HULL_HALF - 0.004
    outline = [
        (CAB_BACK, FLOOR),
        (0.385, FLOOR),
        (0.25, CAB_ROOF),
        (CAB_BACK, CAB_ROOF),
    ]
    k.side_profile(outline, -half_y, half_y, "team", 0.02, "cab")
    # The slit visor across the sloped front.
    slit = [(0.305, 0.198), (0.312, 0.204), (0.272, 0.243), (0.265, 0.236)]
    k.side_profile(slit, -half_y + 0.03, half_y - 0.03, "glass", 0.002, "visor")
    # The roof panel carries the badge.
    k.box((0.172, 0, CAB_ROOF + 0.006), (0.135, 0.28, 0.016), "team_light", 0.006, label="roof")
    badge(k, (0.172, 0, CAB_ROOF + 0.014), 0.062)
    for side in (-1.0, 1.0):
        k.cyl((0.335, side * 0.145, 0.15), (0.37, side * 0.145, 0.135), 0.024, 0.022, "brass", 10, 0.004, "headlamp")
    k.seam((CAB_BACK + 0.006, 0, 0.2), (0.003, half_y * 2 + 0.002, 0.11))


def _crew(k: Kit) -> None:
    """Two facing benches of helmets, the bay's whole point at board size."""
    seat_z = FLOOR + 0.028
    for side in (-1.0, 1.0):
        y = side * 0.103
        k.box((-0.14, y, seat_z + 0.012), (0.42, 0.06, 0.024), "canvas", 0.006, label="bench")
        for x in (-0.285 + 0.03 * side, -0.14 + 0.03 * side, 0.005 + 0.03 * side):
            k.box((x, y, seat_z + 0.05), (0.05, 0.068, 0.05), "team_dark", 0.012, label="trooper")
            k.cyl((x, y, seat_z + 0.074), (x, y, seat_z + 0.08), 0.044, 0.042, "team", 10, 0.002, "brim")
            k.ellipsoid((x, y, seat_z + 0.08), (0.036, 0.036, 0.03), "team_light", 5, 10, label="helmet")


def build(k: Kit) -> None:
    for side in (-1.0, 1.0):
        top = track_run(k, side, TRACK_LEN, TRACK_H, TRACK_W, TRACK_Y, 4, 0.042)
        k.box((-0.27, side * TRACK_Y, top + 0.024), (0.14, 0.085, 0.048), "team_dark", 0.012, label="bin")
        k.box((0.18, side * TRACK_Y, top + 0.012), (0.24, 0.08, 0.024), "team_dark", 0.008, label="locker")
    _hull(k)
    _cab(k)
    _crew(k)
