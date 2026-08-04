# Commander balance

How commander balance is measured, what "balanced enough to ship" means, and the
rule for changing a number when it isn't. This is the committed record of the
readiness plan's **G4 — Balance Gate**; the generated CSV/JSON reports are not
committed (they live under `reports/`, which is gitignored).

## The two halves

Balance is **evidence, not one giant simulation**. Two instruments, and neither
replaces the other:

1. **Automated matrix (`tools/run_commander_balance.gd`).** Plays AI-vs-AI across
   every commander pairing on rotationally-symmetric boards with paired seeds. It
   catches outliers and, because it drives the same `AIController` and `Command`
   objects as play, rule disagreements — a planned command the rules reject, or a
   match that never resolves. It quantifies; it does not judge feel.
2. **Human test deck (manual).** Fifteen informative pairings played with sides
   swapped — 30 structured sessions — scored on clarity, agency, identity, power
   timing, counterplay, and rematch appetite. This decides whether a matchup is
   legible and worth replaying. It cannot be automated and is not in this
   repository; it is run against a candidate build before campaign work resumes.

> **Do not balance to the AI leaderboard alone.** The AI is rule-based and can
> underuse terrain, timing, or a specialised economy effect. A commander outside
> the preferred win band is a **review trigger**, not an automatic numeric nerf.

## Running the automated matrix

```sh
make commander-balance                 # full batch — a release task, 9,680 matches
make commander-balance BAL="--commanders=alina_ward,cass_orlov --seeds=2"  # focused
```

Flags (after `--`): `--commanders=`, `--scenarios=`, `--seeds=`, `--neutral`
(adds each commander vs No Commander), `--days=`, `--out=`.

- **Full batch:** 22×22 ordered pairs (mirrors included) × 5 scenarios × 4 seeds
  = **9,680 matches**. Ordered pairs already side-swap every non-mirror matchup.
  It is deliberately out of `make verify`/`make test`.
- **Focused mode** is the fast iteration loop while tuning one commander.
- Output: `reports/commander_balance/matches.csv` (one row per match) and
  `summary.json` (per-commander win rates, first-side bias, threshold flags).

### The scenarios are fair by construction

All five boards are 180° rotationally symmetric with the teams swapped, and the
runner **asserts** that symmetry on startup (`_assert_symmetric`) — a typo that
broke fairness fails the run rather than biasing it. A first-side bias in the
results is therefore the doctrines' doing, not the map's. `clash` is open and
decisive; `ridge` puts more terrain between the lines; `combined` adds an
airfield, a port and a shared lake, because a doctrine tuned only against tanks
is tuned against a third of the game — several hooks read a unit's move class or
domain, and they behave differently when half the army is not on the ground.
`holdings` gives both sides twelve properties, making price and treasury
doctrines visible instead of fund-starved; `channel` gives both fleets one shared
ocean while preserving a land bridge, so naval doctrines fight without asking
the AI to solve its documented ferry limitation.

A fixture also has to **resolve**. The first version of `combined` separated the
armies with water: it ground to the day cap in 430 of 432 matches and produced a
twenty-point first-side bias out of the tiebreak alone. The shipped version puts a
small lake in the middle instead, so the land armies walk past it and meet on day
one. Its measured first-side bias was 0.0 pp in that historical three-scenario pass.

### Timed matches are decided on score

A rule-based AI rarely races to an enemy HQ, so most matches reach the day cap
undecided. Rather than discard that as a draw, a day-cap match is ranked the way
Advance Wars ranks a timed one — **properties, then surviving units, then
funds**. The CSV's `termination` column keeps natural wins (`rout`/`hq`)
distinguishable from scored ones (`day_cap`); a true tie (every measure equal, as
two identical doctrines in a mirror can produce) stays a draw.

### Determinism

Same scenario + seed + command sequence ⇒ **byte-identical** result rows on a
rerun. The RNG is seeded, the AI is lookahead-free and RNG-free, and the runner
reads neither the clock nor an unseeded RNG. This is what lets a tuning change be
attributed to the change and not to noise.

