# Difficulty tiers and the ladder gate

How the three difficulty tiers are built, how their ordering is measured, and
what the measurement currently says. This is the committed record of the
difficulty plan's **DF4 — Prove the ordering, then tune**; the generated
CSV/JSON reports are not committed (they live under `reports/`, gitignored).

**Standing verdict: the gate FAILS, knowingly.** Measured 2026-08-01 at 15
seeds with the AI Judgement dials live: Normal takes **68.3%** from Easy and
Difficult **53.3%** from Normal, against a required 70%. Zero rejected commands
and zero cap stalls, so the planner and the rules still agree — what is gone is
the *gap* between tiers, not the correctness of any of them.

This was accepted rather than tuned away, and the reasoning is short. The
capabilities that closed the gap — noticing an enemy taking your ground, and
advancing as an army rather than one unit at a time — are basic competence, and
withholding them from Normal to protect a spread is a worse game for the person
actually playing it. Every tier split tried failed the gate — four at 15 seeds,
three exploratory plus the one that shipped, all recorded in §4c — because this
gate measures the *difference* between tiers and improving the middle rung
necessarily shrinks it.

Two things make the failure easier to accept than it reads. The gate is a
20-day-cap instrument, and the Grand Balance Atlas — 20,280 matches at a
250-day cap — already found this ladder **inverted** at long horizons (Easy >
Difficult > Normal, Normal over Easy just 15.6%), so a passing 71.7% was never
evidence the tiers were truly ordered; it measured who was ahead early. And the
balance retune's BL2 owns righting the ladder as a whole, Normal and Difficult
together, on a horizon that resolves — which is the work this needs.

**So: do not read the numbers above as a target to restore by weakening Normal.**
Restoring the ordering is BL2's job and it should do it by making Difficult
better, not the middle rung worse. Details and the tuning record follow.

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
| Easy | `easy` | `data/ai/easy.tres` | Timid: over-weights danger, retreats early, finishes poorly, under-fields capturers, no md tank, loose column, no instinct to defend its own ground |
| Normal | `normal` | `data/ai/default.tres` | The planner's own defaults: answers an enemy taking its property, advances as a column |
| Difficult | `hard` | `data/ai/hard.tres` | Threat-aware and counter-building, sharper trade weights, defends harder and keeps a tighter column |

Each tier is a `Difficulty` resource in `data/difficulty/` — a label plus one of
those profiles. Retuning a tier is editing its `.tres`.

## 2. The three capabilities

Difficult's extra judgement is three `@export` weights on `AIProfile`, each
defaulting to `0.0`, which skips the capability entirely. At `0` the code that
reads it never runs, so **Normal carries none of these three** and they remain
what the tier ladder is built out of.

