# Causeway's match-length measurement — 2026-08-16

A dated measurement. A later campaign supersedes this document **wholesale**
rather than editing it, the convention `docs/bulwark_balance.md` and
`docs/ai_arena_results.md` already keep.

**The question.** Two all-computer four-army matches on `maps/causeway.txt`,
spectated at **Normal**, ran **144 days** (decided) and **158 days** (still
undecided when the watcher gave up). That is two to four times the length of any
duel the Balance Lab reports. The hypothesis this run was written against is
that the length is **the default tier** rather than the board: Hard ships the
whole threat family live (`advance_threat_tiles = 2.0`, `threat_aversion = 0.1`)
and a land-first `build_priority`, where Normal's list leads with
`md_tank, bomber, battleship, fighter, sub, cruiser` — the most navy-heavy of the
tiers — on a board whose four corner islands are joined by bridges.

**The answer is no.** Tier does not close the gap, in either direction, and the
free-for-all does not close at all.

## Method

The instrument is `tools/run_bulwark_measure.gd` (`make board-measure`), as
generalised by PR #289 (`eea940f`, 2026-08-16) to take `--map=`, `--tier=` and a
`--grouping=` in the `--sides=` grammar. Measured at repo SHA
**`0d210e1`** ("Refuse Second Wind when the second action buys nothing", #287).

It plays `test_alliance_soak.gd::_soak`'s loop — `GameState.create`, `state.sides`
set directly, one `AIController` per army — and **seats no commander**: every army
plans through `CommanderType.neutral()`. Fog is off on every seed. So this reads
**board × tier**, not a replay of the two live matches, which *did* seat
commanders; a doctrine on any seat would move these numbers.

Six cells: three tiers × two groupings, **8 seeds each (seeds 1–8), 160-day
horizon** — 48 matches. Both groupings are ones Causeway's seat strip offers: the
free-for-all, and the `1+3v2+4` duel the board's own header names as the fair
opposite-seat pairing (and the one the user played).

```sh
make board-measure BOARD="--map=causeway --tier=normal --grouping=ffa     --seeds=8 --days=160 --out=reports/causeway_normal"
make board-measure BOARD="--map=causeway --tier=normal --grouping=1+3v2+4 --seeds=8 --days=160 --out=reports/causeway_normal"
make board-measure BOARD="--map=causeway --tier=hard   --grouping=ffa     --seeds=8 --days=160 --out=reports/causeway_hard"
make board-measure BOARD="--map=causeway --tier=hard   --grouping=1+3v2+4 --seeds=8 --days=160 --out=reports/causeway_hard"
make board-measure BOARD="--map=causeway --tier=brutal --grouping=ffa     --seeds=8 --days=160 --out=reports/causeway_brutal"
make board-measure BOARD="--map=causeway --tier=brutal --grouping=1+3v2+4 --seeds=8 --days=160 --out=reports/causeway_brutal"
```

The sweep itself ran those six command lines four at a time (the preset expands
to `Godot --headless --path . -s res://tools/run_bulwark_measure.gd -- <flags>`,
and a cell is one process that shares nothing with another).

Everything lands under `reports/` (gitignored); this document is the only
committed artifact and nothing under `ai/`, `core/`, `data/` or `scenes/` moved.
Seeds are the runner's own (`seed = --seed-offset + i + 1`), so the numbers below
are reproducible by re-running any line above — the spot check re-ran Hard /
`1+3v2+4` seed 1 alone and got the identical row (winner side `2+4`, day 111,
7754 commands).

**8 seeds per cell is a direction, not a magnitude**, the convention
`docs/difficulty_check.md` §4b keeps. Nothing was capped silently: the full 6 × 8
× 160 plan ran as written.

## Results

| Tier | Grouping | decided | decided_pct | mean_day | median_day | undecided |
|---|---|---|---|---|---|---|
| Normal | free-for-all | 0 / 8 | **0.0%** | — | — | 8 |
| Hard | free-for-all | 0 / 8 | **0.0%** | — | — | 8 |
| Brutal | free-for-all | 0 / 8 | **0.0%** | — | — | 8 |
| Normal | 1+3v2+4 | 1 / 8 | **12.5%** | 101.0 | 101.0 | 7 |
| Hard | 1+3v2+4 | 3 / 8 | **37.5%** | 94.3 | 106.0 | 5 |
| Brutal | 1+3v2+4 | 1 / 8 | **12.5%** | 148.0 | 148.0 | 7 |

`mean_day` and `median_day` are over the **decided** matches only — an undecided
match has no length, only a horizon it outlived — so the Normal and Brutal 2v2
figures are each one match and are printed for completeness, not as averages.

**Zero rejected commands, zero cap-stalls and zero turn-cap hits in all 48
matches**, at all three tiers and in both groupings. The board and all four
planners never disagreed, no match looped, and no turn was cut short — the
legality half of the reading is clean, and the staleness below is genuinely
"nobody wins", never "the instrument broke". The command ceiling for this
horizon is 193,844 (`301 × 4 × 161`); the busiest match used 20,964.

### Free-for-all — nothing resolves at any tier

24 matches, 0 winners. Only **one** of the 24 saw any army fall at all (Hard,
seed 7: seats 4 then 2 eliminated, and the two survivors were still fighting at
day 161). Twenty-three ran the full 160 days with all four armies alive.

There is therefore no seat spread to report: no seat won a free-for-all at any
tier. That is itself the finding — the arena's +37.5 pp first-seat prior
(measured on `scrimmage`, a duel) has nothing to attach to here.

### 1+3v2+4 — five decided matches out of 24

| Tier | Seed | Winning side | Day | Seats eliminated (in order) |
|---|---|---|---|---|
| Normal | 8 | 2+4 | 101 | 1, 3 |
| Hard | 1 | 2+4 | 111 | 1, 3 |
| Hard | 5 | 1+3 | 106 | 2, 4 |
| Hard | 7 | 1+3 | 66 | 4, 2 |
| Brutal | 6 | 1+3 | 148 | 2, 4 |

Side spread over the five: **1+3 three wins, 2+4 two wins.** At n = 5 that says
only that neither pairing is obviously the favoured one — consistent with the
board's own claim that it is identical under a half turn and both mirror axes,
which makes the four corner seats congruent. Nothing here is evidence of a seat
bias in either direction, and nothing here would detect one.

### Cost, for whoever runs this next

Roughly 30–60 s of wall clock per undecided match, four cells at a time on an
8-core machine; the whole 48-match sweep took about 40 minutes. Brutal is the
expensive tier and not because it plays longer matches — it issues about **1.8×
the commands per match** (mean 19,648 in the free-for-all against Normal's 11,067
and Hard's 11,073) for the same 161 days and fewer decisions.

## What this says

**Tier alone does not close the 144–158-day staleness, and the hypothesis is
refuted.** Hard is the best of the three and its edge is small and inside the
noise of eight seeds: 3 of 8 decided against Normal's 1 of 8 in the 2v2, and
**0 of 8 in the free-for-all, same as everyone else**. The matches Hard does
decide still run 66, 106 and 111 days. Brutal — the arena's searched champion,
sixteen dials off Normal — is no better than Normal here and its one win came on
day 148. So the user's two long matches are typical of this board rather than
symptomatic of a weak default: they were not unlucky, and switching them to Hard
would most likely have produced two more long matches.

The one direction the data does point in is **the grouping, not the tier**: a
2v2 resolves sometimes (5 of 24) and the free-for-all never does (0 of 24). Two
sides can eliminate each other; four mutually hostile armies on four separate
islands apparently cannot get through each other inside 160 days. That is a
capability question about the planner meeting an economy it cannot finish, not a
difficulty setting.

**Follow-up levers, none of them pulled here.** This document recommends no
edit and none was made:

- **The three dials that are `0.0` on every shipped tier** — `withdraw_weight`,
  `focus_fire_bonus` and `join_weight`. Each is implemented, tested and one edit
  from a re-try; all three were measured worthless in duels, which is not the
  same as worthless in a four-army stalemate, and a stalled board is exactly
  where merging wounded armour and concentrating fire could plausibly break a
  line. Judgement plan R3 still binds the threat family: `threat_aversion`,
  `advance_threat_tiles` and `withdraw_weight` read one `ThreatMap` and can price
  one enemy three times — **tune them together, never alone.**
- **`capture_units_per_property`**, the AI Economy D5 capture-roster scaling
  dial, is `0.0` on every tier, so the roster floor is a flat `capture_unit_target`
  (3 on Normal and Hard, 0 on Brutal) no matter how much of a 30×22 board is
  still unowned. Causeway has a neutral chain in the middle that nobody finishes
  taking; a roster that scaled with what is left is the dial written for this
  shape.
- **Goal engageability.** Nothing in the planner asks whether the advance goal it
  picked can actually be reached and fought for. On this board the answer is
  often no — land is a tree of causeways and the sea is the only other route, and
  naval R1 stands: the AI cannot plan a ferry, so anything on the far side of
  water it does not already have a hull beside is a goal it will walk toward
  forever.

Whichever is tried, **this document is the before-picture** and the same six
commands are the after-picture. Re-run them at a wider seed count before reading
any single-digit change as a result.
