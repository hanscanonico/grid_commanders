"""Eyes, brows, nose, mouth, facial hair and the worn accessories.

Every vocabulary here is the roster's own, and every one is a dispatch table: an
unknown key raises rather than drawing a default, which is what the GUT suite's
three "is it one the file can draw?" lints existed to catch.

Slice C builds this module; the vocabularies and signatures below are its
contract.
"""

from __future__ import annotations

from .canvas import Canvas, Point
from .head import Skull
from .light import Ramp

EYE_KINDS = frozenset({"closed", "f", "lidded", "m", "narrow", "wide"})
BROW_KINDS = frozenset({"angled", "cocked", "heavy", "raised", "soft"})
MOUTH_KINDS = frozenset(
    {
        "clench",
        "grin",
        "laugh",
        "neutral",
        "open",
        "smile",
        "smirk",
        "snarl",
        "stern",
        "wry",
    }
)
NOSE_KINDS = frozenset({"broad", "hook", "tick"})
FACIAL_KINDS = frozenset({"beard", "mustache", "none", "stubble"})
ACCESSORY_KINDS = frozenset(
    {
        "bandana",
        "eyepatch",
        "glasses",
        "goggles",
        "headband",
        "headset",
        "hood",
        "none",
        "scar",
    }
)

# The default the handoff gave every face, and the dial the roster scales it by.
EYE_DEFAULT = 1.0


def eyes(canvas: Canvas, skull: Skull, kind: str, *, scale: float) -> None:
    """Sclera, iris ring, pupil and the catchlights, at the roster's eye dial."""
    raise NotImplementedError("slice C")


def brow(canvas: Canvas, skull: Skull, kind: str, ramp: Ramp) -> None:
    raise NotImplementedError("slice C")


def nose(canvas: Canvas, skull: Skull, kind: str, ramp: Ramp) -> None:
    raise NotImplementedError("slice C")


def mouth(canvas: Canvas, skull: Skull, kind: str) -> None:
    """The mouth can never outrank the eyes: its dark area stays the smaller."""
    raise NotImplementedError("slice C")


def facial_hair(canvas: Canvas, skull: Skull, kind: str, ramp: Ramp) -> None:
    raise NotImplementedError("slice C")


def accessory(canvas: Canvas, skull: Skull, kind: str) -> list[Point]:
    """Draw the worn accessory; returns what it added to the silhouette."""
    raise NotImplementedError("slice C")


def earring(canvas: Canvas, skull: Skull) -> None:
    raise NotImplementedError("slice C")


def freckles(canvas: Canvas, skull: Skull, ramp: Ramp) -> None:
    raise NotImplementedError("slice C")
