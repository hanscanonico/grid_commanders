# Composite legibility — 2026-08-19 (generator `30c1e97`, round 9)

What the sweep finds on the sheets shipped by generator `30c1e97`, the contour-precedence fix: every
unit's outer boundary is now its S0 outline, whatever plane the model drew there. A dated
measurement — it supersedes the previous page wholesale rather than editing it, the way
`docs/bulwark_balance.md` and `docs/replay_survey.md` are superseded.

**Nothing was tuned in response to it.** No colour anywhere moved for this run — every number below
is the generator's art read back, and the two harness changes this round made (below) are a sort and
a bar, neither of which touches a pixel.

Re-run with `make legibility-check`. It reads the shipped atlases and the shipped constants, plays
no match, takes about a minute, writes `cells.csv` and `summary.md` under `reports/` (gitignored) —
and redraws the one artifact it publishes, the worst-twenty gallery below. Two runs of one tree
write the same bytes, gallery included.

## What changed in the ruler, and what did not

The **edge reading is unchanged**: for every pixel of the silhouette's perimeter, the ground within
3 px outside it, reported at the **p25** of the perimeter — in ramp steps and in CIE76 chroma
distance. Two ramp steps and a hue bound of 20 are where round 8 left them. The control is exact:
the **previous** units sheet, read by this harness at a flat two-step bar over all 9,900 cells,
reproduces the previous page's headline of **6,634 failing (67.0%)** to the cell.

Two things did move, and both are reporting rather than measuring.

**The gallery now sorts by `max(edge steps / 2, edge hue / 20)`, not `min`.** `min` ranks a cell by
whichever bar it misses hardest, so a figure that is invisible in value and obvious in colour
outranks one that is invisible in both — which is how round 8's sheet came out as twenty tiles of a
single unit. `max` can only be small when *both* readings are small, so the sheet opens on the
doubly-blind class. `min` keeps the job it is right for and that job is not ordering: whether a cell
missed a bar at all is the verdict and the hue bound beside it.

**Fogged cells are held to their own bar of one ramp step, and are out of the headline.** Fog is
drawn to hide; holding it to the bar a clear tile is held to measures the wash doing its job and
files it as an art defect. What a fogged cell still owes is that something is *there* — one step of
boundary surviving the wash. The two classes are counted apart everywhere, because a rate mixing two
bars answers no question.

## Is a unit ever really drawn under the fog wash?

Asked because it decides how much the fogged class is worth. **Read off the game code: no unit ever
*stands* under the shroud, and the only real-play instance is transient.**

- `UnitSprite.refresh()` is `visible = unit.carrier == null and not fogged`
  (`scenes/battle/unit_sprite.gd`), and `fogged` is `not perspective.can_see_unit(unit)`, decided in
  `BattleView` and remembered rather than re-derived.
- Anything the viewer *may* see stands on a cell the fog pass leaves bare. `Vision.can_see_unit`
  returns true outright for a unit on the viewer's own side, and every such unit's own cell is in
  its side's `visible_cells` (it is the centre of its own reveal); an enemy is visible only when
  `visible.has(unit.cell)` — the same test, cell for cell, that `BattleView.refresh_fog` paints the
  shroud by.
- The two remaining viewer modes close the gap from both ends: a hot-seat blackout hides every cell
  **and** every unit, and a replay's omniscient viewer makes `can_see_cell` true everywhere, so
  `refresh_fog` paints no shroud at all.
- **There are no last-known-position ghosts for units.** The board's only memory of what it last saw
  is `BattleView._last_seen_owner`, which is a *property tile's* atlas row; a unit that walks out of
  sight is simply not drawn.

The smoke sweep's own `preview_fog` frame is the picture of that: the shrouded ground holds no
figure at all, and every unit on the board stands on a tile the shroud did not reach.

