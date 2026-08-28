# The AI Arena

Thousands of headless matches between candidate AIs, so that a planner weight is
**measured** rather than argued. This is the committed record of the arena
plan's **AR3** (seating an arbitrary candidate), **AR4** (deciding what "better"
means) and **AR5**'s harness (searching a block of dials): what a match is worth,
who plays whom, on which boards, what the instrument says about the three tiers
the game ships with, and how a search over it is driven.

**`docs/ai_arena_results.md` is what it found.** This document is the instrument
and stays true as long as the instrument does; that one is a dated measurement —
the first search campaign, 93,744 matches on 2026-08-05 — and a later campaign
replaces it rather than editing around it.

Like every other offline instrument here it is **not a gate**: it stays out of
`make verify` and `make test`, and only its own unit tests
(`tests/unit/test_arena_fitness.gd`, `tests/unit/test_arena_pools.gd`,
`tests/unit/test_arena_request.gd`, `tests/unit/test_arena_shard.gd`,
`tests/unit/test_arena_blocks.gd`) are in the suite, plus the search driver's own
`--self-check`, which `make check` runs. Generated runs live under `reports/`,
which is gitignored.

**Nothing in the game knows the arena exists** (plan D1). The driver lives in
`tools/`, it reads `BalanceMatchEngine.Outcome`, and nothing under `core/` or
`ai/` gained a hook, a flag or an "arena mode" — the moment the sim can see the
measurement, the measured game stops being the shipped one.

## The four commands

| Command | What it does |
|---|---|
| `make ai-arena` | Plays candidates: profiles in, one JSON record per match out |
| `make arena-report` | Scores records: a leaderboard out. Plays nothing |
| `make arena-anchors ARENA_POOL=training` | Both, over one fixed pool of the anchor round-robin |
| `make arena-search` | The loop over the three: propose a vector, play it, keep it or drop it |

They are separate on purpose. A finished run can be re-scored after the fitness
function moves without replaying a match, and the thing that plays matches has
no opinion about what winning is worth.

```sh
# one pairing, by hand
make ai-arena ARENA="--map=scrimmage --red-profile=data/ai/default.tres \
  --blue-profile=reports/ai_arena/gen1/c7.tres --seeds=8"

# a whole pool, across the cores, then scored
make arena-anchors ARENA_POOL=training WORKERS=6
```

`docs/balance_sim.md` carries the harness itself — the flags, the shard file,
the record shape, and the merge bar that keeps the arena and the Balance Lab one
engine. This document is about the *judgement* laid over it.

**Commanders are neutral by default and seatable on request.** The first
campaign was commander-free (plan R8): `doctrine_weight` inert, no passives, no
powers — a candidate measured as a planner. `--red-co=` / `--blue-co=` (or
`red_co` / `blue_co` per pairing in a shard file) seat a general on a side, and
the record carries both ids, so a campaign can now measure a vector with
doctrines and powers live. A spec that says nothing plays exactly the
commander-free measurement it always did, one profile duel under two different
generals is not a mirror, and the pools and leaderboard remain commander-blind —
a commander-seated run is its own measurement, read from its own records, until
a campaign that seats generals owns a pool split for them.

## What a match is worth

Win or lose over twenty continuous dials is a step function: almost every
mutation changes nothing measurable, and a search spends its compute on noise.
So a match is **scored** rather than counted (plan D4).

The whole function, from `tools/arena/arena_fitness.gd`, per match and per side:

```
if the match rejected a command or hit the command cap:  invalid — never scored,
                                                         and the run has failed
if it ended on the day cap (termination "day_cap"):      0.0 to both sides
otherwise (a rout or an HQ capture):
    speed = clamp((100 - day_ended) / 100, 0, 1)
    worth = 1.0 + 0.5 * speed
    the winner scores +worth, the loser exactly -worth
```

A candidate's score in a pool is the **mean over its matches**, counting each
match once for each seat it sat in.

**Worked example.** From a real record — `clash`, seed 1136, `default` in the
red seat against `hard` in blue, a rout on day 13:

```
speed = (100 - 13) / 100 = 0.87        worth = 1.0 + 0.5 x 0.87 = 1.435
hard scores +1.435, default scores -1.435
```

### Why this shape

