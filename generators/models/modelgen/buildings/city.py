"""The city: a little market square, its tall houses to the back, the middle left free.

A unit stands on the same cell, so the height sits at the back (+Y here, the
game's -Z) and at the sides. The walls stay pale for every owner; the owner reads
off the roofs, the shutters and the awning.
"""

from __future__ import annotations

from ..kit import Kit

PLINTH = 0.035


def _window(k: Kit, x: float, y: float, z: float, facing: str, w: float = 0.05, h: float = 0.066) -> None:
    """A shuttered window only the bake sees, on the +X, -X or -Y wall."""
    if not k.hi:
        return
    depth = 0.006
    if facing == "front":
        k.box((x, y - depth / 2, z), (w + 0.014, depth, h + 0.014), "bone", 0.0, label="frame")
        k.box((x, y - depth, z), (w, depth, h), "glass", 0.0, label="pane")
        k.box((x, y - depth * 1.5, z), (w, 0.003, 0.005), "bone", 0.0, label="bar")
        k.box((x, y - depth * 1.5, z), (0.005, 0.003, h), "bone", 0.0, label="bar")
        for side in (-1.0, 1.0):
            k.box((x + side * (w / 2 + 0.019), y - depth, z), (0.024, depth, h + 0.008), "team_dark", 0.0, label="shutter")
    else:
        sign = 1.0 if facing == "right" else -1.0
        k.box((x + sign * depth / 2, y, z), (depth, w + 0.014, h + 0.014), "bone", 0.0, label="frame")
        k.box((x + sign * depth, y, z), (depth, w, h), "glass", 0.0, label="pane")
        k.box((x + sign * depth * 1.5, y, z), (0.003, w, 0.005), "bone", 0.0, label="bar")
        k.box((x + sign * depth * 1.5, y, z), (0.003, 0.005, h), "bone", 0.0, label="bar")


def _gable_roof(k: Kit, x: float, y: float, wall_top: float, sx: float, sy: float, rise: float, role: str = "team") -> None:
    """A tiled roof with its ridge along Y, overhanging, courses stepped on the bake's copy."""
    half = sx / 2 + 0.024
    y0, y1 = y - sy / 2 - 0.026, y + sy / 2 + 0.026
    base = wall_top - 0.006
    if k.hi:
        courses = 7
        outline = [(x - half, base - 0.006)]
        for side, rng in ((-1.0, range(courses)), (1.0, range(courses, 0, -1))):
            for i in rng:
                t0, t1 = i / courses, (i + (1 if side < 0 else -1)) / courses
                outline.append((x + side * half * (1 - t0), base + rise * t0 + 0.012))
                outline.append((x + side * half * (1 - t1), base + rise * t1))
        outline.append((x + half, base - 0.006))
        k.side_profile(outline, y0, y1, role, 0.0, "tiles")
    else:
        outline = [(x - half, base - 0.006), (x + half, base - 0.006), (x, base + rise + 0.01)]
        k.side_profile(outline, y0, y1, role, 0.006, "roof")
    k.box((x, y, base + rise + 0.012), (0.026, sy + 0.06, 0.022), "team_dark", 0.008, label="ridge")


def _house(k: Kit, x: float, y: float, sx: float, sy: float, h: float, floors: int, rise: float) -> None:
    z = PLINTH
    k.box((x, y, z + h / 2), (sx, sy, h), "plaster", 0.008, label="walls")
    k.box((x, y, z + 0.018), (sx + 0.016, sy + 0.016, 0.036), "stone", 0.007, label="footing")
    _gable_roof(k, x, y, z + h, sx, sy, rise)
    front = y - sy / 2
    right = x + sx / 2
    for floor in range(floors):
        wz = z + 0.09 + floor * (h - 0.05) / floors
        for dx in (-0.25, 0.25):
            _window(k, x + dx * sx, front, wz, "front")
        for dy in (-0.25, 0.25):
            _window(k, right, y + dy * sy, wz, "right")
        if floor > 0:
            k.seam((x, front - 0.001, wz - 0.058), (sx, 0.004, 0.007), "wood")