The one instance is motion. `BattleCommandPipeline` refreshes fog **after** the move animation has
been awaited, so for the length of a walk a sprite the viewer can already see is tweened across
cells whose shroud has not been lifted yet — an own unit stepping into unscouted ground, or a
visible enemy walking out of the viewer's sight. `FogLayer` sits above `Units` in `battle.tscn`, so
that walk really is drawn under the wash. It is a few hundred milliseconds, of a unit whose identity
the viewer already knows, and it is why the fogged class earns a weaker bar rather than exemption.

## What is measured

Every cell of 18 units × 5 faction rows × {ready, acted} × ten grounds × {no wash, move, fire,
threat, fog} at board resolution, plus the same figures at the cut-in's resolution — **9,900
composites**, stacked in battle.tscn's own node order: terrain, the wash over it, the unit over
that, the fog shroud over everything. One ramp step is **0.1543 luminance**, measured off the
shipped units atlas.

## The headline

**Clear class: 8,100 cells, 4,082 failing (50.4%) at two ramp steps.** 3,119 of those failures
(76.4%) are 20 or more apart in hue — value-blind rather than illegible — which leaves **963
doubly blind** and **151 severe on both** (under half the bar *and* under 20 hue).

**Fog class, reported separately: 1,800 cells, 512 failing (28.4%) at one ramp step**, 251 of them
doubly blind.

The previous sheet, scored by the same harness with the same bars, is the comparison — only the
units atlas differs, and the grounds and the ruler are identical:

| class | previous (`8ba480c`) | shipped (`30c1e97`) |
| --- | --- | --- |
| clear, failing | 4,920 (60.7%) | **4,082 (50.4%)** |
| clear, doubly blind | 1,109 | **963** |
| clear, severe on both | 297 | **151** |
| fog, failing at 1.0 | 716 (39.8%) | **512 (28.4%)** |
| fog, doubly blind | 316 | **251** |

**5,286 of the 9,900 rows moved. 1,061 cells crossed from fail to pass and 19 crossed the other
way**, and all nineteen are the lander (finding 4).

| view | median edge steps | median edge hue | failing |
| --- | --- | --- | --- |
| board | 1.68 → **1.89** | 30.1 → 30.2 | 67.8% → **56.2%** |
| cutin | 3.02 → 3.02 | 27.5 → 27.5 | 4.0% → 4.0% |

(clear class; previous → shipped. The cut-in is unmoved to the cell: 36 failures before and after.)

| ground | median edge steps | failing | doubly blind |
| --- | --- | --- | --- |
| shoal | 1.90 → **2.28** | 54.7% → **33.3%** | 180 → 122 |
| plains | 1.88 → **2.20** | 54.6% → **32.9%** | 24 → 12 |
| mountain | 1.83 → 2.13 | 58.1% → 38.9% | 130 → 95 |
| port | 1.83 → 2.06 | 60.0% → 46.9% | 57 → 53 |
| airport | 1.81 → 2.06 | 59.4% → 46.2% | 45 → 45 |
| woods | 1.67 → 1.80 | 82.2% → 75.6% | 61 → 52 |
| city | 1.56 → 1.73 | 72.9% → 67.4% | 192 → 182 |
| base | 1.52 → 1.55 | 85.4% → **83.1%** | 170 → 164 |
| hq | 1.44 → 1.51 | 80.6% → **79.6%** | 205 → 199 |
| sea | 1.34 → **1.79** | 70.4% → **58.1%** | 45 → 39 |

(clear board rows, every wash.)

| wash | median edge steps | failing |
| --- | --- | --- |
| none | 1.62 → 1.83 | 69.6% → 59.4% |
| move | 1.72 → 1.95 | 65.8% → 53.2% |
| attack | 1.69 → 1.90 | 67.8% → 55.9% |
| threat | 1.67 → 1.91 | 68.2% → 56.3% |
| fog (bar 1.0) | 1.07 → 1.21 | 39.8% → 28.4% |