## Thresholds

| Measure | Band | Meaning |
|---|---|---|
| Per-commander side-normalized win rate | **45–55%** | preferred |
| Same | **40–60%** | automated warning — investigate before merge |
| First-side bias (non-mirror decisive games) | **≤ 5 pp** | map/seed fairness |
| Rejected AI commands, cap stalls | **0** | **hard** — the run fails |

Only the hard invariants fail the run (`exit 1`). Out-of-band win rates and side
bias colour the summary; they are review triggers, per the rule above.

## The one-variable tuning loop

When a commander sits outside the band **and** review confirms the anomaly is
real (repeat seeds, inspect side/map splits, verify the AI actually *uses* the
doctrine rather than merely possessing it), change **one** exported value in
`data/commanders/<id>.tres`, in this order of preference:

1. **Power cost first.** Changes how often the power fires while preserving its
   identity; narrowest blast radius.
2. **Then power magnitude / duration.** One value, then rerun the focused
   matchup subset, then the full batch.
3. **Passive doctrine last.** Always-on modifiers touch every turn and matchup;
   require human confirmation before altering them.

Behaviour stays in the `CommanderType` subclass; only numbers move. Record the
change and its rationale below.

## Status and results

The runner and its five scenarios are verified (symmetry asserted, determinism
byte-identical, hard invariants clean). The 18-commander full batch was run on the
candidate build on 2026-08-01; the 30-session human deck remains the manual
release companion and is not represented as automated evidence here.

The deck's three additions for this roster are deliberately contrastive:
**Calder vs Vale** (cheap breadth against expensive quality), **Ferrow against a
cash-poor opponent** (whether plunder and its counterplay read), and **Colt against
a defensive commander** (whether a late refresh creates agency rather than a
surprise extra turn). Each is played from both seats like the standing twelve.

### Measured for the four-commander expansion (MC5)

The full batch at twenty-two ran **9,680 matches** (22×22 ordered pairs × five
scenarios × four seeds) in **59 minutes** on the development machine — R3's
predicted +49% wall clock, measured. All 9,680 were decisive, with **0 rejected
commands and 0 cap stalls**. First-seat bias was **+33.1 pp**, the standing
banking item described in the N4 section below rather than anything this
expansion introduced.

**All four new generals measured above the preferred band, and all four ship at
the numbers they were designed with.** That is the written exception this
document's own acceptance rule asks for, and the reason is one sentence: the
tuning ladder above puts always-on modifiers last and behind human confirmation,
every one of these four is passive-dominated, and the pass that lowers them is a
deliberate balance decision rather than a milestone's tidy-up. The measurement
below is what that pass should start from. **No `.tres` number moved in MC5.**

| New commander | Full matrix | Worst board | Powers/match | Opponent units left |
|---|---:|---|---:|---:|
| Radek Morn | **89.4% WARN** | `holdings` **100.0%** | 1.77 | **0.72** |
| Iona Vance | **77.8% WARN** | `combined` 94.6% | 3.70 | 1.71 |
| Sera Lark | **65.3% WARN** | `ridge` 83.9% | 5.56 | 2.90 |
| Ivar Thorne | 59.7% watch | `clash` 75.6% | 3.86 | 3.42 |

The field average is 4.14 units left standing, and the shipped eighteen top out
at Viktor Draeg 58.9% and Gideon Holt 55.7% — so this is not a weak field being
measured, it is four strong doctrines. Head to head, Morn beats the other three
85–90%.

**The passive is the term to move, not the power.** Morn fires 1.77 times a match
at 24,000 — the dearest meter in the game, firing least of anyone here — and
still wins 89.4%, which puts most of his edge on the flat +5%/+5% rather than on
Hammerfall. Vance's +3%/+3% alone carries her to 77.8%. The two are one ladder
(D8) and move together or not at all; Morn's `power_cost` is already at the band
ceiling, so cost is not a lever that is left for him.