- **Three ordered classes, and the order can never be crossed from inside a
  class.** A decisive win is worth 1.0 to 1.5, an unresolved match 0.0, a
  decisive loss −1.0 to −1.5. The base dominates the speed term, so the *fact*
  of the win always outranks how quickly it came — the gradient grades inside a
  class and never inverts the ordering the game cares about.
- **Zero-sum.** The loser scores exactly the negative of the winner. This is
  what makes counting both seatings *cancel* the seat instead of reporting it
  (see below); it is a property of the function, not of the weights.
- **An earlier win outranks a later one.** Speed is the graded term, and it is
  the one that is not degenerate — see the next section.
- **The horizon in the formula is the constant 100, not the day cap the run was
  played at.** A score means the same thing in every run it is compared with; a
  shorter cap simply scores in the upper part of the range and the ordering
  inside that run is unchanged.
- **The day-cap tiebreak never reaches the score.** The engine fills `winner` in
  from properties, then units, then funds when a match runs out of days. Scoring
  that pays whoever hoards better (D6). Two candidates that could not beat each
  other have told us something, and what they told us is 0.0.

### What is deliberately *not* in it

D4 asks for the property / surviving-unit / army-value margins the tiebreak
reads. They are not in the formula, and the reason is a measurement rather than
a preference: **in this game a decisive win wipes the loser's board**, because
elimination removes the loser's units and turns its properties neutral
(four-players plan D3). Checked over the 569 decisive matches below: in **every
one** the loser ended with 0 units, 0 properties and 0 army value, so all three
margins read +1 for the winner every time. Including them would add a constant
to every decisive score and grade nothing.

The one class where those margins do vary is the unresolved one — and that is
exactly the class D6 forbids fitness to read, for the hoarding reason above. So
the margins are degenerate where they are allowed and forbidden where they are
not. If elimination ever stops clearing the loser's board, this is the decision
to revisit first.

## Both seatings, and nobody plays themselves

The seat is worth a great deal. Measured on the mirror run below: with two
**identical** vectors, the first seat won 87.5% of 16 matches on `scrimmage` and
62.5% of 16 on `ironworks`. A leaderboard that let a single seating through
would be reporting the seat.

Two rules keep it out, and they are separate rules in separate places:

1. **The pairing generator never emits a self-pairing** (`ArenaPools.pairings`):
   each unordered pair of the candidate list once, and never a candidate against
   itself. Two identical vectors are guaranteed to score level, so playing them
   is spent compute — and played from one seat only they are nothing *but* seat
   credit.
2. **The scorer refuses a pairing it did not see from both seats**
   (`ArenaLeaderboard.problem`). It does not care who asked for the match; it
   checks that every (board, seed, pair) appears from seat 0 and seat 1, and
   reports the run as unreadable if any does not. A pairing whose two sides are
   the *same* candidate is refused first and **by name as a mirror**
   (`ArenaLeaderboard.mirrored`) — merging a calibration into a leaderboard is
   its own mistake, and "played from one seat only" would describe a broken run
   instead.

That split is what lets a mirror be run **on purpose** as a calibration — which
is the demonstration below — while the generator still never produces one.
The Balance Lab's own mirror shortcut (a mirror plays one seating, because with
both sides the same the second seating is the identical match) stays what it has
always been: a **bias measurement**, and one the arena's scorer refuses to read
as a leaderboard.

### The demonstration

`data/ai/default.tres` against a byte-identical copy of itself
(`reports/ai_arena/mirror/default_twin.tres`), both seatings, 8 seeds on
`scrimmage` and 8 on `ironworks`, 100-day cap — 32 matches:

| Candidate | Matches | Won | Lost | Mean score |
|---|---|---|---|---|
| `data/ai/default.tres` | 32 | 16 | 16 | **+0.000** |
| `…/default_twin.tres` | 32 | 16 | 16 | **+0.000** |

The two seatings of a seed are literally the same match — same winner, same
termination, same day, all 16 seeds — so the first seat won 87.5% / 62.5% of
them. Each candidate held that seat exactly half the time, and a zero-sum score
summed it away. The +50 pp is cancelled, not noted.

## The horizon

