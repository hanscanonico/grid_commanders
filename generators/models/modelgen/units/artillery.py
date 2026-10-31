"""The artillery: a low hull under one very long barrel raised steeply, the tallest thing on land."""

from __future__ import annotations

from ..kit import RECOIL, Kit
from .land_gear import badge, raised, track_run

TRACK_LEN = 0.68
TRACK_H = 0.125
TRACK_W = 0.14
TRACK_Y = 0.212
HULL_TOP = 0.165
PIVOT = (-0.17, 0.235)
ELEVATION = 56.0
REACH = 0.645


def _hull(k: Kit) -> None:
    half_y = 0.175
    outline = [
        (-0.32, 0.08),
        (0.2, 0.08),
        (0.335, 0.125),
        (0.26, HULL_TOP),
        (-0.3, HULL_TOP),
        (-0.33, 0.13),
    ]
    k.side_profile(outline, -half_y, half_y, "team", 0.02, "hull")
    k.box((0.175, 0.075, HULL_TOP + 0.004), (0.095, 0.1, 0.02), "team_light", 0.008, label="hatch")
    k.box((0.235, 0.075, 0.158), (0.03, 0.07, 0.02), "glass", 0.003, label="vision")
    for side in (-1.0, 1.0):
        k.cyl((0.27, side * 0.135, 0.155), (0.322, side * 0.135, 0.136), 0.027, 0.025, "brass", 10, 0.004, "headlamp")
    # The recoil spade folded up at the stern: a big plate the lens reads as the gun's anchor.
    k.box((-0.355, 0, 0.14), (0.04, 0.3, 0.11), "team_dark", 0.012, tilt=-0.35, label="spade")


def _mount(k: Kit) -> None:
    """A low open gun house, its two tall cheeks in the army's colour holding the trunnions."""
    x = PIVOT[0]
    k.box((x, 0, HULL_TOP + 0.012), (0.3, 0.3, 0.03), "gunmetal", 0.008, label="turntable")
    for side in (-1.0, 1.0):
        y = side * 0.105
        k.side_profile(
            [
                (x - 0.15, HULL_TOP + 0.02),
                (x + 0.15, HULL_TOP + 0.02),
                (x + 0.075, PIVOT[1] + 0.075),
                (x - 0.095, PIVOT[1] + 0.05),
            ],
            y - 0.03,
            y + 0.03,
            "team",
            0.018,
            "cheek",
        )
        k.cyl(
            (x, y - side * 0.05, PIVOT[1]),
            (x, y + side * 0.034, PIVOT[1]),
            0.036,
            0.036,
            "gunmetal",
            10,
            0.004,
            "trunnion",
        )
    k.box((x - 0.145, 0, HULL_TOP + 0.05), (0.04, 0.17, 0.06), "team_dark", 0.01, label="back_plate")


def _gun(k: Kit) -> None:
    at = raised(PIVOT, ELEVATION)
    k.moves(k.cyl(at(-0.09), at(0.25), 0.062, 0.058, "gunmetal", 12, 0.006, "cradle"), RECOIL)
    k.moves(k.cyl(at(0.2), at(REACH - 0.06), 0.041, 0.036, "steel", 12, 0.002, "barrel"), RECOIL)
    k.moves(k.cyl(at(0.04, 0, 0.076), at(0.31, 0, 0.076), 0.024, 0.024, "steel", 8, 0.003, "recuperator"), RECOIL)
    k.moves(k.cyl(at(0.33), at(0.37), 0.05, 0.05, "gunmetal", 12, 0.004, "collar"), RECOIL)
    k.moves(k.cyl(at(REACH - 0.075), at(REACH), 0.054, 0.05, "gunmetal", 12, 0.006, "brake"), RECOIL)
    k.marker("muzzle", at(REACH))
    if k.hi:
        for u in (0.0, 0.08, 0.16):
            k.cyl(at(u), at(u + 0.012), 0.066, 0.066, "gunmetal", 12, 0.0, "cradle_band")


def build(k: Kit) -> None:
    _hull(k)
    for side in (-1.0, 1.0):
        top = track_run(k, side, TRACK_LEN, TRACK_H, TRACK_W, TRACK_Y, 4, 0.046)
        if side > 0:
            k.box((0.15, side * TRACK_Y, top + 0.013), (0.2, 0.09, 0.026), "team_dark", 0.008, label="locker")
        else:
            # The muzzle hangs over the deck, and the badge's patch paints anything facing up
            # above it, so the badge rides on the near fender, clear of the gun.
            k.box((0.13, side * TRACK_Y, top + 0.006), (0.18, 0.155, 0.016), "team_light", 0.006, label="plate")
            badge(k, (0.13, side * TRACK_Y, top + 0.014), 0.066)
    _mount(k)
    _gun(k)
