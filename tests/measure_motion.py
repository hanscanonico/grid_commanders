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
2026-08-24 foot-figure and hull ones — the eight land vehicles re-authored to
move a named sub-assembly a whole texel, `units._track`'s link stripe given a
period of eight voxels so pose B advances it four (one texel in the direction
of travel), then the rifleman and the rocket trooper given whole-texel body
beats of their own, then the two copters' rotors turned rather than swapped,
and finally the four static hulls given a moving assembly each on top of the
bob (guns, autocannon, periscope, bow visor):

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
                 99    33   12  1.75  |    393   112   46  1.43   remass
  rockets       119    12    0 12.00  |    469    43    0 43.00   before
                119    47   11  3.27  |    469   185   43  3.30   after
  apc            86     6    0  6.00  |    340    25    0 25.00   before
                 86    17    3  4.67  |    340    75   15  4.00   after
                 95    34    8  3.25  |    375   133   32  3.16   remass
  fighter        62    55   30  0.83  |    243   237  114  1.08
  bomber        101    83   36  1.31  |    369   328  144  1.28
  b_copter       44    49   25  0.96  |    209   207   97  1.13   before
                 44    49   28  0.75  |    209   209  107  0.95   after
  t_copter       60    58   24  1.42  |    260   241   90  1.68   before
                 60    62   30  1.07  |    260   249  109  1.28   after
  missiles       74     7    0  7.00  |    289    36    3 11.00   before
                 74    29   10  1.90  |    289   118   35  2.37   after
  battleship     80    66   30  1.20  |    329   267  116  1.30   before
                 80    69   33  1.09  |    329   285  133  1.14   after
  cruiser        71    64   22  1.91  |    241   225   88  1.56   before
                 71    65   24  1.71  |    241   229   95  1.41   after
  sub            60    43   24  0.79  |    252   177   96  0.84   before
                 60    44   25  0.76  |    252   181  100  0.81   after
  lander         58    46   18  1.56  |    216   188   72  1.61   before
                 58    50   20  1.50  |    216   199   81  1.46   after
  ALL          1367   544  216  1.52  |   5452  2209  856  1.58   before
               1367   731  299  1.44  |   5452  2937 1170  1.51   after
               1381   754  309  1.44  |   5503  3011 1203  1.50   remass

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

The REMASS rows are 2026-08-24, when the APC and the artillery were rebuilt
to separate from the tank at rung 1 (`Silhouette`'s zoomed-out reading) and
both idles had to be re-authored to suit the new mass:

- the APC is no longer a featureless slab with a nose to dip, so the whole
  raised cab — roof, cupola, glacis and bumper — dips together over an open
  cargo deck that holds still, and it goes 3 -> 8 silhouette texels at rung 1;
- the artillery's howitzer stands three z per y now instead of two, which
  puts it near-VERTICAL on screen, and a near-vertical spike recoiling one
  texel slides down its own column: 3 silhouette texels against 23 interior
  ones, 6.67 shimmer, over the 5.0 bar. The stroke is two texels for the same
  reason the MBT's thin gun lays two, and comes in at 12 and 1.75.

What each unit moves is otherwise in its builder's docstring.

Everything that flies or floats does change silhouette texels, but read that
carefully before crediting it as animation: fighter and bomber build the SAME
model for both poses (verified against `build_model`), and differ only by
`atlas.BOB_PX` — pose B is pose A translated four atlas pixels up, which is
one whole rung-1 texel of altitude and nothing else. They score the way a
translated shape scores: every boundary texel of the sprite moves, which is
why their counts dwarf a land unit's moving one assembly.

The four hulls used to score that way too — the BEFORE rows above are the bob
on its own, with a fleet that rose and fell in unison and nothing on any ship
moving. Each now moves one named assembly a texel BESIDES bobbing, and the
gain shows in both columns: a part that rises with the bob travels two texels
where the hull travels one. The lander is the one that had to change its mind
about which way: the bow visor dips in a landing craft, but a texel down
under a texel of bob pins the bow's outline exactly where pose A left it (17
silhouette texels, below the 18 the bob scored alone), so the visor rides UP
its hinge posts instead.

The copters' own BEFORE row is the 45-degree sweep they used to do, which is
the ambiguous middle of a four-blade disc's 90-degree symmetry and was drawn
with a different blade set besides: two long diagonals against pose A's four
axial blades. That scored well here and read as two aircraft alternating —
silhouette IoU between the frames, bob taken out, 0.74 on b_copter and 0.74
on t_copter. The AFTER row is the same four blades turned 14 degrees
(`units._BLADE_B`), at 0.88 and 0.87, which is one aircraft with its rotor
advanced, and it still moves 28 and 30 silhouette texels at rung 1. Silhouette
share is not the measure of an idle on its own: WHICH texels move is.

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
