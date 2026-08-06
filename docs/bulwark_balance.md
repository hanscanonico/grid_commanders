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
nothing: AB3 measured, AB4 read the measurement, and AB4's answer was that no
board change it tried beat leaving the board alone.

**AB3 measures and does not tune, and nothing in its sections below is a
recommendation.** The AB4 section at the end is the one place this document
recommends anything, and it says which of its lines are guardrails.

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

**Fog is off for every seed**, and that is a condition of the number rather
than an omission. The soak beside this instrument alternates fog by seed on
purpose, to walk the shared-sight path; this one holds it off so every seed
measures the same board under the same information — fog moves AI pathing (a
committed path is walked with the mover's own visibility) and switches off the
AR1 plan cache, so a sample that alternated it would be two measurements
reported as one. Read the spread as the clear-weather board.

Measured at **20 seeds (1–20), 100-day horizon**, both groupings:

```sh
make bulwark-measure BULWARK="--seeds=20 --days=100 --grouping=alliance"
make bulwark-measure BULWARK="--seeds=20 --days=100 --grouping=ffa"
```

## Results

### 3v1 — the board's own grouping

0 rejected commands, 0 cap-stalls and 0 turn-cap hits across all 20 matches —
the "no rejected command, no stall" half of AB3's gate holds clean. 1 of 20
(5.0%) still running at the 100-day horizon, counted **undecided** rather than
forced to a score.

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

Same 20 seeds, same 100-day horizon. 0 rejected, 0 cap-stalls, 0 turn-cap
hits. 1 of 20 (5.0%) undecided.

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
- **0 turn-cap hits too, and that one is recorded without being part of the
  verdict.** A turn that proposes more than
  `BalanceMatchEngine.MAX_COMMANDS_PER_TURN` commands is force-ended where it
  stands, which truncates that army's play; on the roster's largest board a run
  of them would bias the spread while the two zero-tolerance numbers above
  still read clean. Neither grouping had one — `total_turn_cap_hits` is 0 in
  both summaries — so no percentage above was measured on a turn that was cut
  short. The runner counts them per match (`turn_cap_hits` in `matches.csv`,
  `total_turn_cap_hits` in `summary.json`) and prints them beside the rejected
  and cap-stall totals, but excludes them from the broken/clean verdict — the
  same call `BalanceMatchEngine` makes, because a planner that overstayed did
  nothing illegal. Had it been anything but zero, the spread would have needed
  re-reading at that width before AB4 moved the board on it.
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

## AB4 — the retune, and why the board did not move

**AB4's finding is a measurement rather than an edit: no board change tried
beat leaving the board alone, and the board's own number is better than AB3
could see.** `maps/bulwark.txt`'s terrain, ownership and starting armies are
the ones AB2 authored, unchanged cell for cell; the only thing that moved is its
header, which now carries the guardrails below where an editor will meet them.

### The hypothesis, and its refutation

The alliance's real edge is tempo (plan R1) — three armies act three times a
day to the bulwark's once — and §2 names the belt as "the alliance's win
condition". The belt also sits entirely on the alliance's own side of the wall
(y 7–15, north of the rampart at y 16–18), so three armies can walk into it
from their doorstep while the bulwark has to cross the wall first. That made a
poorer belt the obvious first dial, and fewer passes the obvious second.

**Both were measured and both are wrong, one of them catastrophically.** Four
board-only changes, each at the same width AB3 used
(`--seeds=20 --days=100 --grouping=alliance`), no unit or base added to any
seat and nothing outside `maps/bulwark.txt` touched:

| # | Change | Alliance | Bulwark | Undecided |
|---|---|---|---|---|
| — | the board as authored (4 passes, belt as shipped) | 73.7% (14/19) | 26.3% (5/19) | 1/20 |
| 1 | Belt shallower: the two outermost belt rows (y 7, 9) cleared of their 11 neutral cities | 85.0% (17/20) | 15.0% (3/20) | 0/20 |
| 2 | Passes fewer: the outer pair (x 7–8 / 40–41) closed to solid mountain, 4 → 2 | 100% (20/20) | 0% (0/20) | 0/20 |
| 3 | Passes more: a second mirrored pair (x 13–14 / 34–35) opened, 4 → 6 | 70.0% (14/20) | 30.0% (6/20) | 0/20 |
| 4 | #3 plus a richer belt: belt row y 8's six woods turned to cities, 30 → 36 neutral | 100% (20/20) | 0% (0/20) | 0/20 |

### Why #3 was not shipped

#3 reads as an improvement and is not one. **The alliance won 14 of 20 on both
the authored board and #3** — the percentage moved only because the seed that
was undecided at the horizon resolved. So the sample was widened to settle it:
seeds 21–40, both boards, same horizon, through the runner's own
`--seed-offset` (seed = offset + i + 1):

```sh
make bulwark-measure BULWARK="--seeds=20 --seed-offset=20 --days=100 --grouping=alliance"
```

The candidate board was measured with that same command over a working copy of
`maps/bulwark.txt`, since the runner loads the board from `res://` by path.

| Board | seeds 1–20 | seeds 21–40 | n=40 total | Alliance share |
|---|---|---|---|---|
| as authored, 4 passes | 14 / 5 (1 undecided) | 11 / 9 | 25 / 14, 1 undecided | **64.1%** |
| #3, 6 passes | 14 / 6 | 11 / 9 | 25 / 15 | **62.5%** |

The two boards are **identical on the twenty fresh seeds** — 11 alliance, 9
bulwark, both — and the whole n=40 gap is that same one undecided match. A
second pass pair does nothing measurable, and shipping it would have widened
the rampart's frontage from 8 cells to 12, changing a number the board's own
header, the plan's §2 and `CLAUDE.md` all state, in exchange for nothing.

### What the widened sample says about the board

**AB3's 73.7% was itself narrow-sample noise.** The same unchanged board reads
**64.1% alliance / 35.9% bulwark over 40 seeds**, and the first twenty happened
to run alliance-heavy. That is not parity, and the alliance is genuinely the
favourite — but it is not a foregone conclusion in either direction, which is
the bar AB4 was reading for, and it is close enough to the band that a board
edit justified by the n=20 figure would have been an edit justified by noise.

### The guardrails this leaves behind

- **The belt is not a dial that helps the bulwark, in either direction.**
  Poorer (#1) lost the bulwark 11 points; richer (#4, on top of #3) took it to
  zero. R1 names "the garrison and the belt" as the dial if the alliance runs
  away with it; the belt half of that does not hold up here, and the reason is
  the hypothesis's own premise — the belt is the alliance's to spend whatever
  its size.
- **Closing passes is the worst thing that can be done to this board**, and it
  runs exactly opposite to the "fewer doorways favour the defender" instinct.
  #2 was catastrophic and fast, matches ending day 22–45 instead of the 3v1
  baseline's 36–101:
  the garrison's own tanks and artillery need the passes to sortie north and
  contest ground as much as the alliance's armour needs them to push south,
  while infantry ignores passes entirely and crosses on a 49-cell front. The
  rampart's four passes are load-bearing at four — **do not narrow them.**
- **D6 held.** No unit and no base was added to any seat at any point, which is
  the drift D6 names AB4 as most likely to fall into.

### What a next attempt should try

The garrison's own size or placement is the one untried lever, and it is D6's
discouraged one — but it now has measured evidence behind reconsidering it
rather than an assumption, because both preferred dials underperformed. Past
that the question stops being a number and becomes a design one: whether one
dug-in army needs a materially different mechanic from "the same units, with
less of everything else around them" to hold three attackers at parity.

**Free-for-all:** AB3's figures stand unaltered, because the board does —
seat 4 takes 89.5%, seat 3 10.5%, seats 1 and 2 none. Nothing was re-measured
here and nothing needed to be. D5 already says a free-for-all on this board is
not fair among the three, and this milestone did not chase it. (#3 was measured
at 85.0% to seat 4 — 17 of 20, against the authored board's 89.5% — before it
was rejected on the 3v1 evidence above.)

### Reading it honestly

- **n=40 is a better direction than n=20 and still not a magnitude.** The
  convention is `docs/difficulty_check.md` §4b's. What widening the sample
  bought was not precision but a negative result strong enough to act on: two
  boards that differ by nothing across twenty fresh seeds.
- **Zero rejected commands, zero cap-stalls and zero turn-cap hits across
  every match measured in this milestone**, on every candidate board — the
  hard invariants never moved.
- **The retune's deliverable is this section.** The board is the only dial AB4
  was allowed, it was pulled four ways, and the honest result is that none of
  them beat leaving it alone.