**100 days** (`ArenaPools.DAYS`, and the reference inside the fitness function).
`docs/difficulty_check.md` at a 20-day cap and the Grand Atlas at 250 disagree
about which tier is stronger, and the gate document concedes that a 20-day
reading "measured who was ahead early".

100 days is where matches on these boards actually finish: of the 576 anchor
matches below, **569 ended decisively** — 502 routs and 67 HQ captures — 6
reached the day cap and 1 hit the command cap. Mean decisive match: day 34.5.

An unresolved match is recorded as unresolved and scored 0.0 (above). A
`command_cap` stall stays what it already is in this toolchain: **a hard
invariant failure of the run**, never a draw — `make arena-report` exits 1 and
says so.

That rule is unchanged. Its trigger is. The first search campaign failed
every one of its seven blocks on a stall, and none of the twelve stalled matches
was broken: replayed with the cap lifted, **all twelve ran to the day cap**, at
3 052 to 5 226 commands, each a 60-to-87-unit army mopping up a last survivor.
The old flat 3 000 was sized when this toolchain played 20-day matches, and at a
100-day horizon it truncated the longest honest games. It is now derived —
`BalanceMatchEngine.command_ceiling`, the per-turn cap times every turn the day
cap allows — so a stall means the day stopped advancing, which is the only thing
the day cap cannot already catch. **Never score a broken match** was right; what
was miscalibrated was the detector, so the rule stands and the trigger moved.

## The pools and the anchors

All of this lives in `tools/arena/arena_pools.gd` and is **fixed for the life of
a run**, because a pool that moves between generations is a leaderboard nobody
can read across them.

### The anchors (D7)

`easy.tres`, `default.tres`, `hard.tres` — the three shipped tiers, **never
re-tuned mid-run**. Every generation is scored against them, and that score is
the only measurement comparable from one generation to the next. Everything else
a generation plays is selection pressure.

### The boards, chosen for resolution

| Pool | Boards | Seeds per board |
|---|---|---|
| Training | `scrimmage`, `riverline`, `arsenal`, `jet_stream` | 12 (indices 0–11) |
| Validation (held out) | `timberline`, `crossfire`, `first_steps` | 8 (indices 12–19) |

**The split is on both axes.** Different boards *and* different seeds, so a
candidate can never be validated on ground it was selected on, and a board added
to both lists later still could not leak (R1). Every reported result carries
both numbers.

Excluded, and why:

- **Naval boards** (`isthmus`, `the_straits`) while the planner cannot plan a
  ferry (naval plan R1). `the_straits` at Easy is 100% command-cap stalls in the
  Atlas — a known instrument failure, and the thing a fitness function must
  never be fed.
- **Every board seating three or four armies.** A match seats exactly two
  candidates.
- **`boot_camp`**, which is shaped to teach rather than to measure.
- **`forge`** and **`steelworks`**: both resolve (forge measured clean over 72
  matches), and both are held in reserve — `forge` asks the build-first question
  `arsenal` already asks, `steelworks` is the largest and slowest of the ten.
- **`ironworks`**, and this one was measured *out*. It was the only board of the
  ten to reach the match-level command cap, then a flat 3 000: once in 72
  matches, at day 91, on a board holding 55 units against 3. Nothing was failing
  to resolve — a cap sized for 20-day gates is simply short of a 100-day horizon
  on the roster's biggest economy — but a stalled match fails the run, and a pool
  that fails its own run is not a pool. **That was read as a cap to revisit
  rather than a board to distrust, and the cap has since been revisited**
  (`command_ceiling`), so the reason is discharged; re-admitting the board is a
  measurement nobody has taken, and it belongs to a run that has not started,
  since the split is fixed for the life of one.

### How a pool is played

`ArenaPools.pool_args()` is the one statement of a pool, and both the command
that plays it and the report that reads it back come from there:
`make arena-anchors` asks `tools/run_arena_plan.gd` for the pool's arguments,
hands them to `tools/balance_pool.py --preset=arena`, and scores what comes
back. `ArenaPools.pool_of()` recovers a match's pool from the board and seed it
was played with, so a leaderboard can never be scored against a split nothing
played.

### A pool a candidate never played is not a score

