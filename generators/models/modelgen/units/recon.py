"""The recon: a fast little scout car, four fat exposed tyres and a pintle gun."""

from __future__ import annotations

from ..kit import RECOIL, Kit
from .land_gear import badge, tyre

WHEEL_R = 0.1
WHEEL_W = 0.09
WHEEL_Y = 0.232
AXLE_X = 0.205
HALF_Y = 0.165
DECK = 0.205
GUN_Z = 0.285
MUZZLE_X = 0.3


def _body(k: Kit) -> None:
    outline = [
        (-0.3, 0.095),
        (0.27, 0.095),
        (0.335, 0.135),
        (0.32, 0.185),
        (0.28, 0.2),
        (0.075, 0.2),
        (0.03, DECK),
        (-0.27, DECK),
        (-0.31, 0.165),
    ]
    k.side_profile(outline, -HALF_Y, HALF_Y, "team", 0.022, "hull")
    # The hood's flat panel, where the army's badge rides.
    panel_top = 0.214
    k.box((0.178, 0, panel_top - 0.01), (0.165, 0.18, 0.02), "team_light", 0.007, label="hood")
    badge(k, (0.178, 0, panel_top), 0.068)
    for side in (-1.0, 1.0):
        k.cyl((0.3, side * 0.115, 0.163), (0.337, side * 0.115, 0.15), 0.028, 0.026, "brass", 10, 0.004, "headlamp")
        # A bold arched fender over each axle: the shape that says wheels from above.
        for x in (-AXLE_X, AXLE_X):
            arch = [
                (x - 0.132, 0.15),
                (x + 0.132, 0.15),
                (x + 0.115, 0.192),
                (x + 0.06, 0.222),
                (x - 0.06, 0.222),
                (x - 0.115, 0.192),
            ]
            k.side_profile(arch, side * (HALF_Y - 0.01), side * (WHEEL_Y + WHEEL_W / 2 - 0.006), "team", 0.014, "fender")
    k.seam((0.07, 0, DECK + 0.001), (0.006, 0.28, 0.003))
    k.rivets([(x, -HALF_Y - 0.0005, 0.13) for x in (-0.09, -0.03, 0.03, 0.09)], (0, -1, 0), 0.007)


def _crew(k: Kit) -> None:
    # The windscreen stands up behind the hood, leaning back.
    k.box((0.052, 0, 0.247), (0.024, 0.29, 0.094), "team_dark", 0.006, tilt=0.55, label="screen_frame")
    k.box((0.066, 0, 0.253), (0.012, 0.25, 0.072), "glass", 0.002, tilt=0.55, label="screen")
    # The driver's helmet, the one soft thing on the car.
    k.ellipsoid((-0.01, 0.075, 0.245), (0.044, 0.042, 0.038), "team_light", 6, 10, label="helmet")
    # The spare, laid flat on the back deck.
    z = DECK
    k.cyl((-0.195, 0, z), (-0.195, 0, z + 0.042), 0.078, 0.074, "rubber", 14, 0.01, "spare")
    k.cyl((-0.195, 0, z + 0.04), (-0.195, 0, z + 0.05), 0.044, 0.038, "wheel", 10, 0.004, "spare_hub")


def _gun(k: Kit) -> None:
    # Off to the near side, so the badge's patch of the hood never paints the barrel over it.
    x = -0.045
    y = -0.1
    k.cyl((x, y, DECK - 0.004), (x, y, GUN_Z - 0.015), 0.04, 0.03, "gunmetal", 10, 0.005, "pintle")
    k.box((x + 0.015, y, GUN_Z), (0.105, 0.052, 0.05), "gunmetal", 0.008, label="receiver")
    k.box((x + 0.075, y, GUN_Z + 0.002), (0.024, 0.13, 0.082), "team_dark", 0.007, label="gun_shield")
    k.moves(k.cyl((x + 0.05, y, GUN_Z), (MUZZLE_X - 0.03, y, GUN_Z), 0.021, 0.019, "steel", 8, 0.002, "barrel"), RECOIL)
    k.moves(k.cyl((MUZZLE_X - 0.04, y, GUN_Z), (MUZZLE_X, y, GUN_Z), 0.028, 0.026, "gunmetal", 8, 0.003, "flash_hider"), RECOIL)
    k.marker("muzzle", (MUZZLE_X, y, GUN_Z))


def build(k: Kit) -> None:
    for side in (-1.0, 1.0):
        for x in (-AXLE_X, AXLE_X):
            tyre(k, x, side, WHEEL_Y, WHEEL_R, WHEEL_W)
    _body(k)
    _crew(k)
    _gun(k)
