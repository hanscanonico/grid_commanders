# Causeway's match-length measurement, v2 — 2026-08-16

A dated measurement. A later campaign supersedes this document **wholesale**
rather than editing it, the convention `docs/bulwark_balance.md` and
`docs/ai_arena_results.md` already keep. **This is v2 and it supersedes v1
(2026-08-16, the tier sweep) whole**; v1's tier table is reprinted below because
it is the baseline story this one is read against.

**The question.** Two all-computer four-army matches on `maps/causeway.txt`,
spectated at **Normal**, ran **144 days** (decided) and **158 days** (still
undecided when the watcher gave up). v1 asked whether that was the *tier* and
answered no: no tier decides a Causeway free-for-all at all. This v2 asks the
next question — **do the planner dials that ship inert close it?** — and sweeps
seven candidate vectors over the two groupings.

**The answer, in one line.** Nothing moves the **free-for-all**: every one of
the seven vectors decides **0 of 8**, exactly as every tier did. One vector moves
the **2v2** a lot: `capture_units_per_property` + `goal_engageability` +
`spend_ceiling_turns` together take `1+3v2+4` from **1 of 8 to 5 of 8 decided**
at no extra planner cost. That vector is the recommendation below, and **nothing
was seated** — this document recommends, a follow-up ships (arena D8).

## Method