**R1 is confirmed rather than predicted.** AJ3 shipped `cohesion_tiles` live and
left its own R1 — the column being Command Power bait — *unobserved*, because
both sides were the same planner and neither punished concentration. Morn is the
instrument, and he reads 100.0% on `holdings` and leaves his opponent 0.72 units
against a field of 4.14. A 3×3 that lands on an advancing column is worth more
than the meter that bought it.

**R2 is confirmed too, and it shows where the risk said it would.** Lark holds
5.28 properties a match against a field of 4.47 while leaving more enemy units
standing than anyone else here (2.90) — that is the property race, not the fight,
which is exactly what movement compounds with. The lever named for her, if the
tuning pass wants one, is Forced March getting dearer or going entirely: a
general whose trick is the passive does not need a second one.

**Owed, and no matrix can settle it:** the human deck's Hammerfall question —
whether aiming it is a decision or a formality. The matrix says only that the
computer's aim is worth firing; whether a player experiences the square as a
choice is the deck's to answer, along with R8 (does a first-time player
understand the meter is spent whether or not the square held anything).

The standing WARN names among the existing eighteen are unchanged and were not
touched, per MC5's own scope: Iris Colt low (the written exception below), Konrad
Vale high, and the review set around them.

### Measured for the six-commander expansion (NC7)

The final candidate ran **6,480 matches** (18×18 ordered pairs × five scenarios
× four seeds) in about **53 minutes** on the development machine. All 6,480 were
decisive, with **0 rejected commands and 0 cap stalls**. First-seat bias was
**+40.8 pp**, still the standing banking/fixture review item described below;
the expansion did not introduce it and it remains a review flag rather than a
hard failure.

| New commander | Full matrix | Owning fixture | Review |
|---|---:|---:|---|
| Ines Calder | 49.3% | `holdings` 56.9% | Proposed 20% discount measured 73.6% on `holdings`; one exported value moved to 10%, then the full matrix was rerun. |
| Konrad Vale | 64.2% WARN | `holdings` 53.5% | The economy fixture is the plan's authority; sparse-board aggregate overstates the elite doctrine. No tune. |
| Perrin Ash | 47.4% | `combined` 52.1% | Domain fixture and aggregate both in the preferred band. |
| Halden Marr | 46.8% | `channel` 44.4% | Aggregate preferred; domain fixture watch, inside the 40–60 safety band. |
| Dane Ferrow | 48.5% | `holdings` 52.8% | Economy fixture and aggregate both preferred; signed plunder reconciled every turn. |
| Iris Colt | 26.4% WARN | `holdings` 47.2% | Written exception: on `holdings` she fired in 100% of games (4.86 powers/match) and landed preferred; sparse fixtures offer few eligible non-attack actions, and the greedy AI underuses a second movement phase. The unit/AI soak proves it fires late and moves twice. Human deck owns the feel judgement. |

The other WARN names are the standing base-roster review set: Cass Orlov low;
Tomas Reed and Viktor Draeg high; Gideon Holt watch. The exact generated reports
remain uncommitted under `/private/tmp/nc7-full-final`; this section is the
committed interpretation.

**The rules under the N4 numbers below have since moved.** The numbers predate
the charge-meter fix that stopped a team from banking charge while its own power
is active (`GameState.add_charge`, `tests/unit/test_charge_meter.gd`), so powers
are now re-earned from empty, slowing every commander's power cadence. The
bug-fix pass of 2026-07-24 then runs the opening side's day-1 `begin_turn` under
its real commander, resupplies passengers aboard a transport at their side's
turn start, banks power charge for cargo sunk with its transport, and touched
the planner itself (`docs/difficulty_check.md` §6 lists those changes) — all of
which shift doctrines that read supply or charge. The AI Judgement dials then
went live on 2026-08-01, moving `data/ai/default.tres` — the profile every
commander in this matrix is planned with — so the CA4 standings predate the
planner too (`docs/difficulty_check.md` §4c). The standings below are kept
as the record of what was measured, not a current claim; re-run the matrix
before quoting them. Only the runner writes these numbers.

### Measured while adding the air and naval domains (N4)

