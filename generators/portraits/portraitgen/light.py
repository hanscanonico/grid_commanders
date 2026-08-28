"""The one light: a fixed key direction, a per-material ramp, a rim, an AO pass.

The sheet is lit from the upper left and a mirrored pose flips geometry only, so
the direction is stated once, here, and never taken from a face's own spec.
Every material is painted out of four named flat tones — deep, shade, base, lit
— plus a rim; no band is an alpha wash over a fill, which is what keeps a
finished raster inside its colour budget.

Slice B builds this module; the signatures below are its contract.
"""

from __future__ import annotations

from dataclasses import dataclass

from .palette import RGB

# The key, in portrait space: x right, y down, so the sun sits up and to the
# left. `spritegen/sun.py` lights the board from the same corner.
KEY = (-0.64, -0.77)
# The four bands every material is painted in, plus the rim. Naming them is the
# palette discipline: a tone is chosen from a ramp, never mixed at the call.
BANDS = ("deep", "shade", "base", "lit")


@dataclass(frozen=True)
class Ramp:
    """One material's four flat tones and its rim."""

    deep: RGB
    shade: RGB
    base: RGB
    lit: RGB
    rim: RGB


def build_ramp(base: RGB, *, rim_hue: RGB | None = None) -> Ramp:
    """A material's four tones from its base colour, rim included.

    Values step on a fixed ladder and chroma rotates toward the sky in shadow
    and toward the sun in light, the way `spritegen/palette.py` builds a faction
    ramp — a ramp is built, never typed.
    """
    raise NotImplementedError("slice B")


def occlusion(occluder, target, *, depth: float):
    """The AO pass: an occluder's own alpha, softened, darkening what is under
    it — the hair fringe, the collar, the jaw, behind the ear."""
    raise NotImplementedError("slice B")


def rim_light(silhouette, ramp: Ramp, *, weight: float):
    """The kicker along the shadow-side silhouette run, at low chroma."""
    raise NotImplementedError("slice B")
