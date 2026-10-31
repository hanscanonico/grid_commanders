"""The transport: a fat flying bus on tandem rotors, its aft one up on a tall pylon."""

from __future__ import annotations

from ..kit import Kit
from .aircraft import AIR_ROLES, rounded_plan, skids

ROLES = AIR_ROLES
FORE_HUB = (0.17, 0.0, 0.225)
AFT_HUB = (-0.19, 0.0, 0.33)
ROTOR_HUB_DROP = 0.01
ROOF_Z = 0.2
SPINE_Z = 0.216
PYLON_Z = 0.3
EMBLEM = (-0.002, 0.0)
EMBLEM_RADIUS = 0.058


def _body(k: Kit) -> None:
    k.loft(
        [
            (0.028, rounded_plan(0.27, -0.3, 0.11, 0.1, 0.05)),
            (0.055, rounded_plan(0.295, -0.335, 0.13, 0.11, 0.05)),
            (0.145, rounded_plan(0.305, -0.345, 0.135, 0.11, 0.05)),
            (0.182, rounded_plan(0.27, -0.34, 0.13, 0.09, 0.05)),
            (ROOF_Z, rounded_plan(0.22, -0.32, 0.105, 0.07, 0.04)),
        ],
        "team",
        0.012,
        label="body",
    )
    # The light nose in front of the wide windscreen.
    k.loft(
        [
            (0.032, rounded_plan(0.312, 0.21, 0.1, 0.07, 0.03)),
            (0.052, rounded_plan(0.345, 0.21, 0.118, 0.08, 0.03)),
            (0.11, rounded_plan(0.355, 0.21, 0.122, 0.085, 0.03)),
            (0.138, rounded_plan(0.326, 0.21, 0.11, 0.075, 0.03)),
        ],
        "bone",
        0.01,
        label="nose",
    )
    k.ellipsoid((0.232, 0, 0.155), (0.082, 0.126, 0.052), "team_dark", 8, 16, "windscreen_rim")
    k.ellipsoid((0.24, 0, 0.168), (0.066, 0.104, 0.052), "glass", 8, 16, "windscreen")
    # The raised spine between the rotors, where the badge goes.
    k.loft(
        [
            (ROOF_Z - 0.006, rounded_plan(0.09, -0.095, 0.08, 0.04, 0.04)),
            (SPINE_Z, rounded_plan(0.08, -0.085, 0.07, 0.034, 0.034)),
        ],
        "team",
        0.008,
        label="spine",
    )
    # Fat sponsons along the flanks: the width the gunship does not have.
    for side in (-1.0, 1.0):
        y = side * 0.13
        k.loft(
            [
                (0.016, rounded_plan(0.15, -0.21, 0.032, 0.03, 0.03)),
                (0.03, rounded_plan(0.17, -0.23, 0.044, 0.04, 0.04)),
                (0.08, rounded_plan(0.17, -0.23, 0.044, 0.04, 0.04)),
                (0.095, rounded_plan(0.15, -0.21, 0.032, 0.03, 0.03)),
            ],
            "team_dark",
            0.008,
            (0, y, 0),
            "sponson",
        )
    # The rear ramp.
    k.box((-0.335, 0, 0.09), (0.026, 0.19, 0.11), "team_dark", 0.008, label="ramp")
    if k.hi:
        for side in (-1.0, 1.0):
            flank = side * 0.133
            k.box((-0.06, flank, 0.16), (0.5, 0.006, 0.022), "team_light", 0.0, label="stripe")
            k.box((0.13, flank, 0.12), (0.1, 0.006, 0.08), "team_dark", 0.0, label="door")
            for x in (-0.24, -0.16, -0.08, 0.0):
                k.cyl(
                    (x, flank - side * 0.004, 0.125),
                    (x, flank + side * 0.004, 0.125),
                    0.016,
                    0.016,
                    "glass",
                    8,
                    0.0,
                    "port",
                )


def _rotor_mounts(k: Kit) -> None:
    # The fore collar on the cab.
    x = FORE_HUB[0]
    k.cyl((x, 0, ROOF_Z - 0.008), (x, 0, ROOF_Z + 0.01), 0.068, 0.056, "team_dark", 12, 0.005, "fore_collar")
    k.cyl((x, 0, ROOF_Z), (x, 0, FORE_HUB[2] - ROTOR_HUB_DROP), 0.036, 0.03, "gunmetal", 10, 0.003, "fore_mast")
    # The aft pylon, the transport's fin, with a light band round its shoulders.
    k.loft(
        [
            (0.19, rounded_plan(-0.09, -0.335, 0.098, 0.05, 0.04)),
            (0.255, rounded_plan(-0.11, -0.3, 0.08, 0.05, 0.035)),
            (PYLON_Z, rounded_plan(-0.125, -0.255, 0.066, 0.04, 0.03)),
        ],
        "team",
        0.007,
        label="pylon",
    )
    k.loft(
        [
            (0.262, rounded_plan(-0.109, -0.293, 0.08, 0.05, 0.035)),
            (0.284, rounded_plan(-0.116, -0.273, 0.074, 0.045, 0.033)),
        ],
        "bone",
        0.004,
        label="pylon_band",
    )
    x = AFT_HUB[0]
    k.cyl((x, 0, PYLON_Z - 0.005), (x, 0, AFT_HUB[2] - ROTOR_HUB_DROP), 0.04, 0.03, "gunmetal", 10, 0.003, "aft_mast")


def build(k: Kit) -> None:
    k.cull = False
    skids(k, 0.15, 0.25, -0.26, 0.04)
    _body(k)
    _rotor_mounts(k)
    k.marker("emblem", (EMBLEM[0], EMBLEM[1], SPINE_Z))
    k.marker("emblem_edge", (EMBLEM[0] + EMBLEM_RADIUS, EMBLEM[1], SPINE_Z))