864 matches, `clash` + `ridge`, 3 seeds, run before and after the change so the
two are comparable. No commander `.tres` was touched: the point of the exercise
was to find out whether the new domains had moved the roster, and the answer is
that the AI's *production* moved it, in both directions.

| | base (`c6f103f`) | with air/naval |
|---|---|---|
| Win-rate spread | 25.0 – 77.1 % (52 pp, 6 WARN) | 31.2 – 68.8 % (38 pp, 4 WARN) |
| First-side bias | +5.6 pp | +14.9 pp |
| Rejected commands / cap stalls | 0 / 0 | 0 / 0 |

The spread **tightened**, which is the expected effect of an AI that fields a
mixed army instead of whatever one unit its priority list happens to favour: a
doctrine that answers tanks well has less to feed on.

The first-side bias **worsened**, and that is a real cost of `save_up_turns`.
Banking is what makes a 20 000 airframe or a 28 000 hull reachable at all — with
no banking the AI's treasury never passes about ten thousand and the expensive
half of the roster is not rare but *unbuyable* — and it hands whoever moves first
a timing edge, since they cross a price threshold a turn earlier. Measured at
+5.6 pp with no banking, +14.9 at a two-turn window, +20.2 at three. Two is
shipped: the air and naval soaks build their full rosters there, so three buys
nothing and costs another five points of first-move fairness.

Stated plainly, because it is easy to read the table above as a pass: **the
shipped configuration sits outside this document's own ≤ 5 pp first-side-bias
threshold**, roughly threefold, and the runner flags it REVIEW. That is a
deliberate accepted trade, not an oversight — without banking the expensive half
of the roster never reaches the board at all — and closing it belongs to the
base-game balance pass, alongside the out-of-band commanders, not to the air and
naval work. How much it bites depends strongly on the board: +14.9 pp is the
`clash` + `ridge` average, while the `combined` fixture measured +0.0 pp.

Everything above is the *base game's* balance seen through a better-playing AI.
The out-of-band commanders are the same names as before (Gideon Holt and Tomas
Reed high, Cass Orlov and Rhea Sol low), which makes them a base-game tuning pass
rather than anything the air and naval rosters introduced — and per the rule at
the top of this document, a review trigger rather than an automatic nerf.

### Measured with the doctrine-aware AI (commander-doctrine-ai plan, CA4)

Two full batches (1,728 matches each), regenerated on both sides of the change
at the same base commit because `reports/` is gitignored: the baseline from
`main` (`99c9c30`), the other from the branch that gave the planner the
commander-advice seam. `make difficulty-check` seats no commanders, and its
`matches.csv` stayed **identical in every column** across the change — the
seam moved no doctrine-free decision. (Both bare 4-seed runs read red against
the ladder gate, identically; `docs/difficulty_check.md` §5 says that subset
"can read red without a regression" and is never the number to quote — the
15-seed gate result then standing (2026-07-28) is unaffected.)

| | `main` (`99c9c30`) | with doctrine advice |
|---|---|---|
| Win-rate spread | 34.7 – 64.2 % (30 pp, 3 WARN) | 29.9 – 62.2 % (32 pp, 4 WARN) |
| First-side bias | +43.2 pp | +39.4 pp |
| Rejected commands / cap stalls | 0 / 0 | 0 / 0 |

What moved, and why it is the change working rather than noise — the field as a
whole got stronger, so the no-advice commanders drifted −2 to −5 pp and any
delta inside that band is environment, not identity:

- **Cassian Rook +7.6 → 46.2 (WARN → ok).** The `wants_power` correction:
  Rapid Redeployment no longer fires on the offensive default — the exact turn
  its −20 % attack penalises — but for ground its movement can buy.
- **Mara Voss +4.5 → 49.3 and Alina Ward → 46.9 (from 59.0).** Ground advice
  centres both: Voss receives fights on starred terrain, Ward's mixed line
  forms on purpose instead of by accident.
- **Sable Wren +8.3 → 59.0.** Vanish actually fires now — staging into cover as
  the meter fills broke the stall where `wants_power` waited forever on woods
  the planner never filled. Her strength is the doctrine finally playing;
  watch-band, review trigger.
