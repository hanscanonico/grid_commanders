"""What the aircraft share: fat fuselages, thick wings, capped fins, skids and rotors."""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import replace
from typing import NamedTuple

from mathutils import Matrix

from ..kit import Kit
from ..paint import ROLES as PAINTS

# An aircraft never meets a road: no dust up its belly, and no chips stitching its long edges.
AIR_ROLES = {
    **{name: replace(role, dust=0.0) for name, role in PAINTS.items()},
    "team": replace(PAINTS["team"], chip=0.3, dust=0.0),
    "team_light": replace(PAINTS["team_light"], chip=0.3, dust=0.0),
    "team_dark": replace(PAINTS["team_dark"], chip=0.2, dust=0.0),
}

# How far up a fin its light cap starts, as `AirModels3D.FIN_CAP` has it.
FIN_CAP = 0.72


class Wing(NamedTuple):
    """One wing in plan: where its edges run between its root and its tip."""

    root_y: float
    tip_y: float
    lead_root: float
    lead_tip: float
    trail_root: float
    trail_tip: float

    def lead(self, y: float) -> float:
        return self.lead_root + (self.lead_tip - self.lead_root) * (y - self.root_y) / (self.tip_y - self.root_y)

    def trail(self, y: float) -> float:
        return self.trail_root + (self.trail_tip - self.trail_root) * (y - self.root_y) / (self.tip_y - self.root_y)

    def outline(self, y0: float, y1: float, side: float) -> list[tuple[float, float]]:
        return [
            (self.lead(y0), side * y0),
            (self.lead(y1), side * y1),
            (self.trail(y1), side * y1),
            (self.trail(y0), side * y0),
        ]


def wings(
    k: Kit,
    wing: Wing,
    z0: float,
    z1: float,
    role: str = "team",
    bevel: float = 0.016,
    cap_y: float | None = None,
    label: str = "wing",
) -> None:
    """A pair of slab wings; `cap_y` is where the livery tip starts, a hair proud of the wing."""
    for side in (-1.0, 1.0):
        outline = wing.outline(wing.root_y, wing.tip_y, side)
        k.loft([(z0, outline), (z1, outline)], role, bevel, label=label)
        if cap_y is not None:
            tip = wing.outline(cap_y, wing.tip_y, side)
            tip = [(x, y + side * 0.003 if abs(y) > cap_y + 0.001 else y) for x, y in tip]
            proud = [(x + (0.003 if i < 2 else -0.003), y) for i, (x, y) in enumerate(tip)]
            k.loft([(z0 - 0.002, proud), (z1 + 0.002, proud)], "bone", bevel, label=f"{label}_tip")


def fuselage(
    k: Kit,
    rings: Sequence[tuple[float, float, float, float]],
    role: str = "team",
    sides: int = 14,
    label: str = "fuselage",
):
    """A smooth body along X from rings of (x, z, half height, half width)."""
    return k.tube([((x, 0.0, z), h, w) for x, z, h, w in rings], role, sides, label)


def fin(
    k: Kit,
    lead_low: tuple[float, float],
    lead_high: tuple[float, float],
    trail_high: tuple[float, float],
    trail_low: tuple[float, float],
    y: float = 0.0,
    thick: float = 0.034,
    cant: float = 0.0,
    role: str = "team_dark",
    bevel: float = 0.01,
    label: str = "fin",
) -> None:
    """A fin's side profile in (x, z), with a light cap; `cant` leans it outward, in degrees."""

    def along(a: tuple[float, float], b: tuple[float, float], t: float) -> tuple[float, float]:
        return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)

    body = [lead_low, trail_low, trail_high, lead_high]
    cap = [along(lead_low, lead_high, FIN_CAP), along(trail_low, trail_high, FIN_CAP), trail_high, lead_high]
    parts = [
        k.side_profile(body, y - thick / 2, y + thick / 2, role, bevel, label),
        k.side_profile(cap, y - thick / 2 - 0.003, y + thick / 2 + 0.003, "bone", bevel, f"{label}_cap"),
    ]
    if cant:
        side = 1.0 if y >= 0 else -1.0
        foot = lead_low[1]
        turn = Matrix.Rotation(math.radians(-side * cant), 4, "X")
        lean = Matrix.Translation((0, y, foot)) @ turn @ Matrix.Translation((0, -y, -foot))
        for part in parts:
            part.matrix_world = lean


def rounded_plan(
    fore: float, aft: float, half: float, fore_r: float, aft_r: float, steps: int = 4
) -> list[tuple[float, float]]:
    """A loaf in plan, its ends rounded: every call with the same `steps` has the same length."""
    points = []
    corners = (
        (fore - fore_r, -(half - fore_r * 0.8), fore_r, -90.0),
        (fore - fore_r, half - fore_r * 0.8, fore_r, 0.0),
        (aft + aft_r, half - aft_r * 0.8, aft_r, 90.0),
        (aft + aft_r, -(half - aft_r * 0.8), aft_r, 180.0),
    )
    for cx, cy, r, start in corners:
        for i in range(steps + 1):
            a = math.radians(start + 90.0 * i / steps)
            points.append((cx + r * math.cos(a), cy + r * 0.8 * math.sin(a)))
    return points


def skids(k: Kit, half_gap: float, fore: float, aft: float, belly: float, role: str = "gunmetal") -> None:
    """Two runners with an upturned toe, each on a pair of struts up to the belly."""
    rail = 0.022
    for side in (-1.0, 1.0):
        y = side * half_gap
        outline = [
            (aft, 0.0),
            (fore - 0.05, 0.0),
            (fore, 0.036),
            (fore - 0.012, 0.046),
            (fore - 0.06, rail),
            (aft, rail),
        ]
        k.side_profile(outline, y - 0.015, y + 0.015, role, 0.005, "skid")
        span = fore - aft
        for t in (0.25, 0.72):
            x = aft + span * t
            k.cyl((x, y, rail - 0.006), (x, y * 0.62, belly), 0.014, 0.014, role, 8, 0.0, "strut")


def rotor(k: Kit, blades: int, radius: float, chord: float, turned: float) -> None:
    """Blades radiating from the hub at the origin, with light tips, turning about Z."""
    k.cull = False
    thick = 0.014
    grip = 0.05
    tip = radius - 0.05
    for i in range(blades):
        a = math.radians(360.0 * i / blades + turned)
        ca, sa = math.cos(a), math.sin(a)

        def turn(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
            return [(x * ca - y * sa, x * sa + y * ca) for x, y in points]

        half = chord / 2
        blade = turn(
            [(0.02, -half * 0.55), (grip, -half), (tip, -half), (tip, half), (grip, half), (0.02, half * 0.55)]
        )
        k.loft([(0.001, blade), (0.001 + thick, blade)], "gunmetal", 0.004, label="blade")
        end = turn(
            [
                (tip - 0.002, -half - 0.001),
                (radius - 0.008, -half - 0.001),
                (radius, -half * 0.55),
                (radius, half * 0.55),
                (radius - 0.008, half + 0.001),
                (tip - 0.002, half + 0.001),
            ]
        )
        k.loft([(0.0, end), (0.002 + thick, end)], "bone", 0.004, label="blade_tip")
    k.cyl((0, 0, -0.01), (0, 0, 0.028), 0.046, 0.04, "gunmetal", 10, 0.006, "hub")
    k.cyl((0, 0, 0.028), (0, 0, 0.042), 0.032, 0.018, "steel", 10, 0.004, "hub_cap")
