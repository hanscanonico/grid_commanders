# Composite legibility — 2026-08-18 (property overlays)

What the sweep finds on the sheets shipped by generator `e26154e` — the r5 unit polish, the
river's shore, and the five property columns as transparent overlays. A dated measurement:
it supersedes the previous page (taken at `81039c9`) wholesale rather than editing it, the
way `docs/bulwark_balance.md` and `docs/replay_survey.md` are superseded.

**Nothing was tuned in response to it.** Every failing cell below is a finding for the art
to answer; the instrument exists so that answer can be measured rather than argued.

Re-run with `make legibility-check`. It reads the shipped atlases and the shipped
constants, plays no match, takes about 15 seconds, and writes `cells.csv` and `summary.md`
under `reports/` (gitignored).

## What is measured

Every cell of 18 units × 5 faction rows × {ready, acted} × {plains, woods, sea, mountain,
shoal} × {no wash, move, fire, threat, fog} at board resolution, plus the same figures at
the cut-in's resolution — 4,950 composites. Each is stacked in battle.tscn's own node
order: terrain, the wash over it, the unit over that, the fog shroud over everything.

**Separation** is the median luminance of the figure's pixels minus the median luminance
of the ground plate under it, in **ramp steps**. One ramp step is the gap between two
neighbouring slots of a faction ramp, measured off the shipped units atlas rather than
restated: **0.1543 luminance** — it was 0.1462 on the previous sheets, and that move is
half the story of this page (see the headline).

Four things to know before reading a number:

- The metric is **value only**. That is deliberate — the atlases' own contract is a value
  ceiling holding terrain under the units' band — but it means a figure rescued by hue
  alone (aurora blue on green) reads as a failure here. Where that is the whole story, the
  crop says so and the finding is "this is carried by hue", not "this is fine".
- The ground is the **whole tile**, not the pixels the silhouette leaves showing. On the
  mountain tile that is mostly the grass plate around the peak, so a figure standing on
  the peak itself is measured against a slightly kinder ground than it stands on.
- The figures are the **ambient frame A** atlas. The board beats between two
  frames, and frame B is not in this sweep — a run that adds it supersedes this page rather
  than extending it.
- The board reading samples one texel per screen pixel (nearest filtering, as the project
  is configured), so a unit's board median is not its cut-in median: the downsample keeps
  a fixed quarter of the art.

## The headline

**3,383 of 4,950 cells (68.3%) are under two ramp steps**, against 3,231 (65.3%) last
time. The population median is **1.80 steps on a bare board cell**, down from 1.90.

**The roster did not get darker — the ruler got longer.** The unit polish let every unit
claim the bright band the terrain ceiling reserves for it, which widened the faction ramps,
and a ramp step is measured off those ramps: 0.1462 → 0.1543 luminance, +5.5%. A figure
whose absolute separation is unchanged therefore reads about 5% fewer steps, and the cells
that were sitting on the bar fell off it. Read this page against its own ruler and the
previous page against its own; the two headline percentages are not directly comparable,
and the *ordering* below — which grounds, which liveries, which units — is what carries
across.

| ground | median steps (board) | ground luminance | failing |
| --- | --- | --- | --- |
| shoal | 2.13 | 0.650 | 43.2% |
| plains | 2.00 | 0.618 | 49.8% |
| mountain | 1.96 | 0.612 | 52.3% |
| sea | 0.92 | 0.400 | 93.4% |
| woods | 0.53 | 0.317 | 99.8% |

| wash | median steps | failing |
| --- | --- | --- |
| none | 1.80 | 56.2% |
| move | 1.70 | 60.8% |
| attack | 1.59 | 64.7% |
| threat | 1.57 | 64.7% |
| fog | 1.19 | 92.2% |

| faction row | median steps (bare board) | failing |
| --- | --- | --- |
| iron | 2.16 | 57.2% |
| aurora | 2.07 | 63.4% |
| meridian | 2.02 | 65.9% |
| verdant | 1.81 | 73.6% |
| neutral | 1.41 | 81.6% |

## Findings

1. **Woods and sea are still where the roster disappears, and woods is now total.** 99.8%
   of woods cells and 93.4% of sea cells fail — woods was 95.5%. Both are dark plates
   (0.317 and 0.400) sitting inside the band the figures are painted in, and the wider
   ramp moved the handful of woods cells that were clearing the bar under it. The
   verdant-bomber-on-woods pair is again the worst in the sweep: its ten board cells run
   **0.00 to 0.72 steps**.
2. **The bomber is the worst airframe** — 272 of its 275 cells fail (98.9%), against the
   submarine's 63 (22.9%) and the battleship's 100 (36.4%). Its silhouette is large and
   flat, so its median is its body colour with almost no outline or highlight to lift it.
   The submarine is the roster's best-separated unit for the same reason read backwards:
   it is small and dark against water it is not the value of.
3. **Iron on mountain is a per-unit split, not a faction one.** A ready iron APC on
   mountain reads **0.67 steps** — grey plate under grey hull — while the iron tank and
   recon clear the same ground at **2.72**. What fails is the light-bodied iron vehicles
   (APC, lander), not the row: iron is still the *best* livery overall (57.2% failing).
4. **Fog costs about 0.6 steps and takes the failure rate to 92.2%.** It sits *above* the
   units, so it compresses figure and ground together — a cell that was marginal in the
   clear is a cell nobody can read in fog.
5. **The three board washes cost 0.10–0.23 steps each and never rescue a cell**: they land
   under the figure, so they can only move the ground, and they move it towards the middle.
   Every wash row above is a board reading, the bare board included — the cut-in view is
   overlay-free by construction and belongs to finding 8, not to this table.
6. **The neutral row is the weakest livery** (median 1.41, 81.6% failing). Its khaki sits
   between the two ends of every terrain's own value range, which is exactly the position
   with nowhere to separate to.
7. **Three unit/faction pairs fail every single board cell**: neutral APC (worst 1.75,
   median 0.61), neutral bomber (worst 1.75, median 0.61) and verdant bomber (worst 1.81,
   median 0.95) — the same three as last time, so the polish moved none of them off the
   list.
8. **The cut-in is slightly worse than the board** (74.7% against 67.7%), which is the
   sampling note above rather than a second defect: the blown-up figure shows all its
   texels, including the dark ones the board's downsample skips.

## Spot check

The metric was read against two composites by eye, both dumped by the harness itself
(`make legibility-check LEGIBILITY="--dump=board:bomber:verdant:ready:woods:none"`).

Known-good, **3.54 steps** — an iron battleship on shoal. The hull separates from the sand
at a glance:

![iron battleship on shoal](images/legibility_pass_battleship_iron_shoal.png)

Known-bad, **0.72 steps** — a verdant bomber on woods canopy. The airframe is present in
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

**No property is in the sweep**, and that is a gap rather than a rule: a unit can stand on
a city. `LegibilityArt.board_cell` now composes a property's transparent overlay over
`TerrainDB.ground()` exactly as the board does, so the grounds can be widened without a
second opinion about what is under a building — but widening them supersedes this page.
