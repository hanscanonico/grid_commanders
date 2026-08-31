# AI Arena search

Base `data/ai/easy.tres`, anchors data/ai/easy.tres, data/ai/default.tres, data/ai/hard.tres.

Compute spent: **97920 matches played**, 129024 read, 696.2 min of pool wall clock, 140.7 matches/min at 15 workers. Total wall clock 697.0 min.

## combat

The axis the tiers differ most on. condition_weight is here rather than on the shelf of its own because kill_bonus is the other correction to the same valuation: a search that fits one first fits it to a price the other then changes (plan R5, and both dials' own doc comments).

8 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `kill_bonus` | 1.0 | 1.2 |
| `counter_weight` | 1.0 | 0.8 |
| `min_useful_score` | 80.0 | 90.0 |
| `condition_weight` | 0.0 | 0.05 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `c9c9c9f9184.tres` | +0.145 | -0.210 | +0.355 |
| `c09592e7315.tres` | +0.138 | -0.085 | +0.223 |
| `ce0684fdf8f.tres` | -0.104 | -0.339 | +0.235 |
| `data/ai/default.tres` (anchor) | -0.363 | +0.276 | |
| `data/ai/easy.tres` (anchor) | -0.294 | -0.221 | |
| `data/ai/hard.tres` (anchor) | +0.381 | +0.578 | |

## economy

defend_weight is built from the first three by the same arithmetic read backwards (Judgement D3), so moving one moves attack and defence at once and it cannot sit in a block of its own. step_cost_penalty is also the rate the attack path converts cover_tiles at.

8 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `capture_score` | 900.0 | 750.0 |
| `capture_progress_bonus` | 45.0 | 90.0 |
| `hq_capture_multiplier` | 3.0 | 3.0 |
| `step_cost_penalty` | 4.0 | 0.0 |
| `advance_score` | 1.0 | 1.0 |
| `defend_weight` | 0.0 | 2.0 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `cdb37cc3465.tres` | +0.153 | -0.184 | +0.337 |
| `c4c9d589e1b.tres` | +0.153 | -0.184 | +0.337 |
| `c3c0f8049c6.tres` | -0.104 | -0.339 | +0.235 |
| `data/ai/default.tres` (anchor) | -0.360 | +0.246 | |
| `data/ai/easy.tres` (anchor) | -0.320 | -0.148 | |
| `data/ai/hard.tres` (anchor) | +0.314 | +0.609 | |

## threat

Three dials over one ThreatMap can price one enemy three times (Judgement R3), so they move together. cover_tiles joins them because a cell a forecast has already priced scores no stars — turning a threat dial on takes cover out of exactly those cells (plan §5b), so the two cannot be measured apart.

8 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `threat_aversion` | 0.3 | 0.05 |
| `advance_threat_tiles` | 3.0 | 6.0 |
| `withdraw_weight` | 0.0 | 0.0 |
| `cover_tiles` | 0.0 | 0.25 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `ce863382e8e.tres` | +0.542 | +0.689 | -0.147 |
| `c00ac20aea9.tres` | +0.487 | +0.805 | -0.318 |
| `c7b86afc83c.tres` | -0.104 | -0.339 | +0.235 |
| `data/ai/default.tres` (anchor) | -0.554 | -0.466 | |
| `data/ai/easy.tres` (anchor) | -0.678 | -0.600 | |
| `data/ai/hard.tres` (anchor) | -0.069 | -0.089 | |

## formation

The first two were probed together and never apart, and tight beat loose by the largest margin the Judgement plan measured, so the pair moves as a pair.

8 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `cohesion_tiles` | 0.5 | 2.0 |
| `cohesion_radius` | 4 | 1 |
| `retreat_hp` | 60 | 45 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `c84a43c99cb.tres` | +0.335 | +0.518 | -0.183 |
| `c73b17228b4.tres` | +0.293 | +0.306 | -0.013 |
| `c92acea1b5f.tres` | -0.104 | -0.339 | +0.235 |
| `data/ai/default.tres` (anchor) | -0.291 | +0.035 | |
| `data/ai/easy.tres` (anchor) | -0.488 | -0.481 | |
| `data/ai/hard.tres` (anchor) | +0.172 | -0.040 | |

## production

save_up_turns buys a measured first-mover edge (+5.6 pp at 0, +20.2 at 3), which the search will happily take; both seatings counted is what stops it scoring (D5).

8 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `capture_unit_target` | 2 | 4 |
| `duplicate_priority_cost` | 3 | 8 |
| `save_up_turns` | 2 | 0 |
| `air_answer_target` | 2 | 3 |
| `build_reactivity` | 0.0 | 0.0 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `cfbcbad679d.tres` | +0.702 | +0.155 | +0.547 |
| `cb995ee33cf.tres` | +0.682 | +0.157 | +0.525 |
| `c5c237465f6.tres` | -0.104 | -0.339 | +0.235 |
| `data/ai/default.tres` (anchor) | -0.601 | -0.098 | |
| `data/ai/easy.tres` (anchor) | -0.877 | -0.359 | |
| `data/ai/hard.tres` (anchor) | -0.341 | +0.483 | |

## economy_map

Three couplings, none optional. capture_units_per_property raises the capture_unit_target floor rather than replacing it; capture_claim_depth is the only limit on how thin a capture line gets, because spreading is untaxed by cohesion_tiles; and the AE3 pair multiplies out to zero at either dial's inert value, so moving one alone is inert half the time. Read per board: the first dial counts what is left to take, so one board measures the map rather than the dial.

Coupled in: `capture_unit_target` (production), `cohesion_tiles` (formation).

8 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `capture_units_per_property` | 0.0 | 0.0 |
| `capture_claim_depth` | 0 | 1 |
| `production_capture_multiplier` | 1.0 | 1.5 |
| `capture_goal_value_tiles` | 0.0 | 0.0 |
| `capture_unit_target` | 2 | 4 |
| `cohesion_tiles` | 0.5 | 0.875 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `cb9c3e234af.tres` | +0.588 | +0.121 | +0.467 |
| `c79db112848.tres` | +0.543 | +0.081 | +0.462 |
| `cc544e4c410.tres` | -0.104 | -0.339 | +0.235 |
| `data/ai/default.tres` (anchor) | -0.432 | +0.028 | |
| `data/ai/easy.tres` (anchor) | -0.916 | -0.154 | |
| `data/ai/hard.tres` (anchor) | -0.144 | +0.263 | |

Held out, board by board:

| candidate | crossfire | first_steps | timberline |
|---|---|---|---|
| `cb9c3e234af.tres` | +0.858 | +0.124 | -0.620 |
| `c79db112848.tres` | +0.665 | +0.206 | -0.628 |
| `cc544e4c410.tres` | -0.006 | -0.672 | -0.339 |
| `easy.tres` | -0.539 | -0.194 | +0.270 |
| `default.tres` | -0.712 | +0.332 | +0.465 |
| `hard.tres` | -0.266 | +0.204 | +0.852 |

## join

What a merge carries is priced by _unit_value, which is condition_weight's, and a join only ever happens to damaged units — so at condition_weight 0 the dial is being fitted against a valuation that calls a 10-HP tank a whole one.

Coupled in: `condition_weight` (combat).

3 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `join_weight` | 0.0 | 0.0 |
| `condition_weight` | 0.0 | 0.0 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `c3d31d9610c.tres` | -0.104 | -0.339 | +0.235 |
| `c32b49e3b97.tres` | -0.111 | -0.384 | +0.273 |
| `data/ai/default.tres` (anchor) | -0.081 | +0.390 | |
| `data/ai/easy.tres` (anchor) | -0.024 | +0.112 | |
| `data/ai/hard.tres` (anchor) | +0.549 | +0.582 | |
