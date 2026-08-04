# The AI Arena

Thousands of headless matches between candidate AIs, so that a planner weight is
**measured** rather than argued. This is the committed record of the arena
plan's **AR3** (seating an arbitrary candidate) and **AR4** (deciding what
"better" means): what a match is worth, who plays whom, on which boards, and
what the instrument says about the three tiers the game ships with.

Like every other offline instrument here it is **not a gate**: it stays out of
`make verify` and `make test`, and only its own unit tests
(`tests/unit/test_arena_fitness.gd`, `tests/unit/test_arena_pools.gd`,
`tests/unit/test_arena_request.gd`, `tests/unit/test_arena_shard.gd`) are in the
suite. Generated runs live under `reports/`, which is gitignored.

**Nothing in the game knows the arena exists** (plan D1). The driver lives in
`tools/`, it reads `BalanceMatchEngine.Outcome`, and nothing under `core/` or
`ai/` gained a hook, a flag or an "arena mode" — the moment the sim can see the
measurement, the measured game stops being the shipped one.

## The three commands

| Command | What it does |
|---|---|
| `make ai-arena` | Plays candidates: profiles in, one JSON record per match out |
| `make arena-report` | Scores records: a leaderboard out. Plays nothing |
| `make arena-anchors POOL=training` | Both, over one fixed pool of the anchor round-robin |

They are separate on purpose. A finished run can be re-scored after the fitness
function moves without replaying a match, and the thing that plays matches has
no opinion about what winning is worth.

```sh
# one pairing, by hand
make ai-arena ARENA="--map=ironworks --red-profile=data/ai/default.tres \
  --blue-profile=reports/ai_arena/gen1/c7.tres --seeds=8"

# a whole pool, across the cores, then scored
make arena-anchors POOL=training WORKERS=6
```

`docs/balance_sim.md` carries the harness itself — the flags, the shard file,
the record shape, and the merge bar that keeps the arena and the Balance Lab one
engine. This document is about the *judgement* laid over it.

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
   reports the run as unreadable if any does not.

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
- **`ironworks`**, and this one was measured *out*. It is the only board of the
  ten that reaches `BalanceMatchEngine.COMMAND_CAP` (3 000): once in 72 matches,
  at day 91, on a board holding 55 units against 3. Nothing was failing to
  resolve — a command cap sized for 20-day gates is simply short of a 100-day
  horizon on the roster's biggest economy — but a stalled match fails the run,
  and a pool that fails its own run is not a pool. **Read that as a cap to
  revisit, not a board to distrust**; the arena wants its economy board back.

### How a pool is played

`ArenaPools.pool_args()` is the one statement of a pool, and both the command
that plays it and the report that reads it back come from there:
`make arena-anchors` asks `tools/run_arena_plan.gd` for the pool's arguments,
hands them to `tools/balance_pool.py --preset=arena`, and scores what comes
back. `ArenaPools.pool_of()` recovers a match's pool from the board and seed it
was played with, so a leaderboard can never be scored against a split nothing
played.

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

## Known limits

- **The command cap and the horizon are in tension on big boards.**
  `BalanceMatchEngine.COMMAND_CAP` is 3 000, sized when the toolchain played
  20-day matches; a 100-day match on `ironworks` can want more. That cost the
  pool its economy board, and AR5 will want it back. Raising it is a change to
  the shared match loop and belongs in a ticket that can re-run both committed
  balance reports.
- **A match seats exactly two candidates**, so every three- and four-army board
  in the roster is out of reach of the arena as it stands.
- **The margins are unused** for the reason measured above, so a decisive win is
  graded by speed alone.
- **Nothing here searches yet.** AR5 is the first real search; this milestone
  ships the ruler, not the thing being measured.
