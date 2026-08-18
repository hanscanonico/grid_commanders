# Composite legibility — 2026-08-18 (every ground, phased sea)

What the sweep finds on the sheets shipped by generator `1216fd5` — Iron levelled by
ordering, the re-massed submarine with its wake, the properties keyed under the unit band,
the de-badged pond ring, the phase-offset sea and the lit woods canopy — measured over a
matrix that now carries **every ground the board can stand a unit on**, the five property
terrains included. A dated measurement: it supersedes the previous page (taken at
`e26154e`) wholesale rather than editing it, the way `docs/bulwark_balance.md` and
`docs/replay_survey.md` are superseded.

**Nothing was tuned in response to it.** Every failing cell below is a finding for the art
to answer; the instrument exists so that answer can be measured rather than argued.

Re-run with `make legibility-check`. It reads the shipped atlases and the shipped
constants, plays no match, takes about 30 seconds, and writes `cells.csv` and `summary.md`
under `reports/` (gitignored).

## What is measured

Every cell of 18 units × 5 faction rows × {ready, acted} × **ten grounds** × {no wash,
move, fire, threat, fog} at board resolution, plus the same figures at the cut-in's
resolution — **9,900 composites**, against 4,950 last time. Each is stacked in
battle.tscn's own node order: terrain, the wash over it, the unit over that, the fog
shroud over everything.

**Separation** is the median luminance of the figure's pixels minus the median luminance
of the ground plate under it, in **ramp steps**. One ramp step is the gap between two
neighbouring slots of a faction ramp, measured off the shipped units atlas rather than
restated: **0.1543 luminance**, exactly what the previous page measured — the ruler did
not move this time, so the numbers below are directly comparable to it wherever the
grounds are the same five.

Four things to know before reading a number:

- The metric is **value only**. That is deliberate — the atlases' own contract is a value
  ceiling holding terrain under the units' band — but it means a figure rescued by hue or
  by silhouette alone reads as a failure here. This page's headline is exactly that case,
  so the crops say so.
- The ground is the **whole tile**, not the pixels the silhouette leaves showing. On the
  mountain tile that is mostly the grass plate around the peak; on a property tile it is
  mostly the ground the board paints under the building, which is why the five properties
  read close to plains rather than to their masonry.
- The figures are the **ambient frame A** atlas. The board also beats to frame B, which
  is not in this sweep — a run that adds it supersedes this page rather than extending it.
- The board reading samples one texel per screen pixel (nearest filtering, as the project
  is configured), so a unit's board median is not its cut-in median: the downsample keeps
  a fixed sixteenth of the art.

## The headline

**6,278 of 9,900 cells (63.4%) are under two ramp steps.** On the five grounds the
previous page measured, and on the same ruler, the figure is **69.7% against 68.3%** —
and **one unit accounts for essentially all of that move.**

**The submarine paid for its re-mass in value.** It was the roster's best-separated unit
at 22.9% failing and is now at **48.4%** on those same five grounds: +25.5 points,
while every other unit moved by at most 0.4. The generator gave the hull freeboard, a
conning tower and a running wake, because a sliver with no freeboard had nothing to
separate it from open sea — and that lifted its board figure median from **0.079 to
0.188**, which is straight into the water's own band (0.404). It reads *better* as a boat
and *worse* on this ruler, and both of those are true at once. Nothing was changed in
response.

The other three sheet changes are visible on the board and nearly silent here: the Iron
ordering fix moved rockets, battleship and b_copter by −0.4 points each and no other unit
at all; the lit woods canopy raised the woods plate from 0.317 to 0.338 and its failure
rate from 97.0% to 97.3%, because the figures sit on both sides of it; and phasing the sea
moved the open-water plate from 0.400 to 0.404, since the three phases are the same water.

| ground | median steps (board, every wash) | ground luminance (bare) | failing |
| --- | --- | --- | --- |
| shoal | 2.10 | 0.650 | 46.5% |
| plains | 1.95 | 0.618 | 52.5% |
| city | 1.91 | 0.612 | 56.8% |
| base | 1.91 | 0.612 | 56.8% |
| airport | 1.91 | 0.612 | 56.8% |
| port | 1.91 | 0.612 | 57.5% |
| mountain | 1.90 | 0.612 | 54.8% |
| hq | 1.88 | 0.608 | 57.9% |
| sea | 0.91 | 0.404 | 97.4% |
| woods | 0.61 | 0.338 | 97.3% |

