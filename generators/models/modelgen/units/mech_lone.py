"""One mech trooper at twice the size, for the battle cut-in's lens."""

from __future__ import annotations

from ..kit import Kit
from .soldier import LONE_SCALE, ROLES, trooper

__all__ = ["ROLES", "TEXTURE", "build"]

TEXTURE = 512


def build(k: Kit) -> None:
    k.marker("muzzle", trooper(k, 0.0, 0.0, LONE_SCALE, 0))
