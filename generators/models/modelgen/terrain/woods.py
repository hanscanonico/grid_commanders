"""One cell of wood: tiered pines and round oaks round the edge, the middle left open."""

from __future__ import annotations

import math
import random

from ..kit import Kit
from ..paint import Role

CAGE = 0.05
REACH = 0.12
ROLES = {
    "needle": Role((0.05, 0.17, 0.055), edge=0.0, wash=0.8, dust=0.0),
    "needle_lit": Role((0.17, 0.40, 0.09), edge=0.0, wash=0.35, dust=0.0),
    "leaf": Role((0.12, 0.28, 0.05), edge=0.0, wash=0.8, dust=0.0),
    "leaf_lit": Role((0.36, 0.55, 0.09), edge=0.0, wash=0.35, dust=0.0),
    "bark": Role((0.13, 0.08, 0.04), edge=0.6, dust=0.4),
}
SPOTS = (
    (-0.3, 0.3, "pine", 1.42),
    (0.28, 0.32, "pine", 1.26),
    (-0.02, 0.36, "oak", 1.2),
    (-0.36, -0.02, "oak", 1.08),
    (0.37, 0.0, "pine", 1.12),
    (-0.33, -0.33, "pine", 0.86),
    (0.34, -0.34, "oak", 0.86),
)


def _pine(k: Kit, x: float, y: float, s: float, rng: random.Random) -> None:
    k.cyl((x, y, 0.0), (x, y, 0.09 * s), 0.024 * s, 0.018 * s, "bark", 6, 0.0, "trunk")
    tiers = ((0.05, 0.115, 0.125), (0.13, 0.092, 0.115), (0.205, 0.066, 0.12))
    for base, radius, height in tiers:
        z0, r, h = base * s, radius * s, height * s
        k.cyl((x, y, z0), (x, y, z0 + h), r, 0.008 * s, "needle", 9, 0.0, "tier")
        if k.hi:
            for _ in range(46):
                t = rng.random()
                angle = rng.random() * math.tau
                radial = r * (1 - t) + 0.008 * s * t
                k.ellipsoid(
                    (x + radial * math.cos(angle), y + radial * math.sin(angle), z0 + h * t),
                    (0.018 * s, 0.018 * s, 0.01 * s),
                    "needle_lit" if rng.random() < 0.6 and t > 0.1 else "needle",
                    3,
                    5,
                    "needles",
                )


def _oak(k: Kit, x: float, y: float, s: float, rng: random.Random) -> None:
    k.cyl((x, y, 0.0), (x, y, 0.1 * s), 0.028 * s, 0.021 * s, "bark", 6, 0.0, "trunk")
    lobes = ((0.0, 0.0, 0.16, 0.095), (-0.048, 0.03, 0.135, 0.072), (0.05, -0.025, 0.14, 0.072), (0.0, 0.0, 0.215, 0.064))
    for dx, dy, dz, radius in lobes:
        cx, cy, cz, r = x + dx * s, y + dy * s, dz * s, radius * s
        k.ellipsoid((cx, cy, cz), (r, r, r * 0.92), "leaf", 5, 8, "crown")
        if k.hi:
            for _ in range(34):
                theta = rng.random() * math.tau
                up = rng.uniform(-0.25, 1.0)
                across = math.sqrt(max(0.0, 1.0 - up * up))
                k.ellipsoid(
                    (cx + r * across * math.cos(theta), cy + r * across * math.sin(theta), cz + r * 0.92 * up),
                    (0.018 * s, 0.018 * s, 0.013 * s),
                    "leaf_lit" if up > 0.0 and rng.random() < 0.75 else "leaf",
                    3,
                    5,
                    "leaves",
                )


def build(k: Kit) -> None:
    k.cull = False
    rng = random.Random(4)
    for x, y, kind, s in SPOTS:
        (_pine if kind == "pine" else _oak)(k, x, y, s, rng)
