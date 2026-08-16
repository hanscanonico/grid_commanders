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
byte-identical, hard invariants clean). The full batch was last run at
twenty-two commanders on 2026-08-15 — **9,680 matches in 33 minutes**, results
under *Measured after the power-gate pass (2026-08-15)* below; the
30-session human deck remains the manual release companion and is not
represented as automated evidence here.

The deck's three additions for this roster are deliberately contrastive:
**Calder vs Vale** (cheap breadth against expensive quality), **Ferrow against a
cash-poor opponent** (whether plunder and its counterplay read), and **Colt against
a defensive commander** (whether a late refresh creates agency rather than a
surprise extra turn). Each is played from both seats like the standing twelve.

### Marr's shore stand advice, focused (2026-08-16)

`HaldenMarr.stand_value` — one tile of preference for shoal, reef or port, two
once Make for the Shore is banked or running — measured on the two fixtures with
water, before and after, with
`make commander-balance BAL="--commanders=halden_marr,perrin_ash,alina_ward --scenarios=combined,channel --seeds=<n>"`.

| Seeds | Marr seats | before | after | Δ | powers before → after |
|---|---:|---:|---:|---:|---:|
| 2 | 24 | 37.5% | 58.3% | +20.8 | 140 → 130 |
| 6 | 72 | 40.3% | 50.0% | **+9.7** | 455 → 424 |

Both runs are 0 rejected and 0 cap stalls. By fixture at six seeds: `channel`
47.2% → 61.1%, `combined` 33.3% → 38.9%. Alina Ward, his most frequent opponent
in the slice, falls 65.3% → 56.9%, which is the same games read from the other
seat rather than a second finding.

**The held-forever claim could not be tested, and that is the finding.** The
2026-08-15 batch reads 528 / 880 held seats for Marr, and every one of them is on
`clash`, `ridge` or `holdings`: none of those three boards carries a shoal, reef
or port glyph, so the advice is structurally zero there — the dry-fixture
`matches.csv` and `summary.json` are **byte-identical** across the change
(`--scenarios=clash,ridge,holdings --seeds=2`). On the two boards that do carry
the coast he was already holding nothing (0 held seats, before and after), because
`_can_use_the_shore` counts ground a unit can *reach* this turn. So the hold-forever
cliff recorded under #216/#218 stands untouched; what this change buys is play on
the boards his doctrine is for.

### Calder's cheap-breadth bias and the recon (2026-08-16)

`InesCalder.build_bias` returns `cheap_build_bias = -3` for every type at or under
`cheap_cost_ceiling = 5000`, which is a **price** and not a list: infantry, mech,
recon and APC. The recon is on no `build_priority` tier, so a negative bias puts it
on that list's tail (`_build_rank`) at 2009, while her second mech sits at 2010 —
from her second cheap purchase onward she fields scouts. Nobody decided that, and
`AIProfile.build_priority`'s docstring recorded the opposite ("Orin Flux and Cassian
Rook … and nobody else does"). Pinned by
`tests/unit/test_ines_calder.gd::test_four_thousand_buys_calder_a_recon`: on a funded
base with the capture roster filled and one mech fielded, 4,000 in the bank buys her
a recon and buys the neutral commander nothing.

Two arms, both measured with
`make commander-balance BAL="--commanders=ines_calder,alina_ward,konrad_vale --scenarios=clash,ridge,combined,holdings,channel --seeds=<n>"`:

- **as-is** — the shipped ceiling.
- **narrowed** — an explicit `_is_cheap_breadth` predicate on the subclass, the
  ceiling **and** `can_capture`, so the bias reaches infantry and mech only. The
  ceiling itself was left alone: `KonradVale` mirrors its shape.

| Seeds | Calder seats | arm | Ines Calder | Alina Ward | Konrad Vale | first-side bias |
|---|---:|---|---:|---:|---:|---:|
| 8 | 240 | as-is | 40.4% watch | 47.1% | 62.5% | +52.5 pp |
| 8 | 240 | narrowed | 38.3% WARN | 47.5% | 64.2% | +46.7 pp |
| 16 | 480 | as-is | **42.1% watch** | 45.8% | 62.1% | +49.6 pp |
| 16 | 480 | narrowed | **39.8% WARN** | 46.2% | 64.0% | +43.3 pp |

