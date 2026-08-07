# The AI Arena's first search campaign

**Measured 2026-08-05.** Seven blocks of planner dials searched independently
against the three shipped tiers, then composed and re-measured. This is AR5's
written result: what it cost, what each block found, and **how much the dials are
worth end to end**.

`docs/ai_arena.md` is the instrument — the fitness, the pools, the anchors and
the search harness. This document is one measurement taken with it, and a later
campaign supersedes this file rather than editing around it.

> **Standing verdict.** The dials are worth a great deal *against these three
> opponents*: the shipped Normal profile wins **49.3%** of its held-out matches
> against `easy`, `default` and `hard`; the composed vector wins **93.8%** of the
> same matches, on boards and seeds no search ever saw. The seven blocks'
> effects **add** rather than cancel, and the composition beats every part of it.
> The plan expected this to be modest and said in writing that a large answer
> would mean it was wrong about the ceiling (AR5's exit clause). The answer is
> large. What it is *not* is proof that the policy's ceiling is high — see
> [What the number is not evidence of](#what-the-number-is-not-evidence-of).
> The shelf it searched is the shelf as it stood on 2026-08-05: COM-65's
> `supply_weight` and `supply_unit_target` have since landed live on every tier
> and no search has touched them — the composed vector carries the shipped
> values for both, and they are the first thing a second campaign should cover.
> No `data/` file was edited *by the campaign* (D8); every profile it wrote is
> under `reports/`.

> **The champion has since shipped.** On 2026-08-06 a human read this document
> and seated the `everything` vector verbatim as a fourth difficulty tier —
> **Brutal**, `data/ai/brutal.tres`, which is D8 working rather than an exception
> to it: the arena recommended and a person decided. Nothing was retuned on the
> way in, so the tier and this measurement are the same sixteen numbers, and
> `tests/unit/test_difficulty.gd` pins them to each other. Everything below still
> reads as the measurement it was; the caveats in [What the number is not evidence
> of](#what-the-number-is-not-evidence-of) shipped with it and are repeated in the
> profile's own header. It is outside the DF4 ladder gate
> (`docs/difficulty_check.md` §1), so both committed balance reports are
> unmoved.

## What it cost

| | matches | wall clock |
|---|---:|---:|
| The seven blocks | 92,016 | 15h42 (05:06 → 20:48) |
| The composition run | 1,728 | 22 min |
| **Total** | **93,744** | **~16h04** |

Six workers throughout, 60–125 matches/min depending on board and machine load.
Per block: `join` 3,312 · `formation` 10,800 · `threat` 11,664 · `combat` 12,240
· `production` 16,848 · `economy` 18,576 · `economy_map` 18,576.

**Every hard invariant held across all 92,016 matches**: zero rejected commands,
zero cap stalls, zero per-turn cap hits, in roughly 40 million commands. 99.06%
of matches ended decisively (82,461 routs, 8,690 HQ captures); 865 reached the
day cap and were scored 0.0 to both sides.

That clean run is itself a result, because the campaign before it failed all
seven blocks on a command-cap stall. **71 of these matches exceeded the old flat
3,000-command cap and two exceeded 6,000, the longest at 8,907** — a 184-unit
army on `arsenal` at day 101. A constant chosen off the previous campaign's
measured worst case (5,226) would have failed this one too; the derived
`BalanceMatchEngine.command_ceiling` (60,802 at this horizon) was never
approached. See `docs/balance_sim.md`, *How a match is bounded*.

## How much the dials are worth, end to end

Seven block results are not that number: each block held every other dial at the
shipped value, so the effects might add, cancel or interact. So they were
composed into one vector and re-measured against the same fixed anchors, both
pools, both seatings.

### How a composition was built

Three of them, nested, so the answer is attributable:

| | blocks composed | dials moved |
|---|---|---:|
| `winners` | `threat`, `production` — the two whose held-out gain was outside noise | 7 |
| `generalisers` | + `formation`, `combat`, `join` — the three that measured level | 12 |
| `everything` | + `economy`, `economy_map` — the two that measured *negative* alone | 16 |

Two dials were claimed by two blocks each, and one rule settles both:
**a borrowed dial's value comes from the block that owns it.** A block borrows a
dial (`ArenaBlocks.couples`) so it is not fitted against a stale valuation, not
so it can set someone else's number. So `condition_weight` is `combat`'s 0.25 and
not `join`'s 0.15, and `capture_unit_target` is `production`'s 0 and not
`economy_map`'s 7.

That rule turns out to be load-bearing rather than cosmetic — see the
`economy_map` section.

### The result

| candidate | training | held out | gap |
|---|---:|---:|---:|
| `everything` (16 dials) | +1.226 | **+1.220** | **+0.006** |
| `generalisers` (12 dials) | +1.190 | +1.100 | +0.090 |
| `winners` (7 dials) | +1.120 | +1.002 | +0.118 |
| the shipped Normal vector | −0.092 | +0.051 | −0.143 |
| best single block (`production`) | +1.121 | +0.944 | +0.177 |

**The effects add.** Every composition beats every one of its parts, and the
widest one wins: `everything` at +1.220 against `production` alone at +0.944 and
`threat` alone at +0.444. They are *sub*-additive — 0.444 + 0.944 is 1.388 and
`winners` scored 1.002 — so the blocks do compete for the same wins, but nothing
cancelled.

Head to head on the held-out pool, both seatings, decisive matches only:

| candidate | vs `easy` | vs `default` | vs `hard` |
|---|---:|---:|---:|
| the shipped Normal vector | 76.1% | 50.0% | 29.2% |
| `winners` | 91.7% | 89.6% | 78.7% |
| `generalisers` | 100.0% | 93.8% | 78.3% |
| `everything` | 97.9% | 95.7% | **91.7%** |

**The end-to-end number: the dials take the shipped Normal profile from 49.3% to
93.8% of its matches against the three tiers, on ground it never trained on.**
In fitness, +0.051 → +1.220, a gain of **+1.169**.

That number survives the one objection its shape invites. The base vector is a
copy of the `default` anchor, so a third of its matches are a known draw (exactly
50.0% above, which is the fitness function's zero-sum property confirming itself).
Re-scored over `easy` and `hard` only, with no mirror in it, the base reads +0.076
and `everything` +1.224 — the same answer.

It is also not board-dependent, which the tier ladder in `docs/ai_arena.md`
emphatically is. Held out, board by board:

| candidate | `timberline` | `crossfire` | `first_steps` |
|---|---:|---:|---:|
| `everything` | +1.287 | +1.297 | +1.076 |
| `generalisers` | +1.337 | +0.926 | +1.038 |
| `winners` | +1.199 | +0.648 | +1.159 |
| the shipped Normal vector | −0.092 | −0.143 | +0.387 |

All three compositions beat all three anchors on all three boards. Where the
shipped tiers reverse their order board to board, this does not.

### What the number is not evidence of

The held-out pool holds out **boards and seeds. It does not hold out opponents.**
Every candidate in this campaign was selected against `easy`, `default` and
`hard` and is reported against `easy`, `default` and `hard`. So +1.220 says the
vector generalises across ground, and says nothing about whether it generalises
across opponents. D7 named that risk and answered it with an archive sampled as
an opponent; this harness keeps one incumbent rather than a population and does
not do that, which is recorded as a known limit in `docs/ai_arena.md`. **A
champion that beats the three tiers and loses to its own ancestors is a result
this campaign could not have seen.**

Four more boundaries, none of them small:

- **Commander-free** (R8). Every match seated the neutral doctrine, so
  `doctrine_weight` is inert and every commander passive that re-prices a
  forecast is absent.
- **Land duels only.** Seven boards, two armies, no naval and no three- or
  four-seat board.
- **Three opponents.** A round-robin against three fixed vectors is a narrow
  test of "better".
- **It optimises winning a headless match against a machine**, and the product is
  a game a person plays (R4, D8). One shape of that risk is visible in the data
  already: the composed vector fields far bigger armies than the shipped one —
  median 15 units alive at the end against the base's 0, with a tail to 115 —
  while *shortening* matches (median day 22 against 32) and taking more HQs. It
  is not the ninety-day turtle R4 predicted. Whether a 100-unit swarm is a better
  opponent or merely a better score is exactly what AR7's watched match is for.

## The training/validation gap

R1 calls this the headline diagnostic rather than a footnote, and the campaign
earned that framing: **the block that led on training by the widest margin is the
one that failed hardest on boards it had never seen.**

| block | training | held out | gap |
|---|---:|---:|---:|
| `economy_map` | +0.464 | **−0.444** | **+0.908** |
| `formation` | +0.274 | +0.084 | +0.190 |
| `production` | +1.121 | +0.944 | +0.177 |
| `economy` | −0.002 | −0.146 | +0.144 |
| `combat` | +0.114 | +0.086 | +0.028 |
| `everything` (composed) | +1.226 | +1.220 | +0.006 |
| `threat` | +0.341 | +0.444 | −0.103 |
| `join` | −0.031 | +0.099 | −0.130 |

Read the sign: a positive gap is ground lost when the boards change. Two things
stand out.

**A large gap is a warning that a leaderboard cannot give.** `economy_map` at
+0.464 training is the second-best block in the campaign; at −0.444 held out it is
the worst, and worse than the vector it started from. Selected on training alone
it would have been reported as a success. The whole cost of the held-out pool —
one third of the campaign's compute — is buying that one sentence, and it paid.

**Composition collapsed the gap rather than widening it.** The three compositions
have gaps of +0.118, +0.090 and +0.006, all narrower than the mean block's. The
naive expectation is the opposite: sixteen dials fitted on four boards should
overfit harder than four dials. It did not, and the honest reading is that the
*search* overfits rather than the *dials* — a block that walks eight waves down a
gradient on four boards is fitting those boards' particulars, while composing
already-chosen values adds no further fitting. That is a hypothesis this campaign
suggests and did not test.

## The seven blocks, separately and in order

Searched in ascending order of width so the cheap answers landed first (R7).
Every block started from `data/ai/default.tres` with every other dial held there,
so each row is attributable to the dials it moved.

| block | matches | waves | training | held out | what moved |
|---|---:|---:|---:|---:|---|
| `join` | 3,312 | 4 | −0.031 | +0.099 | `condition_weight` 0 → 0.15 *(borrowed)* |
| `formation` | 10,800 | 8 | +0.274 | +0.084 | `cohesion_tiles` 1.0 → 2.125, `cohesion_radius` 2 → 1 |
| `threat` | 11,664 | 8 | +0.341 | **+0.444** | `threat_aversion` 0 → 0.175, `advance_threat_tiles` 0 → 0.5, `cover_tiles` 0 → 0.125 |
| `combat` | 12,240 | 6 | +0.114 | +0.086 | `kill_bonus` 1.6 → 1.2, `counter_weight` 0.6 → 0.4, `condition_weight` 0 → 0.25 |
| `production` | 16,848 | 8 | +1.121 | **+0.944** | `capture_unit_target` 3 → 0, `duplicate_priority_cost` 3 → 1, `save_up_turns` 2 → 0, `build_reactivity` 0 → 0.6 |
| `economy` | 18,576 | 7 | −0.002 | −0.146 | `capture_progress_bonus` 45 → 75, `step_cost_penalty` 4.0 → 0.0 |
| `economy_map` | 18,576 | 8 | +0.464 | −0.444 | `capture_claim_depth` 0 → 1, `production_capture_multiplier` 1.0 → 2.0, `capture_unit_target` 3 → 7 *(borrowed)* |

Against a per-candidate standard error of roughly 0.1 on the held-out pool, only
`threat` and `production` are clearly separated from the base vector's +0.051.
`join`, `combat` and `formation` are level with it; `economy` and `economy_map`
are below it.

**`production` carries most of the campaign's return, and it is the result to be
most careful with.** Its direction is: keep no dedicated capture roster
(`capture_unit_target` 0), bank nothing (`save_up_turns` 0), barely discount a
repeated build (`duplicate_priority_cost` 1), and re-rank the build list against
what the enemy actually fields (`build_reactivity` 0.6). That is "spend
everything, every turn, on whatever counters them", and it is what produces the
enormous armies above. It is one block, on one instrument, commander-free,
against three anchors, on seven land boards. **It is evidence that the shipped
production weights are far from optimal against this fitness; it is not evidence
that this is the production policy to ship.**

**Two dials measured worthless and stayed at zero**, and both are AR6's own
acceptance gates answering:

- **`withdraw_weight`** — searched properly for the first time in the `threat`
  block, since AR6d had just unpinned it. It ended at 0.0. So the dial was at
  zero for a reason after all, not only for the defect AR6d fixed; AR6d was still
  worth doing (a refuge that gives up its own firing ring was wrong regardless),
  but it did not make the dial pay.
- **`join_weight`** — AR6c's dial. The `join` block moved **only its borrowed
  `condition_weight`**, leaving `join_weight` at 0.0 through four waves. So AR6c
  bought a capability the search declined to use.

Both now stand exactly where `focus_fire_bonus` stands: implemented, tested,
shipped at zero, one edit from being re-tried. That is the established remedy
here, and it is the honest outcome of a gate that was allowed to say no.

## `economy_map`, reported apart

This block is separated from the rest because it was the only genuinely unmapped
ground in the campaign. Its four dials — `capture_units_per_property`,
`capture_claim_depth`, `production_capture_multiplier`,
`capture_goal_value_tiles` — all ship **inert on every tier** from the AI Economy
plan's AE1–AE3, and nobody had ever measured any of them. If the arena's whole
return had lived here, that would have been a finding about *that* plan rather
than about this project.

**It does not live here.** `economy_map` is the worst block in the campaign on the
held-out pool: −0.444, below the vector it started from, with the widest
overfitting gap measured (+0.908). Of its own four dials the search moved two —
`capture_claim_depth` 0 → 1 and `production_capture_multiplier` 1.0 → 2.0 — and
left `capture_units_per_property` and `capture_goal_value_tiles` at their inert
zero across eight waves. Its largest single move was on a **borrowed** dial,
`capture_unit_target` 3 → 7, in the exact opposite direction to the value
`production` found best (0) over its own 16,848 matches.

That opposition is the block's most useful output. `capture_units_per_property`
raises the `capture_unit_target` floor, which is why the two had to be searched
together; searched together, one block wanted seven capture units and the other
wanted none, and the one that wanted none was measured over more matches and
generalised far better.

Two qualifications, both of which cut against reading this as a verdict on AE1–AE3:

- **The block's failure is a search failure, not necessarily a dial failure.**
  When `economy_map`'s two *own* dials are composed with everything else — with
  `capture_unit_target` coming from `production`, per the ownership rule — the
  result is `everything`, the best vector in the campaign. So those two dials
  contribute positively in company while their block's champion loses badly
  alone. The difference between the two is precisely the borrowed dial.
- **Two of the four dials were never moved off zero at all**, so this campaign
  has measured nothing about `capture_units_per_property` or
  `capture_goal_value_tiles` beyond "a compass search starting at zero did not
  step off it".

Written down here because nobody will re-run 18,576 matches to rediscover a
negative result.

## What the instrument said about itself

**The search refused the exploit it was warned about.** R2 named
`save_up_turns` as a known exploitable seam: banking hands whoever moves first a
timing edge, measured at +5.6 pp with no banking, +14.9 at two turns and +20.2 at
three, and D5's both-seatings scoring is the only thing stopping a search from
buying it. The search moved the dial **2 → 0**, the opposite direction: it gave
the edge up. Both halves of the warning came true at once — the seam is real, and
the scoring closed it.

**The fixed anchor set is comparable across runs, demonstrated rather than
assumed.** The base vector was written as eight separate files in eight
independent runs, and scored **−0.092 training and +0.051 held out in every one**.
That is what makes a block champion's number comparable with a composition's
without replaying it, and it is D7's fixed anchor set doing exactly its job.

**The champion is legible, in the direction the plan predicted.** AR5's
acceptance criterion asks for a champion whose dials can be explained, and
guessed that if the Grand Atlas was right about timidity winning long games it
would show "high threat aversion and low kill bonus". Two blocks that share no
dial found exactly that: `combat` moved `kill_bonus` 1.6 → 1.2 and
`counter_weight` 0.6 → 0.4, and `threat` moved `threat_aversion` 0 → 0.175 with
`advance_threat_tiles` 0 → 0.5. Value a kill less, discount a counter more,
notice incoming fire. The prediction was made before the instrument existed and
the instrument met it.

**One thing was predicted and not observed.** `economy`'s champion sets
`step_cost_penalty` to 0, and `_cover_score = step_cost_penalty × _cover_tiles`,
so composing `economy` with `threat` should switch off cover's attack-path term
while `threat` fitted `cover_tiles` with that penalty at 4.0. It was written down
before the composition ran. `everything` carries both and still beats
`generalisers` by +0.120 held out, so either the term was worth little at
`cover_tiles` 0.125 or the loss is swamped. The interaction is real in the code
and too small to see at this width — which is the cost of blocking (R5), paid and
measured rather than assumed.

## What is still owed

- **AR7**: the champion at a table, described in prose by a human. Nothing here
  can answer whether a 100-unit swarm that wins by day 22 is a better opponent.
- **An opponent-generalisation test.** Every number here is against three fixed
  vectors that were also the selection pressure. The cheapest instrument is D7's:
  re-score the composed vector against the seven block champions and the base,
  which are already on disk under `reports/ai_arena/search/*/candidates/`.
- **A commander spot-check** (R8), before any of this is read as a tier
  recommendation.
- **`ironworks` back in the pool.** It was excluded for reaching the command cap,
  and that cap has been corrected; re-admitting it is a measurement nobody has
  taken, and it belongs to a run that has not started.
- **The two AE dials never moved off zero.** A probe that starts them away from
  zero would say more than this campaign did.

## Reproducing this

Everything is under `reports/`, which is gitignored: `reports/ai_arena/search/`
holds the seven blocks (per-wave `leaderboard.json`, `search.json`, and every
candidate profile ever written under `candidates/` with an `index.json` mapping
each back to its vector), and `reports/ai_arena/composition/` holds the
composition run, its `spec.json`, and the predictions written down before it ran.

The composition was played with the existing instruments and no new code:

```sh
Godot --headless --path . -s res://tools/run_arena_candidates.gd -- \
  --spec=reports/ai_arena/composition/spec.json
tools/balance_pool.py --preset=arena --maps=scrimmage,riverline,arsenal,jet_stream \
  --pairings=<each candidate>::<each anchor> --seeds=12 --seed-offset=0 \
  --days=100 --batch=4 --workers=6 --out=ai_arena/composition/training
Godot --headless --path . -s res://tools/run_arena_report.gd -- \
  --matches=reports/ai_arena/composition/training/matches.json \
  --out=ai_arena/composition/training
```

and the same three lines for the held-out pool
(`--maps=timberline,crossfire,first_steps --seeds=8 --seed-offset=12`).
