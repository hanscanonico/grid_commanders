# Campaign mission difficulty

`make campaigns` says a mission is *playable* — the board parses, the seating is
one it deals, every objective names ground that exists. It says nothing about
whether the mission can be *won*. This is the committed record of the other
question, measured rather than argued, and of the content pass that measurement
paid for (COM-251, COM-248).

The instrument is `tools/run_campaign_difficulty.gd` (`make campaign-difficulty`).
It is `tests/unit/test_campaign_soak.gd`'s loop at a measurement's seed count and
day horizon: the same `BattleSetup.build(mission.to_request())`, the same
`CampaignSession` boundary order — apply, then the beats due, then the verdict —
so what it plays is the mission the game ships. A measurement and not a gate: out
of `make verify` and `make test`, and it edits nothing.

## What the numbers mean, and what they do not

Both armies are driven by the planner at the mission's own tier, the player's
seat included. Three consequences, and every reading below is bounded by them:

1. **The planner cannot see an objective.** It plays for tactical victory, so a
   mission won by taking one town is won here only when the fight happens to go
   through that town. A low `win%` on a mission whose goal is a capture is
   partly this.
2. **The planner is not a player.** It does not spend a purse deliberately and it
   walks units into fire the range preview would have shown a human. So `win%` is
   a **floor**: a mission it wins comfortably is certainly fair, a mission it
   loses may still be fair.
3. **It cannot price a tier or a commander.** Both seats play the mission's own
   tier, so lowering that tier makes *both* sides worse and the number does not
   move — which is why no tier was changed in this pass.

Two columns the planner cannot skew, because they are content an author typed and
are read before the first command:

- **`odds`** — the player's side's opening army value as a fraction of what
  stands against it (`BalanceMatchEngine.army_value` on both halves).
- **`income`** — the same fraction over opening property count. The slower of the
  two and the one that compounds: a side that opens level and earns half as much
  is behind by the middle of every mission it plays.

**A mission is a content fault when a low `win%` sits beside a low `odds` or
`income`.** A mission that opens level (`1.00 / 1.00`) and is still lost is far
more likely to be reading (1) or (2), and none of those was edited here.

## The pass this document paid for

Baseline: 56 of 108 missions never won across nine seeds, mean `win%` 38.1.
After the edits below: 50 never won, mean 42.5, and no mission got worse.

### Deadlines (COM-248)

`DayDeadline` is a **failure** condition — the mission is lost when the clock
passes. Twenty-four of 108 missions carried one, which is far too many for a
condition that ends a battle the player is winning. It is now three.

- **Twenty-one deadlines were deleted.** Every one of those missions already
  carried a `par_day`, so the clock survives as the **speed star**
  (`MissionRuntime._awards`, "Finish by day N") — time pressure as score, which
  is what the objective vocabulary already had for it. Nothing in `core/` moved.
- **Three were kept, because the clock is an event in the fiction rather than a
  stopwatch on the player**: `sm06_the_toll_bridge` (the bridges go down),
  `sm15_the_last_span` (the span goes down) and `tc10_the_squeeze` (a siege is
  relieved or it is not).
- **The three kept ones were loosened to a measured margin**: 8 → 12, 7 → 11,
  7 → 11, each with its own copy, because the briefing sentence and the
  comparison have to agree (`DayDeadlineObjective`'s own rule). All three sat at
  exactly the day their sole primary objective ends on, which is the margin those
  numbers buy: each mission is a `SurviveUntilDay`, `DayDeadlineObjective` fires
  strictly *past* `last_day`, so a clock set to the survival day can only ever
  fire on a board the runtime has already decided. The loosening makes that
  slack explicit rather than incidental — the clock is fiction on these three,
  and the fiction should not be one arithmetic edit away from ending a mission
  the player just won.

Five missions went from never-won to winnable on the deletions alone
(`tc04` 0 → 67%, `tc18` 0 → 33%, `qw03` 0 → 44%, `lf05` 11 → 100%,
`lf06` 0 → 89%).

### Loss limits (COM-251)

A `LossLimit` failure is the same shape as a deadline: a rule that ends a battle
beside the battle. They were not deleted — a mission about a column that has to
arrive needs one — but the twelve the sweep showed *deciding* the mission were
raised, and their copy with them. Remember that a `JoinCommand` merge reads as a
loss (a board diff cannot see which way a unit left), so a limit of three is
tighter than it looks:

| mission | was | now |
| --- | --- | --- |
| `fw09_coalyard_junction`, `fw14_slag_row`, `fw16_arsenal_road` | 3 | 5 |
| `fw15_smelter_yard` | 4 | 6 |
| `tc03`, `tc06`, `tc13` | 5 | 8 |
| `tc15`, `tc17`, `lf17` | 6 | 9 |
| `sm07_the_watchtower`, `sm16_the_wide_field` | 8 | 11 |

### Boards (COM-251)

Eleven missions opened at worse than half the enemy's army value. Each was fixed
with the smallest edit that reads as content rather than as a handicap — a piece
added to the player's opening line, or the enemy's heaviest piece removed — never
both on the same board where one was enough:

- `lf04`, `lf05`, `lf06` — the pursuing column's anti-air came off (there is no
  aircraft on any of the three boards to answer it), and the seawall picket
  gained a mech and a recon. `lf04` opened at **0.24**.
