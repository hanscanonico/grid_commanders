# Composite legibility — 2026-08-19 (generator `0d87068`, round 10)

What the sweep finds on the sheets shipped by generator `0d87068`, which weighs the contour in
**logical pixels** rather than in source pixels. A dated measurement — it supersedes the previous
page wholesale rather than editing it, the way `docs/bulwark_balance.md` and
`docs/replay_survey.md` are superseded.

## Re-read 2026-08-19, after the solid cast shadow (generator `55d2b65`)

The board's cast shadow became solid and the sub's wake with it, so board pixels moved and this
page was re-read rather than re-authored: **1,284 failing (15.9%) clear and 123 (6.8%) fogged**,
against the **1,276 (15.8%) / 118 (6.6%)** below. The control is exact — the shipped harness run
against the *previous* atlas reproduces this page's headline to the cell — so the whole of the
difference is 13 cells, and **every one of the 17 that crossed to failing is the sub** (4 crossed
back on woods). The mechanism is the wake, not the shadow: it is continuous now, so bright foam
sits on the silhouette's contour and against pale shoal or a property lot it is close in value.
827 of the 9,900 rows moved their edge reading, 452 of them the sub's.

No class moved and nothing was tuned in response. Every finding, table and gallery below still
describes the art as this page found it, and the next full campaign supersedes the page wholesale.

**Nothing was tuned in response to it.** No colour anywhere moved for this run, and **the ruler is
unchanged from round 9** — same edge reading, same two-step bar, same hue bound of 20, same
one-step fog bar, same `max` gallery sort. Every number below is the generator's art read back
through the previous page's instrument.

Re-run with `make legibility-check`. It reads the shipped atlases and the shipped constants, plays
no match, takes about a minute, writes `cells.csv` and `summary.md` under `reports/` (gitignored) —
and redraws the one artifact it publishes, the worst-twenty gallery below.

## The ratchet

`make legibility-ratchet` runs the same sweep and diffs its verdicts against
`tests/fixtures/legibility_baseline.csv`, the committed PASS/FAIL per cell. **It fails only where a
cell that passed in the baseline fails now.** A cell that newly passes is printed and nothing more:
the rule this page is written under is unchanged — a failing cell is a finding for the art to
answer, never a colour to move — so the ratchet holds the line rather than demanding it improve. A
cell the baseline does not know about, or one it knows and this run no longer measures, is listed
too; both mean the matrix itself moved, which is a re-baseline and not a regression.

Only the verdicts are committed, never the readings, so a re-render that moves a ramp step without
crossing the bar leaves the file alone. A cell is named by view, frame, unit, faction, state,
terrain and overlay — not by the terrain variant, which is the worst-scoring tile of that family
and may change hands without the verdict moving.

Re-baseline with `make legibility-baseline` after an **intended** art change, alongside `make
tiles`: read the new sweep first, then commit the digest with the art it describes. It is out of
`make verify` for the sweep's own reason — it renders the whole matrix and takes about 24 minutes on
a loaded machine — so it is a step before an art merge, not a per-commit gate.

**No baseline cell fails on purpose**, so any name in `make legibility-ratchet`'s output is a real
regression. S3's one accepted exception — `board:idle_b:mech:iron:ready:port:fog`, carried here from
2026-09-01 — was retired by S8, which re-measured it at **1.25** against the one-step fog bar and
re-baked the digest with it (the 2026-09-01 re-read below).

## Re-read 2026-08-19, over the terrain variants

The ruler now reads a ground on every tile its family can draw and reports the worst (see *What is
measured*), where it used to read the one tile a single probe cell happened to wear. Only open water
has more than one tile today, and the re-read is **1,291 failing (15.9%) clear and 123 (6.8%)
fogged** against the 1,284 (15.9%) / 123 (6.8%) above: **the whole difference is the sea, 90 → 97**,
and the headline percentages are unmoved. The three phases are alike but not identical — of the
sea cells, phase 2 wins the worst-of 151 times and fails 16.6% of them against phase 1's 7.3%, so a
phase is worth naming even now. Nothing was tuned in response, and no other terrain, unit,
faction or class moved by a cell.

## Re-read 2026-08-20, after plains gained phases (generator `21175fc`)

Plains is now a phase-keyed family like the sea — three tiles, phase 0 the atlas column byte for
byte — so the ruler reads it three ways and reports the worst. It is the reference ground most
contrast pairs are read against, which is what made this the real gate for that change, and it
**costs the board nothing**: **1,291 failing (15.9%) clear and 123 (6.8%) fogged**, the previous
re-read's numbers to the cell, and `plains/0`, `plains/1` and `plains/2` each fail **0 of their
cells**, as the single plains tile did. No unit, faction, overlay or other terrain moved by a cell,
and nothing was tuned in response. Only the `terrain/variant` table gained rows.

## Re-read 2026-08-20, after mountain gained phases (generator `8569ba4`)

Mountain is phase-keyed now for the reason plains is, read at its loudest: it is the most
silhouette-dominant tile on the board, so a range drawn from one of them is a wall of the same peak.
A phase moves the summits, the ridges under them and the snow-line seed and **nothing else** — the
ground line and the contact shadow are fixed, so a range stands on one horizon — and the ruler reads
all three and reports the worst. It **costs the board nothing**: **1,300 failing (16.0%) clear and
123 (6.8%) fogged**, which is a same-day control on the atlas-only mountain to the cell (1,300 /
123), and the `mountain` row is 21 failing (2.6%) in both readings. The worst phase is **`mountain/2`
at 13.6%** of the 59 probe cells it wins, against `mountain/1`'s 0.0% of 312 — worth naming, like the
sea's phase 2. One failure moved from value-blind to hue-carried and nothing else did; no unit,
faction, overlay or other terrain moved by a cell, and nothing was tuned in response.

