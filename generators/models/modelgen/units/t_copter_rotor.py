"""The transport's rotor, shared by both hubs of its tandem: three short, broad blades."""

from __future__ import annotations

from ..kit import Kit
from .aircraft import AIR_ROLES, rotor

ROLES = AIR_ROLES
TEXTURE = 128
NORMAL_TEXTURE = 64
RADIUS = 0.23
CHORD = 0.08


def build(k: Kit) -> None:
    rotor(k, 3, RADIUS, CHORD, 20.0)
