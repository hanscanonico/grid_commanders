# Outlines: the 4px band, and the G-buffer that replaced it

Every unit outline on the sheet used to be `voxel._contour`: a band
`CONTOUR_WEIGHT * k` pixels thick — 4 on the lit edges, 2 on the ground-facing
ones — claimed inward off the plane behind each silhouette edge, plus four
patch passes holding the art together against it (`_settle_rims`,
`_free_lit_tip`, `_pair_lone_rims`, `_step_rim_inboard`).

It is now one pass over the depth and normal planes: `gbuffer.edge_mask` and
`gbuffer.convex_edges`, read per pixel, drawing lines one pixel wide.

**Read every "now" below as round 11's**, the state this page was written in.
Since S8 (2026-09-01) that classified line is grown back into an inward band
on a unit and on the massif, and the sunward grades collapse into one answer
there; the last section of this page is the current reading, and a property is
the one thing still drawn exactly as described here.

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
`../../../docs/density_128.md`). That follows the same finding — 128 buys no
logical resolution — from the other side: an outline the board resolves is not what
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

`Faction.outline` is `OUTLINE_LIGHT`, `OUTLINE_HEAVY` or — since 2026-08-24,
see below — `OUTLINE_RIM` (palette.py), and the
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

### The third grade: the two rows a ground is the same COLOUR as (2026-08-24)

Two light rows share a HUE with a ground and not only a band, so the colour
half of the argument did not save them: verdant on plains and aurora over the
water a shoal tile is half made of. They were carried as named debt
(`GroundContrast.SAME_HUE`) for three rounds, and re-measured on the sheet as
it stands they were 10.30% and 6.48% of their boundary tying in value AND
colour, worst sprite 22.8% and 14.2%.

