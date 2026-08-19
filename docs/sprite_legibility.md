# Composite legibility — 2026-08-19 (generator `8ba480c`, edge-band ruler)

What the sweep finds on the sheets shipped by generator `8ba480c`, **read with a new ruler**. The
art has not moved since the previous page; the measurement has. A dated measurement: it supersedes
that page wholesale rather than editing it, the way `docs/bulwark_balance.md` and
`docs/replay_survey.md` are superseded — and because the ruler changed, no number here is
comparable to a number there except where this page says so.

**Nothing was tuned in response to it.** No colour anywhere moved for this run — every number below
is the generator's art read back. Every failing cell is a finding for the art to answer.

Re-run with `make legibility-check`. It reads the shipped atlases and the shipped constants, plays
no match, takes about a minute, writes `cells.csv` and `summary.md` under `reports/` (gitignored) —
and redraws the one artifact it publishes, the worst-twenty gallery below. Two runs of one tree
write the same bytes, gallery included.

## Why the ruler changed

The previous page's worst twenty were **twenty ties**: all 0.00 ramp steps, hues spread over 68.8
to 98.8, ordered only by their keys. That is a ruler that has run out of things to say. It was
measuring the **median pixel of the whole figure** against the **median pixel of the whole tile** —
a fine answer to "is this figure, as a mass, a different value from this ground", and not the
question. Figure-ground separation is a **boundary** phenomenon: what tells a shape from what it
stands on is its contour.

So the headline is now the **edge band**. For every pixel of the silhouette's perimeter, the harness
takes the ground within **3 px outside** that silhouette, and reports the **p25** along the whole
perimeter — of the luminance gap, in ramp steps, and of the CIE76 chroma-plane distance. p25 rather
than a median, because a figure can carry a bright back and a side that vanishes: a quarter of an
outline may go soft, more than a quarter is a shape with a missing edge.

The bars did not move and did not need to. **Two ramp steps** is the shading gap the art itself uses
to tell one face of a hull from the next, which is the same sentence at the boundary as in the
middle; **hue clears at 20**, a property of the eye rather than of the sample. The whole-figure
medians stay in `cells.csv` as `steps` and `hue`, a cheap secondary that decides nothing — and a
cell where the two disagree is exactly the cell worth opening.

## What is measured

Every cell of 18 units × 5 faction rows × {ready, acted} × ten grounds × {no wash, move, fire,
threat, fog} at board resolution, plus the same figures at the cut-in's resolution — **9,900
composites**, stacked in battle.tscn's own node order: terrain, the wash over it, the unit over
that, the fog shroud over everything. One ramp step is **0.1543 luminance**, measured off the
shipped units atlas.

## The headline

**6,634 of 9,900 cells (67.0%) keep less than two ramp steps along their contour, and 4,906 of
those (73.9%) are 20 or more apart in hue there.** **1,728 failures clear neither reading** — the
doubly-blind class — and **613 are severe on both**, under one ramp step *and* under 20 hue.

The totals are close to the previous page's (62.8% failing) and mean something different, so the
comparison worth making is per view:

| view | cells | median edge steps | median edge hue | failing | of those, hue-carried | doubly blind |
| --- | --- | --- | --- | --- | --- | --- |
| board | 9,000 | 1.54 | 30.5 | 73.3% | 73.8% | 1,728 |
| cutin | 900 | 3.02 | 27.5 | **4.0%** | 100.0% | 0 |

The cut-in was **85.3% failing** on the old ruler and is 4.0% on this one. That reversal is finding
1 and it is the whole argument for the change.

| ground | median edge steps | median edge hue | failing | of those, hue-carried | doubly blind | (median ruler) |
| --- | --- | --- | --- | --- | --- | --- |
| plains | 1.81 | 43.4 | 60.2% | 94.3% | 31 | 1.95 / 47.7 |
| shoal | 1.77 | 18.5 | 63.3% | 37.5% | **356** | 2.10 / 29.1 |
| port | 1.67 | 36.2 | 65.7% | 85.6% | 85 | 1.91 / 47.4 |
| mountain | 1.67 | 27.2 | 66.3% | 63.8% | 216 | 1.90 / 45.8 |
| airport | 1.65 | 37.4 | 66.7% | 88.0% | 72 | 1.90 / 46.2 |
| city | 1.44 | 28.3 | 76.0% | 60.4% | 271 | 1.91 / 47.4 |
| base | 1.42 | 28.1 | 88.3% | 68.4% | 251 | 1.91 / 47.4 |
| woods | 1.39 | 30.2 | 85.8% | 89.8% | 79 | 1.15 / 40.9 |
| hq | 1.34 | 27.5 | 84.4% | 61.3% | **294** | 1.88 / 45.8 |
| sea | 1.26 | 30.9 | 76.3% | 89.4% | 73 | 0.91 / 46.2 |