## Re-read 2026-08-25, after the animation install (generator `e16d261`) — A REGRESSION

The animation install regenerates every sheet on the board, and the ruler reads it far worse than
the art it replaces: **7,023 failing (86.7%) clear and 1,439 (79.9%) fogged**, against a same-day
control on the previous art of **1,300 (16.0%) / 123 (6.8%)** — the same harness, the same 8,100 +
1,800 cells, the ramp step unmoved at 0.1549 against 0.1543. This is a finding, not a tuning: no
colour was moved in response, and the art is installed byte-identical to the generator.

**The failure is at board resolution and only there.** The `board` view fails 94.8% of its cells
where the `cutin` view — the same figures at 1:1 — fails 21.6% (control: 17.6% / 4.0%). The board
draws the 64 px cell onto 16 px with nearest filtering, so a contour that is not several source
pixels thick is three-quarters unsampled; round 10's per-edge band is what bought the 15.8% this
page is a reading of, and the new cells do not read as carrying it. 71.1% of the clear failures
still clear the hue bound, so the board is value-blind rather than illegible — the shapes are told
apart by colour, which is exactly what the two-reading bar exists to count rather than pass.

Frame B is the same reading: **7,073 (87.3%) / 1,459 (81.1%)**, board 96.2% against cut-in 16.1%
(`make legibility-check LEGIBILITY="--units=assets/tiles/units_atlas_b.png"`). So the beat costs
nothing on top of the install — both frames are the install's art.

Everything below this line still describes the `0d87068` art. The next generator round supersedes
this page wholesale; until one does, **read the headline as the previous art's and this section as
what shipped over it**.

## Re-read 2026-08-29, over the frame axis — all six unit sheets

The ruler had read one sheet of the six the game ships. It now reads a **frame** — a clip and a
beat — on every row: the board's `idle_a` / `idle_b` (the ambient pair) and `walk_a` / `walk_b`
(the gait pair a unit wears while `BattleAnimator` tweens it along a path), and the cut-in's
`idle_a` / `idle_b`, which are the *figure* sheets, the same poses with the tile's cast shadow
subtracted. Which file a frame is drawn from is the view's, exactly as `UnitSprite._sheet_path`
and `UnitSprite.figure_texture_for` decide it in the scene. The matrix is **37,800 composites**
where it was 9,900, `frame` is a column in `cells.csv`, a table in `summary.md`, a caption line in
the gallery and the second field of `--dump`, and the ramp step is unmoved at **0.1549**.

Nothing was tuned in response and the ruler is unchanged: same edge reading, same bars, same hue
bound, same gallery sort.

| view / frame | sheet | clear cells | failing | median edge | fogged failing |
| --- | --- | --- | --- | --- | --- |
| board `idle_a` | `units_atlas.png` | 7,200 | 6,829 (94.8%) | 1.15 | 1,439 (79.9%) |
| board `idle_b` | `units_atlas_b.png` | 7,200 | 6,928 (96.2%) | 1.17 | 1,459 (81.1%) |
| board `walk_a` | `units_atlas_move.png` | 7,200 | 6,951 (**96.5%**) | 1.11 | 1,491 (82.8%) |
| board `walk_b` | `units_atlas_move_b.png` | 7,200 | 6,862 (95.3%) | 1.15 | 1,456 (80.9%) |
| cut-in `idle_a` | `units_atlas_figures.png` | 900 | 422 (46.9%) | 2.00 | — |
| cut-in `idle_b` | `units_atlas_figures_b.png` | 900 | 399 (44.3%) | 2.01 | — |

Whole run: **clear 30,600 cells, 28,391 failing (92.8%)**, 19,869 of them hue-carried; **fog 7,200
cells, 5,845 failing (81.2%)** at the one-step bar.

**The two frames this page had already read reproduce it to the cell.** Board `idle_a` is
94.8% clear / 79.9% fogged, which is the 2026-08-25 section's headline exactly, and board `idle_b`
is 96.2% / 81.1%, which is that section's `--units=units_atlas_b.png` probe exactly. The axis
therefore adds readings without moving one.

### The four findings

1. **The gait sheets are the install's art, and no better.** `walk_a` is the worst frame on the
   board (96.5% clear, 82.8% fogged) and `walk_b` the middle of the pack; both sit inside the
   spread the ambient pair already had. The move clip did not introduce a legibility problem of its
   own and it did not answer the install's — the whole board still fails at ~95% for the reason the
   2026-08-25 section gives, one source pixel in four surviving the board's decimation.
2. **A frame is a real axis, not a rounding difference.** Between `idle_a` and `walk_a`, 6,720 of
   the 9,000 board cells (both classes) move their edge reading and **267 cross to failing against
   93 the other way**; `idle_a`→`idle_b` is 6,836 moved, 268 / 149. Per unit the spread is widest
   on the **sub (73.8% idling, 90.8% walking, clear class)**, the tank (85.5% `idle_a` to 97.2%
   `walk_a`) and the APC.
   Reading one frame was reading one of four boards.
3. **The cut-in row changed subject, and it was wrong before.** It used to be measured off the
   board's own cell — cast shadow included — which is art the cut-in never draws. Off the sheets it
   actually draws it reads **46.9% / 44.3%** where the old composite read 21.6% / 16.1%. That is
   the harness correcting itself, not the figures moving: the dark shadow band was contour the
   reading was scoring and the screen never shows. It is still the optimistic direction on one
   count — the director paints its own contact shadow under the figure and this composite does not
   — so treat the cut-in numbers as the figure against bare ground.
4. **The worst-twenty gallery is now all four frames.** Ten of the twenty are gait cells and the
   `lander` fogged on a mountain in `walk_b` is the worst cell in the whole sweep at 0.20 edge steps
   / 3.9 hue. The pairing behind them is the previous rounds' unchanged: pale or grey airframes and
   hulls on masonry, shoal and mountain.

