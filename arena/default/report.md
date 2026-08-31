# AI Arena search

Base `data/ai/default.tres`, anchors data/ai/easy.tres, data/ai/default.tres, data/ai/hard.tres.

Compute spent: **104384 matches played**, 136368 read, 351.4 min of pool wall clock, 297.0 matches/min at 15 workers. Total wall clock 352.3 min.

## combat

The axis the tiers differ most on. condition_weight is here rather than on the shelf of its own because kill_bonus is the other correction to the same valuation: a search that fits one first fits it to a price the other then changes (plan R5, and both dials' own doc comments).

8 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `kill_bonus` | 1.6 | 1.5 |
| `counter_weight` | 0.6 | 0.95 |
| `min_useful_score` | 40.0 | 50.0 |
| `condition_weight` | 0.0 | 0.05 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `c0ecb2f2648.tres` | -0.072 | -0.316 | +0.244 |
| `cfa4046cac3.tres` | -0.083 | -0.184 | +0.101 |
| `c99a4f9723e.tres` | -0.224 | -0.115 | -0.109 |
| `data/ai/default.tres` (anchor) | -0.015 | +0.145 | |
| `data/ai/easy.tres` (anchor) | -0.194 | -0.244 | |
| `data/ai/hard.tres` (anchor) | +0.525 | +0.713 | |

## economy

defend_weight is built from the first three by the same arithmetic read backwards (Judgement D3), so moving one moves attack and defence at once and it cannot sit in a block of its own. step_cost_penalty is also the rate the attack path converts cover_tiles at.

8 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `capture_score` | 900.0 | 1500.0 |
| `capture_progress_bonus` | 45.0 | 105.0 |
| `hq_capture_multiplier` | 3.0 | 3.0 |
| `step_cost_penalty` | 4.0 | 7.0 |
| `advance_score` | 1.0 | 1.0 |
| `defend_weight` | 2.0 | 3.0 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `c65674a1d9d.tres` | -0.105 | -0.195 | +0.090 |
| `ca488a108e3.tres` | -0.112 | -0.195 | +0.083 |
| `c2ec01fd227.tres` | -0.224 | -0.115 | -0.109 |
| `data/ai/default.tres` (anchor) | -0.165 | +0.060 | |
| `data/ai/easy.tres` (anchor) | +0.016 | -0.368 | |
| `data/ai/hard.tres` (anchor) | +0.498 | +0.812 | |

## threat

Three dials over one ThreatMap can price one enemy three times (Judgement R3), so they move together. cover_tiles joins them because a cell a forecast has already priced scores no stars — turning a threat dial on takes cover out of exactly those cells (plan §5b), so the two cannot be measured apart.

8 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `threat_aversion` | 0.0 | 0.15 |
| `advance_threat_tiles` | 0.0 | 1.25 |
| `withdraw_weight` | 0.0 | 0.05 |
| `cover_tiles` | 0.0 | 0.25 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `c36e3573173.tres` | +0.304 | +0.309 | -0.005 |
| `c25c6863f7b.tres` | +0.286 | +0.260 | +0.026 |
| `c66821bd311.tres` | -0.224 | -0.115 | -0.109 |
| `data/ai/default.tres` (anchor) | -0.387 | -0.379 | |
| `data/ai/easy.tres` (anchor) | -0.521 | -0.611 | |
| `data/ai/hard.tres` (anchor) | +0.189 | +0.536 | |

## formation

The first two were probed together and never apart, and tight beat loose by the largest margin the Judgement plan measured, so the pair moves as a pair.

7 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `cohesion_tiles` | 1.0 | 2.0 |
| `cohesion_radius` | 2 | 1 |
| `retreat_hp` | 45 | 55 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `c0c42efe8d5.tres` | +0.172 | -0.015 | +0.187 |
| `c24599694cf.tres` | +0.166 | +0.003 | +0.163 |
| `ca7217cc0bc.tres` | -0.224 | -0.115 | -0.109 |
| `data/ai/default.tres` (anchor) | -0.287 | +0.004 | |
| `data/ai/easy.tres` (anchor) | -0.362 | -0.577 | |
| `data/ai/hard.tres` (anchor) | +0.440 | +0.699 | |

## production

save_up_turns buys a measured first-mover edge (+5.6 pp at 0, +20.2 at 3), which the search will happily take; both seatings counted is what stops it scoring (D5).

8 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `capture_unit_target` | 3 | 4 |
| `duplicate_priority_cost` | 3 | 0 |
| `save_up_turns` | 2 | 0 |
| `air_answer_target` | 2 | 2 |
| `build_reactivity` | 0.0 | 0.6 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `c493a57316c.tres` | +0.974 | +1.022 | -0.048 |
| `cc090f3c71f.tres` | +0.964 | +0.842 | +0.122 |
| `c25433f5d86.tres` | -0.224 | -0.115 | -0.109 |
| `data/ai/default.tres` (anchor) | -0.874 | -0.726 | |
| `data/ai/easy.tres` (anchor) | -1.143 | -0.970 | |
| `data/ai/hard.tres` (anchor) | -0.499 | -0.054 | |

## economy_map

Three couplings, none optional. capture_units_per_property raises the capture_unit_target floor rather than replacing it; capture_claim_depth is the only limit on how thin a capture line gets, because spreading is untaxed by cohesion_tiles; and the AE3 pair multiplies out to zero at either dial's inert value, so moving one alone is inert half the time. Read per board: the first dial counts what is left to take, so one board measures the map rather than the dial.

Coupled in: `capture_unit_target` (production), `cohesion_tiles` (formation).

8 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `capture_units_per_property` | 0.15 | 0.75 |
| `capture_claim_depth` | 0 | 2 |
| `production_capture_multiplier` | 1.0 | 0.5 |
| `capture_goal_value_tiles` | 0.0 | 2.0 |
| `capture_unit_target` | 3 | 3 |
| `cohesion_tiles` | 1.0 | 1.5 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `cea80e94053.tres` | +0.675 | +0.404 | +0.271 |
| `cf914aeb650.tres` | +0.610 | +0.388 | +0.222 |
| `c38aa0649a6.tres` | -0.224 | -0.115 | -0.109 |
| `data/ai/default.tres` (anchor) | -0.816 | -0.573 | |
| `data/ai/easy.tres` (anchor) | -0.827 | -0.814 | |
| `data/ai/hard.tres` (anchor) | -0.035 | +0.710 | |

Held out, board by board:

| candidate | crossfire | first_steps | timberline |
|---|---|---|---|
| `cea80e94053.tres` | +0.166 | +0.341 | +0.705 |
| `cf914aeb650.tres` | +0.236 | +0.339 | +0.588 |
| `c38aa0649a6.tres` | -0.537 | +0.278 | -0.085 |
| `easy.tres` | -0.410 | -1.187 | -0.845 |
| `default.tres` | -0.565 | -0.413 | -0.742 |
| `hard.tres` | +1.109 | +0.643 | +0.380 |

## join

What a merge carries is priced by _unit_value, which is condition_weight's, and a join only ever happens to damaged units — so at condition_weight 0 the dial is being fitted against a valuation that calls a 10-HP tank a whole one.

Coupled in: `condition_weight` (combat).

8 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `join_weight` | 0.0 | 0.15 |
| `condition_weight` | 0.0 | 1.0 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `c3a7f1ba502.tres` | +0.147 | +0.111 | +0.036 |
| `c6648d454cb.tres` | +0.123 | +0.062 | +0.061 |
| `c9f4a27b8f1.tres` | -0.224 | -0.115 | -0.109 |
| `data/ai/default.tres` (anchor) | -0.341 | -0.233 | |
| `data/ai/easy.tres` (anchor) | -0.358 | -0.402 | |
| `data/ai/hard.tres` (anchor) | +0.425 | +0.576 | |
