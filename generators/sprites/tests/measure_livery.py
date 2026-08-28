"""Dev instrument for the livery retune — not a test, a readout.

Prints, per unit: how much of the sprite carries faction colour, how loud
that colour is (median/p90 saturation of the faction pixels), and how far
the unit's iron render sits from its neutral render (the 2026-08-13 sprite
review's collapsed pair). The bottom block prints the atlas-row means the
RowSeparation gate asserts over.

Run: .venv/bin/python tests/measure_livery.py [unit ...]
"""

from __future__ import annotations

import statistics
import sys
from pathlib import Path

# The package is not installed, and a file run by path puts its own directory
# on sys.path rather than the repo root, so put the root there ourselves and
# `.venv/bin/python tests/measure_livery.py` works from a bare checkout.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from spritegen import atlas  # noqa: E402
from spritegen.palette import FACTIONS, faction_by_key  # noqa: E402
from spritegen.units import ATLAS_ORDER  # noqa: E402


def saturation(rgb: tuple[int, int, int]) -> float:
    hi, lo = max(rgb), min(rgb)
    return 0.0 if hi == 0 else (hi - lo) / hi


# The dithered drop shadow is identical on every row; readouts measure the
# army, not its shadow (same exclusion as the RowSeparation gate).
SHADOW = (16, 18, 24)


def opaque(img) -> list[tuple[int, int, tuple[int, int, int]]]:
    px = img.convert("RGBA").load()
    out = []
    for y in range(img.height):
        for x in range(img.width):
            c = px[x, y]
            if c[3] > 200 and c[:3] != SHADOW:
                out.append((x, y, c[:3]))
    return out


def mean_rgb(pixels) -> tuple[float, float, float]:
    n = max(1, len(pixels))
    return (
        sum(c[0] for _, _, c in pixels) / n,
        sum(c[1] for _, _, c in pixels) / n,
        sum(c[2] for _, _, c in pixels) / n,
    )


def dist(a, b) -> float:
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5


def unit_report(uid: str) -> str:
    red = atlas.unit_cell(uid, faction_by_key("red")).convert("RGBA")
    blue = atlas.unit_cell(uid, faction_by_key("blue")).convert("RGBA")
    pb = blue.load()
    body = opaque(red)
    fac = [(x, y, c) for x, y, c in body if pb[x, y][:3] != c]
    sats = sorted(saturation(c) for _, _, c in fac) or [0.0]
    iron = mean_rgb(opaque(atlas.unit_cell(uid, faction_by_key("iron"))))
    neutral = mean_rgb(opaque(atlas.unit_cell(uid, faction_by_key("neutral"))))
    return (
        f"{uid:11s} coverage={100 * len(fac) / max(1, len(body)):3.0f}% "
        f"medS={statistics.median(sats):.2f} "
        f"p90S={sats[int(len(sats) * 0.9)]:.2f} "
        f"iron<->neutral={dist(iron, neutral):5.1f}"
    )


def row_means() -> None:
    img = atlas.build_units_atlas()
    px = img.load()
    means = []
    for r in range(len(FACTIONS)):
        tot = [0, 0, 0]
        n = 0
        for y in range(r * 64, r * 64 + 64):
            for x in range(img.width):
                c = px[x, y]
                if c[3] > 200:
                    tot[0] += c[0]
                    tot[1] += c[1]
                    tot[2] += c[2]
                    n += 1
        means.append(tuple(t / n for t in tot))
    for i, f in enumerate(FACTIONS):
        print(f"row {i} {f.key:8s} mean={tuple(round(m) for m in means[i])}")
    for i in range(len(FACTIONS)):
        for j in range(i + 1, len(FACTIONS)):
            print(
                f"{FACTIONS[i].key:8s}<->{FACTIONS[j].key:8s} "
                f"{dist(means[i], means[j]):5.1f}"
            )


if __name__ == "__main__":
    units = sys.argv[1:] or ATLAS_ORDER
    for uid in units:
        print(unit_report(uid))
    if not sys.argv[1:]:
        print()
        row_means()
