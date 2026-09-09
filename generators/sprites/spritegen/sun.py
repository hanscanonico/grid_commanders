"""The one sun the whole sheet is lit by: what a shadow is, and where it falls.

Every model on the sheet — a unit, a hull, a building, a mountain — is lit
from the top-left by the same light, so its shadow is the same tone and falls
in the same direction. Both drawers used to say that separately (`cell.py` for
the unit cells, `terrain/properties.py` for the buildings), each carrying a
comment telling the other to move with it; this module is what those comments
asked for. Import from here, never restate.

It is deliberately a leaf: it imports the palette's type alias and nothing
else, so both the cell composer and the terrain drawers can read it without
either of them having to depend on the other.
"""

from __future__ import annotations

from .palette import RGB


# A cast shadow is the one surface on the sheet lit by AMBIENT and nothing
# else, so its tone is the sky, keyed down: AMBIENT's hue at a third of its
# chroma at L18 — `terrain._tone(AMBIENT, 0.34, 18.0)`, which evaluates to
# this triple. It is written out here rather than derived because `_tone`
# lives downstream of the cell composer that also needs the colour, and the
# derivation shaping the light must not depend on which drawer asks for it.
# A near-black literal chosen freehand would read as a hole punched in the
# board rather than as shade on it; if the sky is ever retuned, this moves
# with it.
SHADOW: RGB = (16, 18, 24)

# One sun, one shadow direction: the light is top-left, so every shadow the
# sheet drops falls DOWN-RIGHT by this much — an aircraft's ellipse and a
# building's silhouette alike. An airborne caster drops further, because the
# gap between unit and shadow is the altitude cue, but never in another
# direction.
SHADOW_OFFSET = (2, 2)


def casts_shadow(kind: str) -> bool:
    """Who casts, of the things the unit sheet draws: only what is airborne.

    A tile already carries its own ground — grass clumps, a road's crown, the
    water's swell — and a dark ellipse baked under every hull read as a hole
    in it rather than as shade, doubling up with the terrain's own shading at
    every zoom rung. So a unit standing on the board casts nothing: the
    contour is what separates it from the tile, and a hull reads by its
    waterline foam and its wake. An aircraft keeps a small ellipse, because
    the gap between unit and shadow is the only altitude cue the sheet has.

    Buildings and scenery are not asked: they stamp their own drop shadow
    (`terrain._drop_shadow`) and keep it.
    """
    return kind == "air"
