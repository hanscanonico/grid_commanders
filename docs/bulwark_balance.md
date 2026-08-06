# Bulwark's fairness measurement

Bulwark (`maps/bulwark.txt`, asymmetric-board plan AB2) is the first shipped
board authored *unfair on purpose*: one entrenched army (seat 4) against three
allied seats massed on the far edge. `tests/unit/test_alliance_soak.gd` proves
the board's own `1+2+3v4` grouping and the reachable free-for-all are both
**legal** — no rejected command, no stall — over one seeded match each at ten
days. This is the committed record of the other half of AB3: **the win spread**, over
enough seeds and enough days for a match to actually resolve.

`BalanceMatchEngine` plays exactly two sides (plan R4), so this board — four
armies, grouped or not — cannot go through `make commander-balance` or
`make difficulty-check`, and both those reports stay byte-identical across this
change. The instrument is its own runner, `tools/run_bulwark_measure.gd`
(`make bulwark-measure`), which plays the same loop
`test_alliance_soak.gd::_soak` does — `MapData.load_from_file` ->
`GameState.create` -> `state.sides` set directly, one `AIController` per army —
at a seed count and a day horizon meant to read a **direction**, not a
**gate**. It is not a `make verify` or `make test` instrument, and it tunes
nothing: this document measures, and AB4 reads it and moves the board.

**AB3 measures and does not tune. Nothing below is a recommendation.**

## Method

Every army plans through a neutral commander (no `set_commander` call is ever
made), so the number is about the board rather than a doctrine. Two groupings,
matching the seat strip's own offer:

- **3v1** — `{1: 0, 2: 0, 3: 0, 4: 1}`, the board's own `# grouping 1+2+3v4`
  header, stated directly on `state.sides` and never read off the tag (plan
  D2 — the tag is the parity lint's alone).
- **Free-for-all** — every seat its own side, the grouping the board's header
  warns is "not fair among the three": seat 2 faces the bulwark's HQ down the
  middle, 1 and 3 flank.

Measured at **20 seeds (1–20), 100-day horizon**, both groupings:

```sh
make bulwark-measure BULWARK="--seeds=20 --days=100 --grouping=alliance"
make bulwark-measure BULWARK="--seeds=20 --days=100 --grouping=ffa"
```

## Results

### 3v1 — the board's own grouping

0 rejected commands, 0 cap-stalls across all 20 matches — the "no rejected
command, no stall" half of AB3's gate holds clean. 1 of 20 (5.0%) still running
at the 100-day horizon, counted **undecided** rather than forced to a score.

Of the 19 decided matches:

| Winner | Wins | % of decided |
|---|---|---|
| alliance (1+2+3) | 14 | 73.7% |
| bulwark (4) | 5 | 26.3% |

Day the match ended: min 36, median 42, mean 52, max 101 (the undecided one).
Every bulwark win lands well inside the horizon (day 40–67); the long tail
belongs to matches the alliance goes on to win by grinding down the garrison.

**Seat spread within the alliance** — how often each allied seat fell during
the match at all, regardless of which side ultimately won (of 20):

| Seat | Fell |
|---|---|
| 1 (flank) | 7 |
| 2 (centre, faces the bulwark's HQ) | 6 |
| 3 (flank) | 5 |

Close to even — no allied seat is a dramatically weaker link than the others
under the board's own grouping. Every bulwark win costs the alliance all three
seats (necessary: the side that wins holds every one of its surviving armies);
every alliance win costs the bulwark alone, with one exception (seed 1) where
one ally (seat 1) also fell before the other two mopped up.

### Free-for-all — reachable, not fair

Same 20 seeds, same 100-day horizon. 0 rejected, 0 cap-stalls. 1 of 20 (5.0%)
undecided.

Of the 19 decided matches:

| Winner | Wins | % of decided |
|---|---|---|
| seat 4 (bulwark) | 17 | 89.5% |
| seat 3 | 2 | 10.5% |
| seat 1 | 0 | 0% |
| seat 2 | 0 | 0% |

Day the match ended: min 32, median 46, mean 52, max 101 (the undecided one).

Seat 2 — the seat the board's own header says stands on the axis, facing the
bulwark's HQ down the middle — is the **first** seat eliminated in 14 of 20
matches; seat 1 is first in 5, seat 3 in only 1. The two matches seat 3 goes on
to win are the same two where the bulwark itself is eventually eliminated too
(after grinding through seats 2 and 1 first) — seat 3 outlasting the table
rather than doing anything differently early on.

## Reading it honestly

- **n = 20 is a direction, not a magnitude** — the same convention
  `docs/difficulty_check.md` §4b uses. At this width a handful of matches
  landing the other way would move the alliance's 73.7% by several points;
  read the shape (alliance favoured under its own grouping, bulwark heavily
  favoured against any one rival) rather than the third digit.
- **The hard invariants are the zero-tolerance numbers here.** 0 rejected
  commands and 0 cap-stalls across all 40 matches means the rules and all four
  planners never once disagreed, and no match looped — that is the half of
  AB3's gate with no honest "it depends."
- **Both groupings left exactly one of 20 seeds undecided (5.0%)** at the
  100-day horizon — not a stall (nothing tripped the command ceiling), a match
  still running when the clock was called. Both are down to a straight fight
  between the bulwark and the last surviving ally, the other two allied seats
  already fallen (see `reports/bulwark/*/matches.csv`, seed 12 for the
  alliance run and seed 5 for the free-for-all), so a longer horizon would
  most likely have resolved them in the direction the rest of their row
  already leans, not flip the picture.
- **Neutral commanders throughout** — this reads the board, not a doctrine. A
  seated commander on either side would move these numbers, which is exactly
  why AB3 seats none.
- **The free-for-all's 89.5%-to-the-bulwark figure answers a different
  question than D5 asked.** D5 only promises the grouping is "not fair among
  the three [allies]" — it says nothing about whether the bulwark stays fair
  against a lone rival, and at this seed count it plainly does not: one
  entrenched army at twice anyone's production beats any one of the three
  roughly nine times in ten. That is the design working as intended — the
  whole premise is concentration beating three smaller, separate armies — and
  it is a fact about the *reachable* free-for-all, not about the grouping the
  board is authored and measured for.
- **AB3 measures and does not tune.** The 73.7%/26.3% alliance-vs-bulwark
  spread under the board's own `1+2+3v4` grouping is the number AB4 reads;
  nothing here changes the board, the garrison, the neutral belt or the
  passes.