`OUTLINE_RIM` is the heavy grade's question with the opposite answer. On the
same sunward SILHOUETTE pixel, where the ordinary lift lands inside the
ground's band AND inside a ground's hue (`palette.shares_a_ground_hue`, the
two chromatic grounds' hues within 30 degrees, greys under S0.20 excluded),
the line climbs to the first rung that clears the band instead of falling to
the contour — at most the rim, which is the band above
`terrain.TERRAIN_VALUE_CEILING` that units own by contract. A green army on
grass has nothing left to spend downward; the rim is the one place it has
room. Both ramps skip S4 on the way (verdant L140, aurora L136 — inside the
band), so in practice the lift lands on S5, L214 and L205.

Three details make it hold:

- the reach is the PAINTING voxel's, not the pass's: only a faction plane may
  climb into the rim band, and only on a model whose `top_slot` reaches it. A
  building stops at `BUILDING_TOP_SLOT`, so the rim grade never fires on a
  property and the five verdant and aurora buildings are byte-identical;
- a fitting keeps the ceiling it was drawn under, so aurora's cyan canopy —
  which does sit inside the water's hue — is unmoved: an accent is capped at
  its own slot plus one, and nothing there clears;
- the lifted pixel joins the despeckle's `keep` mask. Without that, half of it
  folded straight back into the plane behind it (round 9's dotted outline,
  from the light side) and the reading only came down to 2.07% instead of
  0.39%.

The bill, re-recorded over both poses of all 18 units:

| reading | light (meridian) | light (gold) | rim (aurora / verdant) | heavy (neutral / iron) |
| --- | --- | --- | --- | --- |
| S0 share of a unit's own pixels | 14.22% | 14.19% | 14.28% | 17.35% |
| S0 share on the worst sprite (b_copter, pose B) | 24.22% | 23.65% | 24.67% | 30.76% |
| sunward silhouette drawn dark | 7.19% | 6.63% | 6.72% | 63.23% |
| boundary within 25L of shoal | 15.27% | 13.01% | 2.97 / 2.83% | 0.44 / 0.55% |
| boundary within 25L of plains | 14.66% | 14.32% | 3.69 / 3.38% | 0.75 / 0.75% |
| boundary tying in value AND colour, shoal | 0.29% | 0.23% | **0.55 / 0.29%** | 0.15 / 0.07% |
| boundary tying in value AND colour, plains | 0.00% | 0.00% | **0.00 / 0.39%** | 0.00 / 0.00% |
| share above L160 (chromatic max 21.43%) | 19.00% | 18.66% | 20.67 / 21.43% | 18.61 / 18.58% |

Gold is the fifth row, added 2026-08-28, and its column is measured on the
same readings: it is a light row for the same reason meridian is — a token
hue no ground shares — and it lands inside meridian's bill on every line.
The other columns are round 11's record and were not re-run for it, so the
comparison holds to a few tenths of a point rather than exactly: re-measured
today, meridian's L160 share reads 18.46% against gold's 18.45%.

Nothing else moved: the light and heavy rows are byte-identical, the terrain
and every property are byte-identical, and the two open pairs are now inside
the 2% bound `GroundContrast` holds every non-heavy row to, so `SAME_HUE` is
gone rather than shrunk. The order gate
(`UnitBandCoverage.test_no_row_out_lights_the_chromatic_band`) is what this
was tested against and it holds by construction rather than by a tolerance:
the two rows that rise ARE chromatic rows, so the band's owners are still its
loudest, with neutral and iron 2-3 points under them and unmoved.

The alternative kept on the shelf is the terrain side: the woods tile already
carries its own value band for exactly this reason (`CANOPY_TOP`).

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

## S8: the board answer, on top of this file's own mechanism (2026-09-01)

Everything above describes what shipped after round 11's rewrite — a 1px
line, selectively lit — and the game's own legibility sweep read it at
94.8% of clear board cells failing (`docs/sprite_legibility.md`'s
2026-08-25 section): a 1px line is three-quarters unsampled at the board's
4:1 nearest downsample, whichever phase the sample lands on. S8 answers
that without reverting this file's rewrite: `voxel._thicken_contour` grows
the already-classified 1px line into a band `CONTOUR_DEPTH` pixels deep (4
lit, 2 ground-facing, round 10's own shape) entirely INWARD, so nothing
here about the alpha, the self-overlap precedence or the interior contour
moves — a unit's own material structure is unchanged, only more of its
plane behind each edge now carries the edge's own colour. Scoped to units
and the massif (`is_unit`, `top_slot == S_RIM`): a property stops at
`BUILDING_TOP_SLOT` and never thickens, since the board never scores a
roof as a figure and thickening one cost 15 of 20 building-owner pairwise
readings for nothing.

The other half is a value question this file's own numbers already
answered without knowing it: `clears_the_ground` on the sunward
silhouette's ordinary lift is false for every row's S3, S4 and even the
climbed rim rung most of the time — the 71% "sunward silhouette drawn
dark" reading above quoted for the light and rim grades was a FULL-
RESOLUTION reading, and the board's own reading of the same lift is worse
than the two rows the heavy grade already answers for. So on a unit
(never off it) every grade now takes the heavy grade's fallback — the
ground-facing contour where the lift cannot clear — and `OUTLINE_RIM`'s
climb is retired on the board specifically: aurora and verdant read 82-86%
failing through it and 48-52% through the plain fallback, the same range
every other row now sits in. `OUTLINE_LIGHT` and `OUTLINE_RIM` keep every
number this file records for a PROPERTY unchanged; only a unit's own
sunward silhouette moved.

**So the three grades draw one and the same unit now** — `OUTLINE_LIGHT`,
`OUTLINE_HEAVY` and `OUTLINE_RIM` differ only on a property, and all three
are kept rather than collapsed because that is where they still tell rows
apart. A grade is a property's answer; do not read one as a unit's.

Which moves the table at the top of this page. Re-measured 2026-09-01 over
both poses of all 18 units, the same reading, now identical per grade
(`test_livery.MAX_SUNWARD_DARK` / `MAX_CONTOUR` carry the pins):

| reading | band | 1px + sel-out | + S8 band |
| --- | --- | --- | --- |
| S0 share of a unit's own pixels | 34.5% | 13.9% | **32.7-33.0%** |
| S0 share on the worst sprite (b_copter, pose B) | 53.1% | 25.6% | **50.43%** |
| sunward-only boundary pixels drawn dark | 100% | 7.1% | **67.7-68.0%** |
| iron vs neutral row distance (gate: 60) | 63.7 | 64.6 | **63.9** |
| iron vs neutral as composed (gate: 30) | 36.1 | 45.2 | **37.8** |

The interior is bought back thinner than it was, and the composed rows are
diluted with it again: the closest composed pair is neutral vs gold at
**33.0** (34.6 under the band, 45.2 under round 11), still over its bar of
30, while the faction-pixel reading `RowSeparation` actually gates on barely
moves — an army's own pixels are not what the band spends. That is the price
of a line the board can sample, paid where round 10 paid it and stated here
rather than left to be rediscovered. What is not paid at all is the alpha:
the band is inward only, so every geometry reading this file's tests take is
untouched.

The full re-read, with the mountain-and-masonry residual this did not
answer, is `docs/sprite_legibility.md`'s own 2026-09-01 section.
