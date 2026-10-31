"""A fat toy cloud for the cut-in stage's sky: round puffs on a flat underside."""

from __future__ import annotations

from ..kit import Kit
from ..paint import Role

TEXTURE = 256
NORMAL_TEXTURE = 128
CAGE = 0.05
REACH = 0.15
ROLES = {"cloud": Role((0.93, 0.95, 0.98), edge=0.0, wash=0.28, dust=0.0)}
PUFFS = (
    (0.0, 0.0, 0.12, 0.42, 0.3, 0.26),
    (-0.42, 0.04, 0.06, 0.3, 0.24, 0.18),
    (0.42, -0.02, 0.07, 0.32, 0.24, 0.2),
    (0.16, 0.12, 0.2, 0.26, 0.2, 0.2),
    (-0.18, -0.1, 0.16, 0.24, 0.2, 0.16),
    (0.72, 0.03, 0.02, 0.18, 0.15, 0.1),
    (-0.7, -0.03, 0.02, 0.17, 0.14, 0.09),
)


def build(k: Kit) -> None:
    k.cull = False
    for x, y, z, rx, ry, rz in PUFFS:
        k.ellipsoid((x, y, z), (rx, ry, rz), "cloud", 6, 10, "puff")