All four runs are 0 rejected and 0 cap stalls. The spec's own `clash,holdings
--seeds=2` slice (24 seats) reads 37.5% for both arms — the same headline off
different games, which is why it was widened.

**The as-is arm ships and the record is corrected instead.** Narrowing costs Calder
2.1 pp at 240 seats and 2.3 pp at 480, the same sign at both sample sizes and enough
to drop her from `watch` to `WARN`. It is about one standard error, so this is not
evidence that the accident *helps* — it is evidence that removing it does not help,
and the repo's bar is that a doctrine number moves on a measurement rather than on
an argument. `ai/ai_profile.gd` now names Calder as the third commander to field a
recon and says she reaches it by cost rather than by name, so the mechanism and the
roster agree.

Calder's 42.1% here is a three-commander slice against Ward and Vale, not the
roster-wide 40.1% / clash 23.9% of the 2026-08-15 batch below; her standing low-outlier
review is that batch's and is untouched by this reading.

### CA4 re-asked: is doctrine advice still worth its weight? (2026-08-16)

The doctrine plan's CA4 acceptance question — *no commander's advice made the AI
worse with that commander than the neutral planner was* — was answered once, on
2026-07-31, against a planner that has since gained the AI Judgement dials, the
Audit II pass, per-seat difficulty and the `wants_power` benefit gates. Nothing
in the tree re-asks it, so this is the re-take. **Nothing was retuned; every name
below is a review trigger.**

The roster of advisers is `tests/unit/test_commander_ai_advice.gd`'s
`ADVICE_COVERAGE`, which is the authority for who advises and who is silent. It
reads **twelve** here, not the eleven of the CA4 batch: `halden_marr` gained a
`stand_value` earlier the same day (see *Marr's shore stand advice* above), so he
is measured as an adviser for the first time.

The lever is `doctrine_weight` in `data/ai/default.tres`, played at its shipped
`1.0` and then at `0.0`, which skips the three advisory hooks entirely (plan D2).
The dial was reverted at the end of the run and `data/` is byte-clean.

#### Arm A — against the no-commander planner (the controlled reading)

`make commander-balance BAL="--commanders=<one> --neutral --seeds=12"`, once per
adviser, 120 non-mirror games each. This is the arm that answers CA4 as it is
written: the opponent seats no commander, so the dial cannot move that side and
the whole delta is the adviser's own advice.

| Commander | advice on | advice off | Δ |
|---|---:|---:|---:|
| Mara Voss | 50.0% | 57.5% | **−7.5** |
| Rhea Sol | 47.5% | 50.0% | −2.5 |
| Gideon Holt | 65.8% | 66.7% | −0.8 |
| Alina Ward | 55.0% | 55.8% | −0.8 |
| Konrad Vale | 76.7% | 76.7% | 0.0 |
| Halden Marr | 51.7% | 50.8% | +0.8 |
| Ines Calder | 57.5% | 56.7% | +0.8 |
| Orin Flux | 57.5% | 55.0% | +2.5 |
| Tomas Reed | 60.0% | 55.0% | +5.0 |
| Cassian Rook | 47.5% | 41.7% | +5.8 |
| Sable Wren | 60.0% | 50.0% | +10.0 |
| Viktor Draeg | 72.5% | 58.3% | **+14.2** |

**CA4 still passes: the four names below zero are all inside the noise.** At 120
games a side the standard error on a difference is about 6.5 pp, so Mara Voss's
−7.5 is roughly one standard error and Rhea Sol, Holt and Ward are a fraction of
one. Only Draeg (+14.2, ≈2.2 SE) and Wren (+10.0, ≈1.5 SE) are separated from
zero at all. **Mara Voss is the review trigger this run produces** — her
`stand_value` is the only negative as large as its own error bar, it is flat in
Arm B as well, and she is a `watch` row on the standing matrix. It is a trigger
for a *measurement* at more seeds, not for an edit.

#### Arm B — the twelve advisers against each other

`make commander-balance BAL="--commanders=<all twelve> --seeds=2"`, 1,440 matches
per arm.

| Commander | advice on | advice off | Δ |
|---|---:|---:|---:|
| Gideon Holt | 57.5% watch | 65.8% WARN | −8.3 |
| Rhea Sol | 36.2% WARN | 40.8% watch | −4.6 |
| Konrad Vale | 65.0% WARN | 69.2% WARN | −4.2 |
| Alina Ward | 48.3% ok | 51.2% ok | −2.9 |
| Tomas Reed | 55.4% watch | 56.7% watch | −1.2 |
| Orin Flux | 51.7% ok | 52.1% ok | −0.4 |
| Mara Voss | 42.9% watch | 42.9% watch | 0.0 |
| Cassian Rook | 39.2% WARN | 38.8% WARN | +0.4 |
| Halden Marr | 43.8% watch | 42.9% watch | +0.8 |
| Ines Calder | 44.2% watch | 41.7% watch | +2.5 |
| Sable Wren | 52.1% ok | 44.2% watch | +7.9 |
| Viktor Draeg | 63.8% WARN | 52.5% ok | +11.2 |

**Read this arm as a ranking and never as a verdict.** Turning the dial off
removes advice from *both* seats of every game, and every commander in the field
is an adviser, so the field is closed and the twelve deltas sum to zero by
construction (they sum to +1.2 here, the three draws). A negative row means only
that advice helped that commander **less than it helped the field on average** —
it is not the CA4 question, which is Arm A's. That is why Gideon Holt reads −8.3
here and −0.8 against the neutral planner: what moved was Draeg and Wren taking
games off everybody, not Holt's repair gate turning harmful.

Neither arm is comparable to the full-matrix numbers in the section below: this
is a twelve-name field on five scenarios at two seeds, not the roster of
twenty-two at four.

#### Invariants and provenance

All four runs (two arms × two dial positions, 5,760 matches) are **0 rejected
commands and 0 cap stalls**. Arm B: 1,440 matches, 1,440 decisive with advice on
and 1,437 decisive with three draws with it off; first-seat bias +32.1 pp on and
+37.3 pp off, both the standing banking item and outside this document's ±5 pp
threshold as they have been since banking shipped. Terminations moved a little
toward the day cap with advice on (680 rout / 672 `day_cap` / 88 `hq`, against
703 / 650 / 87 off) and powers fired more often (11,751 against 11,115), which is
Wren's staged Vanish and the other timing doctrines doing what they were written
to do.

`reports/` is gitignored, so both sides of every arm were generated in the same
worktree at `d9e7336`. No `.tres` was shipped changed: `data/ai/default.tres` is
byte-identical to `main`, and no commander file was touched.

#### Voss's advice at three times the seeds (2026-08-16)

The trigger above, taken. `make commander-balance BAL="--commanders=mara_voss --neutral --seeds=36"`
at both dial positions — 360 non-mirror games each against the no-commander
planner, three times Arm A's sample, read with Arm A's own arithmetic (her win
rate over the non-mirror games, which is side-normalized by construction since
the schedule plays both seatings).

| Arm | Voss win rate | n |
|---|---:|---:|
| advice on (`doctrine_weight = 1.0`) | 55.3% | 360 |
| advice off (`0.0`) | 56.4% | 360 |

**Δ = −1.1 pp, standard error 3.7 pp: flat at 0.3 SE.** The same games read
paired (both arms play identical scenario/seed/seating triples; 63 flipped to a
win with advice, 67 flipped away) give 0.35 SE, the same answer. **Arm A's −7.5
was noise, and no lever is under suspicion** — `stand_value` is not named and
nothing was retuned. Both runs are 0 rejected commands and 0 cap stalls, 540
matches each, all decisive; first-side bias +43.9 pp on and +32.8 pp off, the
standing banking item. `reports/` is gitignored, so both sides were generated in
one worktree at `3634442`; `data/ai/default.tres` was reverted and `data/` is
byte-clean.

### Measured after the power-gate pass (2026-08-15)

The full batch at twenty-two ran **9,680 matches** (22×22 ordered pairs × five
scenarios × four seeds) in **33 minutes** on the development machine, at
`225fe71`. **0 rejected commands and 0 cap stalls** — the hard invariants are
clean, so the run is comparable to every batch above. 9,679 were decisive and
one match ended a true tie — Ferrow against Ward on `ridge`, seed 1008, level at
the day cap on properties, units and funds alike, which is what the scoring rule
at the top of this document says stays a draw rather than a defect. It is the
first draw any full batch has recorded, and notably not a mirror. First-seat bias was
**+32.6 pp** (red 66.3%), the standing banking item. Terminations: 5,248 rout,
3,903 `day_cap`, 529 `hq`.

**This regen is a measurement, not a tune. No `data/` file was touched in the
change that carries it.** It exists because seven commanders' `wants_power`
gates moved after the 2026-08-14 baseline was taken — Draeg (#210), Ferrow
(#212), Lark and Rowan (#214), Marr (#216), Sol (#217), Ash (#218) — each
merged on a focused measurement rather than a full matrix, plus Orin Flux's
Signal Jam rework (#205), whose changelog entry below already said the
standings predated it. One `wants_power` is one of the two things a doctrine
does, so the full matrix is what the pass owes.

**The seven gates, and what the batch says each one did.** `held` is seats that
filled a meter and never spent it; `lag` is the mean `first_fired −
first_ready`, in days, over the seats that did fire.

| Commander | 2026-08-14 | now | Δ | powers/match | held | lag |
|---|---:|---:|---:|---:|---:|---:|
| Viktor Draeg | 59.1% | **61.2% WARN** | +2.1 | 4.28 | 37 / 877 | 0.92 |
| Sera Lark | 64.9% | **63.9% WARN** | −1.0 | 3.95 | 78 / 880 | 0.30 |
| Nia Rowan | 48.1% | 45.9% ok | −2.2 | 3.46 | 116 / 880 | 1.15 |
| Perrin Ash | 41.5% | 41.7% watch | +0.2 | 0.56 | **732 / 880** | 4.62 |
| Dane Ferrow | 40.9% | 41.4% watch | +0.5 | 5.49 | 0 / 880 | 0.29 |
| Halden Marr | 41.4% | 41.1% watch | −0.3 | 2.35 | **528 / 880** | 0.00 |
| Rhea Sol | 37.7% | **37.4% WARN** | −0.3 | 1.19 | **646 / 880** | 6.01 |

Six of the seven moved less than the field's own drift, and the pass is
therefore what it was argued as: **the gates delete firings that bought
nothing, and deleting them is close to free in win rate.** The one exception is
Draeg at +2.1 pp, which crossed him from `watch` into `WARN` — armour is on
every board, so his gate withholds a meter rather than banking it forever, and
holding it for the turn a tread can use it is worth points.

**Where powers went to zero, and why that is the gate rather than a stall.**
Two commanders have scenario cells at exactly zero fires, both structurally:

| | clash | ridge | holdings | combined | channel |
|---|---:|---:|---:|---:|---:|
| Perrin Ash | **0** | **0** | **0** | 493 | **0** |
| Halden Marr | **0** | **0** | **0** | 1,437 | 633 |

Air Superiority buffs AIR attackers and Make for the Shore keys every effect on
a hull or on shore ground, so on a board with neither the power is a **provable
no-op** — `test_land_only_combat_is_bit_identical_to_neutral` already pinned
that for Ash. A zero there is the meter being held instead of thrown away, and
it costs nothing measurable: both read within 0.3 pp of their pre-gate numbers.
Ash fires only on `combined`, the one board with an airfield; Marr fires on
`combined` and `channel`, the two with water. Rhea Sol has no structural zero
but the same shape by degree — 851 of her 1,044 fires are on `holdings`, 3 on
`clash` — because nobody builds her a gun on the sparse boards.

Nobody else's power stopped: every ungated commander's zero-power seats are
unchanged in character, and the widened commander soak (#211) keeps its
per-commander `fired > 0` assertion.

**The rest of the leaderboard**, every name outside the preferred 45–55% band,
with movement against the 2026-08-14 reading:

| Commander | Full matrix | Δ | Worst fixture | Reading |
|---|---:|---:|---|---|
| Radek Morn | **90.0% WARN** | +0.6 | `channel` 78.4% | Unmoved. Still the least-fired meter of any ungated commander (1.80/match at 24,000; only the gated Ash and Sol fire less) — the edge is the flat passive, as MC5 said. |
| Iona Vance | **78.6% WARN** | +0.3 | `channel` 65.9% | Unmoved. |
| Sera Lark | **63.9% WARN** | −1.0 | `channel` 53.4% | Gated (#214); see above. |
| Konrad Vale | **62.5% WARN** | +0.2 | `holdings` 47.7% | Unmoved, and the split stays inverted — in band on the economy fixture his doctrine is authored for. |
| Viktor Draeg | **61.2% WARN** | +2.1 | `ridge` 56.8% | Gated (#210), and the one gate that moved a win rate. New WARN. |
| Ivar Thorne | 59.2% watch | −0.5 | `holdings` 42.6% | Unmoved. |
| Gideon Holt | 55.6% watch | −0.3 | `channel` 49.4% | Unmoved; 10.2 pp across the five boards, second-flattest behind Draeg's 9.1. |
| Cass Orlov | 44.7% watch | −0.8 | `ridge` 36.9% | Slipped out of band by drift, not by a change. |
| Lyra Quill | 41.9% watch | +0.2 | `clash` 35.8% | Advises nothing on purpose. |
| Perrin Ash | 41.7% watch | +0.2 | `ridge` 34.1% | Gated (#218); domain-only, exactly neutral on land. |
| Dane Ferrow | 41.4% watch | +0.5 | `clash` **27.8%** | Gated (#212); `clash` is the carried trigger below. |
| Halden Marr | 41.1% watch | −0.3 | `ridge` 34.1% | Gated (#216); Ash's structural twin, still within 0.6 pp of her. |
| Ines Calder | 40.1% watch | −0.1 | `clash` 23.9% | Unmoved. |
| Mara Voss | 39.5% WARN | +0.1 | `channel` 33.0% | Unmoved. |
| Cassian Rook | 37.6% WARN | −0.5 | `clash` 21.0% | Unmoved; the gate shape the two march powers now share is his. |
| Rhea Sol | **37.4% WARN** | −0.3 | `holdings` 28.4% | Gated (#217); see the trigger below. |
| Iris Colt | **22.8% WARN** | −0.3 | `clash` 4.5% | The written exception, still the roster's most urgent single name. |

In band and needing nothing: Orin Flux 45.2% (**+1.9**, and back in band — the
Signal Jam rework's predicted direction, at full-matrix scale for the first
time), Nia Rowan 45.9%, Alina Ward 47.4%, Sable Wren 48.4%, Tomas Reed 53.6% —
five of twenty-two, the same count as the last batch with one name swapped
(Orlov out, Flux in).

**What the shape says.** The spread is **22.8 – 90.0% (67.2 pp, 9 WARN)**, a
hair wider than the 66 pp the last batch read, and the extra WARN is Draeg
moving up rather than anyone falling. The top of the field is untouched by this
pass — the four MC5 generals are within 1.0 pp of where they stood — which is
the expected result: a `wants_power` gate cannot reach a doctrine whose edge is
an always-on passive. Every out-of-band name is a **review trigger** per the
rule at the top of this document, and the tuning ladder has not been walked
here.

**Reproduction anchor.** `make commander-balance BAL="--commanders=rhea_sol,alina_ward --seeds=2"`
reproduces PR #217's reviewed slice exactly on this tree — Sol 42.5% watch, 41
powers over 40 seats, 7 of 40 seats firing at all, hold lag 2.57 days, 0
rejected, 0 cap stalls — so the numbers above are the same instrument those PRs
were merged on.

**Carried review triggers.** These are the owed human tuning pass's, not this
regen's; nothing below was changed here.

- **Lark and Rowan's zero-fire matches** (#214). Both march powers now fire for
  ground only, so a board with nothing left to take banks the meter: 78 of 880
  seats for Lark and 116 for Rowan, concentrated on `channel` (78 and 104).
  That is the banked-meter direction the Wren stall taught the roster to watch,
  and the question the pass owns is whether the floor should be a cheaper
  meter rather than a looser gate.
- **Ferrow's `clash` figure** (#212). 27.8%, his worst cell and down from 29.0%
  — plunder still needs a treasury and `clash` still resolves before one
  exists, which the gate correctly refuses to fire into but cannot fix. His two
  thresholds, `collect_want_hp = 6` and `collect_want_funds = 1000`, are
  reasoned defaults never measured against alternatives; too low and he banks
  through a healthy slugging match, too high and the gate is decorative.
- **Rhea Sol** (#217). 37.4% with 646 of 880 seats holding a full meter all
  match: the planner rarely buys her a gun, so the gate is nearly always shut.
  **`indirect_build_bias` is the next lever, not the power** — a saturation
  power with nothing to saturate is an economy problem wearing a power's
  clothes.
- **Ash and Marr's hold-forever cliff** (#218, #216). On a board with no
  aircraft (Ash) or no water (Marr) the meter is held for the whole match by
  design, and no "fire anyway after N days" escape hatch exists. That is
  deliberate — the power is provably worth zero there — but it means both
  generals' doctrines are a single always-on modifier on three of the five
  fixtures, which is what their 41% aggregates are measuring.

### Measured after the Codebase Audit II baseline (2026-08-14)

The full batch at twenty-two ran **9,680 matches** (22×22 ordered pairs × five
scenarios × four seeds) in **46 minutes** on the development machine, at
`025c5ca`. All 9,680 were decisive (0 draws), with **0 rejected commands and 0
cap stalls** — the hard invariants are clean and no per-turn-cap warning fired,
so the run is comparable to the batches above. First-seat bias was **+33.0 pp**
(red side 66.5%), the standing banking item described in the N4 section rather
than anything this baseline introduced. Terminations: 5,271 rout, 3,889
`day_cap`, 520 `hq`.

**This regen is a measurement, not a tune. No `.tres` number moved.** It exists
because the MC5 and CA4 standings had been explicitly marked as predating the
planner: the AI Judgement dials went live, the Codebase Audit II pass moved
`data/ai/default.tres`, the balance levers moved into `data/rules.tres`, and
several audit commits are outcome-moving on their face (shot selection through
`AttackRange.ready_shot`, HQ capture pricing gated on the home-HQ authority,
build reactivity reordered, Sable Wren's cover keyed on `conceals`, the supply
tier's doctrine bias clamped as a sum). What follows is the post-audit baseline
those sections told the reader to re-run for.

Every commander outside the preferred 45–55% band, worst fixture being the board
that carries the anomaly furthest:

| Commander | Full matrix | Worst fixture | Reading |
|---|---:|---|---|
| Radek Morn | **89.4% WARN** | `holdings` 97.7% | Unmoved from MC5's 89.4%. Fires least of anyone (1.80 powers/match at 24,000) and leaves opponents **0.83** units against a field of 4.13 — the edge is the flat passive, not Hammerfall. Beats Vance 90%, Thorne 90%, Lark 85%. |
| Iona Vance | **78.3% WARN** | `combined` 92.6% | MC5 measured 77.8%; +0.5 pp is inside the field's own drift. Holds 6.17 properties a match against a field of 4.48. |
| Sera Lark | **64.9% WARN** | `ridge` 82.4% | MC5 measured 65.3%. Still the property race rather than the fight — 5.24 properties held while leaving 2.94 enemy units standing. |
| Konrad Vale | **62.3% WARN** | `clash` 79.5% | Standing high name, and the split is the same shape NC7 recorded inverted: he is *in band* on `holdings` (47.2%), the economy fixture his doctrine is authored for, and out of band on the sparse boards. |
| Ivar Thorne | 59.7% watch | `clash` 75.0% | Identical to MC5's 59.7%. |
| Viktor Draeg | 59.1% watch | `channel` 66.5% | Standing high name; 62.2% at CA4, drifting down rather than up. |
| Gideon Holt | 55.9% watch | `combined` 60.2% | Standing high name, barely outside; the flattest per-board spread on the roster (50.6–60.2%). |
| Orin Flux | 43.3% watch | `holdings` 40.9% | New to the low set since AU2 re-pegged `scout_build_bias`; flat across boards, so the deficit is not fixture-owned. |
| Lyra Quill | 41.7% watch | `clash` 36.9% | Advises nothing on purpose (forecasts are luck-free), so she measures the field getting stronger around her. |
| Perrin Ash | 41.5% watch | `ridge` 35.2% | Domain-only doctrine, exactly neutral on the land-only boards — `ridge` is where that costs most. |
| Halden Marr | 41.4% watch | `ridge` 35.2% | Ash's structural twin, and the two read within 0.1 pp of each other. |
| Dane Ferrow | 40.9% watch | `clash` 29.0% | Was 48.5% at NC7. Plunder needs a treasury to steal from; `clash` resolves before one exists. |
| Ines Calder | 40.2% watch | `clash` 26.7% | Was 49.3% at NC7 — the largest fall in the field. Cheap breadth is a `holdings` doctrine measured mostly on sparse boards. |
| Mara Voss | 39.4% WARN | `channel` 33.0% | Was 49.3% at CA4. |
| Cassian Rook | 38.1% WARN | `clash` 21.0% | Was 46.2% at CA4, and the widest per-board spread on the roster (21.0–56.8%). Redeployment buys ground, and `clash` has none to buy. |
| Rhea Sol | 37.7% WARN | `holdings` 31.2% | Was 46.9% at CA4; the standing low name returns. |
| Iris Colt | **23.1% WARN** | `clash` 5.1% | The written exception below, now measurably worse (26.4% at NC7). `holdings` 39.8% against `clash` 5.1% is the same diagnosis in sharper relief: sparse fixtures offer almost no eligible non-attack action for Second Wind to refresh. |

In band and needing nothing: Cass Orlov 45.5%, Alina Ward 47.4%, Nia Rowan
48.1%, Sable Wren 48.8%, Tomas Reed 53.5% — five of twenty-two.

**What the shape says.** The spread is **23.1 – 89.4% (66 pp, 8 WARN)**, wider
than any batch recorded in this document, and it is wide at both ends: the four
MC5 generals sit unmoved at the top while six previously-centred names (Rook,
Voss, Sol, Calder, Ferrow, Flux) fell into the low set. The MC5 four not moving
while the field around them fell is the reading that matters — a planner that
plays everyone better rewards a flat always-on modifier and a property race more
than it rewards a power that has to be timed. Per the rule at the top of this
document all seventeen are **review triggers**, and the tuning ladder (power
cost, then power magnitude, then passives last, passives behind human
confirmation) has not been walked here.

**Owed:** a human-confirmed tuning pass. The levers MC5 named for Morn and Lark
are unchanged and still the ones this baseline points at, and Iris Colt at 23.1%
is now the roster's most urgent single name rather than a documented curiosity.

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

- **2026-08-15 — the matrix is regenerated after the power-gate pass; no number
  moved.** 9,680 matches at `225fe71`, 33 minutes, hard invariants clean (0
  rejected, 0 cap stalls, 1 draw), first-seat bias +32.6 pp. It closes
  the "re-run the matrix" note the Signal Jam entry below carries and answers
  for the seven `wants_power` gates merged since the 2026-08-14 baseline
  (Draeg, Ferrow, Lark, Rowan, Marr, Sol, Ash). Six of the seven moved less
  than the field's own drift; Draeg moved +2.1 pp and is a new WARN. **No
  `data/` value was touched**, per the rule at the top of this document that an
  out-of-band commander is a review trigger. The full reading, including the
  power telemetry and the four carried triggers the human tuning pass owns, is
  in *Measured after the power-gate pass* above.
- **2026-08-15 — Signal Jam stops stripping supplies and starts stripping
  movement.** The 43.3 % reading above came with the note that the deficit is
  flat across boards, and the diagnosis is the power rather than a fixture: 10
  fuel off pools of 50–99 that are spent two or three a turn, and one shell off
  six to nine, are not a turn either side plans around, and the third half —
  −1 enemy vision — only bites in fog and buys little against a planner whose
  targeting is omniscient-except-hidden. So the one-shot strip is **deleted**
  and the jam is now two ongoing debuffs: **−1 enemy movement** beside the
  −1 vision it already carried, for the same 11,000 and the same ROUND
  duration. A movement point is the one currency both a human and the planner
  spend, the planner reading the same `MovementResolver.move_budget` the board
  does.

  The hook is `CommanderType.enemy_move_bonus`, the second cross-table hook and
  a verbatim mirror of `enemy_vision_bonus` — asked of every hostile commander,
  `team` passed rather than recovered — read in `move_budget`'s own
  hostile-commander loop, which is the loop `Vision._sight_of` already runs.
  The budget is floored at one point before the fuel cap (slowed, never frozen;
  an empty tank still stays put), and nothing but a jam can reach that floor,
  so every commander-less and unjammed budget is the arithmetic it always was.
  `make verify` is green, determinism golden reproduced.

  Measured as a same-seed A/B rather than argued, `orin_flux:normal` against
  `none:normal`, 40 paired seeds (n=80) a fixture:

  | fixture | old power | new power | Δ |
  |---|---:|---:|---:|
  | `holdings` | 51.2 % | 61.2 % | **+10.0** |
  | `ridge` | 56.2 % | 57.5 % | +1.3 |
  | `clash` | 46.2 % | 45.0 % | −1.2 |

  `holdings` — his worst board in the matrix above at 40.9 % — moves furthest,
  and `clash` is flat because it resolves before the meter matters. This is a
  duel against a neutral, so it is not on the full matrix's scale; the delta is
  the reading, not the level. **The standings above now predate this change for
  Orin Flux**: re-run the matrix before quoting his row.
- **2026-08-14 — the matrix is regenerated on the post-Audit-II baseline; no
  number moved.** 9,680 matches at `025c5ca`, 46 minutes, hard invariants clean
  (0 rejected, 0 cap stalls, 0 draws), first-seat bias +33.0 pp. This closes the
  "re-run the matrix before quoting them" note the MC5, CA4 and 2026-08-05
  entries all carry: those standings predated the live AI Judgement dials, the
  Codebase Audit II planner work and the balance levers' move into
  `data/rules.tres`, and this is what the roster measures with them in. The
  result is a wider field, not a settled one — 23.1 – 89.4%, eight WARN — and
  **no `data/commanders/*.tres` value was touched**, per the rule at the top of
  this document that an out-of-band commander is a review trigger. The full
  reading is in *Measured after the Codebase Audit II baseline* above.
- **2026-08-05 — two build biases re-pegged to a list that grew, and Gideon
  Holt's depot numbers move into data** (codebase audit, AU2). Rockets joined
  every tier's `build_priority` at the tail, and a doctrine's `build_bias`
  counts in *places* on that list, counted from its end for a unit the list
  never names — so lengthening it by one weakened every such pull by one.
  `cassian_rook` `light_build_bias` −3 → **−4** and `orin_flux`
  `scout_build_bias` −2 → **−3** give the two scout doctrines back the place
  they were calibrated at; neither is a strength change, and at −2 Flux had
  stopped buying the recon that names him. Separately, `gideon_holt` gains
  `depot_want_hp`, `depot_want_fuel_pct` and `depot_want_units` at the values
  his subclass already used — they were code defaults alone on the roster, so a
  balance pass reading `data/commanders/` would never have seen them. No
  behaviour moved with them.

  **The MC5 standings above now predate the planner**, the same way the CA4 ones
  do: this slice moved `data/ai/default.tres` (supply and the rockets) and the
  planner itself, and the determinism golden moved with it. Re-run the matrix
  before quoting any of those numbers.
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
  sits on the plan's 14 000 ceiling. [That ceiling described the roster as of
  this date — the four-commander expansion (more-commanders plan, MC1–MC5)
  later seated a costlier tier, Radek Morn's 24,000 in the MC5 section above.]
  The accrual split (100 % lost / 50 % dealt) is the plan's locked D2 and was
  not touched.
