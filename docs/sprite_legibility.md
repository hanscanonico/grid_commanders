# Composite legibility — 2026-08-18

What the sweep found the first time it was run, at `81039c9` (the indexed-palette and
value-ceiling atlases). A dated measurement: a later run supersedes this page wholesale
rather than editing it, the way `docs/bulwark_balance.md` and `docs/replay_survey.md` are
superseded.

**Nothing was tuned in response to it.** Every failing cell below is a finding for the art
to answer; the instrument exists so that answer can be measured rather than argued.

Re-run with `make legibility-check`. It reads the shipped atlases and the shipped
constants, plays no match, takes about 13 seconds, and writes `cells.csv` and `summary.md`
under `reports/` (gitignored).

## What is measured

Every cell of 18 units × 5 faction rows × {ready, acted} × {plains, woods, sea, mountain,
shoal} × {no wash, move, fire, threat, fog} at board resolution, plus the same figures at
the cut-in's resolution — 4,950 composites. Each is stacked in battle.tscn's own node
order: terrain, the wash over it, the unit over that, the fog shroud over everything.

**Separation** is the median luminance of the figure's pixels minus the median luminance
of the ground plate under it, in **ramp steps**. One ramp step is the gap between two
neighbouring slots of a faction ramp, measured off the shipped units atlas rather than
restated: **0.1462 luminance**. The bar is the design spec's, **≥ 2 ramp steps**.

Three things to know before reading a number:

- The metric is **value only**. That is deliberate — the atlases' own contract is a value
  ceiling holding terrain under the units' band — but it means a figure rescued by hue
  alone (aurora blue on green) reads as a failure here. Where that is the whole story, the
  crop says so and the finding is "this is carried by hue", not "this is fine".
- The ground is the **whole tile**, not the pixels the silhouette leaves showing. On the
  mountain tile that is mostly the grass plate around the peak, so a figure standing on
  the peak itself is measured against a slightly kinder ground than it stands on.
- The board reading samples one texel per screen pixel (nearest filtering, as the project
  is configured), so a unit's board median is not its cut-in median: the downsample keeps
  a fixed quarter of the art.

## The headline

**3,231 of 4,950 cells (65.3%) are under two ramp steps.** The population median is
**1.90 steps on a bare board cell** — the bar sits almost exactly at the middle of the
shipped roster, so the reading is "half the army is at or below two steps", not "the art
is broken".

| ground | median steps (board) | ground luminance | failing |
| --- | --- | --- | --- |
| shoal | 2.28 | 0.650 | 40.6% |
| plains | 2.13 | 0.618 | 47.8% |
| mountain | 2.07 | 0.612 | 50.1% |
| sea | 0.98 | 0.400 | 92.4% |
| woods | 0.56 | 0.317 | 95.5% |

| wash | median steps | failing |
| --- | --- | --- |
| none | 1.90 | 60.1% |
| move | 1.80 | 56.3% |
| attack | 1.67 | 60.0% |
| threat | 1.65 | 62.6% |
| fog | 1.25 | 89.9% |

| faction row | median steps (bare board) | failing |
| --- | --- | --- |
| iron | 2.30 | 52.7% |
| aurora | 2.25 | 60.0% |
| meridian | 2.13 | 62.5% |
| verdant | 1.91 | 70.8% |
| neutral | 1.54 | 80.3% |

## Findings

1. **Woods and sea are where the roster disappears.** 95.5% and 92.4% of their cells fail,
   and both are dark plates (0.317 and 0.400) sitting inside the band the figures are
   painted in — the value ceiling holds terrain *under* the units, and on these two it
   holds it under by less than two steps for most of the roster. Round 5's
   verdant-on-woods suspect is confirmed and is the worst pair in the sweep: **every one
   of the 50 board cells of a verdant bomber fails** (worst 1.91 steps, median 1.00), and
   its ten woods cells run 0.00 to 0.76.
2. **The bomber is the worst airframe** — 269 of its 275 cells fail (97.8%), against the
   submarine's 52 (18.9%) and the battleship's 89 (32.4%). Its silhouette is large and
   flat, so its median is its body colour with almost no outline or highlight to lift it.
3. **Iron on mountain is real, and it is the peak rather than the tile.** An iron APC on
   mountain reads 0.71 steps — grey plate under grey hull. It is a per-unit split rather
   than a faction one: the iron tank and recon clear the same ground at 2.87, so what
   fails is the light-bodied iron vehicles (APC, lander), not the row.
4. **Fog costs about 0.65 steps across the board** (median 1.90 → 1.25) and takes the
   failure rate to 89.9%. It sits *above* the units, so it compresses figure and ground
   together — a cell that was marginal in the clear is a cell nobody can read in fog.
5. **The three washes cost 0.10–0.25 steps each** and never rescue a cell: they land under
   the figure, so they can only move the ground, and they move it towards the middle.
6. **The neutral row is the weakest livery** (median 1.54, 80.3% failing). Its khaki sits
   between the two ends of every terrain's own value range, which is exactly the position
   with nowhere to separate to.
7. **Three unit/faction pairs fail every single board cell**: neutral APC, neutral bomber,
   verdant bomber.
8. **The cut-in is slightly worse than the board** (72.0% against 64.6%), which is the
   sampling note above rather than a second defect: the blown-up figure shows all its
   texels, including the dark ones the board's downsample skips.

## Spot check

The metric was read against two composites by eye, both dumped by the harness itself
(`make legibility-check LEGIBILITY="--dump=board:tank:verdant:ready:woods:none"`).

Known-good, **3.73 steps** — an iron battleship on shoal. The hull separates from the sand
at a glance:

![iron battleship on shoal](images/legibility_pass_battleship_iron_shoal.png)

Known-bad, **0.76 steps** — a verdant bomber on woods canopy. The airframe is present in
the tile and cannot be found in it:

![verdant bomber on woods](images/legibility_fail_bomber_verdant_woods.png)

The two agree with the numbers, which is what the bar was checked against.

## What the grounds are

Each terrain is measured as the art the board draws for it when its four neighbours are
the same terrain — asked of `TerrainAutotiles`, never picked by hand. That is the base
atlas cell for plains, mountain, open water and a wood inside a wood (its full-bleed
canopy), and the shoal sheet's mask-0 cell for a beach. A wood's *fringe* and a coastline
draw from their own sheets and are not in this sweep; a later run that widens the grounds
supersedes this one.