![the twenty worst-scoring composites](images/legibility_worst20.png)

The run takes **24 minutes** on a loaded machine (four times the matrix it was), still writes
`cells.csv` and `summary.md` under `reports/`, and still redraws only the gallery above. A cell is
named `view:frame:unit:faction:state:terrain:variant:overlay` now — for example
`make legibility-check LEGIBILITY="--dump=board:walk_b:lander:iron:ready:mountain:0:fog"`.

## Re-read 2026-08-30, after the mountain was redrawn as a peak (COM-264)

The massif's height field was rebuilt — a steeper flank, ridge crests off each summit instead of
isotropic crag speckle, a wider snowcap and a talus fan carrying the mass out to the footprint's
edge — and the three phases were re-seeded with it. Only `mountain` moved: **34,212 failing (93.2%)
clear and 7,037 (81.4%) fogged**, against the previous baseline's art on the same harness, and the
`mountain` row is 94.4% of its 3,672 cells. **55 verdicts changed, all of them mountain's: 36
crossed to failing and 19 the other way**, a net 17 cells of 45,360.

The mechanism is the speckle. The old flank scattered lit top planes over its whole face, and a
sprinkle of bright pixels behind a contour is worth p25 edge steps whatever it does to the read; the
new flank spends its light on continuous crests, so a stretch of outline that used to fall on a
stray light pixel now falls on one plane. No colour moved for a cell: the one thing this sweep did
say out loud is that the new talus fan put a lot more of the rock's darker band under a silhouette,
so `MASSIF_TALUS` went 3 to 2, and running it again after that turned a good share of the losses
back. The board is at 93.2% for the reason the 2026-08-25 section gives, so 17 cells on one terrain
is inside that regression, not a reading of this change.

The baseline digest was rewritten for it (`make legibility-baseline`), which is what that target is
for after an intended art change.

## Re-read 2026-08-30, after the movement wash was made a claim

The reach overlay's baked tile went to a hard edge (fill 86 → 160, edge 127 → 255 in
`generators/sprites/spritegen/chrome.py`) and `OverlayPalette.MOVE` turned mint; `ATTACK`'s palette
alpha dropped so its fill lands where it did. The sweep reads the shipped overlay tile and the
shipped palette, so it answers for the change: **31,832 failing (86.7%) clear and 7,037 (81.4%)
fogged**, against 34,212 (93.2%) / 7,037 (81.4%) above. **2,542 verdicts moved — 2,461 recovered
and 81 regressed** — and both sides are the two washes that changed: 2,451 recoveries and 77 losses
under `move`, 10 and 4 under `attack`, none under `threat`, `fog` or `none`. The `move` row is now
67.8% failing against `attack`'s 95.8% and `threat`'s 95.6%.

The mechanism is that the wash lies under the figure: a denser, brighter mint ground puts more
separation behind a dark contour, which is most of the board. The 81 losses are the other end of
the same lever — the pale hulls on the pale grounds, 39 of them the **sub** and 14 the
**battleship**, 47 of the 81 **iron**, and 40 of them on `shoal` or `sea`, where the wash lifts a
ground that was already close to the figure past it. It is a finding for the art, not a colour to
move back: the wash exists to be seen, and the reach it delimits is the more gameplay-critical read.

The digest was rewritten for it (`make legibility-baseline`) and the gallery redrawn with it.

## Re-read 2026-08-30, after the mountain became one peak with a cap

The redraw above kept three near-equal summits and a cap too dim to tell from the rock beside it;
playtest still read the tile as a rock pile. This pass gives every phase **one dominant summit with
shoulders under it**, measures the snow line **down from that summit** so only it wears a cap, and
draws the cap a ramp slot higher (`palette.TERRAIN_MATERIALS`, `snowcap` on S4) — the snow ramp's
own top three rungs, brightest L172, still under the ceiling that reserves the top band for units.

It **buys the board cells**: **31,811 failing (86.63%) clear and 7,011 (81.15%) fogged**, against
the previous baseline's 31,832 (86.69%) / 7,037 (81.45%), and the `mountain` row is 86.88% of its
4,536 cells against 87.92%. **73 verdicts changed, every one of them mountain's: 60 crossed to
passing and 13 the other way**, a net 47 cells of 45,360. Nothing was tuned in response, and no
unit, faction, overlay or other terrain moved by a cell.

One thing the sweep did say out loud, and the art answered: a first cut drew the band of rock
**under** the snow line a rung darker, which is how a real snow line reads and read well on the
tile. It puts the massif's darkest rung over the middle of the cell, which is where a unit stands,
and the ratchet came back with mountain cells that had passed and no longer did — almost all of
them `acted` or fogged units, whose own values are dimmed. That band is not in the shipped art; the
cap is read by its own rungs alone.

The 13 losses were read one by one and accepted; darkening the cap's top rung to answer them would
trade away the light terminal that bought the 60. They fall in three classes:

- **Nine are the accepted grey-on-grey residual** — seven iron and two neutral, eight in clear
  view and one fogged (`walk_a|b_copter|iron|ready|mountain|fog`). Grey liveries on grey rock is
  the pairing this page has named since round 9 and the cap does not change it.
- **`walk_a|rockets|aurora|ready|mountain|fog` is its own item, under the fog residual** — a
  chromatic livery the shroud pulls to the rock's own value. Named here so it is findable if the
  fog isolation rate is ever revisited.
- **Two are a new class, `acted`-under-wash** — `fighter|aurora|acted|mountain|move` and
  `recon|aurora|acted|mountain|move`: the deliberate `acted` dim meeting the lit mint reach wash
  the section above installed. Neither the mountain's problem nor grey-on-grey's, and the watch
  condition is that the class stays on mountain. If it ever appears on another ground, the answer
  is the wash's value or the `acted` dim's floor — a renderer and overlay ruling — and never
  per-terrain art.

