# Composite legibility — 2026-08-19 (generator `8ba480c`)

What the sweep finds on the sheets shipped by generator `8ba480c` — the round-7 art: the sub's
hull taken dark, the property masonry keyed down a rung, the woods canopy's top lit. Measured
twice per cell, in **value** and in **hue**, on the same ruler as the previous page. A dated
measurement: it supersedes that page wholesale rather than editing it, the way
`docs/bulwark_balance.md` and `docs/replay_survey.md` are superseded.

**Nothing was tuned in response to it.** No colour anywhere moved for this run — every number
below is the generator's art read back. Every failing cell is a finding for the art to answer.

Re-run with `make legibility-check`. It reads the shipped atlases and the shipped constants, plays
no match, takes about 30 seconds, writes `cells.csv` and `summary.md` under `reports/`
(gitignored) — and redraws the one artifact it publishes, the worst-twenty gallery below.

## What is measured

Every cell of 18 units × 5 faction rows × {ready, acted} × ten grounds × {no wash, move, fire,
threat, fog} at board resolution, plus the same figures at the cut-in's resolution — **9,900
composites**, stacked in battle.tscn's own node order: terrain, the wash over it, the unit over
that, the fog shroud over everything.

**Separation** is the median luminance of the figure's pixels minus the median luminance of the
ground plate under it, in **ramp steps** — one step being **0.1543 luminance**, measured off the
shipped units atlas and unmoved from the previous three runs. **Hue** is the CIE76 distance
between exactly those two median colours in Lab's chroma plane, lightness dropped on purpose (it
would restate the value bar), and it **clears at 20** — a stated bound, about eight just-noticeable
differences, not a measured one. The verdict is the value bar's; the hue column is counted beside
it and never passed. The ground is the **whole tile**, not the pixels the silhouette leaves
showing — which this round turns out to matter, see finding 3.

## The headline

**6,222 of 9,900 cells (62.8%) are under two ramp steps, and 5,221 of those (83.9%) are 20 or
more apart in hue.** The previous page read 6,278 (63.4%) and 5,214 (83.1%).

The interesting number is the bottom of the distribution rather than the total. **1,001 failures
clear neither reading** (was 1,064), and **264 are severe on both** — under one ramp step *and*
under 20 hue — against **334** before. The whole of that 70-cell improvement is woods: the
doubly-blind woods count falls **151 → 81**, sea holds at 52, and the property grounds are
unmoved.

| ground | median steps | median hue | failing | of those, hue-carried | ground luminance |
| --- | --- | --- | --- | --- | --- |
| shoal | 2.10 | 29.1 | 44.0% | 64.1% | 0.650 |
| plains | 1.95 | 47.7 | 50.7% | 90.1% | 0.618 |
| city | 1.91 | 47.4 | 53.2% | 90.0% | 0.612 |
| base | 1.91 | 47.4 | 53.2% | 90.0% | 0.612 |
| port | 1.91 | 47.4 | 53.2% | 90.0% | 0.612 |
| airport | 1.90 | 46.2 | 53.2% | 85.8% | 0.612 |
| mountain | 1.90 | 45.8 | 53.2% | 85.8% | 0.612 |
| hq | 1.88 | 45.8 | 54.4% | 83.7% | 0.608 |
| woods | 1.15 | 40.9 | 93.7% | 85.1% | 0.455 |
| sea | 0.91 | 46.2 | 97.1% | 87.3% | 0.404 |

(board rows only, every wash; the luminance column is the bare-board ground. Woods was 0.61 steps
/ 32.1 hue / 99.9% failing at ground luminance 0.338; every other row is within 0.01 of the
previous page, and sea is identical to it.)

| wash | median steps | median hue | failing | of those, hue-carried |
| --- | --- | --- | --- | --- |
| none | 2.11 | 65.5 | 45.0% | 90.1% |
| move | 1.98 | 34.3 | 52.1% | 90.0% |
| attack | 1.85 | 44.9 | 56.1% | 86.1% |
| threat | 1.85 | 43.1 | 56.3% | 81.2% |
| fog | 1.39 | 47.2 | 93.6% | 83.4% |

| faction row | median steps | median hue | failing | of those, hue-carried |
| --- | --- | --- | --- | --- |
| iron | 2.43 | 65.5 | 32.2% | 100.0% |
| aurora | 2.13 | 101.4 | 34.4% | 78.2% |
| meridian | 2.06 | 78.8 | 35.0% | 100.0% |
| verdant | 1.85 | 27.5 | 52.5% | 80.4% |
| neutral | 1.53 | 51.1 | 70.8% | 93.7% |

(bare board, no wash)

## Findings

1. **The lit canopy is the round's whole movement, and it is large.** Woods goes from 99.9% of its
   board cells failing to 93.7%, its median from 0.61 to 1.15 steps, and its median hue from 32.1
   to 40.9 — the one ground where both readings were bad, improving on both. The canopy plate is
   the cause and can be read straight off the sheet: the full-bleed wood's median luminance is
   **0.346 before, 0.455 after**. Every livery moves with it (iron 0.94 → 1.47 steps, neutral
   0.38 → 0.79), and the doubly-blind cells standing in woods halve.
