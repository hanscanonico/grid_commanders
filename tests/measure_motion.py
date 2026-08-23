"""Dev instrument for the ambient animation — not a test, a readout.

The A/B poses are authored at atlas scale, where a moved voxel is obvious.
The board is not at atlas scale: it draws the 64x96 cell onto a 16px grid
with nearest filtering, so at zoom rung 1 the player sees a 16x24 texel
sample of the cell and at rung 2 a 32x48 one. This prints what survives that
sample, per unit, per rung:

  opaque       texels the pose-A cell paints (alpha > 128)
  changed      texels whose colour differs between pose A and pose B
  silhouette   of those, texels one pose paints and the other does not
  shimmer      interior changed / silhouette changed (the divisor floors at
               1, so a unit whose silhouette holds still reports its whole
               changed count)

A unit with silhouette 0 does not move on the board at that rung: whatever
pose B did landed inside a shape the sampler draws identically, so the only
thing the player can see is texels changing tone in place. That is what the
shimmer index counts, and a high shimmer over a zero silhouette is the
failure mode — the sprite boils instead of animating.

The texel rule behind it: one voxel is a 4x4 px cube and projects to
`sx=(x-y)*2`, `sy=(x+y)-2z`, so one board texel at rung 1 is 4 atlas px,
which is a dz of two voxels or a (dx +1, dy -1) diagonal. A pose delta
smaller than that cannot carry a texel a whole texel across: inside the shape
it only re-tones, and at the edge it flips boundary texels with the sampling
phase rather than moving them.

Recorded 2026-08-23 on the red (meridian) row, before any pose fix, so a later
pass can diff it; livery changes the tones, not the shape:

              rung 1 (16x24)          rung 2 (32x48)
  unit         opaq  chng silh shim    opaq  chng silh shim
  infantry       45     6    2  2.00    189    28    8  2.50
  mech           49     7    2  2.50    202    26   15  0.73
  recon          67    19    3  5.33    277    78   13  5.00
  tank           95     5    0  5.00    386    28    0 28.00
  md_tank       122     4    0  4.00    483    26    0 26.00
  anti_air       80     6    0  6.00    321    20    0 20.00
  artillery      94     8    0  8.00    377    29    0 29.00
  rockets       119    12    0 12.00    469    43    0 43.00
  apc            86     6    0  6.00    340    25    0 25.00
  fighter        62    18    1 17.00    243   125   39  2.21
  bomber        101    31    6  4.17    369   169   42  3.02
  b_copter       44    42   22  0.91    209   152   63  1.41
  t_copter       60    43   20  1.15    260   196   86  1.28
  missiles       74     7    0  7.00    289    36    3 11.00
  battleship     80    51   21  1.43    329   160   57  1.81
  cruiser        71    36   14  1.57    241   141   42  2.36
  sub            60    28   14  1.00    252   125   47  1.66
  lander         58    37   12  2.08    216   111   36  2.08
  ALL          1367   366  117  2.13   5452  1518  451  2.37

The whole tracked family — tank, md tank, anti air, artillery, rockets, apc —
moves nothing at either rung. Four of them creep a tread link (`units._track`
walks its phase), which only re-tones link texels inside a track block that
never changes shape; rockets and missiles settle a sub-assembly one voxel,
which is 2 atlas px of dz, half a rung-1 texel, so it lands inside the shape
too — missiles holds that to rung 1 and leaks 3 silhouette texels at rung 2.

Everything that flies or floats does change silhouette texels, but read that
carefully before crediting it as animation: fighter, bomber and every hull
build the SAME model for both poses (verified against `build_model`), and
differ only by the one-pixel bob in `atlas._BOB_BOTTOM` — pose B is pose A
translated one atlas pixel up, a quarter of a rung-1 texel. It scores because
a whole-body translation re-phases the nearest sample, so boundary texels pick
a different source pixel; that is aliasing at the edge, not a move. Only the
copters, which sweep their rotor discs 45 degrees, change the shape itself,
and they are the two with a shimmer index near 1.

Run: .venv/bin/python tests/measure_motion.py [unit ...]
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

# The package is not installed, and a file run by path puts its own directory
# on sys.path rather than the repo root, so put the root there ourselves and
# `.venv/bin/python tests/measure_motion.py` works from a bare checkout.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from spritegen import atlas  # noqa: E402
from spritegen.palette import faction_by_key  # noqa: E402
from spritegen.units import ATLAS_ORDER, Pose  # noqa: E402

# What the board hands the sampler. BattleView draws the 64x96 cell at 0.25
# of its size per zoom rung, so rung r is a (16r, 24r) texel sample of the
# cell; rungs 1 and 2 are the two the game spends nearly all its time at
# (rung 2 is the default), and they are the two that decimate.
RUNGS = {1: (16, 24), 2: (32, 48)}
OPAQUE = 128


def sample(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    """The board's own filtering: nearest, no gamma, no smoothing."""
    return img.convert("RGBA").resize(size, Image.NEAREST)


def counts(a: Image.Image, b: Image.Image) -> tuple[int, int, int]:
    """Painted texels of `a`, texels the pair disagree on, and how many of
    those disagreements are the silhouette rather than the tone."""
    pa, pb = a.load(), b.load()
    opaque = changed = silhouette = 0
    for y in range(a.height):
        for x in range(a.width):
            ca, cb = pa[x, y], pb[x, y]
            if ca[3] > OPAQUE:
                opaque += 1
            if ca != cb:
                changed += 1
                if (ca[3] > OPAQUE) != (cb[3] > OPAQUE):
                    silhouette += 1
    return opaque, changed, silhouette


def shimmer(changed: int, silhouette: int) -> float:
    return (changed - silhouette) / max(silhouette, 1)


def report(uids: list[str]) -> None:
    fac = faction_by_key("red")
    cells = {
        uid: (
            atlas.unit_cell(uid, fac, Pose.A),
            atlas.unit_cell(uid, fac, Pose.B),
        )
        for uid in uids
    }
    for rung, size in RUNGS.items():
        print(f"--- rung {rung} ({size[0]}x{size[1]} texels) " + "-" * 24)
        print(f"{'unit':<12} {'opaque':>7} {'changed':>8} {'silh':>6} {'shimmer':>8}")
        totals = [0, 0, 0]
        for uid in uids:
            a, b = (sample(img, size) for img in cells[uid])
            opaque, changed, silh = counts(a, b)
            totals = [t + v for t, v in zip(totals, (opaque, changed, silh))]
            print(
                f"{uid:<12} {opaque:>7} {changed:>8} {silh:>6} "
                f"{shimmer(changed, silh):>8.2f}"
            )
        print(
            f"{'ALL':<12} {totals[0]:>7} {totals[1]:>8} {totals[2]:>6} "
            f"{shimmer(totals[1], totals[2]):>8.2f}"
        )
        print()


if __name__ == "__main__":
    wanted = sys.argv[1:] or list(ATLAS_ORDER)
    unknown = [uid for uid in wanted if uid not in ATLAS_ORDER]
    if unknown:
        sys.exit(f"unknown unit(s): {', '.join(unknown)}")
    report(wanted)
