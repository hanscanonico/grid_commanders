"""The port: a stone quay on the water's edge, two cranes, sheds along the back.

The water lies along the front of the cell, the side the lens is on, so a player sees
the quay's wall dropping into it. The cranes stand at the two sides and reach out over
the water, which leaves the middle of the quay open for the ship or unit on it.
"""

from __future__ import annotations

from ..kit import Kit
from ..paint import Role, grey
from .parts import flatten_small_bevels, gable_roof, long_gable, paving, window

ROLES = {
    "water": Role((0.035, 0.17, 0.3), edge=0.4, dust=0.0, wash=0.35, roughness=0.2),
    "foam": Role((0.62, 0.7, 0.72), edge=0.4, dust=0.0, wash=0.2, roughness=0.5),
    "swell": Role((0.11, 0.3, 0.44), edge=0.4, dust=0.0, wash=0.1, roughness=0.3),
    # Shed fronts face away from the sun: they start light or they read as dark holes.
    "door": Role(grey(0.9), team=True, chip=0.2, edge=0.6, dust=0.15, wash=0.4),
    "wall": Role((0.95, 0.91, 0.79), edge=0.5, dust=0.35, wash=0.55, roughness=0.9),
}

QUAY = 0.055
EDGE_Y = -0.26
WATER_TOP = 0.012


def _water(k: Kit) -> None:
    near = -0.46
    k.box((0, (near + EDGE_Y) / 2, WATER_TOP / 2), (0.92, EDGE_Y - near, WATER_TOP), "water", 0.0, label="water")
    if not k.hi:
        return
    z = WATER_TOP + 0.001
    # Foam where the wall meets the water, and a few long swells to catch the light.
    k.box((0, EDGE_Y - 0.008, z), (0.92, 0.012, 0.003), "foam", 0.0, label="foam")
    swells = (
        (-0.38, -0.3, 0.07),
        (-0.2, -0.32, 0.09),
        (0.06, -0.3, 0.06),
        (0.26, -0.33, 0.1),
        (-0.3, -0.37, 0.1),
        (-0.07, -0.38, 0.08),
        (0.14, -0.37, 0.07),
        (0.38, -0.38, 0.06),
        (-0.4, -0.43, 0.06),
        (-0.17, -0.44, 0.1),
        (0.07, -0.43, 0.08),
        (0.3, -0.44, 0.09),
    )
    for x, y, length in swells:
        k.box((x, y, z), (length, 0.012, 0.003), "swell", 0.0, label="swell")


def _quay(k: Kit) -> None:
    middle = (EDGE_Y + 0.46) / 2
    depth = 0.46 - EDGE_Y
    k.box((0, middle, QUAY / 2), (0.92, depth, QUAY), "stone", 0.01, label="quay")
    # The coping: a pale kerb along the edge, the line that says "quay" from the board.
    k.box((0, EDGE_Y + 0.02, QUAY + 0.005), (0.92, 0.04, 0.012), "bone", 0.004, label="coping")
    paving(k, -0.445, 0.445, EDGE_Y + 0.044, 0.445, QUAY, 0.075, 1.8, gap=0.006)
    if not k.hi:
        return
    # Ashlar courses on the wall the lens looks at.
    courses = 3
    for row in range(courses):
        z = WATER_TOP + (row + 0.5) * (QUAY - WATER_TOP) / courses
        k.box(
            (0, EDGE_Y - 0.001, z + (QUAY - WATER_TOP) / courses / 2),
            (0.92, 0.002, 0.004),
            "gunmetal",
            0.0,
            label="course",
        )
        pitch = 0.09
        for i in range(11):
            bx = -0.45 + i * pitch + (pitch / 2 if row % 2 else 0.0)
            if abs(bx) < 0.455:
                k.box(
                    (bx, EDGE_Y - 0.001, z),
                    (0.004, 0.002, (QUAY - WATER_TOP) / courses),
                    "gunmetal",
                    0.0,
                    label="joint",
                )
    # Weed along the tide line.
    k.box((0, EDGE_Y - 0.001, WATER_TOP + 0.006), (0.92, 0.003, 0.012), "gunmetal", 0.0, label="tide")
    # Crane rails let into the stone.
    for rx in (-0.415, -0.265):
        k.box((rx, 0.03, QUAY + 0.002), (0.012, 0.5, 0.003), "steel", 0.0, label="rail")


def _bollard(k: Kit, x: float, y: float) -> None:
    top = QUAY + 0.012
    k.cyl((x, y, top), (x, y, top + 0.032), 0.022, 0.017, "gunmetal", 8, 0.003, "bollard")
    k.cyl((x, y, top + 0.03), (x, y, top + 0.043), 0.026, 0.024, "gunmetal", 8, 0.003, "bollard_cap")


