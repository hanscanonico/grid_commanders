"""The base: a factory hall under a sawtooth roof, one big roller door, a smokestack.

The hall fills the back of the cell and its teeth make the zigzag every player knows
for a factory. The forecourt in front of the door is left low for the unit that
rolls out onto it.
"""

from __future__ import annotations

import math

from ..kit import Kit
from ..paint import Role, grey
from .parts import PLINTH, paving, slope, window

# The door faces away from the sun, so it starts light and takes little wash, or it
# reads as a dark slot rather than as the biggest patch of army colour on the wall.
ROLES = {
    "door": Role(grey(0.9), team=True, chip=0.2, edge=0.6, dust=0.15, wash=0.4),
}

FRONT = 0.08
BACK = 0.43
HALF_WIDTH = 0.42
WALL = 0.2
TEETH = 3
RISE = 0.135
# How much of a tooth is the glazed face, the rest being the long slope up to it.
GLAZED_RUN = 0.06
GLASS_LEAN = math.atan2(GLAZED_RUN, RISE)
DOOR_WIDTH = 0.5
DOOR_HEIGHT = 0.17
DOOR_GAP = 0.05


def _tooth(k: Kit, x0: float, width: float, base: float) -> None:
    """One sawtooth: a long army-coloured slope up to +X, a glazed face dropping off it."""
    y0, y1 = FRONT - 0.024, BACK + 0.012
    crest = x0 + width - GLAZED_RUN
    thick = 0.02
    if k.hi:
        top = slope((x0, base + thick * 0.6), (crest, base + RISE + thick * 0.6), 6)
        outline = [(x0, base - 0.004), *top, (crest + 0.006, base + RISE - 0.004)]
        k.side_profile(outline, y0, y1, "team", 0.0, "sheets")
    else:
        outline = [(x0, base - 0.004), (x0, base + thick), (crest, base + RISE + thick), (crest + 0.006, base + RISE - 0.004)]
        k.side_profile(outline, y0, y1, "team", 0.005, "slope")
    # The glass leans out of the wall: edge-on it would vanish from the lens.
    glass = [
        (crest, base + RISE - 0.004),
        (crest + 0.012, base + RISE + 0.006),
        (x0 + width + 0.006, base + 0.008),
        (x0 + width - 0.006, base - 0.004),
    ]
    k.side_profile(glass, y0 + 0.006, y1 - 0.006, "glass", 0.002, "glazing")
    k.box((crest + 0.004, (y0 + y1) / 2, base + RISE + 0.012), (0.03, y1 - y0 + 0.012, 0.024), "team_dark", 0.007, label="crest")
    if k.hi:
        pitch = 0.05
        count = int((y1 - y0 - 0.01) / pitch)
        # Bars across the panes, on the glazed face.
        for i in range(1, count):
            bar_y = y0 + 0.006 + i * pitch
            k.box((x0 + width - GLAZED_RUN / 2 + 0.011, bar_y, base + RISE / 2 + 0.008), (0.005, 0.006, RISE * 1.08), "bone", 0.0, tilt=GLASS_LEAN, label="bar")
        k.box((x0 + width - 0.004, (y0 + y1) / 2, base + 0.012), (0.012, y1 - y0, 0.012), "gunmetal", 0.0, label="gutter")


def _gables(k: Kit, base: float) -> None:
    """The plaster under each tooth, whose top edge is the zigzag the lens sees."""
    width = HALF_WIDTH * 2 / TEETH
    for i in range(TEETH):
        x0 = -HALF_WIDTH + i * width
        outline = [(x0, base - 0.004), (x0 + width, base - 0.004), (x0 + width - GLAZED_RUN, base + RISE)]
        k.side_profile(outline, FRONT, BACK, "plaster", 0.0, "gable")


def _hall(k: Kit) -> None:
    middle = (FRONT + BACK) / 2
    depth = BACK - FRONT
    z = PLINTH
    base = z + WALL
    k.box((0, middle, z + WALL / 2), (HALF_WIDTH * 2, depth, WALL), "plaster", 0.008, label="walls")
    k.box((0, middle, z + 0.018), (HALF_WIDTH * 2 + 0.016, depth + 0.016, 0.036), "stone", 0.007, label="footing")
    _gables(k, base)
    width = HALF_WIDTH * 2 / TEETH
    for i in range(TEETH):
        _tooth(k, -HALF_WIDTH + i * width, width, base)
    # A round light in each gable, under its crest.
    if k.hi:
        for i in range(TEETH):
            crest = -HALF_WIDTH + (i + 1) * width - GLAZED_RUN
            k.cyl((crest - 0.05, FRONT - 0.004, base + 0.052), (crest - 0.05, FRONT, base + 0.052), 0.024, None, "bone", 12, 0.0, "light_rim")
            k.cyl((crest - 0.05, FRONT - 0.007, base + 0.052), (crest - 0.05, FRONT - 0.004, base + 0.052), 0.017, None, "glass", 12, 0.0, "light")
    for wx in (-0.37, 0.37):
        window(k, wx, FRONT, z + 0.115, "front", w=0.038, h=0.08)
    for wy in (0.15, 0.255, 0.36):
        window(k, HALF_WIDTH, wy, z + 0.115, "right", w=0.06, h=0.08)


