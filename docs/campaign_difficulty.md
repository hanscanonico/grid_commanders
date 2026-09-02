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

### Fog seat

Reading (2) has a sharper edge on a fog board: **the planner sees through the
whiteout.** A human plays `fw03_cold_relay` blind and lost it on day 6 to a
destroyed army on a row this table reads at 100% (#624). Thirteen missions
ship with `fog_enabled` — `fw03`, `fw17` and `qw02`–`qw12` — and on each of
them the instrument now plays the player's seat twice:

- **`win%`** — the seat sees the whole board, as it always has. This is the
  number every committed table below reads, so the tables still compare.
- **`fog win%`** — the same seeds with that one seat held to the fog a human
  sees: the planner acts only on enemies `Vision` shows its side, so what it
  cannot see it neither shoots, fears in its threat map nor walks toward. The
  enemy seats keep the sight the live game gives them. `—` on a fog-off
  mission, where the two seats would be the same seat.

The switch is `AIController.honour_fog`, off by default and set nowhere but
`tools/run_campaign_difficulty.gd`, so the shipped opponent is untouched — the
"AI sees everything" rule in `.claude/rules/ai.md` and the difficulty lock stand,
and `make verify`'s determinism golden is the proof.

A fog mission the sighted seat wins at least half the time and the blind seat
never wins is **flagged** beside the never-won rows: that is the `fw03` shape,
a board that reads fair here and plays as impossible. Read a `fog win%` that
sits well under `win%` as the cost of the whiteout on that board — sight is
what the mission is about, and the human's answer is the recon and the
property vision the planner is not using well either.

The 2026-09-02 table below is the first with the column.

## The pass this document paid for

Baseline: 56 of 108 missions never won across nine seeds, mean `win%` 38.1.
After the edits below: 50 never won, mean 42.5, and no mission got worse.

**Read this section as history.** The bespoke-ground rework (#603–#620) gave
every mission ground of its own — the allowlist in
`core/campaign/campaign_boards.gd` is empty — and grew the late-act boards of
four wars, so several boards named below are no longer the ground that ships.
The reasoning survives; the numbers are the 2026-09-02 table.

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
seven properties") and `lf14_the_high_passes` ("hold five of the highland cities")
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

0% → **56%** over nine seeds (50% over eighteen), median win day 6, and the
2026-09-02 table below reads the same 56% on the same median day.

## What is still hard, and why it was left alone

Forty-four missions are still never won by the planner (forty-five on the
second sample), three fewer than the forty-seven this record stood at. They
are not a to-do list — they are the three limits above, and two findings
neither the rework nor the redraws moved:

- **The strongest commanders are cast as the enemy.** Of the missions never won,
  Iona Vance is the enemy in 10 of the 21 she plays, Radek Morn in 10 of 18 and
  Konrad Vale in 8 of 16 — three of the standing high names in
  `docs/commander_balance.md` (78.6%, 90.0% and 62.5%, all WARN), against Dane
  Ferrow's 6 of 29 and Cass Orlov's 5 of 20, whose own standing rates are 41.4%
  and 44.7%. That is the commander matrix showing through the campaign, and its
  fix is a commander retune, not a mission edit: retuning a doctrine here would
  move both committed balance reports.
- **Level boards are lost too.** `tc03`, `tc15`, `hc05` and `hc15` open at
  `1.00 / 1.00` and are never won on either sample — `sm10` and `sm16` join them
  on the first and read 11% and 33% on the second — and `tc03` and `tc15` lose
  to a loss limit rather than to a destroyed army. On a level board the only
  things left are the seat, the commander pairing, the limit and the planner, so
  these are the discriminator working: nothing about them says the content is
  wrong, and nothing about them was changed. `hc01` left this list by being won
  on the corridor #649 drew it; `hc18` by opening at 0.89 on its new board.

The line between the two is not sharp, and the missions on it are still left
alone rather than edited on a hunch: `sm13_the_narrow_gate` (0.62 / 1.00),
`fw11_signal_hill` (0.76 / 0.40) and `qw13_the_open_field` (0.74 / 1.00, one win
in nine on one sample) all sit above the odds bar the 2026-08-17 pass used and
below parity, and none of them is obviously either fault.

The follow-up the table asks for is a **human** pass over the level-board
missions above and over The Furnace Winter as a whole (11 of its 18 missions are
never won on the first sample and 13 on the second, at odds 0.62–1.60 — the war
still furthest from being read by this instrument), because that is exactly where
a planner-run estimate is least trustworthy.

## Reading a row

```
make campaign-difficulty CAMPAIGN="--seeds=9"    # all six wars, ~10 min
make campaign-difficulty CAMPAIGN="--campaign=the_long_front --seeds=3"
make campaign-difficulty CAMPAIGN="--mission=fw06_first_thaw --seeds=9 --days=30"
```

`win%` is over `--seeds` matches; `day` is the median day of the ones it won;
`deadline` is the mission's `DayDeadline` failure or `—`; the last column is the
most common reason it ended, `(still running)` meaning the `--days` horizon was
reached rather than the mission lost. Since `MissionRuntime` started telling a
captured headquarters from a rout, that column reads "Your headquarters fell."
for the former — `hc02` and `qw03` in the table below — and no number moved
with it. A run also writes
`missions.csv` and `summary.json` under `reports/campaign_difficulty/`
(gitignored).

## The measurement, 2026-09-02

108 missions, 9 seeds each, 24-day horizon, measured at `f9c4dd58` — the seed
count and the horizon of every table before it, so the columns compare, plus
the `fog win%` column the instrument gained in #632. It supersedes the
2026-09-01 table wholesale; a later sweep supersedes this one the same way.

Where the record stands: **44 of 108 never won** against the forty-seven the
superseded table read, mean `win%` **45.0** against 43.1. A second independent
nine-seed sample of the same build (`--seed-offset=9`) reads 45 never won and
mean 45.7. No mission's clock is at or under its own median win day, so the
instrument's 46 flagged rows are the 44 never won plus the two fog rows below.

### Nine seeds is still a band

Ten missions move by a third or more between the two samples, and the seven
the 2026-09-01 sweep named are seven of them: `sm07` 11/44, `sm16` 0/33, `tc02`
78/33, `tc18` 33/89, `hc03` 11/56, `lf05` 100/56, `lf06` 89/33 — joined by
`hc04` 78/44, `lf13` 44/89 and `qw14` 67/100, three of the boards redrawn since,
read at the same width as the boards that were not. Two rows crossed zero on
one sample with nothing edited: `sm10` 0/11 and `sm16` 0/33, both level boards
the previous record listed as never won. So the reading stands: one middling
row is a band of roughly ±30 points, the never-won count ±2, and only a 0% or a
100% that repeats is a fact about the mission.

### What moved since 2026-09-01

Twenty-four boards were redrawn or edited between the two sweeps (#624, #639,
#647–#653), and every row that changed hands is one of them — nothing else in
the table moved past the band above. Before → after, first sample / second,
with `odds` / `income` where they changed:

- `hc01_border_skirmish` **0 → 100% / 100%** (median day 7), #649. The Act I
  corridor is new ground and the objective is a hold to day 7 rather than a
  capture at (15,2) — the one mission this sweep took off the never-won list
  on both samples, and off the level-board list above with it.
- `hc04_watchtower` **11 → 78% / 44%**, #649, its ending moving from `(still
  running)` to a destroyed army: the redrawn corridor lets the fight finish.
  `hc05` 0 → 0 / 0 and `hc06` 33 → 33 / 33 on the same pass.
- `lf04_seawall_retreat` **11 → 100% / 100%** (median day 5), #648, odds 0.58 →
  1.04 and income 1.00 → 2.00: the port at (6,1) is a second player property and
  the lander counts as player value, and the harbour is a refuge the planner's
  last unit sits in at the verdict. `lf03_riptide_landing` beside it stays 0%
  with the same ending on the beach road, its odds 0.61 → 0.39 because the
  enemy battleship is 28,000 of army value the fraction now counts.
- `lf07_the_narrows` 0 → 0% / 0% at odds 0.47, #653. The instrument opens a
  fresh session, so it measures the route where the coast watch was lost;
  #653's own measurement of the saved route — a player battleship in the sea
  arm on day 2 — read 100% on both samples, the first time a ledger fact moves
  a row.
- `lf15_the_airfield_raid` **100 → 56% / 67%**, #650, median win day 4 → 20 and
  the rest `(still running)`: the plateau is climbed through one road cell and
  the planner is slow on it. The largest fall in the table, and not a 0%.
  `lf17` and `lf18` stay 0% on both samples with the endings the previous
  record named.
- `lf13_the_foothill_road` 56 → 44% / 89%, `lf14_the_high_passes` 0 → 0 / 0
  with its ending now `(still running)` rather than a destroyed army (the city
  race lost, not a rout), and `lf16` 0 → 0 / 0, #651.
- `qw13_the_open_field` 0 → **11% / 0%**, `qw14_the_daylight_march` 89 →
  67 / 100, `qw16` 0 → 0 / 0 and `qw17` 0 → 0 / 0, #647. Odds and income
  unchanged on all four.
- `fw09`–`fw12`, #652: `fw09` 22 → 22 / 11, `fw10` 11 → 11 / 0, `fw11` 0 → 0 / 0,
  `fw12_last_mile` 0 → **11% / 0%** (median day 23). The two that read one win
  in nine sit at the instrument's floor; #652's 27-seed extension read 3/27 on
  both.
- `fw06_first_thaw` odds **0.56 → 1.00** and `tc08_silencing_the_witness`
  **0.56 → 0.89**, #639, one `[units]` row each. Both stay 0% on both samples,
  which the bar allows: the fault the bar names was the opening, and the
  opening is level. `fw06`'s income 0.33 is still the lowest in the table.
- `fw03_cold_relay` odds 0.67 → 1.00, #624 — the one hand-change the
  superseded table already carried in its row, so the two tables read 1.00
  alike. Vance's base at (11,7) became a city and her mech came off her line,
  so her `income` 0.67 overstates her (a property she cannot spend at counts
  the same as one she can). 100% → 100% sighted, and **0% blind on both
  samples**, below.

Endings moved on two rows without a number moving: `hc02_river_line` and
`qw03_quiet_ground` now read "Your headquarters fell." — the `MissionRuntime`
split the previous table predates.

### Review triggers

Recorded, not acted on: no `.tres`, board or balance number was touched for
this document.

Resolved: `hc01_border_skirmish`, 0% on level ground, by #649 as above. The
four the 2026-09-01 sweep named all stand: `qw15_the_engineering_works` 0% /
0% at 1.29 / 0.75, `hc13_the_capital_road` 11% / 11% with a median win on day
24, `lf17_the_shadow_of_the_keep` 0% / 0% on its nine-unit loss limit, and
`fw08_pipeline_west` 0% / 0% — `(still running)` on the first sample and a
destroyed army on the second, so the horizon is not all of it.

New:

- **`fw03_cold_relay` is 100% sighted and 0% blind on both samples** — the
  shape the column was built for (#632), now on the record with its number.
  The human loss #624 answered was on this row; the board reads level (1.00)
  and the blind seat still never wins the day-3 race.
- **`qw09_ambush_ground` is 100% sighted and 0% blind** on the first sample and
  100% / 44% on the second — the flag fires on one sample, and the second says
  the whiteout costs the row about half its wins.
- No mission the previous table read as won went to 0% on both samples.

The other eleven fog rows are not this shape: `qw02` and `qw11` are 100% on
both seats, `qw03` and `qw05` are won blind at least as often as sighted (67% /
78% blind against 44% / 33% on `qw03`), and the seven at 0% on both seats —
`fw17`, `qw04`, `qw06`–`qw08`, `qw10`, `qw12` — are lost with the whole board in
view, so the whiteout is not what decides them.

| war | mission | tier | win% | fog win% | median day | deadline | odds | income | most common ending |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| furnace winter | `fw01_dry_taps` | easy | 89% | — | 4 | — | 0.81 | 0.67 | Your army was destroyed. |
| furnace winter | `fw02_last_granary` | easy | 44% | — | 24 | — | 0.67 | 0.67 | Your army was destroyed. |
| furnace winter | `fw03_cold_relay` | normal | 100% | 0% | 3 | — | 1.00 | 0.67 | — |
| furnace winter | `fw04_ice_road` | normal | 0% | — | — | — | 0.69 | 0.67 | The fuel sledge went under the ice. |
| furnace winter | `fw05_powder_ration` | normal | 0% | — | — | — | 0.67 | 0.67 | Your army was destroyed. |
| furnace winter | `fw06_first_thaw` | normal | 0% | — | — | — | 1.00 | 0.33 | Your army was destroyed. |
| furnace winter | `fw07_pipeline_east` | normal | 0% | — | — | — | 1.60 | 0.50 | Your army was destroyed. |
| furnace winter | `fw08_pipeline_west` | normal | 0% | — | — | — | 1.60 | 1.00 | (still running) |
| furnace winter | `fw09_coalyard_junction` | normal | 22% | — | 14 | — | 1.14 | 0.50 | More than five of our units left the column, however they went. |
| furnace winter | `fw10_ashen_crossing` | hard | 11% | — | 14 | — | 0.94 | 0.40 | Your army was destroyed. |
| furnace winter | `fw11_signal_hill` | hard | 0% | — | — | — | 0.76 | 0.40 | Your army was destroyed. |
| furnace winter | `fw12_last_mile` | hard | 11% | — | 23 | — | 0.94 | 0.40 | Your army was destroyed. |
| furnace winter | `fw13_foundry_gate` | hard | 0% | — | — | — | 0.71 | 0.75 | Your army was destroyed. |
| furnace winter | `fw14_slag_row` | hard | 33% | — | 7 | — | 0.71 | 0.75 | More than five of our units left the column, however they went. |
| furnace winter | `fw15_smelter_yard` | hard | 0% | — | — | — | 0.62 | 1.00 | More than six of ours lost, to any cause. The yard crews can replace machines, not columns. |
| furnace winter | `fw16_arsenal_road` | hard | 0% | — | — | — | 0.71 | 0.75 | More than five of our units left the line, however they went. |
| furnace winter | `fw17_the_stacks` | hard | 0% | 0% | — | — | 0.71 | 0.75 | Your army was destroyed. |
| furnace winter | `fw18_vales_furnace` | hard | 0% | — | — | — | 0.71 | 0.75 | Your army was destroyed. |
| six marshals | `sm01_border_toll` | normal | 100% | — | 3 | — | 1.08 | 1.00 | — |
| six marshals | `sm02_ambush_pass` | normal | 100% | — | 4 | — | 1.00 | 1.00 | — |
| six marshals | `sm03_the_long_watch` | normal | 89% | — | 6 | — | 0.67 | 1.00 | Ferrow was paid by the kill — more than three of ours lost, to any cause. |
| six marshals | `sm04_the_foundry_gate` | normal | 100% | — | 4 | — | 0.86 | 1.00 | — |
| six marshals | `sm05_the_open_ledger` | normal | 100% | — | 7 | — | 1.00 | 1.00 | — |
| six marshals | `sm06_the_toll_bridge` | normal | 100% | — | 8 | 12 | 1.00 | 1.00 | — |
| six marshals | `sm07_the_watchtower` | normal | 11% | — | 8 | — | 1.00 | 1.00 | Orlov hunted what limped — more than eleven of ours lost, to any cause. |
| six marshals | `sm08_close_quarters` | normal | 100% | — | 7 | — | 1.00 | 1.00 | — |
| six marshals | `sm09_broken_ground` | normal | 100% | — | 7 | — | 1.00 | 1.00 | — |
| six marshals | `sm10_first_blood` | hard | 0% | — | — | — | 1.00 | 1.00 | Your army was destroyed. |
| six marshals | `sm11_the_running_tally` | hard | 100% | — | 6 | — | 1.00 | 1.00 | — |
| six marshals | `sm12_the_narrow_crossing` | hard | 100% | — | 4 | — | 1.00 | 1.00 | — |
| six marshals | `sm13_the_narrow_gate` | hard | 0% | — | — | — | 0.62 | 1.00 | Your army was destroyed. |
| six marshals | `sm14_the_treeline` | hard | 89% | — | 4 | — | 0.58 | 1.00 | Your army was destroyed. |
| six marshals | `sm15_the_last_span` | hard | 100% | — | 7 | 11 | 0.61 | 1.00 | — |
| six marshals | `sm16_the_wide_field` | hard | 0% | — | — | — | 1.00 | 1.00 | Hammerfall took whatever stood together — more than eleven of ours lost, to any cause. |
| six marshals | `sm17_scattered_ground` | hard | 100% | — | 6 | — | 1.00 | 1.00 | — |
| six marshals | `sm18_the_last_terror` | hard | 100% | — | 9 | — | 1.00 | 1.00 | — |
| collection | `tc01_the_ledger_opens` | normal | 100% | — | 5 | — | 1.00 | 1.00 | — |
| collection | `tc02_named_in_the_audit` | normal | 78% | — | 14 | — | 1.00 | 1.00 | Your army was destroyed. |
| collection | `tc03_the_supply_chain` | normal | 0% | — | — | — | 1.00 | 1.00 | More than eight of ours were lost holding the road. |
| collection | `tc04_the_garrison_auction` | normal | 67% | — | 17 | — | 1.00 | 1.00 | Your army was destroyed. |
| collection | `tc05_the_tally_post` | normal | 100% | — | 4 | — | 1.00 | 1.00 | — |
| collection | `tc06_the_seized_province` | normal | 56% | — | 8 | — | 1.00 | 1.00 | More than eight units lost, counting any merged into another. |
| collection | `tc07_the_blockade` | normal | 0% | — | — | — | 0.69 | 0.75 | Your army was destroyed. |
| collection | `tc08_silencing_the_witness` | normal | 0% | — | — | — | 0.89 | 0.60 | The auditor's escort was destroyed. |
| collection | `tc09_the_listening_posts` | normal | 0% | — | — | — | 0.60 | 0.50 | Your army was destroyed. |
| collection | `tc10_the_squeeze` | normal | 100% | — | 7 | 11 | 0.41 | 0.40 | — |
| collection | `tc11_the_comeback` | hard | 0% | — | — | — | 0.69 | 0.33 | Your army was destroyed. |
| collection | `tc12_the_counting_house` | hard | 0% | — | — | — | 0.63 | 0.75 | Your army was destroyed. |
| collection | `tc13_crossing_the_line` | hard | 11% | — | 5 | — | 1.00 | 1.00 | More than eight units lost — the crossing was anything but clean. |
| collection | `tc14_draegs_line` | hard | 100% | — | 6 | — | 1.45 | 1.00 | — |
| collection | `tc15_the_foundry_chain` | hard | 0% | — | — | — | 1.00 | 1.00 | More than nine units lost — the column stopped being spread. |
| collection | `tc16_out_producing_the_foundry` | hard | 89% | — | 7 | — | 1.00 | 1.00 | Your army was destroyed. |
| collection | `tc17_the_foundry_core` | hard | 89% | — | 8 | — | 1.00 | 1.00 | Your army was destroyed. |
| collection | `tc18_closing_the_ledger` | hard | 33% | — | 14 | — | 1.00 | 1.00 | Your army was destroyed. |
| hollow crown | `hc01_border_skirmish` | easy | 100% | — | 7 | — | 1.00 | 1.00 | — |
| hollow crown | `hc02_river_line` | easy | 33% | — | 18 | — | 1.00 | 1.00 | Your headquarters fell. |
| hollow crown | `hc03_the_garrison` | normal | 11% | — | 13 | — | 1.00 | 1.00 | Your army was destroyed. |
| hollow crown | `hc04_watchtower` | normal | 78% | — | 19 | — | 1.00 | 1.00 | Your army was destroyed. |
| hollow crown | `hc05_the_ultimatum` | normal | 0% | — | — | — | 1.00 | 1.00 | Your army was destroyed. |
| hollow crown | `hc06_the_crack` | normal | 33% | — | 21 | — | 1.00 | 1.00 | (still running) |
| hollow crown | `hc07_uneasy_alliance` | normal | 100% | — | 5 | — | 1.00 | 1.00 | — |
| hollow crown | `hc08_shared_supply` | normal | 100% | — | 6 | — | 1.00 | 1.00 | — |
| hollow crown | `hc09_the_crossroads` | normal | 100% | — | 6 | — | 1.00 | 1.00 | — |
| hollow crown | `hc10_broken_column` | hard | 100% | — | 5 | — | 1.00 | 1.00 | — |
| hollow crown | `hc11_two_fronts` | hard | 100% | — | 3 | — | 1.00 | 1.00 | — |
| hollow crown | `hc12_the_bargain_kept` | hard | 100% | — | 6 | — | 1.00 | 1.00 | — |
| hollow crown | `hc13_the_capital_road` | hard | 11% | — | 24 | — | 0.93 | 1.00 | Your army was destroyed. |
| hollow crown | `hc14_last_garrison` | hard | 89% | — | 12 | — | 1.00 | 1.00 | (still running) |
| hollow crown | `hc15_the_regents_gate` | hard | 0% | — | — | — | 1.00 | 1.00 | Your army was destroyed. |
| hollow crown | `hc16_siege_lines` | hard | 100% | — | 4 | — | 1.00 | 0.75 | — |
| hollow crown | `hc17_the_high_seat` | hard | 89% | — | 17 | — | 1.00 | 1.00 | (still running) |
| hollow crown | `hc18_the_hollow_crown` | hard | 0% | — | — | — | 0.89 | 1.00 | Your army was destroyed. |
| long front | `lf01_customs_line` | easy | 0% | — | — | — | 0.71 | 1.00 | The refugee column was lost on the customs road. |
| long front | `lf02_the_last_causeway` | easy | 100% | — | 6 | — | 0.43 | 1.00 | — |
| long front | `lf03_riptide_landing` | easy | 0% | — | — | — | 0.39 | 1.00 | The coast watch was caught on the beach road. |
| long front | `lf04_seawall_retreat` | easy | 100% | — | 5 | — | 1.04 | 2.00 | — |
| long front | `lf05_greenwood_ambuscade` | easy | 100% | — | 6 | — | 0.55 | 1.00 | — |
| long front | `lf06_the_last_grove` | easy | 89% | — | 6 | — | 0.55 | 1.00 | Your army was destroyed. |
| long front | `lf07_the_narrows` | normal | 0% | — | — | — | 0.47 | 2.00 | Your army was destroyed. |
| long front | `lf08_after_hammerfall` | normal | 0% | — | — | — | 0.79 | 1.00 | Your army was destroyed. |
| long front | `lf09_the_bridge_at_carrow` | normal | 0% | — | — | — | 0.79 | 0.50 | Your army was destroyed. |
| long front | `lf10_the_supply_line` | normal | 0% | — | — | — | 0.57 | 1.00 | Your army was destroyed. |
| long front | `lf11_iron_hill` | normal | 0% | — | — | — | 0.57 | 1.00 | Your army was destroyed. |
| long front | `lf12_the_forward_camp` | normal | 22% | — | 9 | — | 0.85 | 0.50 | Your army was destroyed. |
| long front | `lf13_the_foothill_road` | hard | 44% | — | 13 | — | 0.95 | 1.33 | (still running) |
| long front | `lf14_the_high_passes` | hard | 0% | — | — | — | 0.88 | 1.00 | (still running) |
| long front | `lf15_the_airfield_raid` | hard | 56% | — | 20 | — | 1.05 | 1.00 | (still running) |
| long front | `lf16_reckoning_at_averyn_pass` | hard | 0% | — | — | — | 0.80 | 1.00 | Your army was destroyed. |
| long front | `lf17_the_shadow_of_the_keep` | hard | 0% | — | — | — | 1.19 | 1.00 | More than nine units lost, from any cause — nothing left to arrive with. |
| long front | `lf18_the_keep_at_draeg_hold` | hard | 0% | — | — | — | 0.89 | 1.00 | Your army was destroyed. |
| quiet war | `qw01_the_flipped_town` | easy | 100% | — | 3 | — | 0.62 | 0.50 | — |
| quiet war | `qw02_the_column_in_the_pines` | easy | 100% | 100% | 4 | — | 1.60 | 0.50 | — |
| quiet war | `qw03_quiet_ground` | easy | 44% | 67% | 12 | — | 1.60 | 1.00 | Your headquarters fell. |
| quiet war | `qw04_the_governors_scandal` | normal | 0% | 0% | — | — | 0.62 | 0.50 | Your army was destroyed. |
| quiet war | `qw05_the_watch_at_thornfield` | normal | 56% | 56% | 6 | — | 1.00 | 2.00 | More than 3 of ours lost in the wood line, to any cause. |
| quiet war | `qw06_the_forward_safehouse` | easy | 0% | 0% | — | — | 0.69 | 1.00 | Your army was destroyed. |
| quiet war | `qw07_the_cache_at_millhollow` | normal | 0% | 0% | — | — | 0.67 | 0.50 | Your army was destroyed. |
| quiet war | `qw08_the_waystation` | normal | 0% | 0% | — | — | 0.83 | 0.50 | Your army was destroyed. |
| quiet war | `qw09_ambush_ground` | normal | 100% | 0% | 5 | — | 1.60 | 1.00 | — |
| quiet war | `qw10_the_relay_tower` | normal | 0% | 0% | — | — | 0.67 | 0.50 | Your army was destroyed. |
| quiet war | `qw11_the_raid_points` | normal | 100% | 100% | 4 | — | 1.60 | 1.00 | — |
| quiet war | `qw12_the_network_node` | hard | 0% | 0% | — | — | 0.62 | 0.50 | Your army was destroyed. |
| quiet war | `qw13_the_open_field` | hard | 11% | — | 10 | — | 0.74 | 1.00 | Your army was destroyed. |
| quiet war | `qw14_the_daylight_march` | hard | 67% | — | 16 | — | 1.06 | 1.00 | (still running) |
| quiet war | `qw15_the_engineering_works` | hard | 0% | — | — | — | 1.29 | 0.75 | Your army was destroyed. |
| quiet war | `qw16_holding_the_line_in_the_open` | hard | 0% | — | — | — | 0.73 | 1.50 | Your army was destroyed. |
| quiet war | `qw17_the_last_outpost` | hard | 0% | — | — | — | 0.94 | 1.00 | Your army was destroyed. |
| quiet war | `qw18_the_man_himself` | hard | 100% | — | 6 | — | 0.87 | 0.67 | — |