The table is ordered on the held-out pool first, because a candidate that leads
where it was selected and not where it was not has overfitted. That reading only
works if every candidate has a held-out number: a pool one of them never met is
the *absence* of a measurement, not a bad one, and reading it as a mean of zero
sorts the untested candidate above one that was tested and lost — the exact
inversion the ordering exists to catch. Train many, validate few is precisely
what a generational search produces, so this is reachable the moment AR5 lands.

`ArenaLeaderboard` therefore keeps the two facts apart. Only a pool **every**
candidate played orders anything (`ranked_on` in `leaderboard.json` says which
did), the gaps are listed in `uncovered`, and a run holding any of them is
reported as unreadable by the same `problem()` that refuses a one-seat pairing.
Refusing to rank such a run is the answer, not an ordering nobody can trust.

## The calibration: what the arena says about the shipped tiers

The instrument's own acceptance check is that a scored run of the three shipped
tiers reproduces the Grand Atlas's **inverted ladder** (Easy > Difficult >
Normal) at the arena's cap, since ranking them in box-art order would mean the
horizon was measuring the wrong thing.

Measured 2026-08-04, anchor round-robin, 100-day cap, both seatings, neutral
commanders:

| Pool | Matches | `hard` | `default` | `easy` |
|---|---|---|---|---|
| Training (4 boards, 12 seeds) | 288 | **+0.393** | −0.138 | −0.255 |
| Validation (3 boards, 8 seeds) | 144 | **+0.578** | +0.076 | −0.654 |
| All nine boards measured | 576 | **+0.407** | −0.093 | −0.315 |

Head-to-head, training pool (n ≈ 96 a pairing, both seats):
`hard` beats `default` 65.6%, `hard` beats `easy` 61.1%, `default` beats `easy`
54.8%.

**The acceptance criterion is not met.** The arena at a 100-day cap ranks the
tiers **Difficult > Normal > Easy** — the box-art order — on the training pool,
on the held-out pool, and over all nine boards measured. It does not reproduce
the Atlas's Easy > Difficult > Normal at any grouping tried.

Four things are worth stating before that is read as either instrument or tiers
being wrong.

**It is not the fitness function.** The same 576 matches ordered by raw win rate
give the same ranking, and so does the score with the speed gradient switched
off entirely (`hard` 64.9% / `default` 45.9% / `easy` 39.0%). The ordering is in
the matches, not in the weights. **The weights were not tuned toward this
result, or away from it.**

**It is board-dependent, strongly.** Per board (72 matches each, mean score):

| Board | 1st | 2nd | 3rd |
|---|---|---|---|
| `scrimmage` | default +0.648 | hard +0.418 | easy −1.066 |
| `riverline` | hard +0.574 | easy −0.150 | default −0.424 |
| `arsenal` | easy +0.614 | hard +0.215 | default −0.829 |
| `jet_stream` | hard +0.366 | default +0.052 | easy −0.418 |
| `forge` | hard +0.284 | default +0.072 | easy −0.356 |
| `ironworks` | hard +0.240 | easy +0.177 | default −0.422 |
| `timberline` | hard +0.833 | default −0.138 | easy −0.695 |
| `crossfire` | hard +0.467 | default −0.214 | easy −0.253 |
| `first_steps` | default +0.580 | hard +0.433 | easy −1.013 |

Difficult is first on six of nine and never last. **Where Normal and Easy sit
relative to each other is a property of the board**: Easy beats Normal on
`riverline`, `arsenal` and `ironworks`, and loses badly on the other six. The
inversion the Atlas found is *reproduced on a third of the boards* and washed
out by the rest. It is real, and it is not a fact about the whole game.

That sensitivity is not hypothetical: the first training pool ran with
`ironworks` in place of `jet_stream` and reported `hard` +0.362 > `easy` −0.108
> `default` −0.256 — the Atlas's inversion, from swapping **one board of four**.
Any ladder claim resting on a handful of boards is fragile, whoever makes it.

**The Atlas measured a different planner.** It was run in July 2026, before the
AI Judgement dials went live (2026-08-01) and before the AI Economy plan's
AE1–AE3 shipped. The committed difficulty gate agrees with the arena on today's
planner rather than with the Atlas: `docs/difficulty_check.md`'s standing
verdict has Normal taking 68.3% from Easy and Difficult 53.3% from Normal at 15
seeds — box-art order, weakly held. An arena that reproduced a July finding on
an August planner would be the surprising result.

