# Replay survey — reports/balance_sim/grind_replays_scrimmage/replays

12 recordings · 1 boards · 1938 commands · 194 days · 50 findings

> **Every recording re-issued to its end; nothing was dropped.**

## Findings by kind

| finding | count | share | per 100 commands | per match | most often |
| --- | ---: | ---: | ---: | ---: | --- |
| `walk_into_fire` | 37 | 74.0% | 1.91 | 3.1 | infantry ×32, artillery ×2, missiles ×1 |
| `worse_shot` | 6 | 12.0% | 0.31 | 0.5 | infantry ×4, artillery ×1, tank ×1 |
| `oscillation` | 4 | 8.0% | 0.21 | 0.3 | infantry ×3, artillery ×1 |
| `undefended_hq` | 3 | 6.0% | 0.15 | 0.2 | — |

## The recordings

| recording | board | commands | days | winner | findings | stopped |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| scrimmage#none-hard_vs_none-normal#s1797 | scrimmage.txt | 131 | 14 | team 1 | 1 | — |
| scrimmage#none-hard_vs_none-normal#s1798 | scrimmage.txt | 105 | 11 | team 1 | 2 | — |
| scrimmage#none-hard_vs_none-normal#s1799 | scrimmage.txt | 226 | 21 | undecided | 7 | — |
| scrimmage#none-hard_vs_none-normal#s1800 | scrimmage.txt | 210 | 21 | undecided | 1 | — |
| scrimmage#none-hard_vs_none-normal#s1801 | scrimmage.txt | 198 | 19 | team 1 | 4 | — |
| scrimmage#none-hard_vs_none-normal#s1802 | scrimmage.txt | 188 | 18 | team 1 | 3 | — |
| scrimmage#none-normal_vs_none-hard#s1797 | scrimmage.txt | 206 | 21 | undecided | 10 | — |
| scrimmage#none-normal_vs_none-hard#s1798 | scrimmage.txt | 139 | 14 | team 1 | 1 | — |
| scrimmage#none-normal_vs_none-hard#s1799 | scrimmage.txt | 130 | 13 | team 1 | 4 | — |
| scrimmage#none-normal_vs_none-hard#s1800 | scrimmage.txt | 126 | 13 | team 1 | 6 | — |
| scrimmage#none-normal_vs_none-hard#s1801 | scrimmage.txt | 132 | 14 | team 1 | 3 | — |
| scrimmage#none-normal_vs_none-hard#s1802 | scrimmage.txt | 147 | 15 | team 1 | 8 | — |

A rate above is how often a detector fired, not how badly a side played: several of them fire on a doctrine playing exactly as intended. Every counterfactual behind them comes from the rules — `AttackRange`, `MovementResolver`, `CombatResolver.forecast_at` — never from the planner.
