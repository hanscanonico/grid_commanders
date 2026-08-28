"""Hair: a mass silhouette plus tapered strand clusters off the hair ramp.

A style is not a flat shape — it is the mass, then N clusters placed on a fixed
sequence over it, each taking its own band from the ramp. That is what turns a
single dark hex into hair. Slice C builds this module.
"""

from __future__ import annotations

from .canvas import Canvas
from .head import Skull
from .light import Ramp

STYLES = frozenset(
    {
        "bald",
        "bob",
        "braid",
        "bun",
        "buzz",
        "curly",
        "hood",
        "long",
        "ponytail",
        "short",
        "sidepart",
        "spiky",
    }
)
HAIR_COLOURS = frozenset(
    {"auburn", "black", "blonde", "brown", "darkbrown", "grey", "platinum"}
)


def draw(canvas: Canvas, skull: Skull, style: str, ramp: Ramp) -> None:
    """The mass and its clusters. An unknown style raises."""
    raise NotImplementedError("slice C")


def ramp_for(colour: str) -> Ramp:
    """The four tones a hair colour is painted in."""
    raise NotImplementedError("slice C")