2. **It helps dark figures and costs light ones, because a plate can only move one way.** A
   verdant infantry on woods goes from 0.03 to 0.80 steps; a verdant *bomber*, painted lighter
   than the new plate, goes from 0.59 to 0.18 and from 17.8 to 6.3 hue. The net is strongly
   positive because most of the roster sits below the canopy, but the sweep now has a small class
   of figures the canopy has risen past.
3. **The property key-down is real on the sheet and invisible to this ruler.** The masonry is
   measurably darker — the property columns' own opaque pixels read **city 0.385 → 0.304, base
   0.364 → 0.238, hq 0.368 → 0.296, airport 0.376 → 0.300, port 0.394 → 0.304** — and the harness
   reports the five property grounds at **53.5% failing before and after**, medians within 0.01.
   The reason is the whole-tile median: a property cell is a transparent overlay over the ground
   plate, the masonry is about a third of the tile, so the median pixel of the composite is plate
   both times and the ruler never sees the change. What the review moved was the mass a unit
   stands *beside*; what this sweep measures is what it stands *on*. Reading the key-down needs a
   silhouette-aware ground, which would supersede this page.
4. **The dark hull is invisible to the ruler for the same shape of reason.** The sub's sprite
   really did darken — mean luminance 0.373 → 0.346 and the upper quartile 0.612 → 0.538 — but its
   *median* pixel did not move (0.400), so every sub-on-sea cell reads exactly as before: 94.0%
   failing, 1.39 steps, figure luminance 0.188. The sub's overall failure rate moves 35.3% → 33.8%
   and **all of that is its woods cells**, not its water. The submarine class the previous page
   flagged at 48.4% on the five old grounds now reads **45.5%**, again entirely off the canopy.
   A median is the right statistic for "is the figure readable as a mass" and the wrong one for
   "did the top of the hull come down".
5. **Sea is untouched and is now the worst ground on both readings** (0.91 steps, 97.1% failing),
   holding all 52 of its doubly-blind cells. Nothing in this round aimed at it.
6. **Neutral is still the weakest livery** (1.53 steps bare board, 70.8% failing) and still
   carries 93.7% of those failures on hue; iron and meridian still carry 100% of theirs. The
   liveries moved by at most 2.2 pp, all of it the canopy.
7. **The cut-in is unchanged at 85.3% failing with 71.7% hue-carried**, because none of its ten
   grounds is a wood.

## The gallery

`make legibility-check` redraws this sheet: the twenty worst-scoring composites, each magnified to
one tile and labelled with its unit, faction, ground, wash, state, view and both scores.

![the twenty worst-scoring composites](images/legibility_worst20.png)

Read it with finding 4 in hand. **30 cells score exactly 0.00 steps** — the same 30 as before — so
"the worst twenty" is a choice among ties, made total by the row's own six-field key, which is why
the PNG comes out the same twice. Cells 01–06 are meridian and verdant carriers and bombers over
open water at board resolution, and 07–20 are neutral figures at cut-in resolution over water and
over a port: on the ruler they are the worst cells in the game, and on screen they are tan and red
figures on blue water.

## Spot checks

Four composites read by eye, each dumped by the harness itself
(`make legibility-check LEGIBILITY="--dump=board:sub:neutral:ready:sea:none"`), which prints the
two median colours and their hue distance beside the crop.

The dark hull, unmoved by the ruler: a neutral submarine on open water, **1.10 steps** and
**65.2** apart in hue (figure `#4a3a22`, ground `#2b70bf`). Legible at a glance, and the same two
numbers the previous page printed:

![neutral submarine on sea](images/legibility_fail_sub_neutral_sea.png)

The canopy's win: a verdant infantry in woods, **0.80 steps** and **7.9** hue (figure `#22682c`,
ground `#45883a`) — was 0.03 steps. Still doubly blind by both bounds, and no longer the same
green pressed flat against itself:

![verdant infantry in woods](images/legibility_fail_infantry_verdant_woods.png)

The canopy's cost, finding 2: a verdant bomber over the same wood, **0.18 steps** and **6.3** hue
(figure `#2c8636`) — was 0.59 steps. The plate rose past this figure:

![verdant bomber over woods](images/legibility_fail_bomber_verdant_woods.png)

Barely passing, **2.02 steps** — a meridian infantry on a city, unchanged, because the figure
stands on the ground plate beside the darker building rather than on it (finding 3):

![meridian infantry on city](images/legibility_pass_infantry_meridian_city.png)

## What the grounds are

Each terrain is measured as the art the board draws for it when its four neighbours are the same
terrain — asked of `TerrainAutotiles`, never picked by hand. That is the base atlas cell for
plains, mountain and the five properties, a wood inside a wood (its full-bleed canopy), the shoal
sheet's mask-0 cell for a beach, and a phase of the sea sheet for open water — the phase the board
itself draws at the probe's own cell.

A property's column is a transparent overlay, so its cell is composed over `TerrainDB.ground()`
exactly as `BattleView`'s two layers compose it. A wood's *fringe*, a coastline, a road, a river
and a bridge draw from their own sheets and are still not in this sweep: they are edges rather than
fields, and a unit standing on one is standing on a tile the sweep's field-of-its-own-kind probe
cannot state. Widening to them supersedes this page.
