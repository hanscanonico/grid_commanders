"""One cell of mountain: a shoulder a unit stands on, two snow-capped crags at its back."""

from __future__ import annotations

import math
import random

from mathutils import noise, Vector

from ..kit import Kit
from ..paint import Role

CAGE = 0.08
REACH = 0.2
SHOULDER = 0.24
ROLES = {
    "granite": Role((0.1, 0.085, 0.07), edge=0.0, wash=1.0, dust=0.0),
    "granite_lit": Role((0.26, 0.22, 0.17), edge=0.0, wash=0.45, dust=0.0),
    "granite_dark": Role((0.035, 0.028, 0.024), edge=0.0, wash=0.5, dust=0.0),
    "snow": Role((0.82, 0.86, 0.93), edge=0.0, wash=0.65, dust=0.0),
    "turf": Role((0.13, 0.25, 0.05), edge=0.0, wash=0.8, dust=0.0),
}


def _outline(half: float, seed: float, n: int = 16) -> list[tuple[float, float]]:
    """A rough rounded square, so neighbouring mountains' feet run together."""
    points = []
    for i in range(n):
        t = math.tau * i / n
        c, s = math.cos(t), math.sin(t)
        square = half / max(abs(c), abs(s)) ** 0.7
        bump = 1.0 + 0.12 * noise.noise(Vector((c * 1.6 + seed, s * 1.6, seed)))
        points.append((c * square * bump, s * square * bump))
    return points


def build(k: Kit) -> None:
    k.cull = False
    k.smooth_angle = 24.0
    k.loft(
        [
            (0.0, _outline(0.5, 1.0)),
            (SHOULDER * 0.45, _outline(0.45, 2.0)),
            (SHOULDER * 0.82, _outline(0.37, 3.0)),
            (SHOULDER, _outline(0.3, 4.0)),
        ],
        "granite",
        0.012,
        label="shoulder",
    )
    if k.hi:
        # Moss caught on the ledge, and cracks down the rock for the wash to run in.
        rng = random.Random(9)
        for _ in range(70):
            a, reach = rng.random() * math.tau, rng.uniform(0.04, 0.28)
            k.ellipsoid(
                (reach * math.cos(a), -0.05 + reach * math.sin(a), SHOULDER),
                (rng.uniform(0.012, 0.03), rng.uniform(0.012, 0.03), 0.006),
                "turf" if rng.random() < 0.55 else "granite_lit",
                3,
                6,
                "moss",
            )
    for i, (x, y, z, rx, ry, seed) in enumerate(
        (
            (-0.4, -0.38, 0.05, 0.1, 0.08, 3.1),
            (0.36, -0.42, 0.04, 0.09, 0.07, 5.2),
            (0.45, -0.05, 0.08, 0.075, 0.09, 7.3),
            (-0.46, 0.0, 0.07, 0.07, 0.1, 9.4),
            (-0.14, -0.44, 0.035, 0.07, 0.05, 2.2),
        )
    ):
        k.rock((x, y, z), (rx, ry, z * 1.3), "granite", seed, 0.34, 4, 6, label=f"boulder{i}")
    # The peaks: the tall crag, its twin and a low spur, off the back of the shoulder.
    for x, y, rx, ry, top, seed in (
        (-0.15, 0.2, 0.3, 0.25, 0.72, 1.3),
        (0.24, 0.26, 0.24, 0.2, 0.56, 2.7),
        (-0.36, 0.3, 0.14, 0.14, 0.42, 4.9),
    ):
        k.crag(x, y, rx, ry, top, "granite", seed, label="peak")
        if top > 0.5:
            k.crag(x, y, rx, ry, top, "snow", seed, snow_above=top * 0.68, label="cap")
        if k.hi:
            rng = random.Random(int(seed * 10))
            for _ in range(60):
                a, t = rng.random() * math.tau, rng.uniform(0.04, 0.66)
                taper = (1.0 - t) ** 0.85
                k.ellipsoid(
                    (x + rx * taper * math.cos(a), y + ry * taper * math.sin(a), top * t),
                    (rng.uniform(0.012, 0.03), rng.uniform(0.012, 0.03), rng.uniform(0.006, 0.02)),
                    "granite_lit" if rng.random() < 0.7 else "granite_dark",
                    3,
                    6,
                    "strata",
                )
