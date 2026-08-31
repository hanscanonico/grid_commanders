# Replay survey — reports/balance_sim/grind_replays_first_steps/replays

12 recordings · 1 boards · 3317 commands · 242 days · 91 findings

> **Every recording re-issued to its end; nothing was dropped.**

## Findings by kind

| finding | count | share | per 100 commands | per match | most often |
| --- | ---: | ---: | ---: | ---: | --- |
| `walk_into_fire` | 61 | 67.0% | 1.84 | 5.1 | infantry ×32, artillery ×13, mech ×6 |
| `hoarding` | 19 | 20.9% | 0.57 | 1.6 | — |
| `oscillation` | 8 | 8.8% | 0.24 | 0.7 | infantry ×4, mech ×2, apc ×1 |
| `worse_shot` | 2 | 2.2% | 0.06 | 0.2 | tank ×2 |
| `undefended_hq` | 1 | 1.1% | 0.03 | 0.1 | — |

## The recordings

| recording | board | commands | days | winner | findings | stopped |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| first_steps#none-hard_vs_none-normal#s1403 | first_steps.txt | 288 | 20 | team 1 | 5 | — |
| first_steps#none-hard_vs_none-normal#s1404 | first_steps.txt | 280 | 21 | undecided | 8 | — |
| first_steps#none-hard_vs_none-normal#s1405 | first_steps.txt | 289 | 21 | undecided | 6 | — |
| first_steps#none-hard_vs_none-normal#s1406 | first_steps.txt | 282 | 21 | undecided | 12 | — |
| first_steps#none-hard_vs_none-normal#s1407 | first_steps.txt | 251 | 19 | team 1 | 5 | — |
| first_steps#none-hard_vs_none-normal#s1408 | first_steps.txt | 274 | 21 | undecided | 6 | — |
| first_steps#none-normal_vs_none-hard#s1403 | first_steps.txt | 289 | 21 | undecided | 12 | — |
| first_steps#none-normal_vs_none-hard#s1404 | first_steps.txt | 289 | 21 | undecided | 11 | — |
| first_steps#none-normal_vs_none-hard#s1405 | first_steps.txt | 301 | 21 | undecided | 10 | — |
| first_steps#none-normal_vs_none-hard#s1406 | first_steps.txt | 293 | 21 | undecided | 6 | — |
| first_steps#none-normal_vs_none-hard#s1407 | first_steps.txt | 206 | 14 | team 2 | 3 | — |
| first_steps#none-normal_vs_none-hard#s1408 | first_steps.txt | 275 | 21 | undecided | 7 | — |

A rate above is how often a detector fired, not how badly a side played: several of them fire on a doctrine playing exactly as intended. Every counterfactual behind them comes from the rules — `AttackRange`, `MovementResolver`, `CombatResolver.forecast_at` — never from the planner.
