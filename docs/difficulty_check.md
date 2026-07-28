# Difficulty tiers and the ladder gate

How the three difficulty tiers are built, how their ordering is measured, and
what the measurement currently says. This is the committed record of the
difficulty plan's **DF4 — Prove the ordering, then tune**; the generated
CSV/JSON reports are not committed (they live under `reports/`, gitignored).

**Standing verdict: the gate does not pass.** Normal takes 43.3% from Easy and
Difficult takes 66.7% from Normal; neither adjacent pairing clears the required
70%. Difficult now has a measurable advantage, but Easy's intended weakness is
not established. Details and the reasoning below — read §4 before changing a
weight, and §5 before deciding what to do about it.

## 1. What difficulty is allowed to change

Exactly one thing: **which `AIProfile` the computer plans with**.

The AI never cheats at any tier. No income multiplier, no damage multiplier, no
extra vision, no friendlier dice — in either direction, so the player is not
secretly boosted on Easy any more than the AI is on Difficult (plan D2/D3). The
simulation is not touched by this feature at all: `GameState`, the combat
resolver, the damage chart and the fog boundary are identical at every tier, and
a test asserts a tier resource carries nothing but an id, a label and a profile.

That constraint is the whole reason this document exists. With no handicap to
fall back on, the *only* evidence that "Difficult" means anything is that it
wins more games — which is what the gate measures.

| Tier | id | Profile | Character |
|---|---|---|---|
| Easy | `easy` | `data/ai/easy.tres` | Timid: over-weights danger, retreats early, refuses trades, over-buys infantry, no md tank |
| Normal | `normal` | `data/ai/default.tres` | The shipped AI, bit for bit |
| Difficult | `hard` | `data/ai/hard.tres` | Threat-aware and counter-building, sharper trade weights |

Each tier is a `Difficulty` resource in `data/difficulty/` — a label plus one of
those profiles. Retuning a tier is editing its `.tres`.

## 2. The three capabilities

Difficult's extra judgement is three `@export` weights on `AIProfile`, each
defaulting to `0.0`, which skips the capability entirely. At `0` the code that
reads it never runs, so **Normal plans exactly as the pre-difficulty AI did, on
the same RNG stream** — pinned by `test_capability_defaults_plan_exactly_like_the_shipped_profile`,
which compares a full AI turn command for command.

- **S1 threat awareness — two dials on one map.** Builds a per-turn `ThreatMap`
  (`ai/threat_map.gd`): for every visible enemy, its `MovementResolver` reach ×
  its `AttackRange` firing ring, and the damage a `CombatResolver.forecast_at`
  says it would do to the unit standing there. Reuses the single authorities and
  re-derives no rules; the damage it reads is luck-free, and the forecast only
  ever *reads* luck's bounds (for the preview's HP spans) rather than rolling
  them, so it draws no RNG and the replay guarantee holds.
  `forecast_at` takes the defender's cell as an effective value,
  so scoring a hypothetical move is a pure read — nothing is moved to ask. Cached once per turn, keyed on the day and the enemy set, so a
  new day always rebuilds it and a counter-kill mid-turn does too.

  The map is read by two weights, because the two paths that read it do not score
  in the same unit:

  - **`threat_aversion` — attacks, in value.** An attack's score is
    `cost × damage fraction`, so the firing cell's discount is
    `threat × unit cost × threat_aversion` in that same currency. Must stay
    small because the summed threat saturates at a lethal attack and the
    cost-scaled penalty can otherwise make the planner refuse useful trades.
  - **`advance_threat_tiles` — advances, in tiles.** A destination a unit is
    merely walking to scores as `-distance`, stepping by whole integers, so the
    penalty is `advance_threat_tiles × lethality` *tiles* of forward progress,
    where lethality is the forecast damage over the HP the unit has left — `1.0`
    means the shot kills it, so a hurt unit gives up more ground than a fresh one
    for the same incoming fire. Reusing the value-denominated dial here was a
    real defect: at
    Difficult's ladder-safe `0.1` the advance penalty maxes out at a hundredth of
    a tile and could only break ties, so the tier's headline "refuses a kill
    zone" never once cost it a step. Cost-scaling the advance term instead is not
    the fix — that is the R2 coward the superseded probes in §6 measured.
    The floor for a live value is ~1.6: below that a healthy unit cannot buy even
    one tile against a full-strength artillery shot (63 of its 100 points), i.e.
    it is inert where nothing is hurt yet.
    `data/ai/hard.tres` ships `2.0` and `easy.tres` `3.0`; §4 measures those
    values in the current ladder.
