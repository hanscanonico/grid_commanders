"""Shoulders, chest, collar cut, strap and the rank pip.

Slice C builds this module; the vocabularies below are its contract.
"""

from __future__ import annotations

from .canvas import Canvas
from .light import Ramp
from .palette import Faction

COLLAR_CUTS = frozenset({"double", "mandarin", "v"})
COLLAR_DEFAULT = "v"


def draw(canvas: Canvas, faction: Faction, collar: str, ramp: Ramp) -> None:
    """The uniform mass, cut at the collar. An unknown cut raises."""
    raise NotImplementedError("slice C")


def pip(canvas: Canvas, ramp: Ramp) -> None:
    """The rank stud — the four costliest powers wear it, nobody else."""
    raise NotImplementedError("slice C")