That is still true of S1–S3 below. What is **no longer** true is the wider claim
this section used to make — that Normal plans exactly as the pre-difficulty AI
did. Since 2026-08-01 Normal carries the AI Judgement dials `defend_weight` and
`cohesion_tiles` live (§4c), so it plans differently from the pre-difficulty AI
by design. `test_capability_defaults_plan_exactly_like_the_shipped_profile` still
passes and still means something, but what it now pins is that
`AIProfile.new()` and `data/ai/default.tres` agree — an install missing its
profile file plays the same game — rather than parity with a planner that no
longer exists.

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

  The map is read by three weights, because the paths that read it do not score
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
    `data/ai/hard.tres` ships `2.0` and `easy.tres` `3.0`; §4 measured those
    values in the ladder as it stood before the Judgement dials went live.
  - **`withdraw_weight` — withdrawals, in value.** Stepping out of a firing ring
    is a scored candidate rather than the advance fallback, worth
    `withdraw_weight × unit cost × damage avoided / 100` — the same currency an
    attack scores in, so a wounded unit's survival can outbid its own marginal
    shot. It belongs to the AI Judgement plan, **not** to S1–S3: it is a planner
    capability every tier carries at `0.0`, never a Difficult-tier smart.

  These three dials read one map, so a single enemy can be priced by all three at
  once — its shot discounting an attack, its reach costing an advance tiles, and
  its damage buying a withdrawal. Tune them together and never one at a time
  (the AI Judgement plan's R3).
- **S2 `focus_fire_bonus` — focus fire.** Boosts a target other ready friendlies
  could still add damage to. **Un-shipped: `0.0` on all three tiers**, so
  `_focus_bonus` and `_follow_up_damage` never run in a played match — they
  execute only under the tests that build a profile carrying the dial. Read the
  code as a capability the ladder can re-test in one edit, never as behaviour
  anyone has met. It is off because the superseded probes in §6 found the bias
  harmful in both shapes tried and §4b's re-test with cohesion live found it
  negative again, while replanning after every command already exposes a wounded
  target's finishing shot to the next attacker. `data/ai/hard.tres` carries the
  same note at the dial itself.
- **S3 `build_reactivity` — counter-building.** Re-ranks each affordable combat
  unit by its damage-chart effectiveness against the enemy's actual cost-weighted
  roster, blended over the static `build_priority` list. With no enemy in sight
  there is nothing to react to and the static list decides.

## 3. Running the gate

```sh
make difficulty-check                       # default: 4 seeds
make difficulty-check DIFF="--seeds=15"     # the standing invocation (§4c)
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

## 4. What the measurement said before the dials went live

**This section is the pre-2026-08-01 record, not the standing one.** The
standing verdict is at the top of this file and the current numbers are in §4c;
everything below is kept because it is the control §4c is read against — the
last measurement of the ladder before the AI Judgement dials shipped live.

**Measured 2026-07-28, 120 matches, 15 seeds, default 20-day cap:**

| Pairing | Overall | scrimmage | ironworks | Gate |
|---|---|---|---|---|
| Normal over Easy | **71.7%** (43/60) | 93.3% | 50.0% | pass |
| Difficult over Normal | **71.7%** (43/60) | 70.0% | 73.3% | pass |

Zero rejected commands and zero cap stalls across all 120 — the planner and the
rules never disagreed, which is the correctness half of this run and it is clean.

This run follows the planner correctness fixes listed in §6, the current
`ironworks` map with its mirrored airfields, and the per-seat
controller correction in the balance harness. It also follows the production
coverage fix measured here: Easy and Difficult retain their land-priority
prefixes, then list every non-transport air and sea combat unit. A capability
test places an owned airport and port on the same board, blocks the irrelevant
facility, and proves each tier issues a valid build for the remaining domain.

**How much of that was decided on the board.** The repo's standing reading rule
(`tools/balance/run_summary.gd`'s `MIN_RESOLVED_PCT`, `docs/balance_sim.md`)
says a win rate whose games mostly ended on the day cap rather than on the board
is low-confidence, because the tiebreak (properties, then units, then funds) can
turn over on noise. Counting `rout`/`hq` terminations out of `matches.csv`:

| Pairing | Map | Resolved on the board | Higher tier, resolved games | Higher tier, day-cap games |
|---|---|---|---|---|
| Normal over Easy | `scrimmage` | 20/30 (66.7%) | **20/20** | 8/10 |
| Normal over Easy | `ironworks` | **0/30 (0%)** | — | 15/30 |
| Difficult over Normal | `scrimmage` | 11/30 (36.7%) | 10/11 | 11/19 |
| Difficult over Normal | `ironworks` | **0/30 (0%)** | — | 22/30 |

**Not one `ironworks` match resolved on the board** — all 60 ran to day 21 and
were scored by the tiebreak. So `ironworks` contributes no board evidence at
this cap in either pairing, and every per-map `ironworks` number above is a
tiebreak reading, not a rout.

**The `--days=40` probe.** Loosening the cap (15 seeds, same maps and seats)
separates the two pairings:

| Pairing | Overall | `scrimmage` | `ironworks` | Resolved, `scrimmage` | Resolved, `ironworks` |
|---|---|---|---|---|---|
| Normal over Easy | 65.0% (39/60) | 100.0% | 30.0% | 30/30 | 8/30 |
| Difficult over Normal | 71.7% (43/60) | 70.0% | 73.3% | 24/30 | 12/30 |

Difficult's pairing is **unchanged, map for map**, while its board-resolved
share rises from 18.3% (11/60) to 60.0% (36/60) — and it still takes 17 of the
24 resolved `scrimmage` games and 8 of the 12 resolved `ironworks` ones. Its
ordering does not depend on the clock.

Normal-over-Easy does. Given more time `scrimmage` goes to 30/30, all resolved —
Easy is emphatically the weaker planner on the small decisive board — but
`ironworks` inverts to 30.0%, with Normal taking only 2 of the 8 games that
resolved there. The honest reading is that **Easy's measured weakness is proven
on `scrimmage` and unproven on `ironworks`**: on a large city-rich board the
cheaper, capture-light Easy profile is not behind on the tiebreak's currency,
and given forty days it is ahead on the board. The gate is defined on the
combined pairing at the default cap and was met there in this run; this is the
caveat that came with it, not a re-scoring of it. See §6's superseded finding (a) — the
same board showed the same shape before this tune, so it is a property of
`ironworks` inside a day cap rather than something these four weights introduced.

The probe is a read on that result, not a second gate: the gate is the
default cap, and `--days=40` is not a tier `.tres` change, so nothing above was
retuned against it.

### Findings

**(a) Easy now measures weaker without a handicap.** Its capture-unit target
drops from four to two, so it under-staffs the large property race, and its kill
bonus drops from 1.2 to 1.0, worsening its finishing judgement. Normal takes
71.7% overall. The maps remain uneven — 93.3% on `scrimmage`, 50.0% on
`ironworks` — and the combined pairing is the locked gate, which clears. But the
resolution split above says the two halves are not the same kind of evidence:
`scrimmage` is a board result (Normal won every one of the 20 games that
resolved, 30/30 at `--days=40`), while `ironworks` is 30 day-cap tiebreaks and
inverts to 30.0% when the clock is loosened. Read this finding as *Easy is
weaker on the decisive board*; on `ironworks` the ordering is not established.

**(b) Difficult closes the finishing gap without a new capability.** Its kill
bonus rises from 1.8 to 2.0 and its counter-damage weight falls from 0.5 to 0.4.
It values a kill more and discounts a good attack less for its return fire.
Difficult takes 71.7% overall and independently reaches the threshold on both
maps. It is also the pairing the resolution split treats kindly: it holds 71.7%
map for map at `--days=40`, where 80% of its `scrimmage` games and 40% of its
`ironworks` games end on the board and it wins the majority of both. This
ordering is not a tiebreak artefact.

**(c) The honest air/sea production baseline remains intact.** Easy and
Difficult retain their land-priority prefixes, list every non-transport air and
sea combat unit, and never leave an affordable owned airport or port idle merely
because their priority list lacks a compatible unit. No transport was added;
the planner still cannot plan a ferry.

### COM-120 tuning path

Each row changed one judgement hypothesis from the retained candidate, then ran
the same 15-seed, 120-match gate. Rejected values were restored before the next
axis moved. H0 is the control every row below is an improvement or a regression
*against* — the profiles as they shipped before this pass, measured on the same
planner, maps and harness as everything under it; its per-map split is in §6.

| Probe | Profile change | Target pairing | Result | Decision |
|---|---|---|---|---|
| H0 | control — profiles as shipped pre-tune | Normal over Easy | 43.3% | fails the gate; the starting point for H1–H5 |
| H0 | control — profiles as shipped pre-tune | Difficult over Normal | 66.7% | fails the gate; the starting point for H6–H12 |
| H1 | Easy `threat_aversion` 0.3 → 0.5 | Normal over Easy | 40.0% | reject — timidity strengthened Easy on `ironworks` |
| H2 | Easy `capture_score` 900 → 300 | Normal over Easy | 48.3% | reject — did not alter the large-board race |
| H3 | Easy `capture_unit_target` 4 → 2 | Normal over Easy | 68.3% | retain as the better axis |
| H4 | Easy `capture_unit_target` 2 → 1 | Normal over Easy | 75.0% | reject — passed by removing more capture play than needed |
| H5 | Easy `kill_bonus` 1.2 → 1.0, with H3 retained | Normal over Easy | **71.7%** | select |
| H6 | Difficult `build_reactivity` 0.6 → 1.0 | Difficult over Normal | 41.7% | reject |
| H7 | Difficult `advance_threat_tiles` 2.0 → 1.6 | Difficult over Normal | 60.0% | reject |
| H8 | Difficult `advance_threat_tiles` 2.0 → 3.0 | Difficult over Normal | 60.0% | reject |
| H9 | Difficult `kill_bonus` 1.8 → 2.0 | Difficult over Normal | 68.3% | retain as the better axis |
| H10 | Difficult `kill_bonus` 2.0 → 2.2 | Difficult over Normal | 68.3% | reject — no outcome changed |
| H11 | Difficult `kill_bonus` 2.0 → 2.4 | Difficult over Normal | 68.3% | reject — shifted wins between maps only |
| H12 | Difficult `counter_weight` 0.5 → 0.4, with H9 retained | Difficult over Normal | **71.7%** | select |

### Turn time (risk R3)

Mean AI planning per turn in that run:

| Tier | ms/turn | over |
|---|---|---|
| Easy | 71.6 | 1072 turns |
| Difficult | 53.7 | 1146 turns |
| Normal | 33.7 | 2210 turns |

**These numbers predate the Judgement dials and are no longer a reading of the
shipped tiers**: every tier now runs the cohesion term on every advance, and
nothing since has re-measured them. AR1's plan cache (COM-154) has since made a
headless turn several times cheaper again, so no turn-time figure in this
document — here or in §4b — reads the planner as it stands. Normal still builds
no threat map, which is the half of §4b's comparison that stands.

These are measurements, not deterministic outputs; the pairing results,
rejected-command count and cap-stall count are the reproducible gate evidence.

## 4b. The AI Judgement dials — probe bands (AJ4)

> **Downgraded by §4c (2026-08-01): read everything below as hypotheses, not
> findings.** These rows were measured at n=16 with the dials live on Difficult
> alone; the 15-seed splits in §4c carried them on every tier and moved
> consistently the other way. The cohesion headline in particular did not
> survive the wider sample. Nothing here has been re-scored — it is kept as the
> probe it was, and §4c is the current record.

The AI Judgement plan added three planner capabilities: `defend_weight` (AJ1),
`withdraw_weight` (AJ2), `cohesion_tiles` / `cohesion_radius` (AJ3). Each of
them shipped at `0.0` in every tier while this section was measured, so the AI
under probe was the AI that predates them plus the one dial being tried; since
2026-08-01 three of the four ship live and §4c records what that cost.
**This section is AJ4's whole deliverable: the band each
one helps in, the cliff it hurts past where one was found, and — in the closing
list — what the probe could not answer, so the balance retune's BL2 can set a
live value from evidence rather than from taste.** AJ4 adds no code, which is why
these numbers stay true of the planner they were taken on — two earlier attempts
to take them inside a code milestone went stale the moment a review round moved
the planner.

**Method.** The ladder is the instrument. Difficult carries the dial under test,
Normal does not, so `hard`-over-`normal` moves with the dial and the `0` row is
the control. One axis per probe, tiers edited temporarily and restored from
`HEAD` — nothing was committed to `data/`. `--seeds=4 --days=30`, 16 matches a
row, on the gate's two boards.

**Read every row as a direction, not a magnitude.** 16 matches is a quarter of
the gate's 60, `ironworks` resolves badly under a clock (§5), and every number
here is AI-vs-AI, where a mistake only costs you if the opponent punishes it. A
6-point move at this width is a hint; a 25-point move is a finding. §5's warning
about this exact 16-match subset applies to every row below — it can read red
without a regression or green through one — so no colour here is a number to
quote.

**Control: `hard` over `normal` = 62.5%** (scrimmage 50.0, ironworks 75.0).

### `defend_weight` — one match flips, and it flips at every value

| value | hard over normal | scrimmage | ironworks |
|---|---|---|---|
| 0 — control | 62.5% | 50.0 | 75.0 |
| 0.25 | **68.8%** | 62.5 | 75.0 |
| 0.5 | **68.8%** | 62.5 | 75.0 |
| 1.0 | **68.8%** | 62.5 | 75.0 |
| 2.0 | **68.8%** | 62.5 | 75.0 |

**The whole effect is one match of sixteen.** `scrimmage` goes 4/8 → 5/8 and
`ironworks` does not move, identically at all four live values — most plausibly
the same single match flipping the same way four times, which is **one
observation, not four confirmations**: the rows are not independent of each
other. The flat line is the shape the design predicts (the bonus either flips a
decision or it does not, and once it is large enough to flip the ones available
it cannot flip them harder), but flatness across dependent rows is not evidence
for that shape. By this section's own calibration a 6-point move at this width is
a hint, and this is exactly that: a hint. **Suggested band: 0.25–0.5, as
something for BL2 to re-measure at its own sample width before shipping it live,
not a measured band.**

**§4c did not take the low end, and says why.** This section originally advised
it — the whole measured effect is bought there, and a smaller number has less
room to distort a board the probe did not cover. What that reasoning missed is
that a flat line offers nothing to be safe *from*, while the low end left the
reported defect reproducing on the shipped tiers. The live values are 2.0 on
Normal and 2.5 on Difficult, and the coverage they buy is measured in §4c.

### `withdraw_weight` — measures negative at every value tried

| value | hard over normal | scrimmage | ironworks |
|---|---|---|---|
| 0 — control | 62.5% | 50.0 | 75.0 |
| 0.02 | 56.2% | 50.0 | 62.5 |
| 0.05 | 50.0% | 25.0 | 75.0 |
| 0.1 | 50.0% | 25.0 | 75.0 |
| 0.25 | 50.0% | 37.5 | 62.5 |

**Every live value is worse than the control, and the damage arrives early.**
This is the plan's own R4 landing on the dial its author expected least: AJ2 is
the milestone that most directly answers the reported defect, and it is the one
the ladder likes least. Two readings are consistent with the numbers and this
probe cannot separate them — a unit that survives by withdrawing is a unit that
did not trade, and in an AI-vs-AI attrition race not trading is losing; or the
refuge choice is right but the *price* is wrong, because the dial pays full cost
× damage-avoided while an attack pays only its own value. **Recommended: leave at
`0.0`, and do not ship it live on this evidence** — evidence these rows can no
longer give on their own, because they measured the refuge comparator AR6d has
since changed (§4c). The capability stays in the code, which is the standing
remedy for a misbehaving smart — `focus_fire_bonus` is the precedent, kept at
zero for four measurement rounds and re-testable in one edit. A human playtest is
the missing instrument here: "the AI throws units away" is a complaint about how
a match *feels*, and the ladder only scores who wins.

### `cohesion_tiles` × `cohesion_radius` — the largest gain measured here, and not reproduced (see §4c)

| | radius 2 | radius 4 |
|---|---|---|
| 0.5 | 68.8% | 50.0% |
| 1.0 | 75.0% | 62.5% |
| 2.0 | **87.5%** | 62.5% |

The plan's one deliberately two-dimensional probe, and the reason it was worth
running: the two axes do not behave alike. At radius 2 the dial climbs steeply to
**+25 points over control**; at radius 4 it never beats the control by more than
nothing. A column that closes to two tiles fights as one army; a column allowed
to spread to four does not. **Suggested band: `cohesion_tiles` 1.0–2.0 at
`cohesion_radius` 2.** This is the largest move in the section by a wide margin,
and at the time it was read as the one dial whose effect was unambiguous at this
sample width. **§4c withdrew that confidence**: at 15 seeds, with Normal
carrying cohesion too, Difficult at exactly 2.0 / radius 2 scored below its own
dial-at-zero baseline in every split tried. The band above is a hypothesis for
BL2 to re-measure, not a finding.

**2.0 is the top of the probe, not a measured ceiling.** The curve is still
rising there (68.8 → 75.0 → 87.5 at radius 2) and no upper cliff was located, so
the band is bounded above by what was tried rather than by evidence. Finding the
cliff is on the open list below.

**R1 is not observed, and that is not the same as refuted.** The plan's named risk
was that a tight column is artillery bait and Command Power bait; the tightest
setting measured is the best one. But both sides here are the same planner, and
neither is good at punishing concentration — the instrument is blind to exactly
the failure R1 describes. **R1 stays open and belongs to a human playtest**, not
to this table.

### `focus_fire_bonus` with cohesion live — the third refutation

| value | hard over normal | scrimmage | ironworks |
|---|---|---|---|
| 0.0 — control | 62.5% | 62.5 | 62.5 |
| 0.2 | 62.5% | 50.0 | 75.0 |
| 0.5 | 56.2% | 37.5 | 75.0 |
| 1.0 | 37.5% | 37.5 | 37.5 |

Both tiers at `cohesion_tiles = 1.0`, so this is the re-test AJ3 argued for and
could not keep current: focus fire measured on a planner whose units *do* now
arrive together. **It is negative again** — 0.2 ties the control and everything
above it falls away. `focus_fire_bonus` stays at `0.0`, now on three independent
refutations, and the DF3 reasoning is the one that survives: the planner re-plans
after every command, so a wounded target's finishing shot is already free to the
next attacker, and biasing the *first* shot pulls it off its own best trade.
Cohesion fixes **where units are**, not which of them shoots first — those turn
out to be separate problems, which is itself the useful result.

### The cross-term — three of the four cells, so AI Judgement R3 stays open

`threat_aversion`, `advance_threat_tiles` and `withdraw_weight` read one
`ThreatMap`, so the plan's R3 predicted they would price a single enemy three
times and reproduce the coward §6 measured at 11.7%. The probe turned the other
two off underneath `withdraw_weight`:

| configuration | hard over normal |
|---|---|
| control — threat dials at shipped values, `withdraw` off | 62.5% |
| `withdraw` 0.05, threat dials at shipped values | 50.0% |
| `withdraw` 0.05, threat dials **off** | 37.5% |
| `withdraw` 0.1, threat dials at shipped values | 50.0% |
| `withdraw` 0.1, threat dials **off** | 50.0% |

**The cell that would price the cross-term was never run: threat dials off *and*
`withdraw` off.** Turning the threat dials off changes `hard` alone — `normal`
ships them at `0.0` — so without that fourth cell these rows cannot separate
withdrawal's marginal cost from `hard` simply being weaker without its shipped
threat smarts. The arithmetic makes it plain: if the missing cell were also
37.5%, withdrawal costs **0** with the other dials off against **−12.5** with
them on, which **confirms** R3 rather than refuting it. The rows as printed are
equally consistent with either reading, so **R3 is untested, not refuted, and it
stays open.**

The missing cell is one row — `hard` with `threat_aversion`,
`advance_threat_tiles` and `withdraw_weight` all at `0.0`, `normal` unchanged —
and BL2 should fold it into its own sweeps. R3's instruction stands on the
reasoning it was written from and owes nothing to this probe: these three dials
share one map and one another's job, so tune them together and never one at a
time.

### The wall clock (AI Judgement R6)

Deferred here from AJ2, and measurable only now that a dial exists to make the
threat map build on a tier that otherwise never builds one. Mean AI planning time
per turn, same sweep:

| configuration | normal | hard | easy |
|---|---|---|---|
| every threat dial forced to `0.0` on all three tiers | 33.2 ms | 37.9 ms | 65.7 ms |
| `withdraw` 0.1 on all three, so all three build the map | 63.0 ms | 75.6 ms | 105.2 ms |

**Neither row is a shipped tier.** `easy.tres` ships `threat_aversion` 0.3 /
`advance_threat_tiles` 3.0 and `hard.tres` ships 0.1 / 2.0, so Easy and Difficult
build the threat map today and only Normal does not. Both rows here are forced
configurations, and the `hard` and `easy` columns therefore straddle a change
those two tiers have already partly paid for — they do **not** supersede §4's
turn-time table, which reports different numbers (Easy 71.6, Difficult 53.7).
Neither table is a reading of the tiers as they ship today: §4's predates the
Judgement dials, and no run since has re-measured them.

**Normal is the column this comparison is valid for, and there a live
threat-map dial roughly doubles per-turn planning time: 33 → 63 ms.** It is a
real cost and it is an affordable one: the absolute numbers are tens of
milliseconds on the gate's boards, against turns a human spends seconds on. It is
worth knowing before BL2 turns a dial on for a tier that previously never built
the map at all — Normal is exactly that tier. R6's mitigation stands as written
for the map *build*, which the per-turn cache already amortises; what this
measures is the build plus the per-cell `forecast_at` sweep that reads it.

### What BL2 is being handed

| dial | recommendation | confidence |
|---|---|---|
| `cohesion_tiles` / `cohesion_radius` | **1.0–2.0 at radius 2, as a hypothesis** | largest move here (+25) but **not reproduced at 15 seeds — see §4c**; 2.0 is the top of the probe |
| `defend_weight` | **0.25–2.0, flat, as a hint** | one match of sixteen flipped, at every value — re-measure; §4c ships the top of it |
| `withdraw_weight` | **stay at 0.0** | negative at every value tried |
| `focus_fire_bonus` | **stay at 0.0** | third independent refutation |

Two of the four are recommendations to *not* ship a dial, which is what a
measurement milestone is for. And one caveat covers the whole table: it is
measured on Difficult, against Normal, on two boards, by a planner playing
itself. A human playtest can still overturn any row here — most plausibly
`withdraw_weight`, whose defect is about how a match feels rather than who wins
it, and `cohesion_tiles`, whose best setting this instrument is structurally
unable to punish.

### What this section does not know

The honest half of the handover. None of these is a hedge on a row above; each is
a question the probe was not shaped to answer.

- **R3's missing cell.** Threat dials off *and* `withdraw_weight` off was never
  run, so the cross-term is unpriced and R3 stays open rather than refuted. One
  row fills it.
- **Cohesion's upper cliff.** 2.0 is the highest value tried and the curve is
  still rising at it, so the recommended band is bounded above by the probe, not
  by evidence.
- **`defend_weight`'s size.** One match of sixteen flipped, at all four values;
  the four rows are not independent observations. BL2's wider sample is what
  decides whether the effect is there at all.
- **R1, the artillery-bait risk.** Unobserved rather than refuted: both sides are
  the same planner and neither punishes concentration, so the instrument is
  structurally blind to the exact failure R1 names. It belongs to a human
  playtest.
- **How any of this feels.** The ladder scores who wins. The defect that started
  the plan — "the computer throws units away" — is a complaint about a match's
  texture, and no row here can settle it.

## 4c. Going live, and what it cost the ladder (2026-08-01)

The AI Judgement dials shipped live. §4b measured them one at a time on
Difficult; this is what happened when every tier carried them.

| tier | `defend_weight` | `withdraw_weight` | `cohesion_tiles` | `cohesion_radius` |
|---|---|---|---|---|
| Easy | 0.0 | 0.0 | 0.5 | 4 |
| Normal | 2.0 | 0.0 | 1.0 | 2 |
| Difficult | 2.5 | 0.0 | 1.5 | 2 |

Easy carries the configuration §4b measured as *weak* — a loose column and no
instinct to defend its own ground — which is judgement rather than a handicap and
so stays inside the never-cheats rule. It also gives a beginner a real
affordance: rushing an Easy AI's headquarters now works, deliberately.

**`defend_weight` shipped at 0.35 / 0.5 first, and was raised the same day.**
Those were chosen on the reasoning that the low end of §4b's band is safer, and
the measurement does not support it: §4b found this dial *flat* from 0.25 to 2.0,
every value scoring 68.8% against a 62.5% control, so there is nothing measurable
to be safer from. What the low value did buy was a defect: at 0.35 the report
that started this plan — "when the HQ is attacked the AI does not really care" —
still reproduced against any rival worth roughly a Recon or more, and played out
to an actual elimination. 2.0 is the top of the range §4b measured and 2.5 keeps
Difficult a step above Normal.

**Which rivals the shipped weights now cover, measured on the AJ1 fixture
shape** — our HQ under capture, our Tank one tile away, a rival enemy the same
distance the other way, swept across how rich that rival is and at four capture
stages (results identical at all four):

| rival at (2,1) | cost | Easy — the dial-off control | Normal 2.0 | Difficult 2.5 |
|---|---|---|---|---|
| Infantry | 1000 | ignores | **defends** | **defends** |
| Mech | 3000 | defends | **defends** | **defends** |
| Recon | 4000 | ignores | **defends** | **defends** |
| Artillery | 6000 | ignores | **defends** | **defends** |
| Tank | 7000 | ignores | **defends** | **defends** |
| Anti-Air | 8000 | ignores | **defends** | **defends** |
| Rockets | 15000 | ignores | *ignores* | *ignores* |
| Md Tank | 16000 | defends | defends | defends |

Read the Easy column first: it is `defend_weight` 0.0, so the two rows where it
already defends are not the dial's doing — a Tank's shot at a Mech or at an Md
Tank is a poor enough trade to lose to the HQ on its own. The dial changes the
choice in six of the eight rows, and **one rival still outbids a headquarters
about to fall: Rockets.** Its crossover is between 3.0 and 4.0 (Recon's and
Tank's are between 0.5 and 1.0), and it sits that high because an indirect unit
cannot return fire, so the attack it offers is priced as pure profit.

**That last row is the dial's ceiling, and no value removes it.** The defence
bonus is linear and denominated in the same currency as a kill — which is what
lets the two compete in one `AIUnitPlan` at all (AJ1 D3) — so a rich enough target
always outbids a capture, including one that would end the army. Raising the
weight moves the crossover; it cannot make a match-ending capture
incommensurable with an ordinary kill. **The structural follow-up is the pricing
*shape*, not the value:** losing a home HQ is not a setback of some number of
funds, and a defence that answers it should probably not be scored as a bonus on
the same scale as a trade. That is BL2's or a successor plan's to decide; this
section only records that the value has been pushed as far as it usefully goes.

**The ladder numbers below were measured at 0.35 / 0.5 and were not re-run for
the raise.** §4b measured the dial flat across this whole range, the gate is
already failing knowingly, so re-running 120 matches to re-confirm a flat line
was not judged worth it. If a later pass finds the ladder moved by this dial
after all, §4b's flatness is what to disbelieve first.

**Four tier splits were measured at 15 seeds — three exploratory, plus the one
that shipped, which is the last row of the table. None passed.**

| Easy / Normal / Difficult (cohesion + defend) | Normal over Easy | Difficult over Normal |
|---|---|---|
| all dials 0 — the old baseline | 71.7% | 71.7% |
| 0.5·r4+0 / 1.5+0.35 / 2.0+0.5 | 66.7% | 56.7% |
| none / 1.0+0.25 / 2.0+0.5 | **76.7%** | 51.7% |
| none / 0.5+0.25 / 2.0+0.5 | 68.3% | 63.3% |
| **shipped cohesion** — 0.5·r4+0 / 1.0+0.35 / 1.5+0.5 | 68.3% | 53.3% |

The last row is the shipped cohesion split, measured before `defend_weight` was
raised to 2.0 / 2.5; that raise is above and is unmeasured on the ladder by
choice.

The shape is consistent and it is not a tuning failure: **improving Normal
shrinks the gap the gate measures.** The third row is the clearest case — Normal
over Easy reached 76.7%, comfortably the best result on that pairing ever
recorded here, and the same configuration put Difficult over Normal at its worst.
The two halves of the gate pull against each other once the middle rung gets
better, and no split of these three dials resolves it.

**The shipped split is dominated on Difficult-over-Normal, and that was a
choice.** The row above it — `none / 0.5+0.25 / 2.0+0.5` — ties it on
Normal-over-Easy at 68.3% and beats it by ten points on the other pairing,
63.3% against 53.3%. It buys that separation by halving Normal's cohesion from
1.0 to 0.5, which is to say by making the tier most people actually play less
competent, and that is the opposite of what this change is for: the whole point
of turning the dials on was that a column and a defended headquarters are basic
competence rather than a difficulty smart. Naming the trade in both directions,
because it is real in both: the cost of shipping the split we shipped is that
Difficult is now only marginally stronger than Normal, so a player choosing
Difficult gets less for it than they used to. That is a product cost, not only
a gate number. **If BL2 decides tier separation matters more than Normal's
competence, `none / 0.5+0.25 / 2.0+0.5` is the alternative to evaluate first** —
it is measured, it is on the same 15 seeds, and it is the cheapest way back to a
visible spread. The instruction at the top of this file still stands: prefer
making Difficult better to making Normal worse.

**§4b's headline does not survive the wider sample.** That section reports
`cohesion_tiles` 2.0 at radius 2 as +25 points over control, measured at n=16 and
called unambiguous. Difficult carried exactly that value in all three splits
above and scored 56.7 / 51.7 / 63.3 — every one *below* the 71.7% it managed with
the dial at zero. The conditions are not identical (Normal carries cohesion too
in each), so this is not a strict refutation, but the direction is consistently
opposite and the honest reading is that a 16-match row could not support the
confidence §4b placed in it. Treat §4b as hypotheses, not findings.

**`withdraw_weight` shipped at 0 for a positioning defect, and that defect is
fixed.** At 0.05 it used to make an artillery stop short of maximum standoff, so
the unit ended its move inside more firing rings while gaining nothing — a defect
in how the refuge was priced, not a matter of taste. AR6d (COM-162) priced it:
the refuge comparator now ranks the weapon the walk costs, under safety and over
repair, and `tests/unit/test_ai_withdrawal.gd` pins both halves of that ordering
as well as the errand case that used to slip past it. The dial is still 0, but
nothing in the code holds it there any more — what it now wants is the
measurement §4b never took at a useful width, and it remains the dial that most
directly answers the "the AI throws units away" report.

## 5. Where this leaves the feature

Everything the plan asked to be built and measured is now shipping: the tier
plumbing, menu picker, save key, all three capabilities and production coverage.
The DF4 ladder itself does **not** pass — see the standing verdict at the top of
this file and §4c for why that was accepted. What has never moved to obtain a
number, passing or failing, is the rest of it: no threshold, income, vision,
damage, luck, map, harness, or simulation code has been touched by this feature.

Two reads stay open, and neither is a reason to hold the tune.

A human playtest at Easy and Difficult is still required to judge whether the
measured profiles also feel distinct and fun. This report proves the automated
ordering, not that subjective claim.

And Easy's ordering on `ironworks` is unproven, for the reason §4's resolution
split gives: inside a 20-day cap that board resolves nothing, and given forty it
scores Easy ahead. That is a property of a large city-rich board under a clock —
§6's superseded finding (a) found the same shape on the previous profiles — so
the lever is the board or the cap, not the four weights, and moving either is a
map or gate change this pass is not allowed to make. The next honest step is a
board that can resolve, not a weight that flatters the tiebreak.

`make difficulty-check` remains an opt-in release task outside `make verify`.
Run at the standing invocation — `make difficulty-check DIFF="--seeds=15"` — it
reports the gate, and today it exits non-zero on the knowingly-failing ladder
above; it is BL2's instrument for reading a repair rather than a green light to
protect. The bare target is the 4-seed default (16 matches a pairing, a strict
subset of the standing 60): a fast smoke of the same code path, not the gate.
Both pairings sit within a few points of the threshold, so that subset can read
red without a regression or green through one, and a colour from it is never the
number to quote.

## 6. Superseded measurements

**None of this section is a current claim.** The standing verdict is at the top
of this file and §4c holds the current measurements; §4 is the last record
before the Judgement dials went live. These
numbers are kept only because code comments and other documents were written
against them and cite the shapes they found, or — for the COM-120 control
directly below — because §4's tuning table cannot be read as an improvement
without the number it improved on. Nothing here has been re-scored by estimate:
`make difficulty-check` is the only thing allowed to write a standing number.
Everything from "What changed under them" onward predates the planner, the maps
and the harness §4 was measured on; the control does not, and differs from §4 in
nothing but the four tuned weights.

**Superseded standing result — the COM-120 pre-tune control (H0).** Same 15
seeds, 120 matches and 20-day cap as §4, with `easy.tres` at `kill_bonus` 1.2 /
`capture_unit_target` 4 and `hard.tres` at `kill_bonus` 1.8 / `counter_weight`
0.5:

| Pairing | Overall | scrimmage | ironworks | Gate |
|---|---|---|---|---|
| Normal over Easy | 43.3% (26/60) | 63.3% | 23.3% | fail |
| Difficult over Normal | 66.7% (40/60) | 70.0% | 63.3% | fail |

`ironworks` is where the tuning moved: Easy went from beating Normal 23 games in
30 to an even split, while `scrimmage` widened 63.3% → 93.3%.

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
`ai/ai_unit_action_planner.gd`'s `_focus_bonus` comment refers to: as an
independent bonus scaled by follow-up damage (43.3 / 41.7 / 43.3), and reshaped
as a proportion of the shot's own value capped at doubling it (43.3 / 46.7 /
46.7 / 45.0) — better, still below parity, and it dragged the best combination
from 61.7% to 46.7%. The capability is kept, gated, unit-tested and set to
`0.0`.

**Superseded turn time:**

| Tier | ms/turn | over |
|---|---|---|
| Normal | 72.9 | 2310 turns |
| Difficult | 102.1 | 1160 turns |
| Easy | 144.3 | 1154 turns |
