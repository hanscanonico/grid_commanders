# Balance Lab

Two independent AIs on any shipped board, each side carrying any commander at
any difficulty tier, over N seeded matches with both seats swapped — recording
not just who won but a turn-by-turn timeline of *how*. This is the committed
record of the balance-simulator plan's **BS1–BS4**.

It is an **instrument, not a gate**. Like `make commander-balance` and
`make difficulty-check` it stays out of `make verify` and `make test`; only its
own unit tests (`tests/unit/test_balance_engine.gd`,
`tests/unit/test_balance_recorder.gd`) are in the suite. Generated reports are
not committed — they live under `reports/`, which is gitignored. The one gate
over this code is `make determinism`, and it measures reproducibility rather than
balance: [the committed side of the merge bar](#the-committed-side-of-it-make-determinism).

## The instruments

| Tool | Question it answers |
|---|---|
| `make commander-balance` | Is the commander roster balanced against itself? (`docs/commander_balance.md`) |
| `make difficulty-check` | Do the tiers actually order Easy < Normal < Difficult? (`docs/difficulty_check.md`) |
| **`make balance-sim`** | **Everything in between, plus *why*.** |
| `make ai-arena` | Which of two arbitrary `AIProfile`s plays better? ([below](#seating-an-arbitrary-candidate-arena-plan-ar3)) |

All four run the same match loop — `tools/balance/match_engine.gd` — so a number
one reports means the same thing in the others. Each is a **preset** over it and
keeps its own CLI, because two committed documents cite their exact flags. The
extraction's merge bar was a fixed-seed byte-diff of both their reports before
and after; see [Extraction](#the-extraction-plan-d1).

## Running it

```sh
# one matchup, full telemetry — "why does Gideon crush Cass here?"
make balance-sim SIM="--map=ironworks --red=gideon_holt:normal --blue=cass_orlov:normal --seeds=10"

# mixed tiers and doctrines — "is Difficult worth a commander handicap?"
make balance-sim SIM="--map=scrimmage --red=cass_orlov:hard --blue=gideon_holt:easy --seeds=15"

# sweep axis 1 — every commander (vs --blue) at one tier on one board
make balance-sim SIM="--map=the_straits --sweep=commanders --tier=normal --seeds=4"

# sweep axis 2 — map fairness: identical mirror on every shipped board
make balance-sim SIM="--sweep=maps --red=none:normal --blue=none:normal --seeds=6"

# sweep axis 3 — the tier ladder, with doctrines allowed on both sides
make balance-sim SIM="--sweep=tiers --map=scrimmage --commander=alina_ward --seeds=15"

# watch a match from the report live — same spec + seed = the same battle
make balance-watch SIM="--map=ironworks --red=gideon_holt:normal --blue=cass_orlov:normal --seed=1003"
```

### A side is `<commander>:<tier>`

Commander id or `none`; tier `easy`/`normal`/`hard`. Both halves are optional
(`gideon_holt`, `:hard`, or nothing) and default to `none:normal`. Ids are
checked against the databases, so a typo fails the run instead of quietly
measuring a neutral matchup.

**A tier is only which `AIProfile` plans that side's moves.** No income tilt, no
vision, no damage or luck differs at any tier, in either direction — the
difficulty plan's D2/D3 lock. Mixing tier and commander per side is new
*measurement*, not new mechanics.

### Flags

| Flag | Meaning |
|---|---|
| `--map=` | Any shipped board, or a balance fixture (`clash`, `ridge`, `combined`, `holdings`, `channel`) |
| `--red=` / `--blue=` | Side specs; default `none:normal` |
| `--seeds=` | Paired seed count, default 4. Each seed plays **both seats** |
| `--seed=` | One specific seed instead — replays a single row |
| `--seed-offset=` | Start `--seeds=` counting N seeds into the range — how a shard of a parallel run asks for its slice of it |
| `--days=` | Day cap before a match is scored on points, default 20 |
| `--sweep=` | `commanders`, `maps` or `tiers` — one free axis per run |
| `--tier=` | The tier both sides play at, for `--sweep=commanders` |
| `--commander=` | The doctrine both sides carry, for `--sweep=tiers` |
| `--no-commands` | Skip `commands.jsonl`; a large sweep's is big |
| `--replays` | Also write a watchable recording per match, into `replays/` |
| `--out=` | Output directory under `reports/`, default `reports/balance_sim/<run-name>` |

**One axis per run** (plan D5). Commanders × tiers × maps × seeds is a six-figure
matrix nobody reads; a run pins everything except one swept axis, so every batch
answers one question and finishes in minutes. Broad sweeps are a *sequence* of
runs, which the deterministic seeds make exactly reproducible and comparable.

The run directory is named after the spec, never a timestamp, so rerunning a
question overwrites its own directory and two runs of it are diffable file for
file. Every flag that changes the numbers is in that name — including `--seed=`
and `--days=`, so two seed replays of one matchup, or a 20- and a 25-day run of
it, land in directories of their own instead of overwriting each other.

## What it writes

| File | Grain |
|---|---|
| `matches.csv` | one row per match |
| `timeline.csv` | one row per side per **played turn**, keyed by `match_id` (plus the one edge case below) |
| `commands.jsonl` | one line per applied command (plan Q3) |
| `summary.json` | the aggregates, the flags and the reading rules |
| `report.html` | the same numbers drawn — open it off disk, no server |
| `replays/<match_id>.jsonl` | with `--replays` only: one recording per match |

`commands.jsonl` describes what happened; a recording can be **re-issued**, which
is the difference — a suspicious row becomes a match you can watch or read. The
README's Replays section owns both, and how they differ from `balance-watch`.

### Reading the timeline

Filter one `match_id` in any spreadsheet and you watch the game: day 3 Blue banks
for a bomber, day 5 Red's army value collapses to a power spike, day 8 the
property lines cross.

| Column group | Columns | Detail |
|---|---|---|
| Key | `match_id · day · team · commander · tier` | Joins to `matches.csv` for map, seed, seats, outcome |
| Money | `funds_start · income · plunder · plunder_off_turn · spent · funds_end` | See below |
| Production | `built · built_value` | `infantry x2;tank` and its summed cost |
| Combat | `killed · lost · killed_value · lost_value` | See attribution below |
| Board | `merged · forfeited · unit_count · army_value · properties · captures` | End-of-turn strength; `army_value` = Σ cost × HP fraction, because a 2 HP tank isn't a tank |
| Powers | `power_charge · power_fired` | Meter percentage at turn end; whether the power went off |
| Cost | `commands · planning_ms` | Commands issued and AI planning time |

**A row covers everything from that side's start-of-turn tick to its own
`EndTurnCommand`**, so every event in the match lands in exactly one row. That
seam matters: a side's income, its paid repairs and any unit that dies with a dry
tank all happen inside the *previous* side's `EndTurnCommand`, and they belong to
the incoming side's row.

The one row that is *not* a played turn is that seam's own edge. A match can end
on the tick that opens a turn nobody then plays — the day cap falls, or the tick
strands a side's last aircraft and routs it. When that tick took a unit off the
board the row is filed anyway, with `commands = 0`: the death is real, the census
below has to see it, and it is worth reading in the timeline rather than only
balancing an equation. An otherwise empty final row is dropped.

**`income` is the whole start-of-turn tick** — property income less any repairs
paid on it — because that is what can be observed without re-deriving a rule the
sim owns. A commander economy hook would therefore show up here as a residual
rather than hide. **`plunder` is the signed funds transfer caused by kills during
the turn**: positive for the bounty earner and negative for the victim. Within
the turn the only ordinary spend is production, so
`funds_start + plunder − spent = funds_end` closes exactly, and the run fails if
it ever doesn't.

A bounty has two ends and only one of them is on turn, so **`plunder_off_turn` is
the other end**: what enemy bounties took from this side — or what its own
counter-fire took back — since its previous row. It is a signed number outside the
row's own window, and it is what keeps the *row-to-row* relation exact:
`funds_end` (previous row) `+ income + plunder_off_turn = funds_start`, checked
per match like the equation above.

**`planning_ms` is the one wall-clock column.** Everything else in a timeline row
is a pure function of (map, seed, side specs) and reproduces byte for byte; this
one measures how long the planner thought and cannot. The determinism test
compares rows with it excluded, and `make determinism` keeps the file out of its
golden for the same reason.

The tally cells — `built`, `killed`, `lost` — are alphabetical, and are sorted as
Strings to be so: sorting them as `StringName`s orders by intern position, which
is the order the ids were first mentioned by a loading script. That was a real
flap in `timeline.csv` (`recon;mech`), not a hypothetical one.

### Kill and loss attribution (plan D3)

A unit leaving the board is not always a death. Removals are classified by **the
command that caused them**, never by blindly diffing the board:

| Cause | Recorded as |
|---|---|
| `AttackCommand`, target dies | the acting side's `killed` |
| `AttackCommand`, attacker dies to counter-fire | the acting side's `lost` |
| `EndTurnCommand`, an empty tank at the start-of-turn tick | the owner's `lost` |
| `CaptureCommand`, a home HQ falls and its owner is eliminated | `forfeited` — neither a kill nor a loss |
| `JoinCommand`, the mover merges into its twin | `merged` — neither a kill nor a loss |
| `LoadCommand`, a passenger boards | **nothing** — it never left `state.units` |

An eliminated army's remaining units are **forfeited, not killed**: nobody shot
them, so crediting the capturer with destroying an army at full cost would inflate
every exchange figure the report reads off `killed_value`. They still leave the
board, so the census counts them.

Anything else that removes a unit is *unattributed*, and unattributed removals
fail the run. Every match is also reconciled against its own final board:

```
started + built − lost − killed-by-the-enemy − merged − forfeited  =  units on the board
```

A miscount is a red build, not a quiet lie in the data someone then tunes
against. Each case is pinned by a test in `tests/unit/test_balance_recorder.gd`.

## How to read the judgement

`summary.json` and the HTML report apply the same bands as
`docs/commander_balance.md`, so a Balance Lab number is read against the
committed thresholds:

| Measure | Band | Meaning |
|---|---|---|
| Side-normalized win rate per swept value | **45–55%** | preferred |
| Same | **40–60%** | warning — investigate before merge |
| First-seat bias (games with a winner) | **≤ 5 pp** | map/seed fairness |
| Rejected AI commands, cap stalls | **0** | **hard** — the run exits 1 |

Only the hard invariants fail the run. Out-of-band win rates are review triggers,
per the standing rule: **do not balance to the AI leaderboard alone.**

The summary also emits *reading rules* as data, so they travel with the numbers
instead of living in a document nobody has open:

- **Low confidence.** Under 50% of a value's games resolved on the board (`rout`
  or `hq`); the rest were settled by the day-cap tiebreak, which
  `docs/difficulty_check.md` §6's superseded finding (a) showed can turn over on
  noise and score the known-weaker side. Probe with a longer `--days=` before believing the
  ordering. *"Resolved" and "decisive" are deliberately different words here:* a
  day-cap game **has** a winner and counts as decisive, but it was not resolved
  on the board.
- **AI-bounded.** The board can build hulls (today: `isthmus`, `the_straits`).
  The AI never plans a ferry, so a result there reflects what the AI can express
  on water, not what the board is worth to a human. A documented reading rule,
  not a fix — fixing it is AI work owned by the naval plan's standing R1. The
  flag is derived from `TerrainType.builds`, not a map name, so a board that
  gains a port is annotated the day it does and only then.
- **Mirror.** With both sides identical, the win-rate column is the *first
  seat's* rate and not a balance reading — which is exactly what a mirror sweep
  is for. Its answer lives in the bias table. (Mirror matchups play one seat per
  seed rather than two, because swapping the seats of a mirror replays the
  identical match.)

## Watching a match (BS3)

Any spec the Lab can score it can also **show**. `make balance-watch` boots the
real battle scene, windowed, with both sides AI-driven and the match RNG pinned:

```sh
make balance-watch SIM="--map=clash --red=viktor_draeg:hard --blue=cass_orlov:easy --seed=1138"
```

Nothing is recorded or streamed from the harness — the scene simply runs the same
deterministic pipeline, animated at whatever game speed this device is set to
(README's *Game speed*; `--speed=instant` skips the theatre for one run and is
the quickest way to watch a long match out). That works because the AI
plans from state alone (lookahead-free, RNG-free) and only `CombatResolver` draws
from the seeded `state.rng`; `BattleAiRunner`'s pacing delays are pure
presentation and touch no sim state.

The scene prints `watch: team N wins on day D` and exits when the match ends, so
the fidelity check is a diff against the `matches.csv` row, not someone watching
a window and remembering.

**Watch mode honours `--days=` too** (default 20, the Lab's default). Most rows
terminate `day_cap` — a rule-based AI rarely races to an HQ — and those are
scored on the same `BalanceMatchEngine.tiebreak` the harness uses, so a capped
row can be watched to the same line as a decisive one. The cap is watch mode's
alone: a hot-seat or player-versus-AI match still runs until somebody wins.

One alignment detail rides along: the scene's per-turn command cap and the
harness's now come from one constant (`BalanceMatchEngine.MAX_COMMANDS_PER_TURN`),
so neither can cut a game the other would let run.

## The extraction (plan D1)

`tools/run_commander_balance.gd` kept its CLI and both committed gates; the
shared loop moved to `tools/balance/`. The merge bar was a fixed-seed byte-diff of
both reports before and after:

| Gate | `matches.csv` | `summary.json` |
|---|---|---|
| `make commander-balance BAL="--commanders=alina_ward,cass_orlov,gideon_holt --seeds=2"` | identical | identical |
| `make difficulty-check DIFF="--seeds=2 --days=12"` | identical | identical |

That second row used to read *identical bar `turn_ms`*: mean planning wall-clock
was written into the difficulty gate's `summary.json`, which made this bar
unmeetable exactly where it was being claimed. It is written to `timing.json`
beside the two reports now, and printed to stdout as it always was, so both
diffed artifacts are byte-stable and `docs/difficulty_check.md` reads its timings
where it always did.

### The committed side of it: `make determinism`

The bar above was also a *procedure*: `reports/` is gitignored, so there was
nothing committed to diff against and it ran when somebody remembered.
`make determinism` is that missing side — one pinned match (`clash`, seed 1000,
20 days, `--no-commands`, about a second) whose `matches.csv` and `summary.json`
are committed under `tests/fixtures/determinism/` and byte-diffed on every run.
It is cheap enough to sit in CI beside the four `make verify` gates, and
`tools/check_determinism.sh` owns the pinned flags.

A rules, data or planner change is *supposed* to move it. The diff it prints is
what that change did to one whole match — read it, then accept it with
`make determinism REFRESH=1` and say in the commit which change moved it. The
full-size presets stay the release tools they are; this is the tripwire under
them.

`timeline.csv` and `report.html` are deliberately out of the golden: both carry
`planning_ms` (below). Their numbers still reach the diff, aggregated into
`summary.json`.

The balance fixtures live in `maps/fixtures/` rather than in that file, so the
Lab can name one with `--map=` and the battle scene can boot one for watch mode.
That directory is deliberately *not* `maps/` itself: `MapCatalog.paths()` scans
only the top level, so a fixture stays out of the menu, the map lint and the
per-map AI soak, while `MapCatalog.resolve()` — the single answer to "which board
is this name?" — finds both.

## Does the instrument agree with the committed record?

A first calibration run, 200 matches, every commander against No Commander at
Normal on `clash`, 8 seeds, 25-day cap:

```sh
make balance-sim SIM="--map=clash --sweep=commanders --tier=normal --seeds=8 --days=25"
```

| Commander | Lab win rate | `docs/commander_balance.md` |
|---|---|---|
| Gideon Holt | 87.5% (highest) | named high ✅ |
| Cass Orlov | 25.0% (lowest) | named low ✅ |
| Tomas Reed | 62.5% | named high — directionally agrees ✅ |
| Rhea Sol | 50.0% | named low — **does not reproduce here** ❌ |

Three of the four known outliers point the way the committed record says, and the
two extremes are the two names it calls out. Rhea Sol does not, and that is worth
stating rather than rounding off: **this is not the same measurement.** The
committed record is the full commander-versus-commander matrix over every
fixture; this is each commander against *no commander* on one board. A doctrine
that is weak against other doctrines but fine against a neutral opponent will
read differently here, which is exactly the case a vs-neutral sweep cannot see.
Use `make commander-balance` for the roster-against-itself question; the Lab's
commander sweep answers the power-level-against-baseline one.

The run also measured **+14.0 pp first-seat bias on `clash` alone**, against the
+14.9 pp the committed record measured across `clash` + `ridge` — independent
corroboration of the standing base-game bias debt, which
`docs/commander_balance.md` accepted as a deliberate trade of `save_up_turns`.
Note the confidence column: at a 25-day cap most of these games still ended on
the day-cap tiebreak, so the *ordering* between adjacent rows is soft even where
the extremes are not.

## Playing a sweep in parallel (arena plan AR2)

`make balance-pool` — `tools/balance_pool.py` — plays one matrix as several
headless Lab processes at once. It is Python because the matrix expansion, the
per-shard timeout, the deterministic merge and the JSON run record are all a few
lines of stdlib and none of them are pleasant in shell; the Grand Atlas's driver,
which this is modelled on, made the same call. It needs nothing but `python3`.

```sh
make balance-pool POOL="--maps=ironworks --pairings=none:normal/none:hard --seeds=32 --days=100"
```

| Flag | Meaning |
|---|---|
| `--maps=` | Comma list of boards |
| `--pairings=` | Comma list of `<red side>/<blue side>` — the preset's own side grammar, passed through untouched (`--preset=arena` pairs on `::`, since a side is a path and paths carry `/`) |
| `--preset=` | Which driver plays the shards: `lab` (default) or `arena` |
| `--seeds=` | Paired seeds per pairing (default 4, the Lab's) |
| `--batch=` | Seeds per shard (default 4) |
| `--days=` | Day cap; omitted, the driver's own default stands |
| `--workers=` | Processes at a time (default `min(6, cores)` — 6 is the measured peak below) |
| `--out=` | Run directory, **relative to `reports/`**, default `reports/balance_pool/<spec>` |
| `--timeout=` | Seconds per shard, default 3600 |
| `--dry-run` | Resolve the spec, print the shard plan, and stop |
| `--self-check` | Run the `--out` and resume-key rules over their cases and stop |

**Everything a run writes lands under `reports/`, and a path that would leave it
is refused before a match is played.** That rule is every instrument's, not just
the pool's: `--out=x/y` means `reports/x/y`; a leading `reports/` is accepted
rather than doubled, so both spellings work; a `res://`-spelled path is the same
directory said the other way; and an absolute path or one that climbs out with
`..` is an error at startup. That is a containment rule and not a tidiness one:
Godot's `path_join` concatenates rather than resolves, so each of those spellings
has the tool writing inside the repo under a name nobody reads while reporting
the path it was handed — `--out=/tmp/x` writes `<repo>/tmp/x` while the driver
reads `/tmp/x`, every shard reported failed with its results on disk the whole
time, and resume, which is keyed on finding a shard's `summary.json`, replaying
all of them forever. Refusing the path is what makes that unreachable.

There is one policy in two places, because the driver has to refuse a path
*before* it launches a preset and the preset is what actually writes:
`resolve_out` in `tools/balance_pool.py`, and `BalanceReportWriter.resolve_out`,
which every `--out=` in `tools/` — the Lab, the commander matrix, the difficulty
ladder, the arena and both reports — is resolved through, for the write *and*
for the line it prints. The two share one case table: `--self-check` runs it
(and `tools/check_scripts.sh` runs that, so `make check` and `make verify` gate
it), and `tests/unit/test_report_writer.gd` runs the same shapes against the
GDScript half.

**A shard is one pairing on one board over a contiguous slice of the seed
range** — the smallest unit of work that amortises the engine boot (~0.9 s
against ~2 s a match) and is still independently readable, since it writes its
own `matches.csv` and `summary.json` under `shards/`. The run directory also
holds `progress.log`, `status.txt` (poll a live run with `cat`) and `pool.json`,
which records the throughput and the load average it was measured under.

**Resumable, and that is the point.** A shard whose marker artifact exists is
skipped — `summary.json` for the Lab, `matches.json` for the arena — so a killed
sweep costs the shard in flight and nothing else; rerun the same command to pick
it up, and Ctrl-C ends the engines in flight rather than waiting them out. Both
drivers write their artifacts in one go at the end, so a shard is on disk either
complete or not at all; the marker cannot be half true.
The run directory is derived from the spec like the Lab's is, so it is also the
resume key: the same sweep asked for twice finds its own work. **A shard is keyed
on the arguments it was played with**, digest and all, so the same directory
asked for a different sweep — `--out=mine --days=20`, then `--out=mine
--days=100` — replays rather than handing back the answer to the other question.

The driver **aggregates nothing**. It expands the matrix, runs processes and
concatenates their rows in plan order, because a merged summary would be a second
opinion about numbers `BalanceRunSummary` already owns — the per-shard
`summary.json` files stay readable, and a pairing worth a closer look is re-run
through `make balance-sim` with the full instruments on — shards are played
`--no-commands`, so a sweep leaves no `commands.jsonl` behind.

### The merge bar

**A sharded run is the single-threaded run, row for row.** Measured on
`ironworks`, `none:normal` vs `none:hard`, 8 seeds, 100-day cap — one Lab run
against four shards of two seeds at four workers:

| Artifact | Result |
|---|---|
| `matches.csv` | byte-identical (`41c23a74…`) |
| `timeline.csv` | identical bar `planning_ms`, the wall-clock column the determinism test already excludes |

The same diff holds for a run that was killed halfway and resumed, which is the
proof that a resumed sweep is not a differently-played one.

**The bar earned itself on the way in.** It first failed on the timeline's
`built` / `killed` / `lost` cells — same units, same counts, different order —
and two *identical* pool runs then disagreed with each other the same way, which
ruled out the sharding. The cause was in the recorder:
`BalanceMatchRecorder._tally_text` sorted the tally's `StringName` keys, and a
`StringName` compares by its interned pointer rather than by its text, so the
cells were ordered by wherever the engine happened to allocate the ids — per
process, and alphabetical only by luck, which is exactly the promise that
function's own comment makes. It now sorts as `String`. Nothing reads those cells
but a human and `_count_of`, which counts rather than orders, so `matches.csv`
and `summary.json` cannot move — but the reports of the two committed gates carry
a `timeline.csv` whose mixed-unit cells will now read alphabetically, and
reproducibly, where before they read whatever that process's heap said.

### What it buys, measured

48 matches (`ironworks`, neutral mirror at Normal, 100-day cap, 16 shards of 3
seeds), the same workload at every worker count, run twice — once ascending, once
descending — because a machine's thermal and load state moves under you and two
readings hours apart are not comparable:

| Workers | Pass 1 (asc) | Pass 2 (desc) | Mean | Speedup | Load at start (p1 / p2) |
|---|---|---|---|---|---|
| 1 | 26.1 | 26.1 | **26.1** | 1.00× | 4.5 / 7.5 |
| 2 | 40.9 | 41.5 | **41.2** | 1.58× | 4.9 / 10.6 |
| 3 | 56.2 | 54.2 | **55.2** | 2.12× | 6.1 / 11.8 |
| 4 | 63.3 | 60.8 | **62.1** | 2.38× | 7.1 / 13.4 |
| 6 | 79.7 | 78.8 | **79.3** | 3.04× | 10.4 / 14.7 |
| 8 | 72.8 | 75.5 | **74.2** | 2.84× | 11.2 / 16.9 |

Matches per minute, on an Apple M1 with **4 performance and 4 efficiency cores**
and a **4.3 baseline load average with nothing of ours running**. The two passes
agree inside 4% at every worker count despite the load drifting from 4.5 to 16.9
across the hour, so the curve is the machine's and not the moment's.

**It peaks at 6 and regresses at 8.** Four workers is not the ceiling — the
efficiency cores are worth a further 28% — but eight is past it: the pool then
competes with the machine's own standing load for the same cores, and the
scheduler spreads each engine thinner than it fills a core. "Eight cores, one
busy" was the premise; "six workers, three times the throughput" is the
measurement.

Per match at the peak: **0.76 s of wall clock for a 100-day `ironworks` match**,
against 2.0–2.3 s single-threaded. The single-threaded figure is worth stating
carefully, because it is seed-dependent: the first four seeds of this board
average 1.6 s a match and the first 48 average 2.0 s, so a four-seed sample reads
20% cheap.

### The thread spike, abandoned

The plan's timeboxed alternative was N matches in N threads over
`WorkerThreadPool` inside one engine. It was built and measured, and it is not
being shipped:

- **Reproducibility held.** Eight matches played sequentially and then in eight
  threads produced identical digests — winner, day, command and rejection counts,
  the final RNG state, and every surviving unit's cell, HP, ammo and fuel. Zero
  mismatches.
- **The throughput did not.** 16.2 s sequential against 14.5 s threaded: **1.1×**
  for eight threads, roughly 1.7 cores busy. GDScript does not run eight
  independent interpreters, and the process pool's 3.0× is not close to being in
  reach.

Threads were an optimisation, and this one does not pay for the risk surface it
carries. The process pool ships alone.

## Seating an arbitrary candidate (arena plan AR3)

A Lab side is `<commander>:<tier>`, and both halves are checked against the
databases on purpose — so a side can be exactly **three** parameter vectors:
`easy.tres`, `default.tres`, `hard.tres`. A tournament's whole input is "play
*this* vector", and there was no grammar for it anywhere.

`make ai-arena` — `tools/run_ai_arena.gd` — is that grammar, as a **third preset
over the one match loop**: same `BalanceMatchEngine`, same seeds, same both-seats
pairing. `BalanceSideSpec` is untouched; a profile path is a different flag, not
a third field in a spec whose grammar watch mode shares.

```sh
make ai-arena ARENA="--map=scrimmage \
  --red-profile=data/ai/default.tres --blue-profile=reports/ai_arena/gen1/c7.tres --seeds=8"

# or a whole shard in one process
make ai-arena ARENA="--pairings=reports/ai_arena/gen1/shard0.json"
```

| Flag | Meaning |
|---|---|
| `--red-profile=` / `--blue-profile=` | The candidate in each seat: a path to an `AIProfile` `.tres`, project-relative or `res://`-spelled |
| `--pairings=` | A shard file — every pairing in it, played by one process |
| `--map=` | Board for pairings that name none (default `scrimmage`) |
| `--seeds=` | Paired seeds per pairing, both seats each (default 4) |
| `--seed-offset=` | Skip the first N seeds of the range, so a pool can split a pairing |
| `--days=` | Day cap, default **100** — the horizon that resolves (plan D6) |
| `--out=` | Output directory under `reports/` (default `reports/ai_arena/<spec>`) |

A shard file is those flags, once per pairing. Nearest setting wins: a pairing's
own, then the file's, then the command line's — and a key it does not recognise
is refused rather than ignored, because `offset` for `seed_offset` would replay
the front of the seed range and the shard would look healthy.

```json
{"map": "scrimmage", "seeds": 4, "days": 100, "pairings": [
  {"red": "data/ai/default.tres", "blue": "reports/ai_arena/gen1/c7.tres"},
  {"map": "clash", "red": "data/ai/hard.tres", "blue": "reports/ai_arena/gen1/c7.tres"}]}
```

**Commanders are neutral throughout**, so `doctrine_weight` is inert and a
candidate is measured as a planner rather than as a general. That is a scope
choice, and the plan records it as R8.

### What it writes

One artifact: `matches.json`, an array of one record per match.

```json
{"match_id": "clash#default_vs_hard#s1136", "map": "clash", "seed": 1136, "seat": 0,
 "red": "data/ai/default.tres", "blue": "data/ai/hard.tres",
 "winner": 2, "termination": "rout", "day_ended": 13, "commands": 127,
 "rejected": 0, "cap_stall": false, "turn_cap_hits": 0,
 "red_units": 0, "blue_units": 6, "red_props": 0, "blue_props": 3,
 "red_funds": 28400, "blue_funds": 7000, "red_army_value": 0, "blue_army_value": 27590}
```

Which fields, and why exactly these: the plan's D4 builds fitness from the winner,
the day it ended and the property / surviving-unit / army-value margins, and D6
needs to know a scored result from a decided one — `termination` says which, so
nothing downstream has to re-derive it. `rejected`, `cap_stall` and
`turn_cap_hits` are the hard invariants: a match where the AI and the rules
disagreed is not a result, and a run that produced one exits 1.

**No CSV, no timeline, no `commands.jsonl`.** At arena volume the telemetry is
the dominant write cost and answers a question nobody is asking; a single
interesting pairing is re-run through `make balance-sim` with every instrument
on, which is what the two being one engine buys.

### The merge bar

**The arena plays the Lab's matches.** Both presets read one schedule —
`tools/balance/match_schedule.gd`, which owns the seed range and which seatings a
matchup plays — so the check is that the two agree match for match. Measured on
`clash` and `ridge`, three pairings each (`normal` vs `hard`, `easy` vs `normal`,
and a mirror), 3 seeds, 30-day cap: **30 arena records against 30 Lab rows, keyed
on (board, seed, seat, red profile, blue profile), identical in all 15 fields
both emit** — winner, termination, day, commands, rejected, cap-stall, turn-cap
hits and the four per-side margins. The mirror pairing plays 3 matches in each,
not 6: one seating, from the same authority.

The two files are shaped differently on purpose — the arena emits fewer columns —
so the bar is that comparison rather than a `diff`. It is worth re-running after
any change to the schedule, the engine or either driver:

```sh
make balance-sim SIM="--map=clash --red=none:normal --blue=none:hard --seeds=3 --days=30 \
  --no-commands --out=reports/bar/lab"
make ai-arena ARENA="--map=clash --red-profile=data/ai/default.tres \
  --blue-profile=data/ai/hard.tres --seeds=3 --days=30 --out=reports/bar/arena"
# then compare reports/bar/arena/matches.json against reports/bar/lab/matches.csv
# on (map, seed, seat), field for field
```

### A matrix of candidates

`make balance-pool POOL="--preset=arena …"` plays one, on several cores and
resumably. Sides are paths, so its pairings separator is `::`:

```sh
make balance-pool POOL="--preset=arena --maps=scrimmage \
  --pairings=data/ai/default.tres::reports/ai_arena/gen1/c7.tres --seeds=32 --days=100"
```

Everything else about the pool is unchanged, because none of it was
format-specific: the shard plan, the digest resume key, `status.txt`,
`progress.log` and `pool.json` are the same code either way. What the preset
selects is the driver, the flags a shard is handed, the marker resume reads and
how the shards are merged — JSON records for the arena, where the Lab merges CSV
rows. The merged `matches.json` is what a single arena process of the same spec
writes, record for record.

## Runtime

Measured on the vendored Godot 4.7.1, headless, on an Apple-silicon laptop:

| Run | Matches | Wall clock |
|---|---|---|
| One matchup, 2 seeds, 12-day cap | 4 | ~2 s |
| Neutral mirror across all 12 boards, 3 seeds, 15-day cap | 36 | ~20 s |
| One matchup, 6 seeds, 25-day cap | 12 | ~11 s |

**The table predates AR1's plan cache (COM-154)**, which made a headless match
several times cheaper without moving a single result — read it as an upper bound
until a run re-measures it.

Matches are tens to hundreds of milliseconds each; telemetry is reads and
appends and does not measurably change that — and `planning_ms` lands in every
row, so if the recorder ever *did* get expensive it would be visible in its own
output. `commands.jsonl` is the one large artifact: budget roughly 170 bytes per
command, so a 1 700-match batch is over 100 MB. Pass `--no-commands` for sweeps
you do not intend to step through.
