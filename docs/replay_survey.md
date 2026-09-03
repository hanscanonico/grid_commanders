# The replay survey

The analyser (`make replay-report`, replay plan RP4) has existed since the
recordings did, and it had never produced a number anybody could cite: one
report is one match, which is an anecdote. This is the committed reading of the
other half — **how often each detector fires**, over a bounded pool of matches,
with the commands that reproduce it.

Read the caveat first, because it is the whole point of the instrument's D6
boundary: **these are finding rates, not a verdict.** Several detectors fire on
a doctrine playing exactly as intended, and every counterfactual behind them
comes from the rules (`AttackRange`, `MovementResolver`,
`CombatResolver.forecast_at`) rather than from the planner. A rate says how
often the *game* offered a side something better than what it did — never that
the side was wrong to pass.

## Reproducing it

Four boards × three seeds = twelve matches, about four minutes of sim:

```sh
make balance-sim SIM="--map=scrimmage   --seeds=3 --replays --out=replay_survey/scrimmage"
make balance-sim SIM="--map=the_straits --seeds=3 --replays --out=replay_survey/the_straits"
make balance-sim SIM="--map=jet_stream  --seeds=3 --replays --out=replay_survey/jet_stream"
make balance-sim SIM="--map=powder_keg  --seeds=3 --replays --out=replay_survey/powder_keg"

for m in scrimmage the_straits jet_stream powder_keg; do
	make replay-report REPLAY=reports/replay_survey/$m/replays_s3 \
		ARGS="--out=reports/replay_survey/$m/survey"
done

mkdir -p reports/replay_survey/all/replays
cp reports/replay_survey/*/replays_s3/*.jsonl reports/replay_survey/all/replays/
make replay-report REPLAY=reports/replay_survey/all/replays ARGS="--out=reports/replay_survey/all"
```

The `_s3` is the seed count the Lab wrote into the recordings directory, so a
re-run at a different `--seeds=` lands beside these rather than on top of them —
surveying a directory folds in every `.jsonl` it finds, and a shrunk pass that
inherited a wider one's files would quietly widen the pool. `all/replays` is
gathered by hand above and is not one of those directories.

`ironworks` is deliberately out of the pool: it is the one board measured to hit
the match-level command cap, and it is out of the arena's pools for that same
reason (`docs/ai_arena.md`).

Both sides are `none-normal` — no commander, Normal tier — which is the Lab's
default seating and what makes this a reading of the *planner* rather than of a
doctrine. The Lab's default day cap is 20 — a match that runs the cap out reads
21 in the days column, the loop exiting on the day it refused to play — so most
of these matches are undecided at the horizon rather than routed; that is a fact
about the pool, not a defect, and it is why the per-100-commands column is the
one to compare across boards.

## What it measured

`make replay-report` is not in `make verify` and this file is not a gate — it is
a dated measurement, superseded wholesale by a later one rather than edited.

- **Date:** 2026-08-16.
- **Analyser state:** the five fixes merged the same night — #232 (the hoarding
  and idle detectors quieted), #248 (every finding kind held to a fixture), #250
  (the two power findings read against the post-gate roster), #257 (every
  counterfactual held to what the side could see) and #265 (`abandoned_capture`).
  Every number below is the *fixed* instrument's.
- **Pool:** 12 recordings, 4 boards, 3,106 commands, 227 days, 133 findings.
- **Dropped:** none. Every recording re-issued to its end.

### All twelve

| finding | count | share | per 100 commands | per match | most often |
| --- | ---: | ---: | ---: | ---: | --- |
| `walk_into_fire` | 98 | 73.7% | 3.16 | 8.2 | infantry ×57, recon ×9, mech ×8 |
| `hoarding` | 17 | 12.8% | 0.55 | 1.4 | — |
| `oscillation` | 13 | 9.8% | 0.42 | 1.1 | mech ×7, infantry ×3, anti_air ×1 |
| `worse_shot` | 4 | 3.0% | 0.13 | 0.3 | anti_air ×1, bomber ×1, infantry ×1 |
| `undefended_hq` | 1 | 0.8% | 0.03 | 0.1 | — |

Six of the eleven detectors fired **not at all** over the pool:
`missed_capture`, `idle_unit`, `abandoned_capture`, `banked_power`,
`spent_power` and `stranded_transport`. Each silence has a reason: `idle_unit`
is what #232 quieted, `abandoned_capture` shipped (#265) with a fixture and no
real sighting — a watch on a failure the architecture allows rather than one the
shipped planner commits — the two power detectors need a commander and this pool
seats none (`none-normal` both sides), and `stranded_transport` needs a
transport the planner never builds (naval R1).

### Per board

Rates per 100 commands, so the four are comparable despite matches of very
different lengths:

| board | commands | findings | `walk_into_fire` | `hoarding` | `oscillation` | `worse_shot` | `undefended_hq` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `scrimmage` | 448 | 21 | 2.68 | 1.12 | 0.67 | — | 0.22 |
| `the_straits` | 1311 | 38 | 2.36 | 0.15 | 0.23 | 0.15 | — |
| `jet_stream` | 797 | 38 | 3.64 | 0.75 | 0.38 | — | — |
| `powder_keg` | 550 | 36 | 4.73 | 0.73 | 0.73 | 0.36 | — |

## How to read it

**`walk_into_fire` dominates, and infantry is most of it.** 98 of 133 findings,
and 57 of those are infantry. That is the shape to expect rather than a bug:
the detector fires only when *staying put was survivable*, and a capture race is
a planner deliberately spending cheap bodies to reach ground before the enemy
does. What the number is good for is a baseline — a change that moves 3.16 per
100 commands a long way in either direction has changed how the planner values a
capturer's life, and this file is what says which way.

**The economy detectors are quiet.** `hoarding` at 0.55 and nothing at all from
`idle_unit` is what #232's floor and its shot check were for, and the spread
across boards is legible: `scrimmage` (small, few properties) hoards at 1.12
while `the_straits` (long, naval, plenty to buy) hoards at 0.15.

**One `undefended_hq` in twelve matches** is the rarest thing here and the most
expensive kind when it fires — worth reading the single `scrimmage` finding
rather than the rate.

**Do not compare a rate here to one taken before 2026-08-16.** Five of the
detectors were changed the same night; the pool would be the same and the
numbers would not.
