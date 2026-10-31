"""The battleship: the whole cell's length, three twin turrets on a cream deck, a stepped tower."""

from __future__ import annotations

from ..kit import Kit
from . import naval

ROLES = {
    **naval.ROLES,
    "deck": naval.Role((0.71, 0.68, 0.58), edge=0.3, wash=1.0, dust=0.0, roughness=0.8),
    "deck_line": naval.Role((0.30, 0.25, 0.18), edge=0.0, wash=0.4, dust=0.0, roughness=0.9),
}

DECK = 0.09
PLAN = naval.Plan(0.414, 0.165, 0.3, stern=0.06, fullness=1.5, transom=0.72)
SHEER = (0.29, 0.03)
DECK_INSET = 0.03
DECK_TOP = DECK + 0.008
GUN_THICKNESS = 0.055
GUN_SPACING = 0.1
GUN_LENGTH = 0.15
GUNS = (-GUN_SPACING / 2, GUN_SPACING / 2)
FORE_X = 0.205
SECOND_X = 0.06
SECOND_FLOOR = 0.165
AFT_X = -0.235
TOWER_X = -0.085
EMBLEM_RADIUS = 0.05


def _deck(k: Kit) -> None:
    naval.deck_plate(k, PLAN, DECK, 0.008, "deck", SHEER, DECK_INSET)
    if not k.hi:
        return
    for y in (-0.1, -0.067, -0.033, 0.0, 0.033, 0.067, 0.1):
        stations = [x / 100 for x in range(-39, 30) if PLAN.width(x / 100) - DECK_INSET > abs(y) + 0.008]
        start, stop = stations[0], stations[-1]
        k.box(((start + stop) / 2, y, DECK_TOP), (stop - start, 0.004, 0.003), "deck_line", 0.0, label="plank")


def _tower(k: Kit) -> None:
    """Three steps of army colour and a funnel: the mass the lens looks down on."""
    x = TOWER_X
    floor = DECK_TOP
    k.box((x, 0, floor + 0.04), (0.16, 0.17, 0.084), "team", 0.012, taper=0.96, label="tier")
    second = floor + 0.08
    k.box((x + 0.03, 0, second + 0.036), (0.11, 0.135, 0.074), "team_light", 0.012, taper=0.94, label="tier")
    third = second + 0.072
    k.box((x + 0.035, 0, third + 0.028), (0.08, 0.105, 0.058), "team", 0.01, taper=0.96, label="bridge")
    naval.band(k, x + 0.035 - 0.042, x + 0.035 + 0.042, 0.054, third + 0.03)
    top = third + 0.056
    k.cyl((x + 0.025, 0, top - 0.004), (x + 0.025, 0, 0.44), 0.017, 0.013, "steel", 8, 0.002, "mast")
    # The funnel, raked aft, behind the bridge.
    funnel = x - 0.047
    k.cyl((funnel, 0, second - 0.004), (funnel - 0.01, 0, second + 0.082), 0.034, 0.031, "team_dark", 10, 0.006, "funnel")
    k.cyl((funnel - 0.01, 0, second + 0.08), (funnel - 0.011, 0, second + 0.084), 0.022, None, "gunmetal", 10, 0.0, "funnel_cap")
    for side in (-1.0, 1.0):
        k.rivets([(x + dx, side * 0.084, floor + 0.05) for dx in (-0.055, -0.02, 0.015, 0.05)], (0, side, 0), 0.007)


def build(k: Kit) -> None:
    k.cull = False
    naval.hull(k, PLAN, DECK, SHEER, limit=0.42)
    naval.rail_rivets(k, PLAN, 0.058, [i * 0.06 - 0.33 for i in range(11)], DECK)
    _deck(k)
    muzzle = naval.turret(k, FORE_X, DECK, GUNS, GUN_LENGTH, GUN_THICKNESS / 2)
    k.marker("muzzle", (muzzle[0], 0.0, muzzle[2]))
    # The second turret fires over the first from a barbette.
    k.cyl((SECOND_X, 0, DECK_TOP - 0.004), (SECOND_X, 0, SECOND_FLOOR + 0.006), 0.076, 0.072, "team_dark", 12, 0.008, "barbette")
    naval.turret(k, SECOND_X, SECOND_FLOOR, GUNS, GUN_LENGTH, GUN_THICKNESS / 2)
    # A gun facing aft has no room to slide back along -X, so it never recoils.
    naval.turret(k, AFT_X, DECK, GUNS, GUN_LENGTH, GUN_THICKNESS / 2, facing=-1.0, recoil=False)
    _tower(k)
    roof = SECOND_FLOOR + 0.068 + 0.007
    k.marker("emblem", (SECOND_X, 0.0, roof))
    k.marker("emblem_edge", (SECOND_X + EMBLEM_RADIUS, 0.0, roof))
