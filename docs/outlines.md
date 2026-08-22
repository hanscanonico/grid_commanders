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

## The two rows that cannot pay in light (2026-08-21)

Selective outlining trades a dark edge for a light one, and the trade is only
paid for where the light edge reads against the ground. The sheet review after
round 11 measured where it does not: the share of a unit's boundary sitting
within 25L of the tile under it, over both poses of all 18 units, was 0% under
the band and came back as

| row | shoal | plains |
| --- | --- | --- |
| neutral | 10.3% | 19.0% |
| meridian | 16.8% | 14.5% |
| aurora | 11.2% | 15.3% |
| iron | 12.7% | 19.1% |
| verdant | 13.0% | 14.9% |

Every row loses value contrast, because a lit line lands at S4 (L134-156) and
GRASS_DARK to SAND is L118-166 — the lift walks into the ground's own band
rather than out of it. What separates the rows is what they have left. The
chromatic three are the design-system tokens themselves, so a red hull tying
with the grass in value still breaks with it in colour; measured as an RGB
distance over the same boundary, meridian and verdant on shoal come to 0.15%
and everything on plains to 0.00%. Neutral is the sand's own khaki and Iron is
achromatic and capped at S3 (L129) by `IRON_SLOT_CEILING`, so those two rows
have nothing but value — and no room above to find it in, because Iron's cap
is the middle of the band.

### The grade, and why it is per faction

`Faction.outline` is `OUTLINE_LIGHT` or `OUTLINE_HEAVY` (palette.py), and the
heavy grade asks one more question of a sunward SILHOUETTE pixel before it
lights it: does the lifted colour clear the ground's band —
`palette.clears_the_ground`, i.e. below L93 or above L191, off `GROUND_BAND`
and `GROUND_BREAK`. Where it does, the line stays light, which is how the rim
flash both rows key off survives (`UnitBandCoverage`'s 3% above L200: the
neutral and iron subs, the tightest sprites on the sheet, hold 3.82% — round
11's own figure — where a blanket dark sunward edge took them to 2.71%). Where it cannot, the pixel takes the ground-facing contour it would
have taken one side over.

The per-pixel test is what makes the grade cheap; the per-faction grade is
what keeps it off the rows that do not need it. The alternative — asking every
row the same question — was measured first and is not selective outlining any
more: every row's lit line is inside the band, so all five would take the dark
edge everywhere and round 11 would be reverted by arithmetic.

The bill, over both poses of all 18 units:

| reading | light rows | heavy rows |
| --- | --- | --- |
| S0 share of a unit's own pixels | 13.99% | **17.22%** |
| S0 share on the worst sprite (b_copter, pose B) | 25.57% | **30.71%** |
| sunward silhouette drawn dark | 7.07% | **64.79%** |
| boundary within 25L of shoal | 11.2-16.8% | **0.46 / 0.61%** |
| boundary within 25L of plains | 14.5-15.3% | **0.56 / 0.56%** |
| worst sprite, either ground | 22.9-29.7% | **2.24%** (tank) |
| iron vs neutral row distance (gate: 60) | — | 64.4 |
| iron vs neutral as composed (gate: 30) | — | 43.8 |
| share above L160 (chromatic max 18.66%) | — | 18.24 / 18.20 |

The light rows are bit-identical to round 11: the grade changes nothing about
them, and the three readings that were 13.9% / 25.6% / 7.1% in the table at
the top of this file are the same numbers measured on three rows instead of
five. `GroundContrast` holds the heavy rows to 2% per row and 4% per sprite,
and the two budget gates above are stated per grade rather than loosened.

### What is still open

Two light rows share a HUE with a ground and not only a band, so the colour
half of the argument does not save them: verdant on plains (12.2% of its
boundary ties in both value and colour) and aurora over the water a shoal tile
is half made of (7.9%). `GroundContrast.SAME_HUE` names them rather than
folding them into a bound. Neither is a regression this round introduced —
both are the same round-11 trade — and neither is answered by a value rule,
since a green unit on grass has no value left to spend either. The candidates
are a ground-aware lift into the rim slot for those pairs, or the terrain
side: the woods tile already carries its own value band for exactly this
reason (`CANOPY_TOP`).

`b_copter`'s blades are not a faction defect either, but they are not
untouched. Measured over both frames of all five rows, 2 to 8 of the 35 blade
pixels that touch another drawn pixel sit within 25L of everything around
them, and the heavy grade RAISES that count on its two rows (neutral and Iron
go 3/6 to 7/8, the light rows do not move). That is the reading's blind spot
rather than a merge: where a blade tip and the body edge under it are now both
S0, the metric sees two pixels of the same value and calls them one surface,
which is exactly what an outline is. What the sheet review actually saw —
blades dissolving into the tile behind them — is the reading
`test_the_value_only_rows_cut_out_of_the_ground_they_stand_on` covers, and
b_copter's own boundary there goes 10.2% to 0.87% on shoal (Iron) and
6.4% to 0.29% (neutral).
`GroundContrast.test_the_b_copters_blades_stay_off_the_body_under_them`
therefore guards the 1px lattice at 25% — a floor under the rotor, not a
reading of the livery.