The remaining cell, `idle_b|apc|verdant|ready|mountain|attack`, is logged against the standing
verdant hue-gap follow-up (round 11's saturation residual, finding 7 below) as that follow-up's
concrete worst case.

The baseline digest was rewritten again (`make legibility-baseline`), so the 60 gains are the line
the next change is held to.

## Re-read 2026-09-01, after S8 answered the board-scale regression

The 2026-08-25 regression above is answered. Read the whole way through this page as **the previous
art's** until here; this section supersedes every headline number above it — including the
worst-twenty gallery embedded twice above, which is one regenerated file and today holds S8's own
twenty, described under *What resists* below. Same control this page
has always used, run on this tree before the change: **clear 31,625 failing (86.1%) and 6,968 (80.6%)
fogged**, against 4,082 (50.4%) the round-10 band once bought and 1,276 (15.8%) the 1px G-buffer
outline it replaced — three re-reads of unrelated shipped work (S2's air retones, S3's shadow refit,
the mountain peak and the wash) had drifted the board's own headline to 87.1% clear / 79.1% fogged on
`idle_a` alone, against the 2026-08-25 section's 94.8% / 79.9%, and neither move was a finding for
this page to answer. **After: clear 18,247 failing (49.7%) and 2,921 (33.8%) fogged** — 17,690 of the
45,360 rows moved against the digest that was committed before this change, **17,672 FAIL → PASS and
18 PASS → FAIL**, a net −17,654. The eighteen are named under *What resists* rather than absorbed by
the re-bake. (That digest was baked one tree back, so its own totals — 31,811 clear and 7,011 fogged
failing — sit a little above the control re-run here; the moved-row count is the artifact's, the
headline percentages are the control's, and the two are not the same measurement.)
Hue-carried failures fall with everything else,
72.9% → 69.5% of what remains, so the residual is still mostly value-blind rather than newly
illegible.

| view | clear cells | failing (before → after) | fogged failing (before → after) |
| --- | --- | --- | --- |
| board | 34,560 | 88.2% → **52.5%** | — |
| cutin | 2,160 | 52.2% → **4.3%** | — |

| frame | clear cells | failing (before → after) | fogged failing (before → after) |
| --- | --- | --- | --- |
| board `idle_a` | 8,640 | 87.1% → **47.7%** | 79.1% → **28.4%** |
| board `idle_b` | 8,640 | (unread) → 51.4% | (unread) → 32.2% |
| board `walk_a` | 8,640 | (unread) → 55.5% | (unread) → 34.4% |
| board `walk_b` | 8,640 | (unread) → 55.6% | (unread) → 40.3% |
| cutin `idle_a` | 1,080 | (unread) → **5.2%** | — |
| cutin `idle_b` | 1,080 | (unread) → **3.3%** | — |

(`idle_a`'s before is the only frame this page's own control read on the previous section's tree;
the other five are read once, after, since the frame axis moved with the same commit.) **The cut-in
reading did not get worse — it improved by an order of magnitude**, the same mechanism that answers
the board paying it forward: the figure sheets are the board sheets minus the tile's cast shadow
(`test_figure_sheet.gd`), so a thicker, value-clearing contour on the board is the same contour at
1:1.

| faction row | failing (all clear cells, board + cut-in) |
| --- | --- |
| iron | **35.7%** |
| gold | 52.5% |
| meridian | 51.1% |
| aurora | 50.9% |
| neutral | 53.9% |
| verdant | 54.1% |

(Every non-fog row of the digest: the board under all four washes plus the cut-in, which carries
`none` alone — **not** the `bare board, no wash` slice the previous art's tables below are cut on,
which is one view and one overlay of the six.)

Iron stays the strongest row — it was already answering the board-scale question the other five
now share, having worn `OUTLINE_HEAVY` since round 11 — and the other five converge on one number
within five points of each other, where round 11 had meridian and gold at 7% sunward-dark and iron
and neutral at 63%. That convergence is the mechanism, not a coincidence: see below.

### The mechanism

Two changes, both in `spritegen/voxel.py`, scoped to units and the massif — never to a property,
which a board reads AGAINST an army and not as one (`is_unit`, `top_slot == S_RIM`, below).

1. **`_thicken_contour`.** The round-10 band is back, in shape only: `CONTOUR_DEPTH` states 4 px on
   the lit edges and 2 on the ground-facing ones, same split round 10 measured through this same
   harness. It is not round 10's implementation — that band grew outward as well as in, spending a
   `_HALO` this codebase's `_bounds` margin no longer reserves, and the round-11 G-buffer outline it
   grew from is a different mechanism entirely (per-pixel, off `edge_mask`, not a band walk from a
   silhouette scan). S8's version claims **entirely inward**, off the plane behind each already-
   decided 1px line, so the alpha never moves and every geometry-only reading — silhouette IoU, mass
   drift, the S3 shadow footprint — answers exactly as it did with a 1px line. Four things stop a
   claim: the model's own alpha boundary, a pixel already carrying another line (`MID_CONTOUR`), a
   fixed accent or a gunmetal fitting's own lit face (the identifying feature the round-10 band gave
   up reach for), and a pixel already boundary-adjacent on its OWN account — a part thinner than
   `CONTOUR_DEPTH` (a rotor blade, a rack rail) is left at its 1px line rather than having one edge's
   walk read clean through to the far side's.
2. **`_selective_outline`'s fallback, made unconditional for units.** S8 measured that no row's
   ordinary lift clears the board's own ground band from the sunward silhouette — not `OUTLINE_HEAVY`
   alone, every row, including a chromatic row's own S3 token (`clears_the_ground`, the mechanism
   `generators/sprites/docs/outlines.md` names). Round 11's `OUTLINE_LIGHT` paid that in colour
   alone, which the cut-in's 1:1 reading could afford and the board's 4:1 one could not; S8 gives
   every row heavy's old answer —
   fall to the ground-facing contour where the lift cannot clear — and retires `OUTLINE_RIM`'s climb
   on the board specifically, because a climbed rung is still a colour bet and the ruler measured
   aurora and verdant reading WORSE through it (82-86% failing) than through the plain fallback
   (48-52%, matching the other four rows). Off the board — a property, which stops at
   `BUILDING_TOP_SLOT` rather than the rim a unit keeps — nothing changed: `OUTLINE_LIGHT` and
   `OUTLINE_RIM` keep round 11's own answer there, because applying the fallback to properties too
   cost 15 of 20 faction-pair ownership readings
   (`PropertyPalette.test_two_owners_are_tellable_apart_at_the_boards_own_scale`) for a class the
   sweep never scores as a figure.

