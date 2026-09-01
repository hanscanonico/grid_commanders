# Grind digest

host `mini-pc-Default-string` · commit `09fbc560` · pass 151 · up 31.9h · written 2026-09-02 00:27:33

now: **nothing running** — idle, started —

queued this pass: commander-balance, campaign-difficulty, legibility-ratchet, balance-pool-arsenal, replay-survey-arsenal, balance-pool-crossfire, replay-survey-crossfire, balance-pool-first_steps, replay-survey-first_steps, balance-pool-jet_stream, replay-survey-jet_stream, balance-pool-riverline, replay-survey-riverline, balance-pool-scrimmage, replay-survey-scrimmage, balance-pool-timberline, replay-survey-timberline

## arena-search-default — done (58.7h ago, 5.9h)

combat: kill_bonus 1.6->1.5, counter_weight 0.6->0.95, min_useful_score 40.0->50.0, condition_weight
economy: capture_score 900.0->1500.0, capture_progress_bonus 45.0->105.0, step_cost_penalty 4.0->7.0
economy_map: capture_units_per_property 0.15->0.75, capture_claim_depth 0->2, production_capture_mul
formation: cohesion_tiles 1.0->2.0, cohesion_radius 2->1, retreat_hp 45->55 — train +0.172 / held ou
join: join_weight 0.0->0.15, condition_weight 0.0->1.0 — train +0.147 / held out +0.111
production: capture_unit_target 3->4, duplicate_priority_cost 3->0, save_up_turns 2->0, build_reacti
…
report: reports/ai_arena/search/default/report.md

## arena-search-easy — done (47.1h ago, 11.6h)

combat: kill_bonus 1.0->1.2, counter_weight 1.0->0.8, min_useful_score 80.0->90.0, condition_weight 
economy: capture_score 900.0->750.0, capture_progress_bonus 45.0->90.0, step_cost_penalty 4.0->0.0, 
economy_map: capture_claim_depth 0->1, production_capture_multiplier 1.0->1.5, capture_unit_target 2
formation: cohesion_tiles 0.5->2.0, cohesion_radius 4->1, retreat_hp 60->45 — train +0.335 / held ou
join: base held — train -0.104 / held out -0.339
production: capture_unit_target 2->4, duplicate_priority_cost 3->8, save_up_turns 2->0, air_answer_t
…
report: reports/ai_arena/search/easy/report.md

## arena-search-hard — done (40.8h ago, 6.3h)

combat: kill_bonus 2.0->1.5, min_useful_score 40.0->50.0, condition_weight 0.0->0.05 — train +0.541 
economy: capture_score 900.0->1200.0, capture_progress_bonus 45.0->15.0, step_cost_penalty 4.0->2.0,
economy_map: capture_units_per_property 0.15->0.55, capture_claim_depth 0->2 — train +0.917 / held o
formation: cohesion_tiles 1.5->1.0, retreat_hp 45->30 — train +0.494 / held out +0.525
join: join_weight 0.0->0.3 — train +0.447 / held out +0.561
production: duplicate_priority_cost 3->1, save_up_turns 2->0, air_answer_target 2->3 — train +1.170 
…
report: reports/ai_arena/search/hard/report.md

## difficulty-check — failed (1s ago, 2m)

=== difficulty ladder ===
matches 240   rejected 0   cap-stalls 0   gate >= 70%
  normal  over easy      76.7%  (92/120)  ok
      on scrimmage    85.0%  (51/60)
      on ironworks    68.3%  (41/60)
  hard    over normal    53.3%  (64/120)  FAIL
…
make[1] : on quitte le répertoire « /home/mini-pc/Documents/grid_commanders »

## commander-balance — done (31.3h ago, 30m)

=== commander balance ===
matches 9680   decisive 9679   draws 1   rejected 0   cap-stalls 0
first-side bias (non-mirror decisive games) +33.9 pp (REVIEW, threshold +-5)
commander            win%   n   band
  iris_colt           22.3  880  WARN
  rhea_sol            36.9  880  WARN
…
make[1] : on quitte le répertoire « /home/mini-pc/Documents/grid_commanders »

## campaign-difficulty — done (31.3h ago, 1m)

campaign-difficulty: 51 flagged (never won, or a deadline at or under the median win)
the_furnace_winter fw02_last_granary                easy    win   0%  day  0  deadline  0  odds 0.67
the_furnace_winter fw04_ice_road                    normal  win   0%  day  0  deadline  0  odds 0.69
the_furnace_winter fw05_powder_ration               normal  win   0%  day  0  deadline  0  odds 0.67
the_furnace_winter fw06_first_thaw                  normal  win   0%  day  0  deadline  0  odds 0.56
the_furnace_winter fw07_pipeline_east               normal  win   0%  day  0  deadline  0  odds 1.60
…
make[1] : on quitte le répertoire « /home/mini-pc/Documents/grid_commanders »