def _fender(k: Kit, x: float) -> None:
    k.box((x, EDGE_Y - 0.009, WATER_TOP + 0.036), (0.05, 0.018, 0.05), "rubber", 0.005, label="fender")


def _portal_crane(k: Kit, x: float, y: float) -> None:
    """The big gantry, side on to the lens: its boom clears the shed roofs behind it."""
    beam_z = 0.36
    half_x, half_y = 0.075, 0.07
    for dx in (-half_x, half_x):
        for dy in (-half_y, half_y):
            k.box((x + dx, y + dy, (QUAY + beam_z) / 2), (0.044, 0.044, beam_z - QUAY), "team", 0.006, label="leg")
        k.box((x + dx, y, 0.2), (0.03, half_y * 2, 0.03), "team_dark", 0.004, label="brace")
    k.box((x, y - half_y, 0.2), (half_x * 2, 0.03, 0.03), "team_dark", 0.004, label="brace")
    k.box((x, y, beam_z), (half_x * 2 + 0.06, half_y * 2 + 0.06, 0.03), "team_dark", 0.006, label="deck")
    k.box((x, y, beam_z + 0.058), (0.14, 0.14, 0.09), "team", 0.008, label="house")
    k.box((x, y, beam_z + 0.106), (0.152, 0.152, 0.012), "team_dark", 0.004, label="house_roof")
    boom_z = beam_z + 0.1
    tail, tip = -0.455, 0.215
    outline = [(tail, boom_z - 0.028), (tip, boom_z - 0.014), (tip, boom_z + 0.014), (tail, boom_z + 0.028)]
    k.side_profile(outline, y - 0.028, y + 0.028, "team_light", 0.006, "boom")
    k.box((tail + 0.04, y, boom_z - 0.058), (0.07, 0.07, 0.06), "stone", 0.006, label="counterweight")
    apex = (x + 0.01, y, 0.62)
    for dy in (-0.05, 0.05):
        k.cyl((x + 0.01, y + dy, beam_z + 0.11), apex, 0.013, 0.01, "team", 6, 0.0, "a_frame")
    k.cyl(apex, (tip - 0.02, y, boom_z + 0.014), 0.006, None, "gunmetal", 6, 0.0, "stay")
    k.cyl(apex, (tail + 0.02, y, boom_z + 0.028), 0.006, None, "gunmetal", 6, 0.0, "stay")
    # A box on the hook, swung in over the quay.
    hook_x = tip - 0.03
    k.cyl((hook_x, y, boom_z - 0.014), (hook_x, y, 0.27), 0.005, None, "gunmetal", 4, 0.0, "cable")
    k.box((hook_x, y, 0.245), (0.09, 0.055, 0.05), "team_dark", 0.005, label="cargo")
    if k.hi:
        # A truss's panels painted along the boom.
        for i in range(10):
            bx = tail + 0.03 + i * 0.066
            k.box((bx, y - 0.0285, boom_z), (0.006, 0.003, 0.026), "team_dark", 0.0, label="truss")
            k.box((bx, y + 0.0285, boom_z), (0.006, 0.003, 0.026), "team_dark", 0.0, label="truss")
        window(k, x, y - 0.07, beam_z + 0.058, "front", w=0.05, h=0.045)


def _dock_crane(k: Kit, x: float, y: float) -> None:
    """The little slewing crane on a post, its jib raised and reaching in along the edge."""
    z = QUAY
    k.cyl((x, y, z), (x, y, z + 0.022), 0.062, 0.054, "stone", 12, 0.004, "crane_foot")
    k.cyl((x, y, z + 0.022), (x, y, z + 0.18), 0.042, 0.034, "team", 10, 0.004, "crane_post")
    k.box((x, y + 0.006, z + 0.22), (0.1, 0.11, 0.08), "team", 0.008, label="crane_cab")
    k.box((x, y + 0.006, z + 0.266), (0.112, 0.122, 0.012), "team_dark", 0.004, label="crane_roof")
    k.box((x + 0.02, y + 0.076, z + 0.21), (0.08, 0.034, 0.055), "stone", 0.005, label="crane_weight")
    tip = (x - 0.16, y - 0.22, z + 0.37)
    k.cyl((x - 0.03, y - 0.03, z + 0.21), tip, 0.027, 0.014, "team_light", 6, 0.0, "jib")
    k.cyl(tip, (tip[0], tip[1], z + 0.075), 0.005, None, "gunmetal", 4, 0.0, "cable")
    k.box((tip[0], tip[1], z + 0.06), (0.04, 0.03, 0.03), "brass", 0.004, label="hook")
    if k.hi:
        window(k, x, y - 0.049, z + 0.22, "front", w=0.05, h=0.04)