One knock-on, in `spritegen/aa.py`: the thicker band lengthens same-toned runs along a silhouette, so
a staircase corner's softened write can now strand a NEIGHBOUR pixel that used to match it — measured
on `rockets`' thin rack, an isolated pixel `IndexedPalette.test_no_isolated_pixel_outside_the_dither`
would have caught had it shipped. `_safe` filters exactly those writes out, off the same original
pixels every other write is computed from (`test_aa.NeverStrands`). Refusing a write is itself a
change of who still carries that colour, so the filter is a **fixed point** rather than one pass —
two corners flanking one shared pixel each read the other as its fallback and both ship otherwise,
which `staircase(2, 2)` pins and the suite's run/rise/`min_run` sweep generalises. It moves no pixel
of the shipped art: at `MIN_RUN = 3` the one-pass and settled answers agree on every unit pose,
livery and property (0 of 216 unit renders and 0 of 30 building renders differ), so nothing was
re-baked for it.

### What resists

**Mountain rock and property masonry, plus the grey and blue liveries that key off them.** The worst
20 cells are eleven mountain-phase composites (cruiser, fighter, mech, recon, lander) and nine on
HQ, base or port — the pairing round 10's own finding 5 named and left for "the next round": a dark
unit's contour is reliably near-black now, but a dark ROCK or a dark WALL is near-black too, and no
contour thickness separates two things that are already the same value. Per unit the worst are
`missiles` (86.5%), `cruiser` (79.4%), `lander` (73.4%), `b_copter` (72.5%) and `fighter` (71.0%) —
grey airframes and grey-blue hulls, the roster's own palest rows sitting closest to the rock and
masonry they are read against. Per terrain, `hq` (74.3%) and `base` (72.6%) hold nearly every
building-side survivor, `mountain` 49-53% across its three phases. This is a VALUE question about the
ground, which S8's own locked scope leaves to the ground: **nothing here was tuned in response**, and
moving a property's or the massif's own value to answer it is the follow-up this page names rather
than slides in.

![the twenty worst-scoring composites](images/legibility_worst20.png)

**The eighteen cells that went the other way.** They are 0.10% of the sweep against 17,672 recoveries,
and none is a new class — every one is a dark or mid hull already inside the residual above, tipped
just under the bar by a contour that now reads as one more dark mass against a dark ground. By
family:

| cells | what they are |
| --- | --- |
| 9 | `tank` on `aurora` and `gold`, `idle_b` — `acted` on sea, shoal and woods (`idle_b/tank/aurora/acted/shoal/none`), plus `aurora` `ready` on base under the move wash |
| 3 | `t_copter` on `iron`, `idle_a`, `acted`, under the move wash — hq, mountain, woods |
| 2 | `md_tank` on `gold` and `meridian`, `walk_b`, `acted` on airport in fog |
| 2 | `sub` on `verdant`, cut-in `idle_a`, on sea and port |
| 1 | `fighter` neutral, `idle_b`, `acted` on airport under the move wash |
| 1 | `rockets` on `iron`, `walk_b`, `ready` on woods under the attack wash |

Sixteen of the eighteen are the `acted` dim, an overlay, or both, which is the same renderer ruling
the 2026-08-30 re-read logged: the dim and the wash are what the cell is read *through*, and neither
is per-terrain art. The other two are the cut-in `sub` on `verdant` — the value question this section
already names, at 1:1. Nothing here was tuned in response.

The S3 accepted ratchet exception — `board:idle_b:mech:iron:ready:port:fog`, 1.11 → 0.77 against the
fog bar of 1.0 — is resolved rather than carried forward: re-measured at 1.25, it clears the bar
outright. The baseline this page's `make legibility-baseline` rewrote holds it as an ordinary PASS,
so the exception this page has recorded since S3 is retired.

Full sweep, `make legibility-check`; the digest, `make legibility-baseline`; the ratchet holds this
page's own numbers trivially (0 regressed, run against the digest this re-read wrote).

## What the generator changed

The board draws a 64 px cell onto a 16 px grid with nearest filtering: it keeps one source pixel in
four. Round 9 made every unit's outer boundary structurally its S0 outline and the APC still failed
99.2% of its board cells, because a **1 px** contour is three-quarters unsampled and which quarter
survives is an accident of where the edge falls. Round 10 states the band per edge in source pixels
— 4 on the lit (top and left) edges, 2 on the ground-facing ones — so a board-scale sample lands on
contour whatever the phase. The band grows **inward**, off the faction plane behind the edge; the
outward halo is round 9's unchanged, because the md_tank already fills 63 of the 64 px its cell
allows.

The control is exact: the **previous** units sheet, read by this harness at today's bars, reproduces
the previous page's headline of **4,082 failing (50.4%)** and its fog line of **512 (28.4%)** to the
cell.

## What is measured