| wash | median steps | failing |
| --- | --- | --- |
| none | 2.06 | 45.8% |
| move | 1.98 | 52.8% |
| attack | 1.84 | 56.9% |
| threat | 1.84 | 57.1% |
| fog | 1.36 | 93.6% |

| faction row | median steps (bare board) | failing |
| --- | --- | --- |
| iron | 2.43 | 46.6% |
| aurora | 2.13 | 59.4% |
| meridian | 2.05 | 61.0% |
| verdant | 1.85 | 70.7% |
| neutral | 1.51 | 79.4% |

## Findings

1. **The submarine is the whole of this run's movement**, and the headline says why. On
   sea alone it went from 27.3% of its cells failing to 94.5%. It is still one of the
   three best-separated units overall (35.3%), because it keeps its edge on every bright
   ground; what it lost is the one ground it fights on.
2. **A property is grass with a building on it, as far as a figure standing there is
   concerned.** The five new grounds sit at 0.608–0.612 against plains' 0.618 and fail at
   56.8–57.9% against plains' 52.5% — a two-to-five point tax, not a new hazard. The
   building covers a minority of the tile, so the ground the metric reads is mostly the
   `TerrainDB.ground()` plate the board paints under it. **The properties are not where
   the roster disappears**; that is still woods and sea, and adding half a matrix of
   properties is what pulled the overall rate *down* from 69.7% to 63.4%.
3. **HQ is the hardest property and port the second hardest**, both by under a point.
   The HQ's plinth is the largest of the five and its plate the darkest (0.608), which is
   the whole of the difference. No property is a per-unit split the way mountain is.
4. **Woods and sea remain where the roster disappears**: 97.3% and 97.4%. The lit canopy
   moved the woods plate up 0.021 and its failure rate not at all — the figures that were
   under it are still under it, and the ones above it came down by the same amount.
5. **Fog costs about 0.7 steps and takes the failure rate to 93.6%.** It sits *above* the
   units, so it compresses figure and ground together — a cell that was marginal in the
   clear is a cell nobody can read in fog.
6. **The three board washes cost 0.08–0.22 steps each and never rescue a cell**: they land
   under the figure, so they can only move the ground, and they move it towards the middle.
7. **The neutral row is still the weakest livery** (median 1.51, 79.4% failing) and iron
   is still the best (2.43, 46.6%) — the ordering fix did not change that ranking, which
   is what it was for: it levelled Iron's share of the bright band without moving its
   value.
8. **Three unit/faction pairs fail every single board cell** — neutral APC (median 0.59),
   neutral bomber (0.59) and verdant bomber (1.05) — the same three as the last two runs,
   so no sheet has moved them yet.
9. **The cut-in is worse than the board** (85.3% against 61.2%), which is the sampling
   note above rather than a second defect: the blown-up figure shows all its texels,
   including the dark ones the board's downsample skips.

## Spot check

Two composites were read by eye, both dumped by the harness itself
(`make legibility-check LEGIBILITY="--dump=board:sub:neutral:ready:sea:none"`).

Known-bad by the ruler, **1.10 steps** — a neutral submarine on open water. It is legible
at a glance, and that is carried by hue and by the wake's silhouette, neither of which
this metric can see. This is the finding, photographed:

![neutral submarine on sea](images/legibility_fail_sub_neutral_sea.png)

Barely passing, **2.02 steps** — a meridian infantry on a city. The figure stands on the
ground plate beside the building rather than on the masonry, which is what the numbers in
finding 2 say:

![meridian infantry on city](images/legibility_pass_infantry_meridian_city.png)

## What the grounds are

Each terrain is measured as the art the board draws for it when its four neighbours are
the same terrain — asked of `TerrainAutotiles`, never picked by hand. That is the base
atlas cell for plains, mountain, the five properties and a wood inside a wood (its
full-bleed canopy), the shoal sheet's mask-0 cell for a beach, and **a phase of the sea
sheet for open water** — the phase the board itself draws at the probe's own cell, since
the phase is a hash of the coordinate and the harness asks the same authority the board
asks.

A property's column is a transparent overlay, so its cell is composed over
`TerrainDB.ground()` exactly as `BattleView`'s two layers compose it. A wood's *fringe*, a
coastline, a road, a river and a bridge draw from their own sheets and are still not in
this sweep: they are edges rather than fields, and a unit standing on one is standing on a
tile the sweep's field-of-its-own-kind probe cannot state. Widening to them supersedes
this page.