(board rows. Fog's rate is at its own bar; at the clear bar the same cells read 95.2% → 93.4%.)

| faction row | median edge steps | median edge hue | failing |
| --- | --- | --- | --- |
| iron | 1.81 → 1.95 | 51.7 | 64.2% → 52.2% |
| aurora | 1.65 → 1.86 | 54.1 | 66.4% → 56.1% |
| meridian | 1.59 → 1.84 | 53.4 | 66.7% → 56.1% |
| verdant | 1.61 → 1.75 | 26.6 | 76.1% → **66.9%** |
| neutral | 1.55 → 1.69 | 45.5 | 74.7% → 65.6% |

(bare board, no wash. The hue column did not move — the fix is a value fix.)

| unit | median edge steps | failing | doubly blind |
| --- | --- | --- | --- |
| tank | 2.89 → 2.89 | 8.2% → 8.2% | 1 |
| recon | 2.84 → 2.84 | 14.2% → 14.2% | 1 |
| missiles | 2.36 → 2.36 | 19.8% → 19.8% | 7 |
| battleship | 2.14 → 2.22 | 39.2% → 30.2% | 26 → 21 |
| artillery | 1.63 → **2.15** | 85.5% → **32.5%** | 25 → 3 |
| sub | 2.13 → 2.13 | 31.5% → 31.5% | 34 |
| rockets | 2.07 → 2.09 | 43.8% → 43.5% | 31 → 32 |
| t_copter | 1.79 → 1.97 | 66.5% → 53.8% | 79 → 72 |
| cruiser | 1.15 → **1.93** | 100.0% → **52.5%** | 59 → 33 |
| b_copter | 1.53 → 1.88 | 87.2% → 57.8% | 72 → 57 |
| lander | 1.87 → **1.84** | 67.8% → **69.8%** | 47 → 51 |
| mech | 1.60 → 1.71 | 91.2% → 78.2% | 121 → 110 |
| anti_air | 1.70 → 1.70 | 72.2% → 72.2% | 12 |
| fighter | 1.44 → 1.58 | 95.0% → 78.5% | 152 → 124 |
| infantry | 1.17 → 1.50 | 100.0% → 95.2% | 160 → 159 |
| md_tank | 1.17 → 1.34 | 99.2% → 78.0% | 71 → 37 |
| bomber | 0.71 → 1.12 | 100.0% → **96.2%** | 150 → 151 |
| apc | 0.78 → **0.89** | 99.5% → **99.2%** | 61 → 58 |

(clear board rows, every wash, 400 cells each.)

## Findings

1. **The contour fix is the largest single art movement this instrument has measured, and it lands
   exactly where the ruler looks.** The clear class goes 60.7% → 50.4% failing, severe-on-both
   halves (297 → 151), and 1,061 cells cross the bar. Nothing else could have done it: the terrain
   sheets are byte-identical to the previous adoption, so every one of those cells moved because a
   figure's *outline* changed colour.
2. **Five units did not move at all, and that is the fix working rather than missing.** Missiles
   moved on 0 rows, anti-air on 2, the sub on 6, the tank on 13 and the recon on 19 — their outer
   boundary was already S0, so the pass had nothing to claim there, and the rim it pushed one pixel
   inboard is interior pixels the edge reading does not read. Their sprite bytes all changed; their
   numbers are identical to the digit.
3. **The APC did not clear, and it is now the roster's worst hull alone.** 99.5% → 99.2% failing,
   median contour 0.78 → 0.89 steps. Its flagship cell is unmoved to the hundredth — a neutral APC
   on plains still reads **0.05 edge steps** at 47.1 hue — because the boundary that vanishes there
   was already the outline: it is the right *kind* of pixel and the wrong *value*, a mid-tan the
   grass already holds. The contour fix could only ever make an outline consistent; making it darker
   is a separate ruling.
4. **The lander is the one unit that lost ground, and all nineteen new failures are its.** Median
   1.87 → 1.84 steps, 131 rows worse, worst −0.42, split 72 acted to 59 ready and confined to six of
   the ten grounds — the beach, base, HQ, city, plains and mountain, none at sea. It is small and it
   is real; it is the price of an outline that no longer borrows the value of whichever plane drew
   it.
5. **Sea, sand and grass are answered; the properties are not.** Open water gains most of any ground
   (1.34 → 1.79 steps, 70.4% → 58.1%), plains and shoal both clear the two-step bar at the median
   for the first time. Base (83.1%) and HQ (79.6%) barely move, because what fails there is a figure
   lying on a grey building rather than an outline that had the wrong owner — the same defect the
   previous page's finding 5 named, untouched by a fix aimed at outlines.
6. **Fog costs less than the previous page could say.** At its own one-step bar the shroud fails
   28.4% of its cells, down from 39.8% on the previous sheet — and 251 of those are doubly blind,
   which is a quarter of that class rather than the third the flat bar reported. The wash is still
   the strongest single term in the sweep; it is no longer the headline, because the headline
   should not be the game hiding what it means to hide.
7. **Hue did not move anywhere.** Every faction row's median edge hue is unchanged to the tenth, and
   verdant is still the weakest livery at 26.6 against 51–54 for the other three. Green figures on
   green ground remain the standing defect, and no generation has answered it.

## The gallery

`make legibility-check` redraws this sheet: the twenty cells with the least margin on the **further**
of the two readings, each magnified to one tile and labelled with its unit, faction, ground, wash,
state, view, both edge numbers and both median ones.

![the twenty worst-scoring composites](images/legibility_worst20.png)

It is no longer one unit: twelve bombers, four APCs, two fighters, an md_tank and an infantry, five
of them fogged. **The sort did that, not the art** — on this same shipped sheet the old `min` order
still returns twenty APCs, because the APC's hue margin is enormous everywhere and `min` never looks
at it. Every hue on the sheet is under 6: this is the doubly-blind class, which is what the order was
changed to show.

Read it with finding 3 and finding 5 in hand. The APCs are the beach under the move wash — tan on
sand, the one ground where the APC's colour does not save it. The bombers are grey aircraft lying on
grey masonry, and the fogged five are that same pairing with a grey wash over it.

## Spot checks

Four composites read by eye, each dumped by the harness itself
(`make legibility-check LEGIBILITY="--dump=board:cruiser:aurora:ready:sea:none"`), which prints both
readings beside the crop.

The fix at its best: an aurora cruiser on open water, **1.38 → 2.06 edge steps** (figure `#2d47a4`,
ground `#2b70bf`) — a hull that now passes on a ground where its whole class used to fail 100% of
the time:

![aurora cruiser on sea](images/legibility_r9_cruiser_aurora_sea.png)

The fix at its limit: a neutral APC on plains, **0.05 edge steps** before and after, 47.1 hue. The
outline is the outline the fix guaranteed; the value is the value it could not change:

![neutral APC on plains](images/legibility_r9_apc_neutral_plains.png)

The regression, at its worst cell: a meridian lander on a city, greyed out, **1.81 → 1.39 edge
steps** while its whole-figure median went the other way (2.34):

![meridian lander on a city](images/legibility_r9_lander_meridian_city.png)

The fog class at its own bar: a neutral bomber on a base under the shroud, **0.35 edge steps** and
**1.5** hue — still a failure at 1.0, and one of the 251 the shroud blinds on both readings:

![neutral bomber on a base under fog](images/legibility_r9_bomber_neutral_base_fog.png)

## The history re-run

The previous three generations were re-scored through the round-8 ruler on the previous page and
that table is not repeated here: this round's whole comparison is the one above, previous sheet
against shipped, because only the units atlas moved. `make legibility-check LEGIBILITY="--units=<file>"`
is still how a past generation is read through today's ruler, and holding the grounds at today's art
is still deliberate — a generation's numbers should move because its *figures* moved.

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