Every cell of 18 units × 5 faction rows × {ready, acted} × ten grounds × {no wash, move, fire,
threat, fog} at board resolution, plus the same figures at the cut-in's resolution — **9,900
composites**, stacked in battle.tscn's own node order: terrain, the wash over it, the unit over
that, the fog shroud over everything. One ramp step is **0.1543 luminance**, measured off the
shipped units atlas.

A ground is measured on **every tile its family can draw** where its own kind surrounds it, and the
row reports the **worst** of them, named — open water, plains and mountain are three phases each of
their own sheets, everything else on the board is one tile today. So a row is keyed by a tile rather
than by a terrain: the
`variant` column beside `terrain` in `cells.csv` and in the `terrain/variant` table names it (a
phase index, a connection mask, or `atlas` for a base-atlas cell), and `--dump` takes it as its
sixth field. Which variants exist is asked of `TerrainAutotiles` by walking a probe cell along a row
of its terrain, so a family that gains phases is measured through them without this harness learning
its name.

## The headline

**Clear class: 8,100 cells, 1,276 failing (15.8%) at two ramp steps** — down from 4,082 (50.4%).
783 of those failures (61.4%) are 20 or more apart in hue — value-blind rather than illegible —
which leaves **493 doubly blind** and **2 severe on both** (under half the bar *and* under 20 hue).

**Fog class, reported separately: 1,800 cells, 118 failing (6.6%) at one ramp step**, 101 of them
doubly blind.

| class | previous (`30c1e97`) | shipped (`0d87068`) |
| --- | --- | --- |
| clear, failing | 4,082 (50.4%) | **1,276 (15.8%)** |
| clear, doubly blind | 963 | **493** |
| clear, severe on both | 151 | **2** |
| fog, failing at 1.0 | 512 (28.4%) | **118 (6.6%)** |
| fog, doubly blind | 251 | **101** |

**9,528 of the 9,900 rows moved. 3,200 cells crossed from fail to pass and none crossed the other
way** — the first round of this instrument with zero regressions, and the round that finally
cleared the previous page's own two open findings (the APC, finding 3; the lander, finding 4).

| view | median edge steps | failing |
| --- | --- | --- |
| board | 1.89 → **2.61** | 56.2% → **17.2%** |
| cutin | 3.02 → 3.03 | 4.0% → 4.0% |

(clear class; previous → shipped. The cut-in is unmoved to the cell: 36 failures before and after —
at 64 px nothing was ever unsampled, so the fix has nothing to buy there. What it *costs* there is
finding 4.)

| ground | median edge steps | failing | doubly blind |
| --- | --- | --- | --- |
| shoal | 2.28 → **3.22** | 33.3% → **0.0%** | 122 → 0 |
| plains | 2.20 → **3.21** | 32.9% → **0.0%** | 12 → 0 |
| airport | 2.06 → 3.02 | 46.2% → 7.4% | 45 → 14 |
| port | 2.06 → 3.01 | 46.9% → 4.9% | 53 → 6 |
| mountain | 2.13 → 2.81 | 38.9% → 2.9% | 95 → 12 |
| city | 1.73 → 2.65 | 67.4% → 28.3% | 182 → 144 |
| hq | 1.51 → 2.22 | 79.6% → **46.4%** | 199 → 175 |
| sea | 1.79 → 2.17 | 58.1% → 9.9% | 39 → 4 |
| woods | 1.80 → 2.15 | 75.6% → 23.2% | 52 → 10 |
| base | 1.55 → 2.01 | 83.1% → **49.3%** | 164 → 128 |

(clear board rows, every wash.)

| wash | median edge steps | failing |
| --- | --- | --- |
| move | 1.95 → 2.63 | 53.2% → 13.9% |
| threat | 1.91 → 2.60 | 56.3% → 16.8% |
| none | 1.83 → 2.60 | 59.4% → 22.6% |
| attack | 1.90 → 2.59 | 55.9% → 15.6% |
| fog (bar 1.0) | 1.21 → 1.72 | 28.4% → 6.6% |

