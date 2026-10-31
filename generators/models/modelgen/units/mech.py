"""Mech: two heavy troopers with packs and shouldered bazookas."""

from __future__ import annotations

from ..kit import Kit
from .soldier import ROLES, trooper

__all__ = ["ROLES", "TEXTURE", "build"]

TEXTURE = 512
SQUAD = ((0.12, -0.17, 0), (-0.14, 0.17, 1))


def build(k: Kit) -> None:
    muzzles = [trooper(k, x, y, 1.0, phase) for x, y, phase in SQUAD]
    k.marker("muzzle", muzzles[0])
