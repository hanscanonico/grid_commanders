"""The window field behind a bust: a faction gradient, a treatment, the frame.

Every treatment is hard lattice or band geometry inside the 0.20-0.26 opacity
band — brighter and it competes with the face. Slice C builds this module.
"""

from __future__ import annotations

from .canvas import Canvas
from .palette import Faction

KINDS = frozenset({"bars", "burst", "grid", "halftone", "rays", "speed", "wedge"})
# The band a treatment is drawn at, over the faction field.
OPACITY_BAND = (0.20, 0.26)


def draw(canvas: Canvas, kind: str, faction: Faction) -> None:
    """The field, the treatment and the ink window border. Unknown kinds raise."""
    raise NotImplementedError("slice C")
