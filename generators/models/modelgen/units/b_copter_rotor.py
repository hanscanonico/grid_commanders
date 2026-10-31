"""The gunship's main rotor: four long blades, run along and across the fuselage at rest."""

from __future__ import annotations

from ..kit import Kit
from .aircraft import AIR_ROLES, rotor

ROLES = AIR_ROLES
TEXTURE = 128
NORMAL_TEXTURE = 64
RADIUS = 0.285
CHORD = 0.056


def build(k: Kit) -> None:
    rotor(k, 4, RADIUS, CHORD, 0.0)
