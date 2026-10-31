"""The city: a little market square, its tall houses to the back, the middle left free.

A unit stands on the same cell, so the height sits at the back (+Y here, the
game's -Z) and at the sides. The walls stay pale for every owner; the owner reads
off the roofs, the shutters and the awning.
"""

from __future__ import annotations

from ..kit import Kit
from .parts import PLINTH, house, square


def build(k: Kit) -> None:
    square(k)
    # The town hall: back-left, the tallest thing on the cell, with its belfry.
    hall_x, hall_y = -0.2, 0.235
    house(k, hall_x, hall_y, 0.36, 0.3, 0.3, 2, 0.1)
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
    k.cyl(
        (hall_x + 0.085, hall_y + 0.03 - 0.066, tower_top - 0.055),
        (hall_x + 0.085, hall_y + 0.03 - 0.072, tower_top - 0.055),
        0.036,
        None,
        "bone",
        12,
        0.002,
        "clock",
    )
    k.cyl(
        (hall_x + 0.085, hall_y + 0.03, tower_top + 0.125),
        (hall_x + 0.085, hall_y + 0.03, tower_top + 0.205),
        0.006,
        None,
        "gunmetal",
        6,
        0.0,
        "pole",
    )
    k.box((hall_x + 0.122, hall_y + 0.03, tower_top + 0.18), (0.07, 0.008, 0.045), "team_light", 0.002, label="flag")
    # The door the hall opens onto the square, its steps down to the cobbles.
    k.box((hall_x - 0.06, hall_y - 0.15, PLINTH + 0.052), (0.075, 0.016, 0.104), "wood", 0.004, label="door")
    k.box((hall_x - 0.06, hall_y - 0.175, PLINTH + 0.011), (0.11, 0.05, 0.022), "stone", 0.005, label="step")

    # A narrower house back-right, with a chimney.
    house(k, 0.235, 0.27, 0.3, 0.24, 0.2, 1, 0.1)
    k.box((0.3, 0.3, PLINTH + 0.3), (0.05, 0.05, 0.11), "stone", 0.006, label="chimney")

    # Two low shops at the front corners: they must never hide the unit behind them.
    house(k, -0.335, -0.2, 0.2, 0.24, 0.105, 1, 0.075)
    house(k, 0.335, -0.2, 0.2, 0.24, 0.105, 1, 0.075)
    k.box((0.335, -0.335, PLINTH + 0.098), (0.2, 0.05, 0.012), "team_light", 0.003, label="awning").rotation_euler[
        0
    ] = 0.0
    k.box((-0.335, -0.335, PLINTH + 0.098), (0.2, 0.05, 0.012), "team_light", 0.003, label="awning")

    # Life on the square: a well, a lamp, two crates by the shop.
    k.cyl((-0.07, -0.385, PLINTH), (-0.07, -0.385, PLINTH + 0.04), 0.034, 0.032, "stone", 10, 0.005, "well")
    k.cyl((-0.07, -0.385, PLINTH + 0.04), (-0.07, -0.385, PLINTH + 0.045), 0.024, None, "glass", 10, 0.0, "water")
    k.cyl((0.09, -0.385, PLINTH), (0.09, -0.385, PLINTH + 0.13), 0.006, 0.005, "gunmetal", 6, 0.0, "lamp_post")
    k.cyl((0.09, -0.385, PLINTH + 0.13), (0.09, -0.385, PLINTH + 0.158), 0.015, 0.012, "brass", 8, 0.002, "lamp")
    k.box((0.2, -0.385, PLINTH + 0.02), (0.04, 0.04, 0.04), "wood", 0.004, label="crate")