**What it means for the instrument.** The check exists to catch a horizon that
measures who was ahead early. This horizon does not: 98.8% of its matches end in
a rout or an HQ capture, mean day 34.5, and the ladder it reports is stable
across a held-out pool. What the check assumed — that today's tiers are inverted at a
long horizon — is the part that did not survive the measurement. The tiers
themselves are BL2's, not the arena's (plan D8: the arena recommends, a human
ships).

## The search (AR5's harness)

`make arena-search` is the loop over the three instruments above and nothing
else: it proposes a vector, writes it as an `AIProfile`, plays it through the
pool, scores it through the report, and keeps it or drops it. It reimplements no
fitness, no leaderboard and no match loop, and **it edits nothing under `data/`**
(plan D8) — every candidate it writes stays under `reports/`.

```sh
make arena-search SEARCH="--block=all --dry-run"        # the budget, and stop
make arena-search SEARCH="--block=combat --train-seeds=6"
```

The harness is `tools/arena_search.py` (the loop, in Python for the same reason
the pool is: processes, resume-on-disk and JSON are a few lines of stdlib), over
three GDScript pieces that keep every decision on the engine's side of the fence:
`tools/arena/arena_blocks.gd` is the search space, `tools/run_arena_blocks.gd`
prints it — with the pools, the anchors and the base vector — as one JSON object,
and `tools/run_arena_candidates.gd` writes the profiles. The Python derives none
of those: a driver that restated a range or a seed range would be a second
opinion about the search space, and the first thing to drift.

### The blocks

**Blocks, never one joint optimisation** (R5). A run searches one block and holds
every other dial at the base vector, so a result is attributable to the dials
that moved.

| Block | Dials | Borrowed |
|---|---|---|
| `combat` | `kill_bonus`, `counter_weight`, `min_useful_score`, `condition_weight` | — |
| `economy` | `capture_score`, `capture_progress_bonus`, `hq_capture_multiplier`, `step_cost_penalty`, `advance_score`, `defend_weight` | — |
| `threat` | `threat_aversion`, `advance_threat_tiles`, `withdraw_weight`, `cover_tiles` | — |
| `formation` | `cohesion_tiles`, `cohesion_radius`, `retreat_hp` | — |
| `production` | `capture_unit_target`, `duplicate_priority_cost`, `save_up_turns`, `air_answer_target`, `build_reactivity` | — |
| `economy_map` | `capture_units_per_property`, `capture_claim_depth`, `production_capture_multiplier`, `capture_goal_value_tiles` | `capture_unit_target`, `cohesion_tiles` |
| `join` | `join_weight` | `condition_weight` |

**A coupling is declared, not discovered.** `couples` names dials another block
owns that this one has to move with its own, and they are searched jointly; the
split is only what the report reads to say why a dial from elsewhere was on the
table. The four that are not optional:

- `capture_units_per_property` raises the `capture_unit_target` **floor** rather
  than replacing it, so it cannot be searched apart from Production.
- `capture_claim_depth` against `cohesion_tiles`, AE2's own instruction:
  spreading is untaxed by cohesion, so claim depth is the only thing limiting how
  thin a capture line gets.
- `capture_goal_value_tiles` × `production_capture_multiplier` multiplies out to
  zero at either dial's inert value, so moving one alone is inert half the time —
  both are in the same block already.
- `condition_weight` with `kill_bonus`, which both dials' doc comments state: the
  bonus is the other correction to the same valuation, so a search that fits it
  first fits it to a price the other then changes.

**Where AR6's three dials went.** `condition_weight` is in `combat` because of
that last coupling. `cover_tiles` is in `threat` rather than beside it: a cell a
forecast has already priced scores no stars, so turning a threat dial on takes
cover out of exactly those cells (plan §5b) — the coupling is to the threat map,
by construction. `join_weight` gets a block of its own, but not alone: what a
merge carries is priced by `_unit_value`, and a join only ever happens to damaged
units, so at `condition_weight` 0 the dial is being fitted against a valuation
that calls a 10-HP tank a whole one.

