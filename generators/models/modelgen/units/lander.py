"""The lander: a blunt open barge, walls down its sides, a big bow ramp, a bridge at the stern."""

from __future__ import annotations

import math

from ..kit import Kit
from . import naval

# The ramp's end catches the sun, and a dry brush there would cross into the ramp's white.
ROLES = {**naval.ROLES, "ramp": naval.replace(naval.ROLES["team_light"], edge=0.15)}

DECK = 0.07
HALF_BEAM = 0.178
BOW_X = 0.325
STERN_X = -0.405
RAMP_TILT = math.radians(58)
RAMP_LEN = 0.2
RAMP_HINGE = (0.302, 0.085)
WALL_TOP = 0.132
BRIDGE_TOP = 0.25
EMBLEM_RADIUS = 0.072


def _plan(along: float = 1.0, across: float = 1.0, grow: float = 0.0) -> naval.Outline:
    """A barge's blunt box with its corners knocked off; starts at the bow's middle."""
    x0, x1 = STERN_X * along - grow, BOW_X * along + grow
    y = HALF_BEAM * across + grow
    return [
        (x1, 0.0),
        (x1, y * 0.72),
        (x1 - 0.045, y),
        (x0 + 0.05, y),
        (x0 + 0.012, y * 0.9),
        (x0, y * 0.7),
        (x0, 0.0),
        (x0, -y * 0.7),
        (x0 + 0.012, -y * 0.9),
        (x0 + 0.05, -y),
        (x1 - 0.045, -y),
        (x1, -y * 0.72),
    ]


def _hull(k: Kit) -> None:
    k.loft([(naval.KEEL, _plan(0.95, 0.7)), (0.012, _plan(0.99, 0.94)), (DECK, _plan())], "team", 0.012, label="hull")
    if k.hi:
        k.loft(
            [(naval.KEEL + 0.012, _plan(0.97, 0.82, 0.004)), (0.0, _plan(0.99, 0.93, 0.004))],
            "team_dark",
            0.0,
            label="stripe",
        )
        k.loft([(-0.001, _plan(0.99, 0.94, 0.004)), (0.021, _plan(0.993, 0.95, 0.004))], "foam", 0.0, label="stripe")
    naval.wash(k, _plan(0.99, 0.94), 0.04, 0.01)


def _well(k: Kit) -> None:
    """The open cargo deck between the walls, its floor ribbed and dark."""
    x0, x1 = -0.22, 0.31
    k.box(((x0 + x1) / 2, 0, DECK + 0.002), (x1 - x0, 0.28, 0.01), "team_dark", 0.003, label="well")
    if k.hi:
        for i in range(8):
            k.box((x0 + 0.04 + i * 0.066, 0, DECK + 0.007), (0.012, 0.26, 0.004), "gunmetal", 0.0, label="rib")
    for side in (-1.0, 1.0):
        y = side * 0.158
        k.box(
            (0.03, y, (DECK + WALL_TOP) / 2 - 0.006), (0.58, 0.04, WALL_TOP - DECK + 0.012), "team", 0.012, label="wall"
        )
        k.box((0.03, y, WALL_TOP), (0.6, 0.05, 0.016), "team_light", 0.006, label="rail")
        k.rivets([(-0.2 + i * 0.066, side * 0.179, 0.105) for i in range(8)], (0, side, 0), 0.007)
    # What it carries: two lashed bundles, so the well never reads as a hole.
    k.box((0.13, -0.05, DECK + 0.04), (0.135, 0.105, 0.07), "canvas", 0.018, taper=0.92, label="cargo")
    k.box((-0.07, 0.05, DECK + 0.04), (0.135, 0.105, 0.07), "canvas", 0.018, taper=0.92, label="cargo")
    if k.hi:
        for x, y in ((0.13, -0.05), (-0.07, 0.05)):
            for dx in (-0.035, 0.035):
                k.box((x + dx, y, DECK + 0.073), (0.01, 0.1, 0.004), "wood", 0.0, label="lashing")


def _ramp(k: Kit) -> None:
    """The bow door, hinged at the well's end, half raised: this ship's whole identity."""
    hinge_x, hinge_z = RAMP_HINGE
    dx, dz = math.cos(RAMP_TILT), math.sin(RAMP_TILT)
    centre = (hinge_x + dx * RAMP_LEN / 2, 0.0, hinge_z + dz * RAMP_LEN / 2)
    k.box(centre, (RAMP_LEN, 0.335, 0.03), "ramp", 0.012, tilt=RAMP_TILT, label="ramp")
    k.cyl((hinge_x, -0.16, hinge_z), (hinge_x, 0.16, hinge_z), 0.024, None, "gunmetal", 10, 0.003, "hinge")
    # Face rungs, standing just proud so the bake reads them.
    nx, nz = -dz, dx
    if k.hi:
        for t in (0.2, 0.36, 0.52, 0.68, 0.84):
            x = hinge_x + dx * RAMP_LEN * t + nx * 0.016
            z = hinge_z + dz * RAMP_LEN * t + nz * 0.016
            k.box((x, 0, z), (0.018, 0.3, 0.006), "team_dark", 0.0, tilt=RAMP_TILT, label="rung")
    for side in (-1.0, 1.0):
        y = side * 0.17
        outline = [
            (hinge_x - 0.05, DECK + 0.01),
            (hinge_x + 0.02, WALL_TOP + 0.015),
            (hinge_x + 0.1, WALL_TOP + 0.1),
            (hinge_x + 0.1, WALL_TOP + 0.06),
            (hinge_x + 0.03, DECK + 0.01),
        ]
        k.side_profile(outline, y - 0.012, y + 0.012, "team_dark", 0.004, "gusset")


def _bridge(k: Kit) -> None:
    low = [(STERN_X + 0.012, -0.165), (-0.205, -0.165), (-0.205, 0.165), (STERN_X + 0.012, 0.165)]
    high = [(STERN_X + 0.03, -0.14), (-0.235, -0.14), (-0.235, 0.14), (STERN_X + 0.03, 0.14)]
    k.loft([(DECK - 0.002, low), (BRIDGE_TOP, high)], "team", 0.02, label="bridge")
    naval.band(k, -0.355, -0.232, 0.147, 0.208, 0.03)
    k.box((-0.3, 0, BRIDGE_TOP + 0.005), (0.11, 0.24, 0.012), "team_light", 0.005, label="bridge_roof")
    k.cyl((-0.355, 0.1, BRIDGE_TOP), (-0.355, 0.1, 0.34), 0.016, 0.012, "steel", 8, 0.002, "mast")
    k.seam((-0.22, 0, 0.13), (0.004, 0.32, 0.008))


def build(k: Kit) -> None:
    k.cull = False
    _hull(k)
    _well(k)
    _ramp(k)
    _bridge(k)
    roof = BRIDGE_TOP + 0.011
    k.marker("emblem", (-0.3, 0.0, roof))
    k.marker("emblem_edge", (-0.3 + EMBLEM_RADIUS, 0.0, roof))
