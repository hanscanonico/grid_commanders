"""The cruiser: a lean hull, one forward gun, a big radar dish, a missile block aft."""

from __future__ import annotations

from ..kit import Kit
from . import naval

ROLES = naval.ROLES

DECK = 0.08
PLAN = naval.Plan(0.335, 0.118, 0.26, stern=0.05, fullness=1.35, transom=0.78)
SHEER = (0.2, 0.03)
DECK_TOP = DECK + 0.007
TURRET_X = 0.17
GUN_LENGTH = 0.12
GUN_RADIUS = 0.027
BRIDGE_X = -0.035
BRIDGE_TOP = 0.215
BLOCK_X = -0.22
TURRET = (0.05, 0.056, 0.058, 0.066)
EMBLEM_RADIUS = 0.038


def _bridge(k: Kit) -> None:
    x = BRIDGE_X
    low = [(-0.1, -0.09), (0.09, -0.09), (0.09, 0.09), (-0.1, 0.09)]
    high = [(-0.075, -0.066), (0.052, -0.066), (0.052, 0.066), (-0.075, 0.066)]
    k.loft([(DECK_TOP - 0.003, low), (BRIDGE_TOP, high)], "team", 0.02, (x, 0, 0), "bridge")
    naval.band(k, x - 0.073, x + 0.058, 0.074, 0.178, 0.028)
    k.box((x - 0.012, 0, BRIDGE_TOP + 0.006), (0.09, 0.09, 0.016), "team_light", 0.006, label="bridge_roof")
    # The mast and the dish: the one big shape up high, a pale ring with a dark face.
    mast_x = x - 0.02
    top = BRIDGE_TOP + 0.07
    k.cyl((mast_x, 0, BRIDGE_TOP + 0.01), (mast_x, 0, top), 0.018, 0.014, "steel", 8, 0.002, "mast")
    back = (mast_x, 0.012, top + 0.006)
    rim = (mast_x + 0.002, -0.014, top + 0.034)
    k.cyl(back, rim, 0.022, 0.068, "steel", 14, 0.005, "dish")
    k.cyl(rim, (mast_x + 0.0025, -0.0155, top + 0.036), 0.052, None, "gunmetal", 14, 0.0, "dish_face")
    for side in (-1.0, 1.0):
        k.rivets([(x + dx, side * 0.083, 0.13) for dx in (-0.06, -0.015, 0.03)], (0, side, 0), 0.007)


def _missiles(k: Kit) -> None:
    x = BLOCK_X
    size = (0.125, 0.135, 0.065)
    k.box((x, 0, DECK_TOP + size[2] / 2 - 0.002), size, "team_light", 0.012, label="missile_block")
    top = DECK_TOP + size[2] - 0.002
    for row in (-0.03, 0.03):
        for col in (-0.042, 0.0, 0.042):
            k.box((x + row, col, top + 0.002), (0.038, 0.028, 0.004), "gunmetal", 0.0, label="cell")
            if k.hi:
                k.box((x + row, col, top + 0.004), (0.014, 0.016, 0.002), "brass", 0.0, label="cap")


def build(k: Kit) -> None:
    k.cull = False
    naval.hull(k, PLAN, DECK, SHEER, foam_width=0.036, bow_wave=0.016, limit=0.34)
    naval.rail_rivets(k, PLAN, 0.052, [i * 0.055 - 0.24 for i in range(9)], DECK)
    naval.deck_plate(k, PLAN, DECK, 0.007, "team_dark", SHEER, 0.02)
    muzzle = naval.turret(k, TURRET_X, DECK, (0.0,), GUN_LENGTH, GUN_RADIUS, size=TURRET)
    k.marker("muzzle", muzzle)
    _bridge(k)
    _missiles(k)
    roof = DECK + TURRET[3] + 0.007
    k.marker("emblem", (TURRET_X, 0.0, roof))
    k.marker("emblem_edge", (TURRET_X + EMBLEM_RADIUS, 0.0, roof))
