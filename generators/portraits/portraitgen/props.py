"""The signature props: one per general, each touching the bust and casting.

A prop never floats: it merges with the silhouette through a hand, a shoulder, a
strap or a cable, and a shouldered prop is carried by something drawn in front
of it. Slice C builds this module.
"""

from __future__ import annotations

from .canvas import Canvas
from .light import Ramp
from .palette import Faction

PROPS = frozenset(
    {
        "anchor",
        "axe",
        "baton",
        "book",
        "card",
        "cigar",
        "coins",
        "compass",
        "dagger",
        "drone",
        "falcon",
        "hammer",
        "helm",
        "ledger",
        "medal",
        "pipe",
        "plane",
        "radio",
        "sabre",
        "scales",
        "whistle",
        "wrench",
    }
)
# The props worn on a shoulder, which the strap crosses in front of.
SHOULDERED = frozenset({"anchor", "axe", "hammer", "sabre", "wrench"})


def draw(canvas: Canvas, key: str, faction: Faction, ramp: Ramp) -> None:
    """The prop, behind the figure, with its strap in front. Unknown keys raise."""
    raise NotImplementedError("slice C")
