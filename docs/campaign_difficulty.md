# Campaign mission difficulty

`make campaigns` says a mission is *playable* — the board parses, the seating is
one it deals, every objective names ground that exists. It says nothing about
whether the mission can be *won*. This is the committed record of the other
question, measured rather than argued. It measures *Five Flags*, the campaign that
replaced the six wars on 2026-09-28; the six wars' tables, and the content passes
they paid for (COM-248, COM-251), are this file's history in git.

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
whiteout.** A human played the old war's `fw03` blind and lost it on day 6 to
a destroyed army on a row the instrument read at 100% (#624). Seven Five Flags
missions ship with `fog_enabled` — ff03, ff15, ff16, ff19, ff24, ff27 and ff35 —
and on each of them the instrument plays the player's seat twice:

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
never wins is **flagged** beside the never-won rows: that is the old `fw03` shape,
a board that reads fair here and plays as impossible. Read a `fog win%` that
sits well under `win%` as the cost of the whiteout on that board — sight is
what the mission is about, and the human's answer is the recon and the
property vision the planner is not using well either.


## Reading a row

```
make campaign-difficulty CAMPAIGN="--campaign=five_flags --seeds=6"   # the whole war
make campaign-difficulty CAMPAIGN="--mission=ff13_the_capital_line --seeds=6 --days=30"
```

`win%` is over `--seeds` matches; `day` is the median day of the ones it won;
`deadline` is the mission's `DayDeadline` failure or `—`; the last column of the
instrument's own output is the most common reason a run ended, `(still running)`
meaning the `--days` horizon was reached rather than the mission lost. A run also
writes `missions.csv` and `summary.json` under `reports/campaign_difficulty/`
(gitignored). **The instrument opens every mission on an empty ledger**, so a
mission whose board a fact changes is measured on the route where nothing was
earned; the routes the table cannot see are listed after it.

## The measurement, 2026-09-29

Five Flags, 39 missions, 6 seeds each, 24-day horizon, measured on the
integration branch at `a70a6162` (Act VI's seven rows re-run on the settled tree
after it merged mid-sweep). Tiers: 3 easy, 20 normal, 16 hard. Par is the
mission's own speed star, set for a human who plays the objective.

| Mission | Tier | win% | fog win% | day | par | odds | income |
|---|---|---|---|---|---|---|---|
| ff01 Twenty Years | easy | 83% | — | 5 | 6 | 1.29 | 0.33 |
| ff02 The Toll Bridge | easy | 100% | — | 4 | 5 | 0.97 | 1.00 |
| ff03 Lanterns in the Orchard | easy | 83% | 100% | 11 | 9 | 0.79 | 1.00 |
| ff04 The Lantern Hall | normal | **0%** | — | — | 6 | 1.55 | 1.33 |
| ff05 Five Flags Down | normal | 50% | — | 6 | 7 | 0.31 | 0.44 |
| ff06 The Last Parade | normal | **0%** | — | — | 6 | 1.30 | 2.00 |
| ff07 Harbour Lights | normal | 83% | — | 18 | 9 | 0.85 | 7.00 |
| ff08 The Voss Line | normal | 67% | — | 9 | 9 | 1.00 | 1.00 |
| ff09 The Quartermaster's Road | normal | 67% | — | 8 | 8 | 1.12 | 1.75 |
| ff10 The Mint at Aurum Ford | normal | 67% | — | 8 | 6 | 1.45 | 0.83 |
| ff11 The Green Border | normal | 67% | — | 9 | 8 | 1.48 | 1.00 |
| ff12 Black Skies | normal | 67% | — | 12 | 8 | 1.70 | 1.00 |
| ff13 The Capital Line | normal | 50% | — | 10 | 10 | 0.52 | 1.14 |
| ff14 The People's March | normal | 50% | — | 8 | 10 | 1.62 | 1.00 |
| ff15 Nia's Road | normal | **0%** | 0% | — | 7 | 1.31 | 0.50 |
| ff16 The Hunters' Road | normal | **0%** | 0% | — | 8 | 1.59 | 0.67 |
| ff17 Thorne's Wall | hard | 67% | — | 23 | 14 | 2.19 | 0.80 |
| ff18 The Race to Skyreach | normal | 67% | — | 19 | 10 | 0.81 | 1.00 |
| ff19 Signal and Noise | normal | 50% | 17% | 11 | 10 | 1.26 | 1.00 |
| ff20 The Open Sky | hard | 50% | — | 8 | 12 | 0.69 | 1.50 |
| ff21 The Grauwald Pass | normal | 50% | — | 20 | 11 | 0.87 | 1.25 |
| ff22 Ferrow's Price | normal | 67% | — | 17 | 12 | 0.46 | 0.71 |
| ff23 The Foundries of Kessel | normal | 83% | — | 16 | 12 | 1.41 | 1.00 |
| ff24 Orlov's Hunt | normal | 50% | 50% | 9 | 9 | 1.08 | 1.00 |
| ff25 Kharn | normal | **0%** | — | — | 9 | 0.90 | 0.33 |
| ff26 Draeg | hard | 33% | — | 17 | 10 | 0.89 | 0.50 |
| ff27 Wren | hard | 67% | 33% | 12 | 11 | 0.35 | 0.67 |
| ff28 The Counting Houses | hard | 50% | — | 18 | 12 | 1.16 | 0.60 |
| ff29 Glass Shore | hard | 50% | — | 11 | 10 | 0.93 | 0.71 |
| ff30 Rhea's Line | hard | 50% | — | 19 | 14 | 0.90 | 0.86 |
| ff31 The Arithmetic | hard | 50% | — | 13 | 14 | 0.91 | 0.56 |
| ff32 Recalculation | hard | 33% | — | 9 | 9 | 2.02 | 1.67 |
| ff33 The March of Five | hard | 50% | — | 11 | 12 | 0.93 | 1.10 |
| ff34 The Field Marshal | hard | 50% | — | 9 | 10 | 1.33 | 1.43 |
| ff35 Ostrava | hard | 50% | 33% | 6 | 8 | 0.81 | 0.50 |
| ff36 The Arsenal | hard | 50% | — | 17 | 14 | 1.04 | 1.14 |
| ff37 The Hammer | hard | 33% | — | 19 | 16 | 2.38 | 2.00 |
| ff38 The Hammer, Alone | hard | 33% | — | 22 | 17 | 2.89 | 1.80 |
| ff39 Five Flags | hard | 67% | — | 15 | 16 | 2.40 | 1.29 |

Mean `win%` **50.9**; by act, 53 / 67 / 41 / 47 / 50 / 48. **Five missions are
never won here, and all five are escorts** — the reason below. No fog mission is
flagged: every fog row the blind seat reads under the sighted one still wins.

### The five zeros are escorts, and each was played to a win another way

The planner cannot see an objective, so on a mission won by *getting a named unit
somewhere* it drives that unit into the nearest fight and loses it. Every one of
these opens at fair odds, and each was checked with a scripted player during
review — the planner for everything except the escorted unit, which waits and
then runs:

- **ff04** — the cars held one day, then driven west: **6 of 6 won on day 3**;
  driving them on day 1 loses 6 of 6, which is the mission's real choice.
- **ff06** — the planner's attacks plus a drive for the border: **12 of 12 won**,
  mostly on day 4 against par 6.
- **ff25** — the truck waits in the cage, then runs for the road: **2 of 6 won** on
  day 7 against par 9, a crude escort a human will beat.
- **ff15 / ff16** — no scripted player settled them; the case is the board's (the
  car's one crossing, escorts that can flank it, three mechs against the tanks),
  and ff15's briefing now teaches holding the far bank before the car crosses,
  which defuses the mill-bridge ambush. **These two want a human playtest first.**

### The routes an empty ledger cannot see

- **ff13** reads `ff_convoys`: 50% with none delivered, **67% with two, 83% with
  three** — Hollin's garrison is real help.
- **ff26** reads `ff_draeg_spared`: the table is the not-spared route; spared,
  Draeg's column defects on day 3 and the scripted run won **3 of 3**.
- **ff34** writes `ff_vance_joined` only when the bridgehead falls by day 7 with
  her tank alive, which the planner never does; a steered run took it on day 5 and
  won on day 7, so the branch is live.
- **ff39** is the ledger's sum: **67%** on the empty ledger (Nia counts as spared),
  **33%** on the worst (Nia fought, nothing else earned, still 2.4× odds), and
  **100% by day 12** with every ally earned — generous, and Morn answers Vance's
  arrival with a Hammerfall so it stays a fight.

### Review triggers

Read a change to any of these as a reason to re-measure the mission, not as a
board fact on its own:

- **ff20**'s air balance is knife-edged: one more Vale fighter took the planner
  from 90% to 0% during authoring.
- **ff07**'s median day 18 sits against par 9 because the planner never hunts the
  flagship; a human who does meets the par.
- **ff17**, **ff21**–**ff23** and **ff28**/**ff30** are won slowly by the planner
  (days 16–23), always by routing rather than by the objective; their pars assume
  a human who goes for the HQ, the fort or the town.
- Iris Colt's doctrine (−10% attack and defence) sets the last act's balance, so
  most Act VI boards open above even odds; a retune of Colt moves all seven rows.
