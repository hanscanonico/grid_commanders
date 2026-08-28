"""The FACES table: one row per general, the columns the painter draws from.

Slice D transcribes `tools/commander_faces.gd` into `FACES` column for column —
it is a port, not a re-art — and the vocabularies each column is drawn from are
owned by the module that draws them, never restated here.
"""

from __future__ import annotations

from dataclasses import dataclass

from .head import Skull


@dataclass(frozen=True)
class Face:
    """One general's spec.

    `skin` and `hair` name a ramp, `style` a hair mass, `brow`/`eyes`/`mouth`/
    `nose`/`facial`/`acc` a feature glyph, `collar` a cut, `bg` a backdrop and
    `prop` a signature prop; `eye` scales the eyes (0.82-1.06), `head` is the
    skull's four dials and `pose` is [tilt degrees, zoom, mirrored].
    """

    id: str
    skin: str
    hair: str
    style: str
    brow: str
    eyes: str
    mouth: str
    eye: float
    facial: str
    acc: str
    collar: str
    head: Skull
    nose: str
    pose: tuple[float, float, bool]
    bg: str
    prop: str
    pip: bool = False
    earring: bool = False
    freckles: bool = False


SKIN_TONES = frozenset({"dark", "light", "medium", "pale", "tan"})

# id -> Face, for the 22 generals and the empty seat. Slice D fills it.
FACES: dict[str, Face] = {}