**Two corrections to the shelf as the plan states it.** The count is the code's,
not the plan's: `ArenaBlocks.DIALS` carries **27 searchable weights**, where the
plan's §5a arithmetic — nineteen dials plus the four AE economy ones plus AR6's
three — was already short of its own shelf, which is how a smaller number first
got written here. The dial no §5a row names at all is `defend_weight`, which
ships live at 2.0 on Normal and 2.5 on Difficult. It sits in `economy`, whose
price list it reads backwards (Judgement D3), which is also why that block
cannot be narrower.
`refuel_margin_turns` stays excluded but its stated reason does not survive AR4:
"only matters on boards this plan excludes" was true when the plan was written
and stopped being true when the training pool took `jet_stream`. It is live on
one training board of four and one validation board of three, which is too little
of a pool to read a dial on — so it is excluded for want of boards, not for want
of relevance. `tests/unit/test_arena_blocks.gd` holds every live weight to being
in a block or on the exclusion list with a reason, and it has now paid twice:
it found `defend_weight` when the shelf was built, and it caught COM-65's
`supply_weight` / `supply_unit_target` when they landed after the first campaign
was measured — both sit on the exclusion ledger as unsearched, the first thing a
second campaign should cover.

### The algorithm, and what it costs

**A compass (pattern) search over a snapped lattice.** One incumbent; each wave
proposes it plus one step up and one step down on every dial, all evaluated in
one pool run; the best training score becomes the next incumbent, and a wave that
finds nothing halves the step instead. It stops when the step is the dial's own
precision or the wave budget runs out.

Chosen over anything cleverer for three reasons, in this order:

- **It is explainable.** Every move is one dial, one step, and the wave that
  bought it is in the record. AR5's acceptance criterion asks for a champion
  whose dials are legible; a search whose path cannot be read cannot produce one.
- **It is cheap per improvement.** `2D` probes buy a move, where a coarse grid
  over five dials at three levels each is 243 evaluations, and each evaluation
  here is hundreds of matches.
- **It is robust to a noisy evaluation.** It only ever asks which of a handful of
  vectors scored best over a few hundred matches — never for a gradient that a
  mean of noisy matches cannot give.

A candidate costs `boards × seeds × 2 seatings × 3 anchors` matches per pool:
**288** on the full training pool and **144** on the held-out one. The worst case
per block is `(1 + 2D) + 2D(W−1)` candidates over `W` waves, which
`--dry-run` prints before anything is played:

| Block | Dials | Candidates | Matches | Hours at 65/min |
|---|---|---|---|---|
| `combat` | 4 | 65 | 19 152 | 4.9 |
| `economy` | 6 | 97 | 28 368 | 7.3 |
| `threat` | 4 | 65 | 19 152 | 4.9 |
| `formation` | 3 | 49 | 14 544 | 3.7 |
| `production` | 5 | 81 | 23 760 | 6.1 |
| `economy_map` | 6 | 97 | 28 368 | 7.3 |
| `join` | 2 | 33 | 9 936 | 2.5 |
| **all seven** | | **487** | **143 280** | **36.7** |

That is eight waves and the full pool, and it is a worst case in one direction
only: it assumes every wave improves and none stops early. `--train-seeds=6`
halves it, and the seed ranges are a **prefix** of each pool's own, so a reduced
run still lands inside the split `pool_of` reads matches back against.

### What it reports, and what it keeps

**Training and validation, always** (R1). Every wave is played on the training
pool alone — the held-out pool can never touch a selection — and at the end of a
block the top `--keep` candidates plus the vector the search started from are
replayed on the held-out boards and seeds. The gap between the two numbers is the
headline: a champion that leads where it was selected and not where it was not
has fitted the pool rather than the game.

Read the two halves of a table differently. A **candidate**'s score is against
the three fixed anchors, so it means the same thing in every wave and across the
whole run — that is what a fixed anchor set is for (D7). An **anchor**'s score is
against whatever candidates shared its table, so it moves as the search does and
is context rather than a reference.

A block declaring `per_board` is also scored one board at a time off the shards
the held-out run already played, at no extra match. `economy_map` declares it,
because `capture_units_per_property` counts what is left to take: on `scrimmage`
that is 6 properties and on `arsenal` 22, so a single board measures the map
rather than the dial.

A run leaves behind `report.md` (the readable answer), `<block>/search.json`
(every wave, every vector, every score), `<block>/summary.json`, per-wave
`leaderboard.json` and `matches.json`, and `candidates/` — **every profile it
ever wrote**, named for a digest of the vector it carries, with an `index.json`
mapping the name back to the block and the numbers. A champion is re-run by
naming its file.