- **S2 `focus_fire_bonus` — focus fire.** Boosts a target other ready friendlies
  could still add damage to. Ships at `0.0`: the superseded probes in §6 found
  the bias harmful in both shapes tried, while replanning after every command
  already exposes a wounded target's finishing shot to the next attacker.
- **S3 `build_reactivity` — counter-building.** Re-ranks each affordable combat
  unit by its damage-chart effectiveness against the enemy's actual cost-weighted
  roster, blended over the static `build_priority` list. With no enemy in sight
  there is nothing to react to and the static list decides.

## 3. Running the gate

```sh
make difficulty-check                       # default: 4 seeds
make difficulty-check DIFF="--seeds=15"     # the standing result below
```

It is the same runner as the commander matrix in `--difficulty-check` mode, so a
match here resolves exactly as one in the battle scene. Adjacent tiers only
(Easy-vs-Normal, Normal-vs-Difficult), **no commanders on either side** so a
doctrine cannot colour a measurement of planning, on two committed maps that are
asserted 180°-rotationally symmetric before a match runs, **both seats played on
every seed** so a first-side advantage cancels.

- `scrimmage` (12×9) — the small decisive board.
- `ironworks` (24×16) — the large city-rich board.

**Gate:** the higher tier takes ≥ 70% of its pairing. Missing it means tuning the
`.tres` (or zeroing a misbehaving capability) — never loosening the number.
Rejected commands and cap stalls are hard failures on top: they would mean the
planner and the rules disagree.

## 4. What the measurement says

**Standing result — measured 2026-07-28, 120 matches, 15 seeds, default
20-day cap:**

| Pairing | Overall | scrimmage | ironworks | Gate |
|---|---|---|---|---|
| Normal over Easy | **43.3%** (26/60) | 63.3% | 23.3% | fail |
| Difficult over Normal | **66.7%** (40/60) | 70.0% | 63.3% | fail |

Zero rejected commands and zero cap stalls across all 120 — the planner and the
rules never disagreed, which is the correctness half of this run and it is clean.

This run follows the planner correctness fixes listed in §6, the current
`ironworks` map with its mirrored airfields, and the per-seat
controller correction in the balance harness. It also follows the production
coverage fix measured here: Easy and Difficult retain their land-priority
prefixes, then list every non-transport air and sea combat unit. A capability
test places an owned airport and port on the same board, blocks the irrelevant
facility, and proves each tier issues a valid build for the remaining domain.

### Findings

**(a) Production coverage was a real defect, but fixing it is not sufficient to
prove the ladder.** Easy and Difficult no longer leave an affordable owned
airport or port idle merely because no compatible unit appears in their static
priority list. The full gate nevertheless puts Easy ahead of Normal overall,
and especially on `ironworks`: Normal wins only 7 of 30 there. The intended
"timid and weaker" Easy profile therefore needs a separate tuning pass.

**(b) Difficult is stronger, but not enough.** It exactly clears 70% on
`scrimmage`, takes 63.3% on `ironworks`, and reaches 66.7% overall. That is a
clear improvement over the superseded 50% record, but the gate is defined on the
combined pairing and remains red by 3.3 points.

The two maps still disagree sharply about Easy: Normal takes 63.3% on
`scrimmage` but only 23.3% on `ironworks`. The report does not license an
explanation by estimate; the next pass must change one profile hypothesis at a
time and rerun the same fixed-seed gate.

### Turn time (risk R3)

Mean AI planning per turn in the standing run:

| Tier | ms/turn | over |
|---|---|---|
| Easy | 104.3 | 1118 turns |
| Difficult | 65.8 | 1138 turns |
| Normal | 42.1 | 2258 turns |

These are measurements, not deterministic outputs; the pairing results,
rejected-command count and cap-stall count are the reproducible gate evidence.

## 5. Where this leaves the feature

Everything the plan asked to be *built* is built, tested and shipping: the tier
plumbing, the menu picker, the save key, all three capabilities, and this gate.
What is not established is the ordering the gate exists to prove.

The production defect and its coverage test stay isolated in their own change.
The next step is a separate tuning ticket and pull request: tune Easy against
Normal first, then close Difficult's 3.3-point overall gap, changing one
profile hypothesis at a time and rerunning the 15-seed gate. No threshold,
income, vision, damage, luck, map, or harness change is an acceptable substitute
for a passing profile ladder. A human playtest at Easy and Difficult remains the
other required read on whether the measured profiles are also fun.

