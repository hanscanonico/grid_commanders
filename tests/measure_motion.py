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

Recorded on the red (meridian) row; livery changes the tones, not the shape.
BEFORE is main at the 2026-08-23 land-idle pass, AFTER is that pass plus the
2026-08-24 foot-figure one — the eight land vehicles re-authored to move a
named sub-assembly a whole texel, `units._track`'s link stripe given a period
of eight voxels so pose B advances it four (one texel in the direction of
travel), and then the rifleman and the rocket trooper given whole-texel body
beats of their own:

                     rung 1 (16x24)               rung 2 (32x48)
  unit         opaq  chng silh shim   |   opaq  chng silh shim
  infantry       45     6    2  2.00  |    189    28    8  2.50   before
                 45    31   12  1.58  |    189   126   45  1.80   after
  mech           49     7    2  2.50  |    202    26   15  0.73   before
                 49    10    7  0.43  |    202    41   29  0.41   after
  recon          67    19    3  5.33  |    277    78   13  5.00   before
                 67    12    4  2.00  |    277    46   13  2.54   after
  tank           95     5    0  5.00  |    386    28    0 28.00   before
                 95    26    5  4.20  |    386   125   26  3.81   after
  md_tank       122     4    0  4.00  |    483    26    0 26.00   before
                122    30    6  4.00  |    483   120   20  5.00   after
  anti_air       80     6    0  6.00  |    321    20    0 20.00   before
                 80    25    8  2.12  |    321    88   31  1.84   after
  artillery      94     8    0  8.00  |    377    29    0 29.00   before
                 94    27    7  2.86  |    377    96   30  2.20   after
  rockets       119    12    0 12.00  |    469    43    0 43.00   before
                119    47   11  3.27  |    469   185   43  3.30   after
  apc            86     6    0  6.00  |    340    25    0 25.00   before
                 86    17    3  4.67  |    340    75   15  4.00   after
  fighter        62    55   30  0.83  |    243   237  114  1.08
  bomber        101    83   36  1.31  |    369   328  144  1.28
  b_copter       44    49   25  0.96  |    209   207   97  1.13
  t_copter       60    58   24  1.42  |    260   241   90  1.68
  missiles       74     7    0  7.00  |    289    36    3 11.00   before
                 74    29   10  1.90  |    289   118   35  2.37   after
  battleship     80    66   30  1.20  |    329   267  116  1.30
  cruiser        71    64   22  1.91  |    241   225   88  1.56
  sub            60    43   24  0.79  |    252   177   96  0.84
  lander         58    46   18  1.56  |    216   188   72  1.61
  ALL          1367   544  216  1.52  |   5452  2209  856  1.58   before
               1367   718  282  1.55  |   5452  2890 1104  1.62   after

Before the pass the whole tracked family — tank, md tank, anti air,
artillery, rockets, apc — moved nothing at either rung. Six of them crept a
tread link (`units._track` walked its phase), which only re-toned link texels
inside a track block that never changes shape, and did it at period 2, which
is exactly Nyquist at the board's 4:1 sample: the pattern inverted rather than
travelled. Rockets, missiles and recon settled a sub-assembly one voxel, which
is 2 atlas px of dz, half a rung-1 texel, so it landed inside the shape too.

The two foot figures were the pass after that. Both were at 2 silhouette
texels on a one-voxel hold — the rifleman easing his muzzle down, the trooper
settling his launch tube — which is half a texel and reads as the sprite
boiling. The rifleman now leans his ENTIRE upper body, belt line up, one
`(dx +1, dy -1)` step over planted boots, rifle and both hands riding with the
shoulders; a `dz = -2` compression moves the same texel but costs him 4 px of
height and 64 opaque pixels, under the floors in `tests/test_infantry_read.py`.
The trooper's shoulder and launcher drop `dz = -2` together.

What each land unit moves is in its builder's docstring. Two of them are worth
the reader's time here, because they are what the projection costs: the APC
has no turret and no gun and a roof detail buries itself under the roof's own
far edge, so its texel is the nose dipping; and the MBT's barrel is two voxels
wide, thin enough that a one-texel lay measured 2 silhouette texels, so its
gun lays two.

Everything that flies or floats does change silhouette texels, but read that
carefully before crediting it as animation: fighter, bomber and every hull
build the SAME model for both poses (verified against `build_model`), and
differ only by `atlas.BOB_PX` — pose B is pose A translated four atlas pixels
up, which is one whole rung-1 texel of altitude and nothing else. They score
the way a translated shape scores: every boundary texel of the sprite moves,
which is why their counts dwarf a land unit's moving one assembly. Only the
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