(board rows. Fog's rate is at its own bar.)

| faction row | median edge steps | median edge hue | failing |
| --- | --- | --- | --- |
| iron | 1.95 → 2.76 | 51.7 | 52.2% → 15.8% |
| aurora | 1.86 → 2.65 | 53.4 | 56.1% → 21.4% |
| meridian | 1.84 → 2.63 | 52.1 | 56.1% → 21.9% |
| neutral | 1.69 → 2.51 | 45.4 | 65.6% → 22.5% |
| verdant | 1.75 → 2.45 | 42.3 | 66.9% → **31.4%** |

(bare board, no wash.)

| unit | median edge steps | failing | doubly blind |
| --- | --- | --- | --- |
| tank | 2.89 → 3.19 | 8.2% → 2.5% | 1 → 0 |
| anti_air | 1.70 → **3.18** | 72.2% → **0.2%** | 12 → 0 |
| rockets | 2.09 → 3.17 | 43.5% → 3.5% | 32 → 1 |
| md_tank | 1.34 → **3.16** | 78.0% → **0.5%** | 37 → 0 |
| artillery | 2.15 → 3.14 | 32.5% → 0.0% | 3 → 0 |
| recon | 2.84 → 3.12 | 14.2% → 2.5% | 1 → 0 |
| apc | 0.89 → **2.99** | 99.2% → **11.8%** | 58 → 4 |
| lander | 1.84 → **2.79** | 69.8% → **9.8%** | 51 → 1 |
| missiles | 2.36 → 2.67 | 19.8% → 0.5% | 7 → 0 |
| cruiser | 1.93 → 2.54 | 52.5% → 23.5% | 33 → 6 |
| battleship | 2.22 → 2.45 | 30.2% → 12.8% | 21 → 13 |
| b_copter | 1.88 → 2.33 | 57.8% → 27.0% | 57 → 47 |
| sub | 2.13 → 2.30 | 31.5% → 12.8% | 34 → 11 |
| t_copter | 1.97 → 2.28 | 53.8% → 30.8% | 72 → 61 |
| bomber | 1.12 → 2.27 | 96.2% → 32.2% | 151 → 76 |
| infantry | 1.50 → 2.14 | 95.2% → 40.0% | 159 → 86 |
| mech | 1.71 → 2.12 | 78.2% → 37.8% | 110 → 84 |
| fighter | 1.58 → **1.84** | 78.5% → **62.0%** | 124 → 103 |

(clear board rows, every wash, 400 cells each. The sweep's own per-unit table counts the cut-in rows
too, which is why it reads the APC at 10.9% and the lander at 9.1%.)

## Findings

1. **The APC is answered, and it was the point of the round.** 99.2% → 11.8% failing, median 0.89 →
   2.99 steps. Its flagship cell — the neutral APC on plains, which the previous page recorded at
   **0.05 edge steps** before *and* after round 9's fix — now reads **3.46**. The previous page's
   diagnosis was that the outline was the right kind of pixel and the wrong value; the real answer
   was that at board scale three of its four pixels were never sampled at all.
2. **The lander regression is gone, and no unit regressed to replace it.** The lander goes 69.8% →
   9.8% and its worst cell (a meridian lander greyed out on a city, 1.39 steps) now reads 3.42.
   Across all 9,900 rows, **3,200 crossed to pass and zero crossed to fail** — every previous round
   of this instrument traded some cells for others.
3. **Five units are now effectively solved and two grounds are perfect.** Anti-air, md_tank,
   artillery, missiles and rockets all sit at or under 3.5% failing with zero or one doubly-blind
   cell; plains and shoal fail nothing at all, and sea, port, airport, mountain and woods are all
   under 10%. The whole remaining problem is one shape of cell.
4. **The band is real weight, and the cut-in is where it is paid.** The sweep cannot see this — the
   cut-in reads 36 failures before and after, because a thicker contour can only ever help a
   figure-vs-ground reading. Measured off the sprites instead: the silhouette is unchanged to the
   pixel (the halo did not grow), but **6.2% to 17.2% of every figure's interior was darkened into
   contour** — battleship 6.2%, md_tank 9.3%, APC 10.0%, mech 14.1%, and the **infantry worst at
   17.2%**, because a 4 px band is a large share of a 681 px figure. At board scale that is
   invisible and good. At cut-in scale the smallest figures read heavier — closer to inked than to
   crisp — which is finding 4's whole content and the one thing a human should look at before this
   is called finished. It is a *judgement*, not a defect the sweep found: see the pair below.
5. **What is left is grey aircraft on grey masonry, and it is the previous page's finding 5
   unchanged.** Base (49.3%), HQ (46.4%) and city (28.3%) hold nearly every survivor; the fighter
   (62.0%), infantry (40.0%), mech (37.8%), t_copter (30.8%) and bomber (32.2%) hold nearly every
   unit-side one. The gallery is twenty cells of exactly that pairing. A contour weight cannot fix
   it: the outline is dark and the roof is dark, so the figure is separated from the grass and not
   from the building. That is a property-column value question, and it is the next round's.
6. **Fog is close to free now.** At its own one-step bar the shroud fails 6.6% of its cells, down
   from 28.4%. What survives the wash is contour, and there is now four times as much of it.
7. **Verdant is still the weakest livery** (31.4% on the bare board against iron's 15.8%) and the
   gap is still hue: green figures on green ground. The contour narrowed it — verdant was 66.9% —
   without answering it, because the contour is not the livery.

## The gallery

`make legibility-check` redraws this sheet: the twenty cells with the least margin on the **further**
of the two readings, each magnified to one tile and labelled with its unit, faction, ground, wash,
state, view, both edge numbers and both median ones.

![the twenty worst-scoring composites](images/legibility_worst20.png)

**No APC appears on it** — the previous page's sheet held four. It is now twelve fighters, five
bombers and three t_copters, one of them fogged and nothing else on it: aircraft parked on an HQ or
a base, every hue under 11, which is the doubly-blind class the `max` sort exists to surface. Read
it with finding 5.

## Spot checks

Three composites read by eye, each dumped by the harness itself
(`make legibility-check LEGIBILITY="--dump=board:apc:neutral:ready:plains:atlas:none"`), which
prints both readings beside the crop.

The round's headline, at the cell two previous rounds could not move: a neutral APC on plains,
**0.05 → 3.46 edge steps**. Nothing about the model changed; the outline is simply thick enough to
survive the board's one-in-four sample:

![neutral APC on plains](images/legibility_r10_apc_neutral_plains.png)

The previous page's regression, answered: a meridian lander on a city, greyed out, **1.39 → 3.42**:

![meridian lander on a city](images/legibility_r10_lander_meridian_city.png)

What is left, at its worst: a verdant fighter on an HQ, **1.02 edge steps at 3.6 hue** — dark grey
airframe on dark grey masonry, blind on both readings, and untouched by anything a contour can do:

![verdant fighter on an HQ](images/legibility_r10_fighter_verdant_hq.png)

## The cost, at cut-in scale

Finding 4 as a picture rather than a percentage: the same verdant infantry in the cut-in's own
resolution, previous sheet then shipped. The silhouette is identical; the band has taken the left
shoulder and squeezed the helmet's lit face to a sliver. This is the roster's smallest figure and so
its heaviest case.

![verdant infantry, previous sheet](images/legibility_r10_cutin_infantry_before.png)
![verdant infantry, shipped sheet](images/legibility_r10_cutin_infantry_after.png)

The generator measured a 4-px-on-every-edge variant as better still on the board (12.8% clear
against this one's 15.8%) and did not ship it, for this reason. Whether even the shipped band is too
much for the cut-in is a human call on the frames, not something this sweep can answer — it reads
figure against ground, and more ink always wins that reading.

## Re-read 2026-09-02, after S6 grew the move clip to four frames

The frame axis gained two rows: `walk_c` / `walk_d`
(`units_atlas_move_c.png` / `_move_d.png`), the gait's third and fourth key since the
animation-frames plan's S6. **`walk_a` and `walk_b` reproduce their own previous reading to the
digit** — 55.5% / 55.6% clear failing, 34.4% / 40.3% fogged, the exact numbers the 2026-09-01
section above tabulates — which is the art's own claim checked rather than assumed: S6 states that
neither sheet moved a pixel (every family's MOVE_A/MOVE_B stays the shipped art, the new gait and
tread content living on MOVE_C/MOVE_D alone), and the ruler agrees to four significant figures.

| frame | clear cells | failing | % | fogged cells | fogged failing | % |
| --- | --- | --- | --- | --- | --- | --- |
| board `idle_a` | 8,640 | 4,121 | 47.7% | 2,160 | 613 | 28.4% |
| board `idle_b` | 8,640 | 4,443 | 51.4% | 2,160 | 696 | 32.2% |
| board `walk_a` | 8,640 | 4,791 | 55.5% | 2,160 | 742 | 34.4% |
| board `walk_b` | 8,640 | 4,800 | 55.6% | 2,160 | 870 | 40.3% |
| board `walk_c` | 8,640 | 4,390 | **50.8%** | 2,160 | 679 | **31.4%** |
| board `walk_d` | 8,640 | 4,739 | **54.8%** | 2,160 | 826 | **38.2%** |
| cutin `idle_a` | 1,080 | 56 | 5.2% | — | — | — |
| cutin `idle_b` | 1,080 | 36 | 3.3% | — | — | — |

Board and cut-in are separate views on separate sheets and each row is one of them, as in the
2026-09-01 table above: the six board rows reproduce that section's figures to the digit, and the
cut-in carries no fogged reading because fog is a board overlay. The whole-run lines below are the
two views added together.

Whole run: clear 54,000 cells, 27,376 failing (50.7%), 18,880 hue-carried (69.0%); fogged 12,960
cells, 4,426 failing (34.2%), 887 hue-carried (20.0%) — both a shade under the S8 control's own
52.5%/33.8% board-plus-cutin figures, `walk_c` and `walk_d` landing a little easier than `walk_a`/
`walk_b` rather than a little harder. Nothing was tuned to buy that; it is the two new gait keys'
own geometry (the tracked family's quarter-phase tread step and the two copters' further rotor
tick move less of a unit's silhouette per frame than the parked-to-walking beat does) read through
the same contour S8 shipped.

**The ratchet is clean by construction, not by exception.** Every builder in the diff moved MOVE_C
and MOVE_D only — `parts._tread_phase` holds MOVE_A/MOVE_B at the exact quarter-positions they
always stood at, `foot.mech`'s scissor keeps its shipped `swing=1`/`swing=6` pair unmoved, and the
two jets' and four hulls' MOVE_C/MOVE_D interpolate rather than author — so `make legibility-ratchet`
against the pre-S6 baseline read **0 regressed, 0 recovered**, and the only diff was `walk_c`'s and
`walk_d`'s combined 21,600 cells (their clear-plus-fogged totals above, 8,640 + 2,160 each), named
"not in the baseline" rather than judged, exactly as the plan's S8 precedent states. The baseline
was re-baked once after, `tests/fixtures/legibility_baseline.csv` now 66,960 rows, and
`make legibility-ratchet` reads clean against it (0 regressed / 0 recovered / 0 added / 0 missing).
`docs/images/legibility_worst20.png` was redrawn with the re-bake; sixteen of its twenty are now
`walk_b`/`walk_d` pairs on `cruiser` and `fighter` against mountain and the other four are `walk_a`
`mech` under fog, the same pale-airframe-and-hull and fogged-transport classes every previous
worst-twenty has read — `walk_d` inheriting `walk_b`'s own worst cells rather than opening new ones,
and no `walk_c` cell placing at all.

**One `walk_d` correction since, same day.** Review found the rocket trooper's `gather=2` passing
step had moved its whole shin as one block, leaving each boot two voxels along both axes from its
own knee plate — a leg touching the figure at a corner and nothing else, which no gate then read
(`foot._mech_legs`, now bridged by a joint voxel; `generators/sprites/tests/test_board_read.py`
`BoardScaleEdge.test_no_foot_figure_walks_out_of_its_own_legs` is where a boot that comes off the
figure fails from here on). `units_atlas_move_d.png` is the only sheet it moved, and only the mech
column's six cells of it, and every table above still stands: the ratchet reads **0 regressed /
0 recovered / 0 added / 0 missing** against the re-baked baseline, so no cell changed verdict and
no frame's percentage moved. The mech's own gait readings are unchanged too — the
`MOVE_C`-to-`MOVE_D` step measures the same 13 changed / 6 silhouette rung-1 texels it did
before the bridge.

## What the grounds are

Each terrain is measured as the art the board draws for it when its four neighbours are the same
terrain — asked of `TerrainAutotiles`, never picked by hand. That is the base atlas cell for the
five properties and the reef, a wood inside a wood (its full-bleed canopy), the shoal sheet's mask-0
cell for a beach, and a phase of its own sheet for open water, plains and mountain — the phase the
board itself draws at the probe's own cell.

A property's column is a transparent overlay, so its cell is composed over `TerrainDB.ground()`
exactly as `BattleView`'s two layers compose it. A wood's *fringe*, a coastline, a road, a river
and a bridge draw from their own sheets and are still not in this sweep: they are edges rather than
fields, and a unit standing on one is standing on a tile the sweep's field-of-its-own-kind probe
cannot state. Widening to them supersedes this page.