### Watching one

A campaign is hours to days of matches and its log only speaks at wave
boundaries, so `tools/arena_status.sh` reads the artifacts the run has already
written — the pool's status line and each block's `search.json` — and prints
where it is now: whether the search is running, how many waves each block has
finished, the best training score so far, and which dials have moved off the
vector it started from. It plays nothing, writes nothing and is safe against a
live run. With no argument it reads the newest run under `reports/ai_arena/`,
and it refuses out loud rather than guessing when there is none.

```sh
tools/arena_status.sh                          # the newest run
tools/arena_status.sh reports/ai_arena/gen4 --watch
```

`--watch` redraws every 10 s until interrupted; macOS ships no `watch(1)`.

### Resumable at three levels

The pool already skips a shard whose records are on disk. Above that, a candidate
is named for a **digest of its vector**, so an incumbent that survives a wave is
replayed for free — the shard's resume key is the argument list, and the argument
list holds the same path. Above that again, `<block>/search.json` records every
finished wave, so an interrupted run re-reads its own decisions rather than
replaying them, and a block whose held-out run is already played is not replayed
either. Rerun the same command to pick a search up; a run that names an `--out`
holding a search of a different spec is refused rather than continued.

Measured on the smoke configuration below: a full rerun of a finished search
costs **2.8 s and zero matches**.

### The harness, proved small

One block narrowed to two dials, one seed a board, three waves —
`--block=combat --dials=kill_bonus,condition_weight --train-seeds=1 --val-seeds=1
--max-waves=3 --keep=2`, six workers, on a machine carrying a load average of 7
to 19 from other work:

| | |
|---|---|
| Matches played | 270 (390 read; the difference is the incumbent, resumed) |
| Wall clock | 3.9 min |
| Throughput | 71.2 matches/min at 6 workers |
| Waves | 3 — moved, moved, contracted |
| Champion | `kill_bonus` 1.6 → 1.2, `condition_weight` 0.0 → 0.25 |
| Training / held out | +0.324 / +0.257, gap +0.067 |

**One seed a board is a rehearsal of the machinery and not a measurement**: at 24
training matches a candidate the standard error swamps the differences the table
shows, and the champion above is not a finding. What it proves is that the loop
runs end to end — propose, write, play, score, move, contract, validate, report —
and what it costs.

## Known limits

- **The longest matches here are enormous, and that is the game rather than a
  fault.** The worst measured is 8 907 commands over 100 days — a 184-unit army
  hunting one survivor across `arsenal`. `command_ceiling` leaves room for it,
  but a pool of such matches is slow, and a fitness function that pays for speed
  (above) is the only thing pushing against it.
- **A match seats exactly two candidates**, so every three- and four-army board
  in the roster is out of reach of the arena as it stands.
- **The margins are unused** for the reason measured above, so a decisive win is
  graded by speed alone.
- **The campaign has been run once, and its limits are its own document's.**
  `docs/ai_arena_results.md` carries what the dials were worth end to end and
  what that number is not evidence of. The sharpest limit belongs here too: the
  held-out pool holds out **boards and seeds, never opponents**, so a candidate
  is reported against the same three anchors it was selected against.
- **The two permutations are not searchable here.** `build_priority` and
  `air_answer_ids` are ordered arrays, and a permutation move and a step along an
  axis do not belong in one proposal distribution (D9). They need a block of
  their own and a proposal of their own.
- **Candidates do not play each other.** The opponent set is the three fixed
  anchors, which is what makes a score comparable across waves; a generation
  playing itself is `C²` pairings and D7's third opponent set (a sample of the
  archive) is not reachable from a search that keeps one incumbent rather than a
  population. What that costs is stated rather than hidden: this harness cannot
  see a candidate that beats the anchors and loses to its own predecessors.
- **A base copied from an anchor plays a known draw.** The base vector is written
  as a candidate like any other, so when it equals a shipped tier — which it does
  by default — one of its three pairings is two identical vectors and scores
  exactly level, both seatings. That is a correct measurement rather than a
  distortion, and it costs one pairing of compute once per run, cached after.