- `tc07`, `tc09` — a mech and an infantry on the player's line.
- `tc11` — the occupation's artillery came off and the belt gained a mech and an
  infantry; it opened at **0.26** with one town to the enemy's four.
- `fw02`, `fw03`, `fw05` — the enemy tank came off the three "capture before you
  can build" teaching boards, where the player cannot answer a tank at all until
  the crossroads base is taken.
- `fw06` — a mech.
- `qw06` — one of the safehouse garrison's two tanks.

Thirty-one missions opened owning a **third to a half** of the enemy's
properties. Eleven of them — `tc12`, `fw01`–`fw05`, `lf08`, `lf13`, `lf16`,
`lf17`, `qw06` — gained one neutral city on their own side of the board. The bar
a city had to clear is what kept the other twenty off the list: never a base
(which would retire a "capture the base to build" lesson), never a cell an
objective or a beat names, and never a city closer to the enemy's headquarters
than to the player's. Two boards are worth naming because they look like
candidates and are not: an `OwnProperties` objective counts by **terrain kind**
rather than by named cells, so on `fw06_first_thaw` ("hold four of the pass's
seven properties") and `lf14_the_high_passes` ("hold all four highland cities")
every neutral city is one the primary objective counts, and handing one over
would discount the goal rather than level the income. **Honest reading: this
moved one mission (`fw01` 33 → 89%) and no other.** The planner banks funds it
never spends, so this instrument is close to blind to income; the edit stands on
the opening asymmetry it removes, not on a number it moved, and it is the
weakest-evidenced part of this pass.

### The Watch at Thornfield, 2026-08-22

`qw05_the_watch_at_thornfield` was the one mission of the pass above whose
failure line was its own ending: 0% over nine seeds, every loss reading "Rook's
picket was overrun in the wood line." A `ProtectUnit` failure named the tagged
mech, and that mech opened at (2,2) — seven tiles from the town it was
supposed to be watching and three from Vale's nearest infantry — so the
mission was decided in the open on day 2 or 3, before the five-day hold could
begin. Three edits, all content:

- **The picket opens in the wood line.** The mech moved to (8,3) and an infantry
  to (7,1), either side of Thornfield, with Vale's two infantry pulled back to
  (13,1) and (12,4). (13,4) is still clear, which is where the day-4 armour
  spawns.
- **`ProtectUnit` became `LossLimit(3)`.** One named unit in the open is a
  coin-flip failure rather than a bill the player can pay; the tag stays on the
  mech as the inert data it always was. At 2 the limit still decided the mission
  (22%), which is why it is 3.
- **The board opens level.** The picket gained an infantry at (6,1) and a mech at
  (7,3), both in woods, taking `odds` from **0.56** to **1.00** — the lowest
  opening in The Quiet War, and the fault this document's own bar names.

0% → **56%** over nine seeds (50% over eighteen), median win day 6. The
table below carries the re-measured row; every other row is the 2026-08-17 sweep.

## What is still hard, and why it was left alone

Forty-nine missions are still never won by the planner (fifty before Thornfield
above). They are not a to-do list — they are the three limits above, and two
findings:

- **The strongest commanders are cast as the enemy.** Of the missions still never
  won, Iona Vance is the enemy in 12 of the 21 she plays, Radek Morn in 11 of 18
  and Konrad Vale in 10 of 16 — three of the standing high names in
  `docs/commander_balance.md` (89.4%, 78.3% and 62.3%, all WARN, against the
  41% and 45% of Ferrow and Orlov, who between them are the enemy in most of the
  missions that read fine). That is the commander matrix showing through the
  campaign, and its fix is a commander retune, not a mission edit: retuning a
  doctrine here would move both committed balance reports.
- **Level boards are lost too.** `sm10`, `sm16`, `hc01`, `hc05`, `hc15` and
  `hc18` open at `1.00 / 1.00` and are never won. On a level board the only
  things left are the seat, the commander pairing and the planner, so these are
  the discriminator working: nothing about them says the content is wrong, and
  nothing about them was changed.

The line between the two is not sharp, and the missions on it were deliberately
left alone rather than edited on a hunch: `sm13_the_narrow_gate` (0.62 / 1.00),
`fw11_signal_hill` (0.76 / 0.40) and `qw13_the_open_field` (0.74 / 1.00) all sit
above the odds bar this pass used and below parity, and none of them is
obviously either fault.

The follow-up the table asks for is a **human** pass over the six level-board
missions above and over The Furnace Winter as a whole (16 of its 18 missions are
still never won, at odds 0.56–1.60), because that is exactly where a planner-run
estimate is least trustworthy.

## Reading a row

```
make campaign-difficulty                                     # all six wars, 9 seeds is ~90s
make campaign-difficulty CAMPAIGN="--campaign=the_long_front --seeds=3"
make campaign-difficulty CAMPAIGN="--mission=fw06_first_thaw --seeds=9 --days=30"
```

`win%` is over `--seeds` matches; `day` is the median day of the ones it won;
`deadline` is the mission's `DayDeadline` failure or `—`; the last column is the
most common reason it ended, `(still running)` meaning the `--days` horizon was
reached rather than the mission lost. A run also writes `missions.csv` and
`summary.json` under `reports/campaign_difficulty/` (gitignored).

## The measurement, 2026-08-17

108 missions, 9 seeds each, 24-day horizon, after the pass above. A later sweep
supersedes this table wholesale rather than editing it. Two rows are edited:
`qw05_the_watch_at_thornfield`, re-measured 2026-08-22 above, because a stale 0%
beside a mission that has since been fixed reads as a fault still open; and
`qw18_the_man_himself`, re-measured 2026-08-31 on the new board that split the
Quiet War's finale from the Long Front's, because the row no longer described
any board the game ships.

| war | mission | tier | win% | median day | deadline | odds | income | most common ending |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| furnace winter | `fw01_dry_taps` | easy | 89% | 4 | — | 0.81 | 0.67 | Your army was destroyed. |
| furnace winter | `fw02_last_granary` | easy | 0% | — | — | 0.67 | 0.67 | Your army was destroyed. |
| furnace winter | `fw03_cold_relay` | normal | 0% | — | — | 0.67 | 0.67 | Your army was destroyed. |
| furnace winter | `fw04_ice_road` | normal | 0% | — | — | 0.69 | 0.67 | The fuel sledge went under the ice. |
| furnace winter | `fw05_powder_ration` | normal | 0% | — | — | 0.67 | 0.67 | Your army was destroyed. |
| furnace winter | `fw06_first_thaw` | normal | 0% | — | — | 0.56 | 0.33 | Your army was destroyed. |
| furnace winter | `fw07_pipeline_east` | normal | 0% | — | — | 1.60 | 0.50 | Your army was destroyed. |
| furnace winter | `fw08_pipeline_west` | normal | 0% | — | — | 1.60 | 1.00 | Your army was destroyed. |
| furnace winter | `fw09_coalyard_junction` | normal | 22% | 13 | — | 1.14 | 0.50 | More than five of our units left the column, however they went. |
| furnace winter | `fw10_ashen_crossing` | hard | 11% | 14 | — | 0.94 | 0.40 | Your army was destroyed. |
| furnace winter | `fw11_signal_hill` | hard | 0% | — | — | 0.76 | 0.40 | Your army was destroyed. |
| furnace winter | `fw12_last_mile` | hard | 0% | — | — | 0.94 | 0.40 | Your army was destroyed. |
| furnace winter | `fw13_foundry_gate` | hard | 0% | — | — | 0.71 | 0.75 | Your army was destroyed. |
| furnace winter | `fw14_slag_row` | hard | 33% | 7 | — | 0.71 | 0.75 | More than five of our units left the column, however they went. |
| furnace winter | `fw15_smelter_yard` | hard | 0% | — | — | 0.62 | 1.00 | More than six of ours lost, to any cause. The yard crews can replace machines, not columns. |
| furnace winter | `fw16_arsenal_road` | hard | 0% | — | — | 0.71 | 0.75 | More than five of our units left the line, however they went. |
| furnace winter | `fw17_the_stacks` | hard | 0% | — | — | 0.71 | 0.75 | Your army was destroyed. |
| furnace winter | `fw18_vales_furnace` | hard | 0% | — | — | 0.71 | 0.75 | Your army was destroyed. |
| six marshals | `sm01_border_toll` | normal | 100% | 3 | — | 1.08 | 1.00 | — |
| six marshals | `sm02_ambush_pass` | normal | 100% | 4 | — | 1.00 | 1.00 | — |
| six marshals | `sm03_the_long_watch` | normal | 89% | 6 | — | 0.67 | 1.00 | Ferrow was paid by the kill — more than three of ours lost, to any cause. |
| six marshals | `sm04_the_foundry_gate` | normal | 100% | 4 | — | 0.86 | 1.00 | — |
| six marshals | `sm05_the_open_ledger` | normal | 100% | 7 | — | 1.00 | 1.00 | — |
| six marshals | `sm06_the_toll_bridge` | normal | 100% | 8 | 12 | 1.00 | 1.00 | — |
| six marshals | `sm07_the_watchtower` | normal | 11% | 8 | — | 1.00 | 1.00 | Orlov hunted what limped — more than eleven of ours lost, to any cause. |
| six marshals | `sm08_close_quarters` | normal | 100% | 7 | — | 1.00 | 1.00 | — |
| six marshals | `sm09_broken_ground` | normal | 100% | 7 | — | 1.00 | 1.00 | — |
| six marshals | `sm10_first_blood` | hard | 0% | — | — | 1.00 | 1.00 | Your army was destroyed. |
| six marshals | `sm11_the_running_tally` | hard | 100% | 6 | — | 1.00 | 1.00 | — |
| six marshals | `sm12_the_narrow_crossing` | hard | 100% | 4 | — | 1.00 | 1.00 | — |
| six marshals | `sm13_the_narrow_gate` | hard | 0% | — | — | 0.62 | 1.00 | Your army was destroyed. |
| six marshals | `sm14_the_treeline` | hard | 100% | 4 | — | 0.58 | 1.00 | — |
| six marshals | `sm15_the_last_span` | hard | 100% | 7 | 11 | 0.61 | 1.00 | — |
| six marshals | `sm16_the_wide_field` | hard | 0% | — | — | 1.00 | 1.00 | Hammerfall took whatever stood together — more than eleven of ours lost, to any cause. |
| six marshals | `sm17_scattered_ground` | hard | 100% | 6 | — | 1.00 | 1.00 | — |
| six marshals | `sm18_the_last_terror` | hard | 100% | 9 | — | 1.00 | 1.00 | — |
| collection | `tc01_the_ledger_opens` | normal | 100% | 5 | — | 1.00 | 1.00 | — |
| collection | `tc02_named_in_the_audit` | normal | 78% | 14 | — | 1.00 | 1.00 | Your army was destroyed. |
| collection | `tc03_the_supply_chain` | normal | 0% | — | — | 1.00 | 1.00 | More than eight of ours were lost holding the road. |
| collection | `tc04_the_garrison_auction` | normal | 67% | 17 | — | 1.00 | 1.00 | Your army was destroyed. |
| collection | `tc05_the_tally_post` | normal | 100% | 4 | — | 1.00 | 1.00 | — |
| collection | `tc06_the_seized_province` | normal | 56% | 8 | — | 1.00 | 1.00 | More than eight units lost, counting any merged into another. |
| collection | `tc07_the_blockade` | normal | 0% | — | — | 0.69 | 0.75 | Your army was destroyed. |
| collection | `tc08_silencing_the_witness` | normal | 0% | — | — | 0.56 | 0.60 | The auditor's escort was destroyed. |
| collection | `tc09_the_listening_posts` | normal | 0% | — | — | 0.60 | 0.50 | Your army was destroyed. |
| collection | `tc10_the_squeeze` | normal | 100% | 7 | 11 | 0.41 | 0.40 | — |
| collection | `tc11_the_comeback` | hard | 0% | — | — | 0.69 | 0.33 | Your army was destroyed. |
| collection | `tc12_the_counting_house` | hard | 0% | — | — | 0.63 | 0.75 | Your army was destroyed. |
| collection | `tc13_crossing_the_line` | hard | 11% | 5 | — | 1.00 | 1.00 | More than eight units lost — the crossing was anything but clean. |
| collection | `tc14_draegs_line` | hard | 100% | 5 | — | 3.00 | 1.00 | — |
| collection | `tc15_the_foundry_chain` | hard | 0% | — | — | 1.00 | 1.00 | More than nine units lost — the column stopped being spread. |
| collection | `tc16_out_producing_the_foundry` | hard | 89% | 6 | — | 1.00 | 1.00 | Your army was destroyed. |
| collection | `tc17_the_foundry_core` | hard | 89% | 8 | — | 1.00 | 1.00 | Your army was destroyed. |
| collection | `tc18_closing_the_ledger` | hard | 33% | 14 | — | 1.00 | 1.00 | Your army was destroyed. |
| hollow crown | `hc01_border_skirmish` | easy | 0% | — | — | 1.00 | 1.00 | Your army was destroyed. |
| hollow crown | `hc02_river_line` | easy | 33% | 21 | — | 1.00 | 1.00 | Your army was destroyed. |
| hollow crown | `hc03_the_garrison` | normal | 22% | 24 | — | 1.00 | 1.00 | (still running) |
| hollow crown | `hc04_watchtower` | normal | 11% | 22 | — | 1.00 | 1.00 | (still running) |
| hollow crown | `hc05_the_ultimatum` | normal | 0% | — | — | 1.00 | 1.00 | Your army was destroyed. |
| hollow crown | `hc06_the_crack` | normal | 33% | 23 | — | 1.00 | 1.00 | (still running) |
| hollow crown | `hc07_uneasy_alliance` | normal | 100% | 5 | — | 1.00 | 1.00 | — |
| hollow crown | `hc08_shared_supply` | normal | 100% | 4 | — | 1.00 | 1.00 | — |
| hollow crown | `hc09_the_crossroads` | normal | 100% | 5 | — | 1.00 | 1.00 | — |
| hollow crown | `hc10_broken_column` | hard | 100% | 4 | — | 1.00 | 1.00 | — |
| hollow crown | `hc11_two_fronts` | hard | 100% | 5 | — | 1.00 | 1.00 | — |
| hollow crown | `hc12_the_bargain_kept` | hard | 100% | 5 | — | 1.00 | 1.00 | — |
| hollow crown | `hc13_the_capital_road` | hard | 100% | 16 | — | 1.00 | 1.00 | — |
| hollow crown | `hc14_last_garrison` | hard | 100% | 5 | — | 1.00 | 1.00 | — |
| hollow crown | `hc15_the_regents_gate` | hard | 0% | — | — | 1.00 | 1.00 | Your army was destroyed. |
| hollow crown | `hc16_siege_lines` | hard | 100% | 7 | — | 1.00 | 1.00 | — |
| hollow crown | `hc17_the_high_seat` | hard | 100% | 14 | — | 1.00 | 1.00 | — |
| hollow crown | `hc18_the_hollow_crown` | hard | 0% | — | — | 1.00 | 1.00 | Your army was destroyed. |
| long front | `lf01_customs_line` | easy | 0% | — | — | 0.71 | 1.00 | The refugee column was lost on the customs road. |
| long front | `lf02_the_last_causeway` | easy | 100% | 6 | — | 0.43 | 1.00 | — |
| long front | `lf03_riptide_landing` | easy | 0% | — | — | 0.61 | 1.00 | The coast watch was caught on the beach road. |
| long front | `lf04_seawall_retreat` | easy | 11% | 5 | — | 0.58 | 1.00 | Your army was destroyed. |
| long front | `lf05_greenwood_ambuscade` | easy | 100% | 6 | — | 0.55 | 1.00 | — |
| long front | `lf06_the_last_grove` | easy | 89% | 6 | — | 0.55 | 1.00 | Your army was destroyed. |
| long front | `lf07_the_narrows` | normal | 0% | — | — | 0.47 | 2.00 | Your army was destroyed. |
| long front | `lf08_after_hammerfall` | normal | 0% | — | — | 0.79 | 1.00 | Your army was destroyed. |
| long front | `lf09_the_bridge_at_carrow` | normal | 0% | — | — | 0.79 | 0.50 | Your army was destroyed. |
| long front | `lf10_the_supply_line` | normal | 0% | — | — | 0.57 | 1.00 | Your army was destroyed. |
| long front | `lf11_iron_hill` | normal | 0% | — | — | 0.57 | 1.00 | Your army was destroyed. |
| long front | `lf12_the_forward_camp` | normal | 22% | 9 | — | 0.85 | 0.50 | Your army was destroyed. |
| long front | `lf13_the_foothill_road` | hard | 0% | — | — | 0.85 | 1.00 | Your army was destroyed. |
| long front | `lf14_the_high_passes` | hard | 0% | — | — | 0.70 | 0.50 | Your army was destroyed. |
| long front | `lf15_the_airfield_raid` | hard | 89% | 5 | — | 1.11 | 0.50 | Your army was destroyed. |
| long front | `lf16_reckoning_at_averyn_pass` | hard | 0% | — | — | 0.74 | 1.00 | Your army was destroyed. |
| long front | `lf17_the_shadow_of_the_keep` | hard | 0% | — | — | 0.94 | 0.67 | Your army was destroyed. |
| long front | `lf18_the_keep_at_draeg_hold` | hard | 0% | — | — | 0.80 | 0.67 | Your army was destroyed. |
| quiet war | `qw01_the_flipped_town` | easy | 100% | 3 | — | 0.62 | 0.50 | — |
| quiet war | `qw02_the_column_in_the_pines` | easy | 100% | 4 | — | 1.60 | 0.50 | — |
| quiet war | `qw03_quiet_ground` | easy | 44% | 12 | — | 1.60 | 1.00 | Your army was destroyed. |
| quiet war | `qw04_the_governors_scandal` | normal | 0% | — | — | 0.62 | 0.50 | Your army was destroyed. |
| quiet war | `qw05_the_watch_at_thornfield` | normal | 56% | 6 | — | 1.00 | 2.00 | More than 3 of ours lost in the wood line, to any cause. |
| quiet war | `qw06_the_forward_safehouse` | easy | 0% | — | — | 0.69 | 1.00 | Your army was destroyed. |
| quiet war | `qw07_the_cache_at_millhollow` | normal | 0% | — | — | 0.67 | 0.50 | Your army was destroyed. |
| quiet war | `qw08_the_waystation` | normal | 0% | — | — | 0.83 | 0.50 | Your army was destroyed. |
| quiet war | `qw09_ambush_ground` | normal | 100% | 5 | — | 1.60 | 1.00 | — |
| quiet war | `qw10_the_relay_tower` | normal | 0% | — | — | 0.67 | 0.50 | Your army was destroyed. |
| quiet war | `qw11_the_raid_points` | normal | 100% | 4 | — | 1.60 | 1.00 | — |
| quiet war | `qw12_the_network_node` | hard | 0% | — | — | 0.62 | 0.50 | Your army was destroyed. |
| quiet war | `qw13_the_open_field` | hard | 0% | — | — | 0.74 | 1.00 | Your army was destroyed. |
| quiet war | `qw14_the_daylight_march` | hard | 89% | 8 | — | 1.11 | 1.00 | Your army was destroyed. |
| quiet war | `qw15_the_engineering_works` | hard | 67% | 15 | — | 1.19 | 1.00 | Your army was destroyed. |
| quiet war | `qw16_holding_the_line_in_the_open` | hard | 0% | — | — | 0.70 | 2.00 | Your army was destroyed. |
| quiet war | `qw17_the_last_outpost` | hard | 0% | — | — | 0.94 | 1.00 | Your army was destroyed. |
| quiet war | `qw18_the_man_himself` | hard | 100% | 7 | — | 0.80 | 0.67 | — |