`make difficulty-check` exits non-zero while the gate is unmet. That is
deliberate: it is an opt-in release task, kept out of `make verify`, and a red
result is the honest status of the claim.

## 6. Superseded measurements

**None of this section is a current claim.** §4 is the standing record. These
numbers are kept only because code comments and other documents were written
against them and cite the shapes they found; a fixed anchor is better than a
dangling reference. Every one of them predates the planner, the maps and the
harness §4 was measured on, and nothing here has been re-scored by estimate —
`make difficulty-check` is the only thing allowed to write a standing number.

**What changed under them.** The `advance_threat_tiles` split described in §2
and its rescaling against the HP a unit has left; the threat-map lookup being
hoisted out of the per-cell attack and advance loops; the bug-fix pass of
2026-07-24, which gates the threat map's and the focus-fire follow-up's
who-may-shoot through `AttackRange.can_engage`, retreats a damaged unit only to
a property that repairs its domain, and plans every committed path with the
mover's own vision; the charge-meter fix that stopped a team from banking charge
while its own power is active; the `ironworks` retrofit of 2026-07-21, which
gave that board a mirrored pair of day-1 airfields (data-only — no `AIProfile`
weight and no tier `.tres` moved, as D2/D3 require); the per-seat controller
correction in the balance harness; and the production-coverage fix §4 measures.

**Superseded standing result — 120 matches, 15 seeds, default 20-day cap:**

| Pairing | Overall | scrimmage | ironworks |
|---|---|---|---|
| Normal over Easy | 68.3% (41/60) | 90.0% | 46.7% |
| Difficult over Normal | 50.0% (30/60) | 53.3% | 46.7% |

**Superseded finding (a) — the day-cap tiebreak can turn over on noise.** On
that run `ironworks` scored the known-weaker Easy even with Normal (46.7%), and
re-running at `--days=40` did not help (Normal-over-Easy fell to 37.5% there).
The reading was that on a large city-rich board inside a day cap, both sides
sprawl and capture at similar rates and the tiebreak (properties, then units,
then funds) decides on noise. This is the finding
`tools/balance/run_summary.gd`'s `MIN_RESOLVED_PCT` and `docs/balance_sim.md`'s
low-confidence reading rule were written against — the threshold flags a value
whose games mostly ended on the cap rather than on the board, which is a
standing reading rule regardless of which run first showed it.

**Superseded finding (b) — isolated single-capability probes.** On `scrimmage`,
60 matches each, against the then-shipped Normal profile; 50% is parity:

| Variant | Win % | Read |
|---|---|---|
| control (Normal vs Normal) | 50.0 | sanity check — the harness is unbiased |
| `threat_aversion` 0.02 / 0.05 / 0.10 | 56.7 / 53.3 / 58.3 | mild but real gain |
| `threat_aversion` 0.20 | 35.0 | already harmful |
| `threat_aversion` 0.50 | 11.7 | catastrophic — the R2 coward |
| `build_reactivity` 0.3 / 0.6 / 1.0 | 50.0 / 53.3 / 55.0 | mild gain |
| `kill_bonus` 1.8 + `counter_weight` 0.5 | 50.0 | neutral |
| `threat` 0.1 + `build` 1.0 | 61.7 | best combination found |
| `focus_fire_bonus` 0.2 / 0.5 / 1.0 | 43.3 / 41.7 / 43.3 | negative |

The 0.5 row is the "lost 88% of its games" that `data/ai/hard.tres` and
`data/ai/easy.tres` cite for why `threat_aversion` must stay small: the penalty
is scaled by the exposed unit's cost and the threat total sums every enemy that
could reach the cell, so above ~0.15 the discount exceeds the value of almost
any attack and the planner stops attacking. Easy ships that dial turned the
other way on purpose.

Focus fire measured negative in **both** shapes, which is what
`ai/ai_controller.gd`'s `_focus_bonus` comment refers to: as an independent
bonus scaled by follow-up damage (43.3 / 41.7 / 43.3), and reshaped as a
proportion of the shot's own value capped at doubling it (43.3 / 46.7 / 46.7 /
45.0) — better, still below parity, and it dragged the best combination from
61.7% to 46.7%. The capability is kept, gated, unit-tested and set to `0.0`.

**Superseded turn time:**

| Tier | ms/turn | over |
|---|---|---|
| Normal | 72.9 | 2310 turns |
| Difficult | 102.1 | 1160 turns |
| Easy | 144.3 | 1154 turns |
