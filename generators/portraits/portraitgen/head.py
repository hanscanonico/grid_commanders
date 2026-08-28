"""The skull, the neck and the ear — the geometry every other layer hangs off.

A head is four dials, exactly the `head` column of the roster:
`[width, jaw, crown, spread]`. Slice B builds this module; the signatures below
are its contract.
"""

from __future__ import annotations

from dataclasses import dataclass

from .canvas import Canvas, Point
from .light import Ramp

# The jaw a skull is cut with. An unknown jaw raises: the vocabulary is the
# dispatch table, so nothing falls through to a default.
JAWS = frozenset({"round", "square", "tapered"})

# tools/commander_faces.gd's HEAD_DEFAULT, column for column.
HEAD_DEFAULT: tuple[float, str, float, float] = (1.0, "round", 0.0, 1.0)


@dataclass(frozen=True)
class Skull:
    """One general's head: width 0.86-1.14, a jaw, crown -3..3, spread 0.9-1.1."""

    width: float
    jaw: str
    crown: float
    spread: float


def outline(skull: Skull) -> list[Point]:
    """The skull's silhouette, in portrait pixels, before the pose transform."""
    raise NotImplementedError("slice B")


def draw(canvas: Canvas, skull: Skull, ramp: Ramp) -> None:
    """Paint the head, the neck and the ear in the skin ramp's four bands."""
    raise NotImplementedError("slice B")