def _shed_along(k: Kit, x: float, y: float, sx: float, sy: float, wall: float, rise: float) -> None:
    """The long warehouse with its broad roof to the lens and a row of big doors."""
    z = QUAY
    k.box((x, y, z + wall / 2), (sx, sy, wall), "wall", 0.008, label="walls")
    k.box((x, y, z + 0.016), (sx + 0.016, sy + 0.016, 0.032), "stone", 0.007, label="footing")
    long_gable(k, x, y, z + wall, sx, sy, rise)
    front = y - sy / 2
    for dx in (-0.14, 0.14):
        k.box((x + dx, front - 0.006, z + 0.05), (0.1, 0.012, 0.1), "door", 0.004, label="door")
        if k.hi:
            for off in (-0.025, 0.025):
                k.box((x + dx + off, front - 0.0135, z + 0.05), (0.004, 0.003, 0.096), "team_dark", 0.0, label="plank")
            k.box((x + dx, front - 0.0135, z + 0.05), (0.1, 0.003, 0.006), "team_dark", 0.0, label="plank")
    window(k, x, front, z + 0.08, "front", w=0.05, h=0.05)
    window(k, x + sx / 2, y, z + 0.088, "right", w=0.08, h=0.05)


def _shed_end_on(k: Kit, x: float, y: float, sx: float, sy: float, wall: float, rise: float) -> None:
    """The short warehouse with its gable to the lens."""
    z = QUAY
    k.box((x, y, z + wall / 2), (sx, sy, wall), "wall", 0.008, label="walls")
    k.box((x, y, z + 0.016), (sx + 0.016, sy + 0.016, 0.032), "stone", 0.007, label="footing")
    gable_roof(k, x, y, z + wall, sx, sy, rise)
    front = y - sy / 2
    k.box((x, front - 0.006, z + 0.05), (0.1, 0.012, 0.1), "door", 0.004, label="door")
    window(k, x + sx / 2, y + 0.04, z + 0.075, "right", w=0.08, h=0.045)


def _containers(k: Kit, x: float, y: float) -> None:
    """The stack that says cargo: big boxes in the army's tones."""
    z = QUAY
    h = 0.062
    k.box((x, y, z + h / 2), (0.15, 0.076, h), "team", 0.005, label="container")
    k.box((x, y - 0.082, z + h / 2), (0.15, 0.076, h), "team_light", 0.005, label="container")
    k.box((x, y - 0.04, z + h * 1.5), (0.15, 0.076, h), "team_dark", 0.005, label="container")
    if not k.hi:
        return
    for cy, cz in ((y - 0.082, z + h / 2), (y - 0.04, z + h * 1.5), (y, z + h / 2)):
        for i in range(-3, 4):
            k.box((x + i * 0.02, cy - 0.0385, cz), (0.006, 0.002, h - 0.012), "team_dark", 0.0, label="ribbing")


def _crates(k: Kit, x: float, y: float) -> None:
    k.box((x, y, QUAY + 0.024), (0.06, 0.06, 0.048), "wood", 0.005, label="crate")
    k.box((x + 0.062, y + 0.012, QUAY + 0.02), (0.05, 0.05, 0.04), "wood", 0.005, label="crate")


def _buoy(k: Kit, x: float, y: float) -> None:
    k.cyl((x, y, WATER_TOP), (x, y, WATER_TOP + 0.034), 0.028, 0.014, "team_light", 10, 0.003, "buoy")
    k.cyl((x, y, WATER_TOP + 0.034), (x, y, WATER_TOP + 0.05), 0.006, None, "gunmetal", 4, 0.0, "buoy_top")


def build(k: Kit) -> None:
    _water(k)
    _quay(k)
    for x in (-0.2, 0.0, 0.2):
        _bollard(k, x, EDGE_Y + 0.02)
    for x in (-0.1, 0.1):
        _fender(k, x)
    _shed_along(k, -0.135, 0.345, 0.56, 0.18, 0.125, 0.06)
    _shed_end_on(k, 0.325, 0.3, 0.21, 0.24, 0.105, 0.085)
    _portal_crane(k, -0.34, 0.14)
    _dock_crane(k, 0.345, 0.0)
    _containers(k, -0.355, -0.1)
    _crates(k, -0.1, 0.19)
    _buoy(k, 0.0, -0.36)
    flatten_small_bevels(k, 0.0045)
    k.marker("emblem", (0.0, -0.05, QUAY))
    k.marker("emblem_edge", (0.1, -0.05, QUAY))
