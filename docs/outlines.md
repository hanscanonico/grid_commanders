# Outlines: the 4px band, and the G-buffer that replaced it

Every unit outline on the sheet used to be `voxel._contour`: a band
`CONTOUR_WEIGHT * k` pixels thick — 4 on the lit edges, 2 on the ground-facing
ones — claimed inward off the plane behind each silhouette edge, plus four
patch passes holding the art together against it (`_settle_rims`,
`_free_lit_tip`, `_pair_lone_rims`, `_step_rim_inboard`).

It is now one pass over the depth and normal planes: `gbuffer.edge_mask` and
`gbuffer.convex_edges`, read per pixel, drawing lines one pixel wide.

## What the band was for, and what it cost

The band was round 10's answer to a real defect. The game draws the 64px cell
onto a 16px grid with nearest filtering, so it keeps one source pixel in four;
round 9 had made every unit's outer boundary structurally S0 and the apc still
failed the legibility sweep, because only 44.7-55.9% of a board-scale
silhouette's boundary came out S0 and which pixels did was an accident of
where the edge fell. Four source pixels is one logical pixel, and a logical
pixel is what the board cannot miss.

The bill for that, measured over both poses of all 18 units in all five
factions:

| reading | band | 1px + sel-out |
| --- | --- | --- |
| S0 share of a unit's own pixels | 34.5% | **13.9%** |
| S0 share on the worst sprite (b_copter, pose B) | 53.1% | **25.6%** |
| sunward-only boundary pixels drawn dark | 100% | **7.1%** |
| min faction-material share of a sprite | 30.4% | **41.2%** |
| min share above L200 (gate: 3%) | 3.13% | **3.82%** |
| iron vs neutral row distance (gate: 60) | 63.7 | **64.6** |
| iron vs neutral as composed (gate: 30) | 36.1 | **45.2** |

A third of every sprite was outline. On a 31px infantry that is the unit.

## The replacement, in one order

`edge_mask(depth, threshold=2)` marks any drawn pixel whose 4-neighbour is
empty or breaks the depth step a continuous surface carries in this
projection; that one mask is the silhouette AND every self-overlap.
`_outline_kind` then classifies each marked pixel by WHERE the break is, in a
fixed order, so no pixel is ever both dark and light:

1. **toward the ground** (down or right) — S0, the faction's own, whatever
   material meets the ground there. Round 9's precedence is unchanged and
   still absolute: 0 violations, measured by
   `test_no_plane_touches_the_ground_on_the_shaded_side`.
2. **against a nearer surface** — the FAR side only, at `max(material floor,
   S1)`. The turret keeps its shape; the hull passing behind it takes the
   line. An accent stops at its own floor rather than going black, which is
   what keeps a lamp a lamp and the sprite under 24 colours.
3. **toward the sun** (up or left) — **lighter**, `SEL_OUT_LIFT = 1` slot up
   the pixel's own ramp, clamped by the ceiling the painting voxel already
   answered to. Iron is capped at S3 by `IRON_SLOT_CEILING`, so Iron draws no
   lit line at all — the correct answer for the dark faction, and free.

`convex_edges` adds the same lift to a lit top face along a convex crease, so
a chamfered turret or a raised deck carries a 1px highlight. Concave gutters
get nothing.

`_interior_contour` (S0 between two materials whose value step is too small to
read) **stays**, and stays last. It was tried without first, as it should be:
a barrel lying along a hull is one continuous surface, so there is no depth
break for `edge_mask` to find, and dropping the pass took the sheet from 306
low-contrast faction/gunmetal contacts to 1,390 — a barrel disappearing into a
light Iron hull. With it back the count is 378. All four rim patch passes were
removed and none came back: a rim has nothing to retreat from once the band is
gone.

## What the despeckle may and may not eat

`_despeckle` still folds every lone pixel into the plane it is most like, and
it is now handed the silhouette's dark mask to leave alone. Along a stair edge
a 1px line runs diagonally, so its pixels differ from all four orthogonal
neighbours and the despeckle would fold half of them away — the round-9 dotted
outline, rebuilt one pass later (measured: 2,530 pixels of ground-facing
silhouette lost, before the mask was passed). Those pixels are exactly the
ones spec item 10 exempts anyway, since each has a transparent neighbour.
Everything else the outline pass writes stays subject to the rule: an interior
line or a sel-out pixel alone among four unlike neighbours is dirt like any
other, and `test_no_isolated_pixel_outside_the_dither` still holds with no
exemptions added.

## The two tests that were rewritten, and the one number that got worse

**`test_no_plane_touches_the_ground` → `..._on_the_shaded_side`.** The rule is
the same and still absolute; what changed is the sides it is claimed on. It
now asks the two ground-facing sides orthogonally, because the sunward two are
answered by light instead (a new test,
`test_the_sunward_edge_is_lit_rather_than_outlined`, holds those to under 10%
dark; measured 7.1%, all of it self-overlap, the interior material line and
despeckle settling). Diagonal neighbours are no longer asked: a 1px line is
connected through its sides, and a stair's inner corner is already fenced by
the two line pixels beside it.

**`ContourWeight` → `BoardScaleEdge`.** This is the honest cost. The old
reading — the share of board-sampled boundary pixels that are S0 — was 74-76%
under the band and is **19-27%** now. A 1px line cannot survive 4:1 nearest
sampling and no tuning makes it; that is the trade the band was bought with.

What replaces it measures the claim selective outlining actually makes: the
edge is a VALUE BREAK, dark away from the sun and light into it, and the board
sees the break either way. As the share of board-sampled boundary pixels whose
value falls outside the sprite's own interquartile band:

| phase | 0 | 1 | 2 | 3 |
| --- | --- | --- | --- | --- |
| band | 83.7% | 81.9% | 84.2% | 87.0% |
| 1px + sel-out | 77.6% | 78.9% | 76.5% | 75.2% |

The floor stays where round 10 put it, 0.70, and the margin (0.752 at its
worst phase) is comparable to the one the band cleared on its own reading
(0.743 against 0.70). The light half of the pair is only safe because of the
terrain ceiling: no tile may
reach the band the units' lit planes live in (`ValueCeiling`), so a lit edge
against ground is a break in value even where a dark one would be.

That is a 6-point drop on a board-scale reading in exchange for a fifth of
every sprite. It is worth re-measuring in the game's own legibility sweep,
which is where the band was bought in the first place.

## Two models moved with the change

Both are consequences of the band, not of taste, and neither is a threshold:

- **the sub** (`units.sub`) was the darkest ship afloat partly because the
  band ate its awash hull: with 1px lines the deck's own lit faces show, and a
  shadow-slot deck lights to exactly the body tone every other hull medians
  at — a tie, and `HullValues` wants strictly darker. Both awash rows moved to
  the under slot and the saddle crowns down with them, keeping the crowns one
  band over the hull. Hull median: 0.395 tied → **0.232** against 0.395.
- **t_copter's pose B** drifted 9.3% of its silhouette mass from pose A, over
  `AmbientFrames`' 8%: the band used to pad every sprite with a halo that
  damped the ratio. The swept-blade collar now carries all four blade roots
  rather than two. Lengthening the blades instead was tried first and read as
  a fighter's wings at 32px (`test_frame_b_still_reads_as_its_own_unit`).

## Density

The line is one SOURCE pixel at any `k`, not one logical pixel: at `k = 2` it
is half a logical pixel, where the band doubled to stay one (see
`docs/density_128.md`). That follows the same finding — 128 buys no logical
resolution — from the other side: an outline the board resolves is not what
carries this sheet's edge any more, the contrast pair is, and the pair is
authored in slots rather than in pixels.