## legibility-ratchet — done (31.2h ago, 4m)

# Legibility ratchet
regressed (PASS -> FAIL): 0
recovered (FAIL -> PASS): 0
not in the baseline: 0
in the baseline, not in this run: 0
make[1] : on quitte le répertoire « /home/mini-pc/Documents/grid_commanders »

## balance-pool-arsenal — done (31.2h ago, 5s)

none:hard vs none:normal — red 56%, blue 44%, undecided 0% over 32
none:normal vs none:hard — red 66%, blue 34%, undecided 0% over 32

## replay-survey-arsenal — done (31.2h ago, 11s)

12 recordings, 3311 commands, 81 findings
walk_into_fire: 63 (1.90 per 100 commands)
oscillation: 7 (0.21 per 100 commands)
hoarding: 6 (0.18 per 100 commands)
worse_shot: 5 (0.15 per 100 commands)

## balance-pool-crossfire — done (31.2h ago, 5s)

none:hard vs none:normal — red 59%, blue 41%, undecided 0% over 32
none:normal vs none:hard — red 19%, blue 81%, undecided 0% over 32

## replay-survey-crossfire — done (31.2h ago, 10s)

12 recordings, 3201 commands, 121 findings
walk_into_fire: 62 (1.94 per 100 commands)
hoarding: 31 (0.97 per 100 commands)
oscillation: 27 (0.84 per 100 commands)
worse_shot: 1 (0.03 per 100 commands)

## balance-pool-first_steps — done (31.2h ago, 5s)

none:hard vs none:normal — red 88%, blue 12%, undecided 0% over 32
none:normal vs none:hard — red 47%, blue 53%, undecided 0% over 32

## replay-survey-first_steps — done (31.2h ago, 10s)

12 recordings, 3317 commands, 91 findings
walk_into_fire: 61 (1.84 per 100 commands)
hoarding: 19 (0.57 per 100 commands)
oscillation: 8 (0.24 per 100 commands)
worse_shot: 2 (0.06 per 100 commands)
undefended_hq: 1 (0.03 per 100 commands)

## balance-pool-jet_stream — done (31.2h ago, 5s)

none:hard vs none:normal — red 50%, blue 50%, undecided 0% over 32
none:normal vs none:hard — red 56%, blue 44%, undecided 0% over 32

## replay-survey-jet_stream — done (31.2h ago, 10s)

12 recordings, 3296 commands, 156 findings
walk_into_fire: 113 (3.43 per 100 commands)
hoarding: 27 (0.82 per 100 commands)
oscillation: 9 (0.27 per 100 commands)
worse_shot: 7 (0.21 per 100 commands)

## balance-pool-riverline — done (31.2h ago, 6s)

none:hard vs none:normal — red 97%, blue 3%, undecided 0% over 32
none:normal vs none:hard — red 56%, blue 44%, undecided 0% over 32

## replay-survey-riverline — done (31.2h ago, 10s)

12 recordings, 3178 commands, 102 findings
walk_into_fire: 62 (1.95 per 100 commands)
hoarding: 22 (0.69 per 100 commands)
oscillation: 10 (0.31 per 100 commands)
worse_shot: 8 (0.25 per 100 commands)

## balance-pool-scrimmage — done (31.2h ago, 5s)

none:hard vs none:normal — red 88%, blue 12%, undecided 0% over 32
none:normal vs none:hard — red 91%, blue 9%, undecided 0% over 32

## replay-survey-scrimmage — done (31.2h ago, 5s)

12 recordings, 1938 commands, 50 findings
walk_into_fire: 37 (1.91 per 100 commands)
worse_shot: 6 (0.31 per 100 commands)
oscillation: 4 (0.21 per 100 commands)
undefended_hq: 3 (0.15 per 100 commands)

## balance-pool-timberline — done (31.2h ago, 5s)

none:hard vs none:normal — red 69%, blue 31%, undecided 0% over 32
none:normal vs none:hard — red 72%, blue 28%, undecided 0% over 32

## replay-survey-timberline — done (31.2h ago, 10s)

12 recordings, 3942 commands, 124 findings
walk_into_fire: 76 (1.93 per 100 commands)
hoarding: 25 (0.63 per 100 commands)
oscillation: 17 (0.43 per 100 commands)
worse_shot: 5 (0.13 per 100 commands)
undefended_hq: 1 (0.03 per 100 commands)