def _roller_door(k: Kit) -> None:
    """The door in the army's light tone, the wall's shade being what it stands in."""
    z = PLINTH
    y = FRONT
    half = DOOR_WIDTH / 2
    k.box((0, y - 0.003, z + DOOR_HEIGHT / 2), (DOOR_WIDTH, 0.012, DOOR_HEIGHT), "gunmetal", 0.0, label="slot")
    curtain = DOOR_HEIGHT - DOOR_GAP
    curtain_z = z + DOOR_GAP + curtain / 2
    k.box((0, y - 0.012, curtain_z), (DOOR_WIDTH - 0.008, 0.016, curtain), "door", 0.003, label="curtain")
    for side in (-1.0, 1.0):
        k.box((side * (half + 0.016), y - 0.012, z + (DOOR_HEIGHT + 0.012) / 2), (0.034, 0.028, DOOR_HEIGHT + 0.012), "stone", 0.006, label="jamb")
    k.cyl((-half - 0.02, y - 0.022, z + DOOR_HEIGHT + 0.012), (half + 0.02, y - 0.022, z + DOOR_HEIGHT + 0.012), 0.017, None, "team_dark", 10, 0.003, "roller")
    if not k.hi:
        return
    slat = 0.02
    rows = int(curtain / slat)
    for i in range(1, rows + 1):
        k.box((0, y - 0.0205, z + DOOR_GAP + i * slat), (DOOR_WIDTH - 0.01, 0.002, 0.003), "team", 0.0, label="slat")


def _smokestack(k: Kit, x: float, y: float, top: float, r: float) -> None:
    z = PLINTH + WALL
    k.cyl((x, y, z), (x, y, top), r, r * 0.74, "stone", 12, 0.004, "stack")
    collar = top - 0.05
    collar_r = r * 0.74 + (r - r * 0.74) * 0.14 + 0.006
    k.cyl((x, y, collar), (x, y, collar + 0.034), collar_r, collar_r, "team", 12, 0.003, "stack_band")
    k.cyl((x, y, top - 0.002), (x, y, top + 0.002), r * 0.74 + 0.004, r * 0.74 + 0.002, "gunmetal", 12, 0.0, "stack_lip")
    if not k.hi:
        return
    k.cyl((x, y, top + 0.002), (x, y, top + 0.004), r * 0.74 - 0.012, None, "rubber", 12, 0.0, "stack_mouth")
    for i in range(10):
        ring_z = z + 0.05 + i * (top - z - 0.1) / 10
        t = (ring_z - z) / (top - z)
        ring = r + (r * 0.74 - r) * t + 0.002
        k.cyl((x, y, ring_z), (x, y, ring_z + 0.005), ring, ring, "stone", 12, 0.0, "course")


def _forecourt(k: Kit) -> None:
    paving(k, -0.445, 0.445, -0.445, FRONT - 0.03, PLINTH, 0.14, 1.4, gap=0.009)
    if not k.hi:
        return
    z = PLINTH + 0.0035
    # Painted lanes from the door to the cell's edge, and the hazard band it opens onto.
    for lane in (-0.23, 0.23):
        k.box((lane, -0.2, z), (0.02, 0.45, 0.004), "bone", 0.0, label="lane")
    stripes = 10
    pitch = DOOR_WIDTH / stripes
    for i in range(stripes):
        role = "bone" if i % 2 == 0 else "gunmetal"
        k.box((-DOOR_WIDTH / 2 + (i + 0.5) * pitch, 0.018, z), (pitch, 0.05, 0.004), role, 0.0, label="hazard")


def _fuel_tank(k: Kit, x: float, y: float) -> None:
    """A long tank lying on two stone saddles: the factory's big round low shape."""
    z = PLINTH + 0.062
    half = 0.11
    k.cyl((x, y - half, z), (x, y + half, z), 0.05, None, "team_light", 12, 0.008, "tank")
    for dy in (-0.07, 0.07):
        k.box((x, y + dy, PLINTH + 0.016), (0.11, 0.03, 0.032), "stone", 0.005, label="saddle")
    k.seam((x, y, z + 0.052), (0.014, half * 2, 0.004), "team_dark")
    if k.hi:
        for dy in (-0.05, 0.05):
            k.cyl((x, y + dy, z), (x, y + dy + 0.006, z), 0.052, None, "team_dark", 12, 0.0, "strap")


def _crates(k: Kit, x: float, y: float) -> None:
    k.box((x, y, PLINTH + 0.03), (0.075, 0.075, 0.06), "wood", 0.006, label="crate")
    k.box((x - 0.012, y + 0.075, PLINTH + 0.03), (0.075, 0.07, 0.06), "wood", 0.006, label="crate")
    k.box((x + 0.002, y + 0.03, PLINTH + 0.085), (0.07, 0.07, 0.05), "team_dark", 0.006, label="crate")
    k.cyl((x - 0.085, y + 0.05, PLINTH), (x - 0.085, y + 0.05, PLINTH + 0.06), 0.026, None, "steel", 10, 0.004, "drum")
    if k.hi:
        for cx, cy in ((x, y), (x - 0.012, y + 0.075)):
            k.box((cx, cy - 0.038, PLINTH + 0.03), (0.075, 0.003, 0.01), "leather", 0.0, label="band")


def build(k: Kit) -> None:
    k.box((0, 0, PLINTH / 2), (0.92, 0.92, PLINTH), "stone", 0.012, label="plinth")
    _forecourt(k)
    _hall(k)
    _roller_door(k)
    _smokestack(k, 0.3, 0.33, 0.6, 0.055)
    _fuel_tank(k, -0.385, -0.26)
    _crates(k, 0.385, -0.31)
    k.marker("emblem", (0.0, -0.18, PLINTH))
    k.marker("emblem_edge", (0.105, -0.18, PLINTH))
