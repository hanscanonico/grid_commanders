"""Infantry: three riflemen in a wedge, spread so each one reads at board size."""

from __future__ import annotations

from ..kit import Kit
from .soldier import ROLES, rifleman

__all__ = ["ROLES", "TEXTURE", "build"]

TEXTURE = 512
SQUAD = ((0.11, -0.02, 0), (-0.16, 0.205, 1), (-0.13, -0.235, 1))


def build(k: Kit) -> None:
    muzzles = [rifleman(k, x, y, 1.0, phase) for x, y, phase in SQUAD]
    k.marker("muzzle", muzzles[0])