- **Viktor Draeg +9.0 → 62.2 and Tomas Reed +4.9 → 60.1 (both WARN).** Identity
  expressed upward. Draeg's armour pull first measured 64.9 % at bias −4 and
  ships tempered to −2; both stay review triggers per the rule at the top, not
  automatic nerfs.
- **Rhea Sol: the tempering lesson.** At bias −4 she measured **34.4 %** — the
  pull bought an army of guns the planner cannot move-and-fire, advice fighting
  the planner exactly as the plan's R2 predicted. Shipped at −2 she measures
  46.9 %, inside the field shift. The fix was the `.tres` number, not code.
- **Cass Orlov 29.9 and Gideon Holt 61.5.** The pre-existing outliers, same
  names as every earlier measurement; still the base-game tuning pass.

The first-side bias **improved** (43.2 → 39.4 pp) — doctrine advice makes the
second player's answer slightly better — but remains far outside this
document's ≤ 5 pp threshold, as it has since banking shipped; that standing
accepted trade is documented in the N4 section above and does not belong to
this change.

### Balance changelog

- **2026-08-04 — the four new generals ship un-tuned, on purpose** (more-commanders
  plan, MC5). The 9,680-match batch measured Radek Morn 89.4%, Iona Vance 77.8%,
  Sera Lark 65.3% and Ivar Thorne 59.7%; **no `.tres` number moved**. All four are
  passive-dominated, the ladder above puts always-on modifiers last and behind
  human confirmation, and that confirmation placed the tuning in a later balance
  pass rather than in this milestone. Evidence and the levers left for that pass
  are in the MC5 section above. This is a known departure, recorded rather than
  hidden: the roster currently has a commander winning nine matches in ten.
- **2026-08-02 — Cass Orlov loses her −10 % defence.** The standing low outlier,
  named in every measurement since wave 2, tuned by deleting the penalty half of
  her doctrine: `defense_pct` and the `defense_bonus` override are gone, so her
  army defends like anyone else's and she is a finisher who pays nothing for it.
  Evidence: paired full batches (6,480 matches each) regenerated on both sides at
  base commit `b7b6168`, since `reports/` is gitignored.

  | | before | after |
  |---|---:|---:|
  | Cass Orlov | 38.9 % WARN | **51.1 % ok** |
  | Win-rate spread | 27.1 – 67.1 % (40.0 pp, 6 WARN) | 26.1 – 66.5 % (40.4 pp, 5 WARN) |
  | First-side bias | +38.2 pp | +39.0 pp |
  | Rejected commands / cap stalls | 0 / 0 | 0 / 0 |

  No other name moved up, and none moved down by more than 1.5 pp (Mara Voss
  0.0, Cassian Rook −1.5) — one commander got stronger, so the field it is
  measured against got fractionally weaker. The remaining WARN names are
  unchanged and still the review set: Iris Colt low (the written exception
  above), Gideon Holt, Tomas Reed, Viktor Draeg and Konrad Vale high.
- **2026-07-31 — the doctrine-advice exports ship, two of them tempered by
  measurement** (commander-doctrine-ai plan, CA4). Every advising general's
  `.tres` gains its advisory numbers; `rhea_sol` `indirect_build_bias` measured
  −4 → 34.4 % and ships at **−2** (46.9 %); `viktor_draeg` `armour_build_bias`
  measured −4 → 64.9 % and ships at **−2** (62.2 %). Evidence: the paired full
  batches in the section above. No pre-existing balance value moved.
- **2026-07-23 — every commander, `power_cost`, +2 000 across the roster**
  (8 000→10 000, 9 000→11 000, 10 000→12 000, 11 000→13 000, 12 000→14 000).
  Evidence: human play — powers were firing too often to stay an event. This is
  a global pacing shift, not a per-commander tune, so it moves one value per the
  ladder above while preserving the roster's cost ordering; the top tier now
  sits on the plan's 14 000 ceiling. The accrual split (100 % lost / 50 % dealt)
  is the plan's locked D2 and was not touched.