(board rows, every wash. The last column is the previous page's median reading for the same ground.)

| wash | median edge steps | median edge hue | failing | of those, hue-carried | doubly blind |
| --- | --- | --- | --- | --- | --- |
| move | 1.72 | 27.4 | 65.8% | 69.3% | 364 |
| attack | 1.69 | 30.5 | 67.8% | 82.7% | 211 |
| threat | 1.67 | 32.2 | 68.2% | 86.1% | 170 |
| none | 1.62 | 44.5 | 69.6% | 70.9% | 364 |
| fog | 1.07 | 31.2 | 95.2% | 63.9% | **619** |

| faction row | median edge steps | median edge hue | failing | of those, hue-carried | doubly blind |
| --- | --- | --- | --- | --- | --- |
| iron | 1.81 | 51.7 | 64.2% | 76.2% | 55 |
| aurora | 1.65 | 54.1 | 66.4% | 74.9% | 60 |
| verdant | 1.61 | 26.3 | 76.1% | 58.0% | 115 |
| meridian | 1.59 | 53.5 | 66.7% | 77.9% | 53 |
| neutral | 1.55 | 45.2 | 74.7% | 69.9% | 81 |

(bare board, no wash)

| unit | median edge steps | median edge hue | failing | doubly blind |
| --- | --- | --- | --- | --- |
| tank | 2.69 | 36.8 | 20.2% | 12 |
| recon | 2.62 | 36.8 | 24.0% | 10 |
| missiles | 2.22 | 35.8 | 35.8% | 19 |
| sub | 2.05 | 26.2 | 45.2% | 90 |
| battleship | 2.00 | 28.1 | 49.4% | 67 |
| rockets | 1.89 | 33.8 | 53.6% | 49 |
| lander | 1.79 | 32.4 | 74.2% | 75 |
| t_copter | 1.69 | 27.8 | 73.2% | 130 |
| anti_air | 1.58 | 39.1 | 77.8% | 23 |
| artillery | 1.50 | 36.3 | 88.4% | 36 |
| mech | 1.48 | 25.6 | 93.0% | 172 |
| b_copter | 1.47 | 27.5 | 89.8% | 123 |
| fighter | 1.32 | 23.5 | 96.0% | **209** |
| md_tank | 1.10 | 32.1 | 99.4% | 99 |
| cruiser | 1.09 | 31.6 | 100.0% | 81 |
| infantry | 1.08 | 20.8 | 100.0% | **234** |
| apc | **0.72** | 34.0 | 99.6% | 89 |
| bomber | 0.68 | 23.2 | 100.0% | **210** |

(board rows, every wash)

## Findings

1. **The cut-in is not the problem the old ruler said it was.** It goes from 85.3% failing to
   **4.0%**, and it holds **no doubly-blind cell at all**. The old page's entire worst twenty was
   cut-in and board figures over open water scoring 0.00 — see the spot check below, where a
   neutral infantry that read **0.00 median steps** reads **2.04 along its contour**. At the
   cut-in's 64 px the figure carries an outline the board's 16 px cannot afford, and it is drawn
   against paving rather than against a tile that is half building. Both rulers were right about
   their own question; only one of them was answering ours.
2. **The APC owns the whole worst twenty, and that is a finding rather than a tie.** Its median
   contour is **0.72 steps** — half the next worst hull — because the sprite's upper silhouette is a
   mid-value tan that sits within a hair of every plate on the board: 0.05 steps on plains, 0.03
   under fog. It is legible by colour alone (34.0 median hue) on every ground except the beach.
   Twenty cells of one unit is what a ruler that can separate cells looks like; the previous page's
   twenty were a choice among thirty cells that all scored exactly 0.00.
3. **The bomber is the roster's real dark corner.** 100% of its board cells fail, its median
   contour is **0.68 steps**, and **210 of them are blind on hue too** — the highest count in the
   game after the infantry's 234. Grey aircraft over grey masonry with a grey fog over the pair.
4. **Fog is the strongest single term, and it is stronger here than the old ruler could see.**
   95.2% failing and **619 doubly-blind cells**, more than a third of the game's total: the shroud
   sits *above* the units, so it pulls the contour and the band it is read against toward the same
   grey at once. Every one of the ten worst doubly-blind cells in the game is a fogged one.
5. **Sea is no longer the worst ground; the properties are.** Water reads 1.26 median steps with
   only 73 doubly-blind cells — a figure over water is dark-on-blue and the contour holds. Base
   (88.3% failing), HQ (84.4%, 294 doubly blind) and city (76.0%, 271) are the grounds where a
   silhouette actually disappears, because a property tile is a building the figure is *beside*, and
   a boundary reading finally sees what the whole-tile median could not (the old page's finding 3
   named exactly this blind spot and said reading it would supersede the page — it has).
6. **The beach is the one ground that fails on colour rather than on value.** Shoal's median edge
   hue is **18.5**, under the bound, and only 37.5% of its failures are hue-carried against 85–94%
   on most grounds: sand and the roster's tans are the same paint. It carries the **highest
   doubly-blind count of any ground** (356) while its contour reading is the second best of the
   ten — the one place in the sweep where the hue column is the one doing the work.
7. **Verdant is the weakest livery under this ruler, not neutral.** 76.1% of its bare-board cells
   fail with a median edge hue of **26.3**, the lowest of the five: green figures keep neither
   value nor colour against the board's greens. Neutral, which the old page called the weakest,
   comes second and carries most of its failures on hue.

## The gallery

`make legibility-check` redraws this sheet: the twenty cells with the least margin left, each
magnified to one tile and labelled with its unit, faction, ground, wash, state, view, both edge
numbers and both median ones. The order is `min(edge steps / 2, edge hue / 20)` — the share of the
nearer bar a cell still has — which is what replaced the old value-only sort and its ties.

![the twenty worst-scoring composites](images/legibility_worst20.png)

Read it with finding 2 in hand: every cell is an APC, and the pictures say why — a tan lump whose
top edge dissolves into the plate while its black underside stays sharp. All twenty are ranked by
their **value** margin, hue being the looser of the two bounds on almost every cell in the game;
the one doubly-blind tile on the sheet is 20, a neutral APC on a beach at **4.3** hue, which is
finding 6 in one picture.

The cells blind on **both** readings are a different list, and the ten worst of them are all fog:

| unit | faction | ground | wash | state | edge steps | edge hue |
| --- | --- | --- | --- | --- | --- | --- |
| bomber | verdant | city | fog | ready | 0.30 | 2.19 |
| bomber | verdant | hq | fog | ready | 0.30 | 2.17 |
| bomber | neutral | base | fog | ready | 0.32 | 1.49 |
| bomber | neutral | base | fog | acted | 0.32 | 3.12 |
| fighter | neutral | hq | fog | ready | 0.32 | 2.35 |
| bomber | neutral | city | fog | ready | 0.33 | 2.19 |
| bomber | neutral | hq | fog | ready | 0.33 | 2.17 |
| fighter | verdant | hq | fog | ready | 0.33 | 2.35 |
| bomber | verdant | base | fog | acted | 0.34 | 3.12 |
| bomber | meridian | hq | fog | ready | 0.35 | 2.17 |

## The history re-run

The three generations of `units_atlas.png` this project has adopted, scored through today's ruler:
round 5 (`81039c9`, #312, the indexed-palette and value-ceiling sheets), round 6 (`1216fd5`, #316)
and round 7 (`8ba480c`, #318, shipping). Each is `git show`n into a file and read with
`make legibility-check LEGIBILITY="--units=<file>"`.

**The grounds are held at today's art on purpose.** Only the units sheet is swapped, so a
generation's numbers move because its *figures* moved; an older tree's terrain sheets are not always
a set today's code can read at all (round 5 predates the phased sea sheet). Each generation is
scored on **its own** ramp step, measured off its own sheet — 0.1462 for round 5, 0.1543 for the
other two — because the question is whether that art was legible on its own terms. The control: the
round-7 file put through `--units=` reproduces the shipped run's `cells.csv` byte for byte.

| generation | failing | doubly blind | sub on sea (board) | verdant on woods (board) |
| --- | --- | --- | --- | --- |
| round 5 (#312) | 6,474 (65.4%) | 1,551 | 2.27 steps, 30.9 hue, 11/50 fail | 1.20 steps, 25.7 hue, 162/180 fail |
| round 6 (#316) | 6,634 (67.0%) | 1,728 | 2.14 steps, 30.3 hue, 13/50 fail | 1.38 steps, 25.2 hue, 169/180 fail |
| round 7 (#318) | 6,634 (67.0%) | 1,728 | 2.15 steps, 30.3 hue, 13/50 fail | 1.38 steps, 25.2 hue, 169/180 fail |

Three answers come out of it.

**Round 7 moved exactly one figure.** 142 of 9,900 rows differ from round 6, and **every one of
them is a submarine** — twelve by more than a tenth of a step, the largest by 0.27. That is the
hull the round-7 page said had darkened, and the edge ruler does see it where the median ruler
reported the sub's cells as identical. Everything else that page reported — the lit canopy, the
keyed-down masonry — was a **ground** change, which a units-only history run cannot and does not
claim: read the round-7 column as "the shipped figures", not as "what round 7 did".

**The sub-on-sea "regression" was the ruler's, not the art's.** The round-7 page reported the sub's
hull darkening and the harness not seeing it (its finding 4), and reported sub-on-sea at 1.39
median steps and 94% failing. At the contour the same cells read **2.15 steps and 13 of 50
failing** — and the drop from round 5's 2.27 is 0.12 of a step, a twelfth of the bar. The hull did
darken; it was never illegible on water, before or after.

**The verdant-on-woods "regression" was real, and small, and round 5's.** Verdant figures in woods
*improved* from round 5 to round 6 on the contour (1.20 → 1.38 steps) while their failure count
went **up** (162 → 169 of 180), because the round-6 figures gained value against the canopy and lost
it in the same places they were already thin. Their hue is flat at ~25 throughout, under the bound:
green on green is the standing defect, no generation has answered it, and it is the same defect
finding 7 reads off the shipped sheet.

**Do neutral and iron subs remain true failures under the new ruler? No.** Of the twenty
neutral-and-iron sub-on-sea board cells, **sixteen pass** at a median of 2.23 edge steps and 30.5
hue. The four that fail are the four **fogged** ones (1.39–1.43 steps), which is finding 4 rather
than anything about the sub. The median ruler read the same twenty at 1.31 median steps and failed
seventeen. The prediction was that these were true failures the new ruler would keep; the measurement
says they were artifacts of measuring a hull's middle instead of its outline.

## Spot checks

Four composites read by eye, each dumped by the harness itself
(`make legibility-check LEGIBILITY="--dump=board:apc:neutral:ready:plains:none"`), which prints both
readings beside the crop.

The new worst class: a neutral APC on plains, **0.05 edge steps** and **47.1** hue (figure
`#a4874f`, ground `#6cb549`, median ruler 0.52 steps). Its contour is the same value as the grass
all the way round, and the only thing telling the two apart is that one is tan and one is green:

![neutral APC on plains](images/legibility_edge_apc_neutral_plains.png)

Doubly blind, and the two rulers disagree about *which* reading fails: an iron bomber on a base,
**0.71 edge steps** and **2.35** hue, where the whole-figure medians read 0.67 steps and **66.9**
hue. The figure's mass is a different colour from the tile's mass; its outline is not, because the
outline is grey and it is lying on the grey building:

![iron bomber on a base](images/legibility_edge_bomber_iron_base.png)

The supersession in one tile: a neutral infantry in the cut-in over open water, **0.00 median
steps** — one of the previous page's worst twenty in the game — and **2.04 edge steps**, passing.
Nothing about the art changed:

![neutral infantry in the cut-in over sea](images/legibility_edge_cutin_infantry_neutral_sea.png)

The reviewer's prediction, refuted: a neutral submarine on open water, **2.10 edge steps** and
**43.8** hue against the median ruler's 1.10 steps:

![neutral submarine on sea](images/legibility_edge_sub_neutral_sea.png)

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
