# AI Arena search

Base `data/ai/hard.tres`, anchors data/ai/easy.tres, data/ai/default.tres, data/ai/hard.tres.

Compute spent: **95184 matches played**, 125424 read, 376.1 min of pool wall clock, 253.1 matches/min at 15 workers. Total wall clock 376.9 min.

## combat

The axis the tiers differ most on. condition_weight is here rather than on the shelf of its own because kill_bonus is the other correction to the same valuation: a search that fits one first fits it to a price the other then changes (plan R5, and both dials' own doc comments).

7 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `kill_bonus` | 2.0 | 1.5 |
| `counter_weight` | 0.4 | 0.4 |
| `min_useful_score` | 40.0 | 50.0 |
| `condition_weight` | 0.0 | 0.05 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `c52c1e264a6.tres` | +0.541 | +0.537 | +0.004 |
| `cd2796cdbfb.tres` | +0.537 | +0.500 | +0.037 |
| `c3c1ec44cee.tres` | +0.327 | +0.453 | -0.126 |
| `data/ai/default.tres` (anchor) | -0.787 | -0.859 | |
| `data/ai/easy.tres` (anchor) | -0.682 | -0.642 | |
| `data/ai/hard.tres` (anchor) | -0.049 | +0.011 | |

## economy

defend_weight is built from the first three by the same arithmetic read backwards (Judgement D3), so moving one moves attack and defence at once and it cannot sit in a block of its own. step_cost_penalty is also the rate the attack path converts cover_tiles at.

8 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `capture_score` | 900.0 | 1200.0 |
| `capture_progress_bonus` | 45.0 | 15.0 |
| `hq_capture_multiplier` | 3.0 | 3.0 |
| `step_cost_penalty` | 4.0 | 2.0 |
| `advance_score` | 1.0 | 1.0 |
| `defend_weight` | 2.5 | 1.5 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `c8515deee1e.tres` | +0.432 | +0.499 | -0.067 |
| `cf3e1c39a00.tres` | +0.432 | +0.499 | -0.067 |
| `cecf1957d54.tres` | +0.327 | +0.453 | -0.126 |
| `data/ai/default.tres` (anchor) | -0.600 | -0.780 | |
| `data/ai/easy.tres` (anchor) | -0.552 | -0.559 | |
| `data/ai/hard.tres` (anchor) | -0.098 | -0.112 | |

## threat

Three dials over one ThreatMap can price one enemy three times (Judgement R3), so they move together. cover_tiles joins them because a cell a forecast has already priced scores no stars — turning a threat dial on takes cover out of exactly those cells (plan §5b), so the two cannot be measured apart.

7 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `threat_aversion` | 0.1 | 0.1 |
| `advance_threat_tiles` | 2.0 | 6.0 |
| `withdraw_weight` | 0.0 | 0.0 |
| `cover_tiles` | 0.0 | 0.0 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `ce0961a24fd.tres` | +0.835 | +1.030 | -0.195 |
| `cc629150895.tres` | +0.833 | +1.034 | -0.201 |
| `c055388496a.tres` | +0.327 | +0.453 | -0.126 |
| `data/ai/default.tres` (anchor) | -0.811 | -0.958 | |
| `data/ai/easy.tres` (anchor) | -1.068 | -0.983 | |
| `data/ai/hard.tres` (anchor) | -0.440 | -0.575 | |

## formation

The first two were probed together and never apart, and tight beat loose by the largest margin the Judgement plan measured, so the pair moves as a pair.

5 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `cohesion_tiles` | 1.5 | 1.0 |
| `cohesion_radius` | 2 | 2 |
| `retreat_hp` | 45 | 30 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `cfc7c84e6fe.tres` | +0.494 | +0.525 | -0.031 |
| `c6490289915.tres` | +0.443 | +0.481 | -0.038 |
| `cb35473be10.tres` | +0.327 | +0.453 | -0.126 |
| `data/ai/default.tres` (anchor) | -0.614 | -0.788 | |
| `data/ai/easy.tres` (anchor) | -0.484 | -0.722 | |
| `data/ai/hard.tres` (anchor) | -0.020 | +0.051 | |

## production

save_up_turns buys a measured first-mover edge (+5.6 pp at 0, +20.2 at 3), which the search will happily take; both seatings counted is what stops it scoring (D5).

8 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `capture_unit_target` | 3 | 3 |
| `duplicate_priority_cost` | 3 | 1 |
| `save_up_turns` | 2 | 0 |
| `air_answer_target` | 2 | 3 |
| `build_reactivity` | 0.6 | 0.6 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `c24eb2375dc.tres` | +1.170 | +1.012 | +0.158 |
| `ca2d21c23eb.tres` | +1.152 | +1.069 | +0.083 |
| `cb4435ff2de.tres` | +0.327 | +0.453 | -0.126 |
| `data/ai/default.tres` (anchor) | -1.117 | -0.995 | |
| `data/ai/easy.tres` (anchor) | -1.147 | -0.909 | |
| `data/ai/hard.tres` (anchor) | -0.995 | -0.631 | |

## economy_map

Three couplings, none optional. capture_units_per_property raises the capture_unit_target floor rather than replacing it; capture_claim_depth is the only limit on how thin a capture line gets, because spreading is untaxed by cohesion_tiles; and the AE3 pair multiplies out to zero at either dial's inert value, so moving one alone is inert half the time. Read per board: the first dial counts what is left to take, so one board measures the map rather than the dial.

Coupled in: `capture_unit_target` (production), `cohesion_tiles` (formation).

7 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `capture_units_per_property` | 0.15 | 0.55 |
| `capture_claim_depth` | 0 | 2 |
| `production_capture_multiplier` | 1.0 | 1.0 |
| `capture_goal_value_tiles` | 0.0 | 0.0 |
| `capture_unit_target` | 3 | 3 |
| `cohesion_tiles` | 1.5 | 1.5 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `cada2a096b5.tres` | +0.917 | +0.957 | -0.040 |
| `c36bfd8e890.tres` | +0.917 | +0.957 | -0.040 |
| `cc9fb67d4f8.tres` | +0.327 | +0.453 | -0.126 |
| `data/ai/default.tres` (anchor) | -0.969 | -0.975 | |
| `data/ai/easy.tres` (anchor) | -1.103 | -0.946 | |
| `data/ai/hard.tres` (anchor) | -0.568 | -0.446 | |

Held out, board by board:

| candidate | crossfire | first_steps | timberline |
|---|---|---|---|
| `cada2a096b5.tres` | +1.034 | +0.917 | +0.921 |
| `c36bfd8e890.tres` | +1.034 | +0.917 | +0.921 |
| `cc9fb67d4f8.tres` | +0.543 | +0.394 | +0.424 |
| `easy.tres` | -0.902 | -0.896 | -1.041 |
| `default.tres` | -1.287 | -0.641 | -0.998 |
| `hard.tres` | -0.422 | -0.691 | -0.227 |

## join

What a merge carries is priced by _unit_value, which is condition_weight's, and a join only ever happens to damaged units — so at condition_weight 0 the dial is being fitted against a valuation that calls a 10-HP tank a whole one.

Coupled in: `condition_weight` (combat).

4 wave(s). Champion against the vector it started from:

| dial | base | champion |
|---|---|---|
| `join_weight` | 0.0 | 0.3 |
| `condition_weight` | 0.0 | 0.0 |

A candidate's score is against the three fixed anchors and reads the same in every wave; an anchor's is against whatever shared its table, so it is context rather than a reference.

| candidate | training | held out | gap |
|---|---|---|---|
| `c33bb2eac0f.tres` | +0.447 | +0.561 | -0.114 |
| `c79a16b5cd4.tres` | +0.438 | +0.501 | -0.063 |
| `cceec855faa.tres` | +0.327 | +0.453 | -0.126 |
| `data/ai/default.tres` (anchor) | -0.597 | -0.823 | |
| `data/ai/easy.tres` (anchor) | -0.615 | -0.561 | |
| `data/ai/hard.tres` (anchor) | -0.055 | -0.132 | |