def _square(k: Kit) -> None:
    k.box((0, 0, PLINTH / 2), (0.92, 0.92, PLINTH), "stone", 0.012, label="plinth")
    if not k.hi:
        return
    # Cobbles for the wash to run between: the lens sees them at every zoom.
    for i in range(16):
        for j in range(16):
            cx = -0.42 + i * 0.056 + (0.028 if j % 2 else 0.0)
            cy = -0.42 + j * 0.056
            if abs(cx) < 0.43:
                k.box((cx, cy, PLINTH + 0.001), (0.05, 0.05, 0.004), "stone", 0.0, label="cobble")


def build(k: Kit) -> None:
    _square(k)
    # The town hall: back-left, the tallest thing on the cell, with its belfry.
    hall_x, hall_y = -0.2, 0.235
    _house(k, hall_x, hall_y, 0.36, 0.3, 0.3, 2, 0.1)
    tower_top = PLINTH + 0.45
    k.box((hall_x + 0.085, hall_y + 0.03, PLINTH + 0.3), (0.13, 0.13, 0.3), "plaster", 0.008, label="belfry")
    k.loft(
        [
            (tower_top, [(-0.082, -0.082), (0.082, -0.082), (0.082, 0.082), (-0.082, 0.082)]),
            (tower_top + 0.13, [(-0.012, -0.012), (0.012, -0.012), (0.012, 0.012), (-0.012, 0.012)]),
        ],
        "team",
        0.005,
        (hall_x + 0.085, hall_y + 0.03, 0),
        "spire",
    )
    k.cyl((hall_x + 0.085, hall_y + 0.03 - 0.066, tower_top - 0.055), (hall_x + 0.085, hall_y + 0.03 - 0.072, tower_top - 0.055), 0.036, None, "bone", 12, 0.002, "clock")
    k.cyl((hall_x + 0.085, hall_y + 0.03, tower_top + 0.125), (hall_x + 0.085, hall_y + 0.03, tower_top + 0.205), 0.006, None, "gunmetal", 6, 0.0, "pole")
    k.box((hall_x + 0.122, hall_y + 0.03, tower_top + 0.18), (0.07, 0.008, 0.045), "team_light", 0.002, label="flag")
    # The door the hall opens onto the square, its steps down to the cobbles.
    k.box((hall_x - 0.06, hall_y - 0.15, PLINTH + 0.052), (0.075, 0.016, 0.104), "wood", 0.004, label="door")
    k.box((hall_x - 0.06, hall_y - 0.175, PLINTH + 0.011), (0.11, 0.05, 0.022), "stone", 0.005, label="step")

    # A narrower house back-right, with a chimney.
    _house(k, 0.235, 0.27, 0.3, 0.24, 0.2, 1, 0.1)
    k.box((0.3, 0.3, PLINTH + 0.3), (0.05, 0.05, 0.11), "stone", 0.006, label="chimney")

    # Two low shops at the front corners: they must never hide the unit behind them.
    _house(k, -0.335, -0.2, 0.2, 0.24, 0.105, 1, 0.075)
    _house(k, 0.335, -0.2, 0.2, 0.24, 0.105, 1, 0.075)
    k.box((0.335, -0.335, PLINTH + 0.098), (0.2, 0.05, 0.012), "team_light", 0.003, label="awning").rotation_euler[0] = 0.0
    k.box((-0.335, -0.335, PLINTH + 0.098), (0.2, 0.05, 0.012), "team_light", 0.003, label="awning")

    # Life on the square: a well, a lamp, two crates by the shop.
    k.cyl((-0.07, -0.385, PLINTH), (-0.07, -0.385, PLINTH + 0.04), 0.034, 0.032, "stone", 10, 0.005, "well")
    k.cyl((-0.07, -0.385, PLINTH + 0.04), (-0.07, -0.385, PLINTH + 0.045), 0.024, None, "glass", 10, 0.0, "water")
    k.cyl((0.09, -0.385, PLINTH), (0.09, -0.385, PLINTH + 0.13), 0.006, 0.005, "gunmetal", 6, 0.0, "lamp_post")
    k.cyl((0.09, -0.385, PLINTH + 0.13), (0.09, -0.385, PLINTH + 0.158), 0.015, 0.012, "brass", 8, 0.002, "lamp")
    k.box((0.2, -0.385, PLINTH + 0.02), (0.04, 0.04, 0.04), "wood", 0.004, label="crate")