The instrument is `tools/run_bulwark_measure.gd` (`make board-measure`), the same
one v1 used, measured at repo SHA **`a7348f0`** ("Aim, price and settle the
planner with three inert dials", #295) — the commit that put the last three
candidate dials in the tree.

It plays `test_alliance_soak.gd::_soak`'s loop — `GameState.create`, `state.sides`
set directly, one `AIController` per army — and **seats no commander**: every army
plans through `CommanderType.neutral()`, so `doctrine_weight` is inert and none of
these numbers speaks for a match with generals on the seats. Fog is off on every
seed.

A candidate vector is applied by editing `data/ai/default.tres` in a worktree —
the tool resolves `--tier=normal` through that file — and the file is restored
before the next cell. **The committed diff of this work is this document and
nothing else**: no `ai/`, `core/`, `data/`, `scenes/` or `tools/` change. Runs
land under `reports/`, which is gitignored.

Every cell is **8 seeds (1–8) at a 160-day horizon**, the same shape as v1:

```sh
make board-measure BOARD="--map=causeway --grouping=ffa     --tier=normal --seeds=8 --days=160 --out=reports/sweep_V<n>"
make board-measure BOARD="--map=causeway --grouping=1+3v2+4 --tier=normal --seeds=8 --days=160 --out=reports/duel_V<n>"
```

**8 seeds per cell is a direction, not a magnitude**, the convention
`docs/difficulty_check.md` §4b keeps.

### The ladder

Progressive, so each increment's marginal effect is readable. Everything not
named is the shipped Normal value.

| Cell | Vector (deltas from shipped `data/ai/default.tres`) |
|---|---|
| V0 | baseline, nothing changed |
| V1 | `capture_units_per_property = 0.15` |
| V2 | `goal_engageability = 1.0` |
| V3 | V1 + V2 |
| V4 | V3 + `spend_ceiling_turns = 3.0` |
| V5 | V4 + `build_priority` reordered land-first (`hard.tres`'s list verbatim) |
| V6 | V4 + `capture_threat_aversion = 0.5` |

`capture_units_per_property = 0.15` is not a small edit on this board: Causeway
holds **44 property cells** (4 HQ, 8 base, 8 port, 24 city) and each army opens
owning 8, so a free-for-all army sees 36 unowned and its capture roster goes
`max(3, ceil(0.15 × 36)) = 6` — double the shipped floor, self-damping as the
map fills (AI Economy D5).

`capture_threat_aversion` is the fourth reader of the one `ThreatMap` and AI
Judgement R3 says tune that family together. On **Normal** the other three
(`threat_aversion`, `advance_threat_tiles`, `withdraw_weight`) are all `0.0`, so
V6 raises no double-pricing question *here*; it would on Hard, where two of them
are live.

## Results — free-for-all: nothing closes it

| Cell | decided | decided_pct | mean_day | median_day | mean commands/match |
|---|---|---|---|---|---|
| V0 baseline | 0 / 8 | **0.0%** | — | — | 11,067 |
| V1 | 0 / 8 | 0.0% | — | — | 11,410 |
| V2 | 0 / 8 | 0.0% | — | — | 10,364 |
| V3 | 0 / 8 | 0.0% | — | — | 10,853 |
| V4 | 0 / 8 | 0.0% | — | — | 10,756 |
| V5 | 0 / 8 | 0.0% | — | — | 14,631 |
| V6 | 0 / 8 | 0.0% | — | — | 11,160 |

56 matches, **zero winners**. Zero rejected commands, zero cap-stalls and zero
turn-cap hits in all 56 — the legality half is clean everywhere, so "nobody
wins" is the board and the planner, never the instrument.

**What day 160 looks like.** In 55 of the 56 matches **all four armies are still
alive** at the horizon with nothing eliminated at any point. The single
exception is V3 seed 3, where seat 3 falls and the other three are still going —
the only army any of these vectors managed to kill in a free-for-all, against
none at baseline. Attrition happens (the matches issue 8.5–15.3k commands each;
nothing is idle) but it never compounds: four mutually hostile armies on four
corner islands trade across the causeways for 160 days and no army's board ever
collapses.

The V0 row is a fresh 8-seed run rather than v1's cell copied across, and it
reproduces v1's Normal free-for-all exactly: 0 / 8, 11,067 commands per match.

For scale, the command ceiling for this horizon is 193,844 (`301 × 4 × 161`) and
the busiest free-for-all match used 15,301 — nothing is near a cap.

## Results — 1+3v2+4: the vector that works

Same seeds, same horizon, the grouping the board's own header names as the fair
pairing and the one the user played.

| Cell | decided | decided_pct | mean_day | median_day | mean commands/match | sides |
|---|---|---|---|---|---|---|
| V0 baseline | 1 / 8 | 12.5% | 101.0 | 101.0 | 10,619 | 2+4 ×1 |
| V3 | 3 / 8 | 37.5% | 102.0 | 97.0 | 9,517 | 1+3 ×1, 2+4 ×2 |
| **V4** | **5 / 8** | **62.5%** | 109.2 | 107.0 | **7,962** | 1+3 ×2, 2+4 ×3 |
| V5 | 1 / 8 | 12.5% | 113.0 | 113.0 | 14,155 | 1+3 ×1 |

`mean_day` / `median_day` are over the **decided** matches only; V0's and V5's
are one match each and are printed for completeness, not as averages.

The V0 row was re-measured here rather than copied from v1, and it reproduces
v1's row exactly — seed 8, side 2+4, day 101 — which is also the check that the
six dials shipped since v1 really are inert.

Every decided match, in full:

| Cell | Seed | Winning side | Day | Seats eliminated (in order) |
|---|---|---|---|---|
| V0 | 8 | 2+4 | 101 | 1, 3 |
| V3 | 4 | 2+4 | 142 | 3, 1 |
| V3 | 5 | 2+4 | 67 | 3, 1 |
| V3 | 8 | 1+3 | 97 | 4, 2 |
| V4 | 1 | 2+4 | 107 | 3, 1 |
| V4 | 2 | 2+4 | 138 | 1, 3 |
| V4 | 5 | 2+4 | 134 | 3, 1 |
| V4 | 6 | 1+3 | 66 | 2, 4 |
| V4 | 8 | 1+3 | 101 | 4, 2 |
| V5 | 4 | 1+3 | 113 | 4, 2 |

Side spread over V4's five: **2+4 three, 1+3 two.** At n = 5 that says only that
neither pairing is obviously favoured, which is what the board claims — it is
identical under a half turn and both mirror axes, so all four corner seats are
congruent. Nothing here is evidence of a seat bias and nothing here would detect
one.

**V5 is a refutation, and a useful one.** Reordering Normal's navy-heavy
`build_priority` to Hard's land-first list was the most intuitive candidate in
the ladder — and it is the only cell that made the 2v2 *worse* (5/8 back to 1/8)
while costing **+46% commands per match** against V4 across each cell's own
undecided matches (V5's seven at 14,878, V4's three at 10,192; on the two seeds
undecided in both, 14,682 against 10,460, +40%). Causeway is a board where
the sea is one connected body every port opens onto; deprioritising hulls on it
buys nothing and starves the crossings. Do not carry that idea into the seating
task.

V6 (`capture_threat_aversion = 0.5` on top of V4) was measured on the free-for-all
only, where it changed nothing; it was not carried to the 2v2, because there was
no free-for-all signal to justify a fourth 2v2 cell and the 2v2 ladder was already
answering. That is the one thing this sweep did not finish and it is named as such.

### Cost

Roughly 6 minutes of wall clock per 8-seed free-for-all cell on a loaded 8-core
machine, one cell at a time; the whole campaign (7 free-for-all cells + 4 2v2
cells + two single-seed spot checks, 90 matches) took a little over two hours
of wall clock, sharing the machine. V5 is the expensive vector for
the reason above; **V4 is cheaper than baseline** in the 2v2 (7,962 against
10,619 commands per match) simply because its matches end.

### Reproducibility

Seeds are the runner's own (`seed = --seed-offset + i + 1`), so every row is
reproducible by re-running its command line. Two spot checks were taken:

- Baseline free-for-all seed 1 re-run alone: identical row (undecided, 9,820
  commands).
- **The headline cell, V4 / `1+3v2+4` / seed 1, re-run alone: identical row —
  side 2+4, day 107, 6,491 commands.**

## Recommendation

**Seat V4 on Normal:**

```
capture_units_per_property = 0.15
goal_engageability         = 1.0
spend_ceiling_turns        = 3.0
```

**What it buys.** On Causeway's 2v2, decided matches go **1/8 → 5/8** (12.5% →
62.5%), with a median decided length of 107 days. Against the two live matches
this whole investigation started from (144 days decided, 158 abandoned), that is
the difference between a board that occasionally resolves and one that usually
does.

**What it costs.** Nothing measurable in planner work: **7,962 commands per 2v2
match against baseline's 10,619**, and 10,756 against 11,067 in the undecided
free-for-all. This is not Brutal's 1.8×-for-nothing trade — the vector is
cheaper because it finishes.

**What it does not buy.** The free-for-all, at all: 0/8 before and 0/8 after, and
that stays an open capability question rather than a dial to find. Four mutually
hostile armies on this board do not get through each other in 160 days and no
vector in this ladder changed that. A player who wants a Causeway match to end
should be playing the 2v2, which is also the pairing the board's header
recommends.

**What this measurement does NOT answer, and the seating task must:**

- **Both balance reports.** `make commander-balance` and `make difficulty-check`
  are duel instruments over other boards, and all three dials are live code paths
  once non-zero — the merge bar for moving a Normal number is those two reports,
  read and recorded, not this document.
- **The DF4 ladder.** Its acceptance gate is already failing knowingly (68.3% /
  53.3% against 70%) and BL2 owns Normal's numbers. Making Normal better on one
  board can move the `easy → normal → hard` spread in either direction.
- **Commanders.** This instrument seats none, so `doctrine_weight` never fired
  and every doctrine hook — `build_bias` most of all, which reaches the same
  production tier `spend_ceiling_turns` and the capture roster do — is unmeasured
  here.
- **Other boards.** One board, one grouping's worth of signal. A roster dial that
  helps a 44-property island chain is not thereby right on a 12-property duel map.
- **Which of the three dials is carrying it.** V1 and V2 alone are 0/8 on the
  free-for-all and were not run on the 2v2 individually; the readable increments
  are V3 (both capture dials, 3/8) and V4 (+ the spend ceiling, 5/8). If the
  seating task wants a two-dial vector it should measure V1-only and V2-only on
  `1+3v2+4` first.

Whichever way that goes, **this document is the before-picture** and the command
lines above are the after-picture. Re-run at a wider seed count before reading
any single-digit change as a result.
