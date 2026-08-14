# Design record — the long form

`CLAUDE.md`'s **Designs of record** index carries every plan's scope and its locked decisions. Six
entries had grown far past what an index can hold — 90k characters between them, over half the file
that is loaded into context on every session — so their *long form* lives here instead: the
rationale, the measurements, the superseded clauses and the risk-register prose.

**Read the entry for one of these six areas here before an architectural decision in it.** The
`.lavish/*.html` plans are still the designs of record; this is the record of what was decided or
measured *since* they were written, and where those two disagree this file wins.

Only these six are here. Every other plan is stated in full in `CLAUDE.md` and **has no copy in
this file** — one entry, one place, because a decision written twice is updated in one of them.
The text below is verbatim what the index carried before the split, so nothing has been
re-summarised; an entry that has drifted from the index is a bug in the index, not here.

Covered here: `ai-judgement-plan.html`, `ai-economy-plan.html`, `ai-arena-plan.html`,
`four-players-plan.html`, `asymmetric-board-plan.html`, `campaign-depth-plan.html`.


## `ai-judgement-plan.html`

- `ai-judgement-plan.html` — the three things the planner cannot see: what the enemy is
  *achieving*, what it will *do next turn*, and what our own other units are doing. Milestones
  AJ1–AJ4, **all shipped**. It is scoped against `balance-retune-plan.html` and the boundary is
  the point: **this plan owns planner *capabilities*, BL2 owns Normal's *numbers*** (D2), so no
  AJ milestone edits a shipped value in `data/ai/` and AJ4's deliverable is a probe band in
  `docs/difficulty_check.md`, never a tier value. D1: **every dial ships at `0.0` and `0.0` skips
  the code**, the same contract as the difficulty plan's S1–S3 — so the merge bar for every AJ
  milestone is a fixed-seed byte-diff of *both* balance reports with **no accepted departure**,
  and `test_capability_defaults_plan_exactly_like_the_shipped_profile` keeps passing unchanged.
  D1's *inert* half is superseded as of 2026-08-01, when the dials went live ahead of BL2: on
  every tier `defend_weight` and `cohesion_tiles` / `cohesion_radius` now carry a value scaled to
  the tier's character, and `ai/ai_profile.gd`'s class defaults moved with `data/ai/default.tres`
  because the invariant that pin protects is that an install with no profile file plays the same
  game — which is also what that test now pins, rather than parity with the pre-dial planner.
  `defend_weight` ships at the **top** of the range AJ4 probed (2.0 Normal, 2.5 Difficult): the
  probe measured it flat from 0.25 to 2.0, so a low value bought no measurable safety and left the
  reported HQ defect reproducing against any rival worth a Recon or more. It reduces that defect
  rather than ending it — the bonus is linear and priced on the same scale as a kill, so a rich
  enough target (Rockets, which cannot counter) still outbids a match-ending capture at any weight;
  the ceiling is the pricing *shape*, and `docs/difficulty_check.md` §4c is the measured boundary.
  `withdraw_weight` is the one still at `0.0`, and it was a positioning defect rather than the
  ladder that held it there: at 0.05 it stopped an artillery short of maximum standoff. The AI
  Arena plan's AR6d fixed the refuge's price (see that entry), and the arena's first search
  campaign then took the measurement the dial was waiting on: searched properly for the first
  time, it ended back at 0.0 (`docs/ai_arena_results.md`) — at zero for a reason after all, one
  edit from a re-try.
  What survives untouched is the code property — **`0.0` still skips a capability entirely**,
  proven by the per-capability suites that build explicit zeroed profiles — and the cost is
  recorded rather than hidden: the DF4 ladder now fails knowingly, because that gate measures the
  *gap* between tiers and making Normal competent closes it (`docs/difficulty_check.md` §4c).
  D6: nothing under `core/` is touched and no telemetry is added —
  every read goes through an authority that already exists.
  AJ1's own two decisions: **denial is priced at the price of capture, read backwards** (D3) —
  `_defend_bonus` is built from the same `capture_score` / `capture_progress_bonus` /
  `hq_capture_multiplier` arithmetic `_consider_captures` uses, scaled by `defend_weight`, so at
  1.0 denying a capture is worth exactly what making one is and the two compete in one `AIUnitPlan`
  without a conversion; only a **capture-capable** enemy earns it (what a tank parked on our city
  threatens is the threat map's job, and paying twice is the plan's R3), the ground is our
  *side's* through `GameState.allied`, and the HQ multiplier is asked of `GameState.home_hq`,
  never `terrain_at(cell).id == "hq"` — an HQ a survivor conquered fells nobody, so defending it
  is worth a city and no more. And **only a besieged home HQ diverts the advance path**
  (`_besieged_home_hqs`, the plan's R2): a city is a setback defended by whoever already had a
  shot, an HQ is the match, and a defence goal any unit may adopt for any property empties the
  front the moment one infantry steps on a city.
  AJ2's one decision: **withdrawal is a scored candidate, not the fallback, and it is priced in
  value** (D4). `_consider_withdraw` sits in `_best_unit_plan` beside `_consider_attacks` /
  `_consider_captures` / `_consider_dive` — `_consider_dive` is the precedent, a non-attack action
  that already outbids a shot when the board says so — and it is called **last**, so a withdrawal
  that merely ties with a shot loses to it. `retreat_hp` never reached this case and could not:
  it steers the advance *fallback*, which a unit holding any half-decent shot never reaches, which
  is why a wounded tank took the shot and died. The score is
  `withdraw_weight × cost × damage_avoided / 100` — the currency `_attack_score` is already in, and
  the whole reason this is a third dial rather than a wider `advance_threat_tiles` (that one counts
  in *tiles* and so cannot say "this shot costs me sixteen thousand funds"). The refuge is the
  reachable cell of least `ThreatMap.incoming_damage`, then — since the arena plan's AR6d, see that
  entry — the cell that costs the unit's own weapon least, then ground that repairs us, then the
  shortest walk, and **safety outranks both**, so a workshop inside a firing ring is not a refuge;
  standing still enters the comparison at cost zero, so a merely-equal cell never pulls a unit off
  its own square. Three dials now read one `ThreatMap` (`threat_aversion`,
  `advance_threat_tiles`, `withdraw_weight`) and can price one enemy three
  times — the plan's R3 — so **tune them together and never alone**.
  AJ3's one decision: **cohesion is a term on the advance path, not a formation manager** (D5).
  `_cohesion_penalty` charges a unit `cohesion_tiles` per tile it is adrift of the nearest unit in
  its **own movement domain** beyond `cohesion_radius` — in *tiles*, which is what
  `_advance_value` is denominated in. There are no groups, no leaders and **no waiting state**: the
  goal term still pulls forward, so the equilibrium is a column advancing at the speed of its rear,
  and `tests/unit/test_ai_cohesion.gd` pins that it advances rather than stalls — which is D5's
  emergent waiting, played on a board. (The plan's R1, the clump being artillery and Command Power
  bait, is untouched by that test and stays open; where AJ4's `(cohesion_tiles, cohesion_radius)`
  probe left it is below.)
  Same domain because an army keeps company with what can keep up with it — otherwise a lone hull
  is dragged toward a land column it can never join. Same **team**, and deliberately not the whole
  side: formation is the army's, while defended ground is the side's, which is why AJ1's
  `_defend_bonus` reaches across the alliance through `GameState.allied` and this does not. The
  term taxes the **advance on the enemy** and nothing else, which is the one goal D5 describes it
  for: `AIPlanningContext.AdvanceGoal.keeps_formation` defaults to **false** and only that goal
  turns it on, so every errand `_advance_goal` computes before it — refit, repair, the besieged home
  HQ and a property to capture — goes untaxed by construction rather than by a list of exceptions,
  and `_cohesion_penalty` returns zero for them. Both terms count in tiles and the column's pull is
  the stronger, so charging an errand cancels it outright: a wounded unit trails the column and
  never repairs, an infantry sits at the column's edge and takes no ground, and AJ1's diversion
  never turns anybody around. The
  rejected alternative is an explicit formation manager: it needs cross-turn state the planner has
  nowhere to keep (`AIPlanningContext` is rebuilt every command, and only the threat map
  deliberately survives).
  **AJ3 owns the cohesion term and its goal exemptions; the two measurements are AJ4's, on frozen
  code.** The `focus_fire_bonus` re-test *with cohesion live* was attempted inside AJ3 and moved
  out: every measurement taken agreed on the sign, but each review round changed the planner it had
  been taken on, so no number stayed current while the milestone's code was still moving. It now
  sits in AJ4 beside the sweep's wall clock already deferred there from AJ2 — a measurement belongs
  on the milestone that adds no code.
  AJ4 is that milestone and it adds none: **`docs/difficulty_check.md` §4b is the measured band for
  every dial these four milestones added, and it is what BL2 reads instead of guessing.** Its
  results, all at n=16 and therefore directions rather than magnitudes — and §4b's headline is now
  **downgraded to a hypothesis by §4c**, which re-measured it at 15 seeds with every tier carrying
  the dial and found the direction consistently opposite: `cohesion_tiles` 1.0–2.0 at
  `cohesion_radius` **2** was the largest move measured anywhere in this plan (+25 points over
  control) and **tight beat loose** — radius 4 never clears the control, so the two axes had to be
  probed together, and 2.0 is the top of the probe rather than a measured ceiling; `defend_weight`
  moves one match of sixteen, identically at all four values tried, which is **one observation
  rather than four** and by the section's own calibration a hint — flat from 0.25 to 2.0, offered
  for BL2 to re-measure at its own width and never as a measured band; and **two of the four dials are
  recommended off** — `withdraw_weight` measures negative at every value tried, and
  `focus_fire_bonus` is refuted a third time, now with cohesion live, which retires the argument
  that it only ever failed for want of a column to focus. What the section does **not** know is the
  more useful half of it, and §4b lists it in one place: **R3 is untested, not refuted** — the
  probe never ran threat-dials-off *and* `withdraw`-off, so it cannot separate withdrawal's cost
  from Difficult simply being weaker without its shipped threat smarts, and R3's tune-them-together
  instruction stands on its original reasoning; **R1 is unobserved rather than refuted** — the
  tightest column measured best, but both sides are the same planner and neither punishes
  concentration, so the instrument is structurally blind to the risk and R1 belongs to a human
  playtest. R6's wall clock: **a live threat-map dial roughly doubles Normal's per-turn planning
  time** (33 → 63 ms) — that comparison's other two columns are forced configurations rather than
  shipped tiers (Easy and Difficult already build the map). Normal still builds no threat map, so
  that half stands; but every turn-time figure in that document predates something — §4's table the
  dials, both of them the AR1 plan cache — so none of them reads the planner as it stands, and
  nothing since has re-measured them.


## `ai-economy-plan.html`

- `ai-economy-plan.html` — the planner reads the map as an *economy* rather than as the fight in
  front of it: enough infantry to race for the board, capture goals that fan out across it, and a
  price on the ground that builds tanks. Milestones AE1–AE4, **AE1–AE3 shipped**. It is scoped
  against `ai-judgement-plan.html` (capabilities) and the balance retune (numbers) and inherits both
  boundaries verbatim. D1: **every dial ships inert and inert skips the code** — the merge bar for
  every milestone is a fixed-seed byte-diff of *both* balance reports, `make commander-balance` and
  `make difficulty-check`, with no accepted departure, and `reports/` is gitignored so both sides
  are generated. D2: **this plan owns planner capabilities, BL2 owns the tier numbers** — no AE
  milestone edits a shipped value in `data/ai/`, and AE4's deliverable is a probe band in
  `docs/difficulty_check.md`, never a tier value. D7: nothing under `core/` is touched and no
  telemetry is added — every read goes through an authority that already exists
  (`MapData.property_cells`, `GameState.properties_of` / `allied` / `home_hq`,
  `TerrainType.builds`, `UnitPricing.cost_for`).
  AE1's decision is D5: **the capture roster scales with what is left to take, floored at today's
  number.** `AIProfile.capture_unit_target` is now the *floor* rather than the answer and
  `capture_units_per_property` is what raises it — the target is
  `max(capture_unit_target, ceil(rate × unowned))`, where `unowned` counts property cells this
  team's **side** does not hold, asked of `GameState.allied` exactly as `_advance_goal` already
  reads it. That flat target happened to equal the roster every shipped board deals, so the urgent
  build tier was empty before the first command of every match and the AI opened by banking on a
  board covered in neutral ground. It counts what is *left* rather than the size of the board,
  which is what makes it self-damping: the target falls as the map fills, so an army that has taken
  everything wants no more infantry and the priority list resumes with nothing to switch off.
  `AIProductionPlanner._capture_unit_target` is the one place that asks, one scan per build
  decision; `AIPlanningContext` gained nothing, because this is not a per-decision fact the unit
  planner shares. D5's own clause that the floor "stays at 3 in every tier" is superseded by D2,
  which forbids editing a shipped tier value: **the floor is whatever a tier already ships**, and
  `easy.tres` has carried 2 since COM-120 pruned its capture play (`docs/difficulty_check.md` H3).
  D6 rides on D5 and is why no banking code moved: **`_worth_waiting_for` already refuses to bank
  whenever something urgent is wanted**, and a short capture roster is urgent — so the same branch
  now banks on a small board and spends on a big one, and a property count is the board asking
  whether there is a race on without anything in `ai/` having an opinion about map size.
  `save_up_turns` is deliberately left alone: its comment carries the first-side-bias measurement
  (+5.6 pp at no banking, +14.9 at two turns, +20.2 at three) that a retune would trade away.
  The plan's R2 — a rate that wins the property race by deleting the expensive half of the roster
  everywhere — is guarded by a property-*poor* fixture in `tests/unit/test_ai_economy.gd`, which is
  the milestone's real bar: D6's board-dependence is a claim about two boards and only one of them
  is the bug.
  AE2's decision is D3: **a capture goal is claimed by derivation, never by stored state.** Every
  capture unit used to walk to its own nearest property with nothing marking one as already
  somebody's, so units standing near each other took the same tile together — and on a board dense
  in properties there is always a nearer tile than the far corner, so the far corner was never
  anybody's goal at any point in the match. `capture_claim_depth` is how many units may claim one
  property; `AIUnitActionPlanner._claimed_property` is the one place that answers, inside the
  capture clause of `_advance_goal`, and at 0 it is the shipped `_nearest` call untouched.
  **D3's arithmetic is superseded and its decision is not.** The formula it offered — drop a
  property when that many rivals are strictly closer to it — cannot produce the outcome D3 itself
  states ("the nearest unit still takes the nearest property; the second one is pushed to the
  next"), because a unit at the front of a column is closest to *every* property at once, so the
  units behind it keep nothing and converge exactly as before. What ships instead is an
  **assignment**: the closest unit-property pair settles first, then the next, and a property stops
  accepting once `capture_claim_depth` units hold it. It is settled once per command into
  `AIPlanningContext.capture_claims` and cleared by `begin` — exactly `goals`' lifetime, which is
  the whole of what D3 locks: nothing about a claim survives a command, so the rejected
  cross-decision claims registry stays rejected. **Every tie is
  settled by scan order** over the whole (distance, unit, property) triple, so the sort needs no
  stability and replans off one board always agree; R6's pin is `test_replay_fidelity.gd` plus the
  reversed-pair fixture in `tests/unit/test_ai_economy.gd`. A unit left unplaced — more capturers
  than `capture_claim_depth` places — falls back to the same priced walk an unclaimed capturer
  takes (`_worth_walking_to`, AE3 below), so claiming can never send a capturer at the enemy
  instead. `MovementResolver` is untouched: this filters the candidate list the shipped walk
  already collects and is no new fill, path or geometry.
  AE3's decision is D4: **a property is priced by what it produces, in the currency captures are
  already in.** Nothing in `ai/` knew a property builds anything, so a base, an airport and a port
  scored exactly as a plains city — which is how a closed seat's two factories sat unclaimed while
  the player took them and built out of both. `capture_score` stays the unit of account and
  `production_capture_multiplier` multiplies it **beside** `hq_capture_multiplier`, on the same line
  of arithmetic, so the two compose rather than compete — neither can shadow the other, whatever a
  future terrain builds. On this game's data they never both apply: `data/terrain/hq.tres` builds
  nothing, so a headquarters is priced by `hq_capture_multiplier` alone and a base, a port and an
  airport are the production properties. **That supersedes the plan's AE3 card**, which asserts "a
  captured enemy headquarters is already a production property and should read as both" — false
  against the shipped terrain, and the composition is worth having on its own terms.
  **One judgement, two readings, and they cannot disagree.** The same multiplier feeds the goal side
  through `capture_goal_value_tiles`, which buys
  `capture_goal_value_tiles × (production_capture_multiplier − 1)` tiles of detour — zero at either
  dial's inert value, so the sign of the two readings is one number's sign. They are denominated
  differently because the two paths are: `_consider_captures` competes in **value** against
  `_attack_score`, a goal is chosen in **tiles**, and that is the same split `threat_aversion` and
  `advance_threat_tiles` already live on. A unit that walks to a factory because it is valuable must
  still want it when it arrives, or it turns round on the doorstep.
  `AIUnitActionPlanner._produces` is the one place that answers "does this ground build", and it
  asks `TerrainType.builds` — the field `BuildCommand`, the build menu and the production planner's
  facility scan already read — so **AE3 adds no terrain id to `ai/`**. `_goal_steps` is the one
  place that converts the judgement into tiles, read by both the plain walk (`_worth_walking_to`)
  and AE2's claimed assignment, so a claimed goal and an unclaimed one price the same ground alike.


## `ai-arena-plan.html`

- `ai-arena-plan.html` — the self-play arena: thousands of headless matches between candidate
  AIs, so a planner weight is *measured* rather than argued. Milestones AR1–AR7 (AR1 make a match
  cheap, AR2 make the machine busy, AR3 seat an arbitrary candidate, AR4 decide what "better"
  means, AR5 calibrate, AR6 widen the shelf, AR7 the verdict). **AR1–AR6 are shipped** — the
  harness seats any candidate, the ruler exists, the shelf is in the tree and `make arena-search`
  is the search loop laid over them; only AR7's human verdict remains.
  **`docs/ai_arena.md` is the committed record of what "better" means and how the search is
  driven** and is the document to read before any arena claim; **`docs/ai_arena_results.md` is
  what the first campaign found** (93,744 matches, 2026-08-05) — a dated measurement a later
  campaign supersedes wholesale rather than edits.
  D1: **the arena is an instrument and the game never learns it exists** — the driver lives in
  `tools/` and reads `BalanceMatchEngine.Outcome`; nothing in `ai/` gains an "arena mode", because
  the moment the sim can see the measurement the measured game stops being the shipped one (the
  balance plan's D2, applied to a new instrument). D2: **a performance change is proven
  byte-identical, never argued** — a fixed-seed byte-diff of `make commander-balance` *and* `make
  difficulty-check` across the change, no accepted departure, plus a differential test that keeps
  the two planners agreeing command for command afterwards; a faster planner that plays a
  different game is a different AI and would silently invalidate the ladder, the Atlas and every
  number in `docs/commander_balance.md` in one commit. D3: **a candidate is an `AIProfile` and
  nothing else** — the search space is exactly `ai_profile.gd`'s `@export`s, so anything the arena
  finds ships as an edit to one `.tres` rather than as a code branch nobody can play. D7: **the
  opponent is the archive, not the champion** — this game is measurably intransitive (Easy beats
  Difficult beats Normal beats Easy is in the Atlas), so a ladder that only ever plays the current
  leader walks a circle and reports progress every lap; every generation scores against a fixed
  anchor set, a sample of past champions and its own generation, and **progress is the anchor
  score**. D8: **the arena recommends and a human ships** — no milestone and no `make` target
  writes a searched number into `data/ai/`, because the arena optimises for winning a headless
  match against a machine and the product is a game a person plays.
  **D8 has been exercised, and the shipping is what it looks like working.** On 2026-08-06 the
  campaign's `everything` vector was read at a table and seated verbatim as a fourth difficulty
  tier, **Brutal** — sixteen dials off Normal, not one of them retuned on the way in, so the tier
  and `docs/ai_arena_results.md` are the same numbers and
  `tests/unit/test_difficulty.gd` pins them to each other by value: an edit to one of those
  sixteen stops being a balance tweak and becomes a claim the campaign did not make. The route in
  was a person's decision, not a target's — no `make` target writes `data/ai/` and none was
  taught to. The campaign's own boundaries shipped with it rather than being quietly dropped
  (commander-free, land duels only, and a vector that fields 100-unit armies to win by day 22),
  restated in the profile's header where a retuner will meet them. AR7's watched match is still
  what says whether that is a better opponent or only a better score.
  **D1's "nothing under `core/` gains a field, hook or branch" carries one recorded waiver**, the
  user's, taken in AR1 when the cache alone came in under the plan's own speedup floor:
  `MovementResolver._occupants` (one occupancy index per movement fill, never stored — a
  longer-lived one would need every writer that moves, kills, builds, loads or unloads a unit to
  maintain it, and the one that forgot would answer wrong rather than fail) and
  `AttackRange.band` / `reaches` (a unit's firing ring resolved once per unit instead of once per
  candidate-cell × enemy pair). Both are pure reads that decide nothing, and **D2's byte bar is
  what stands in for D1 here** — both reports byte-identical over 6,480 matches, plus the cache
  differential asserting command-for-command identity with the cache on and off, which is two files:
  `tests/unit/test_ai_plan_cache.gd` (one fixture per invalidation rule) and
  `tests/unit/test_ai_plan_cache_diff.gd` (whole seeded matches), both driving
  `tests/helpers/plan_cache_diff.gd` and neither keeping a copy of it. **A milestone that adds a dial
  to the planner adds a run** to the second, because a cache that is exact only while a dial is zero
  is the silent divergence they exist to refuse. Read the `core/` changes as a waived departure, not
  a rule violation. AR6a is the plan's only other `core/` touch and is not a second waiver: a
  private static became `CombatResolver.cover_stars`, no field, hook or branch, so the planner asks
  the damage formula what cover a cell gives rather than reading `defense_stars` itself.
  AR6d departs from its own ticket in the same recorded way: the ticket asks for a
  boolean "can it still fire" key, which scores maximum standoff and one tile short of it
  identically and so would not have fixed the reported board — what ships is a **rank**
  (`_position_rank` against the enemy the unit is orienting on), under safety and over repair,
  reaching indirect units only. `withdraw_weight` keeps its shipped `0.0` throughout (the
  difficulty plan's D2 owns tier numbers), so AR6d is inert in every shipped tier.
  AR6a–AR6c are the rest of that shelf, three dials on `AIProfile` — `cover_tiles`,
  `condition_weight`, `join_weight` — on the AI Judgement D1 contract they inherit whole: **`0.0` on
  every tier, and `0.0` skips the code** rather than evaluating to zero, so the merge bar is both
  balance reports byte-identical and it held. They shipped **unmeasured on purpose** until AR5's
  first campaign priced the shelf: `cover_tiles` and `condition_weight` earned places in its
  champion, while `join_weight` — like `withdraw_weight` — measured worthless and stayed at zero
  (`docs/ai_arena_results.md`), standing where `focus_fire_bonus` stands: implemented, tested,
  shipped at zero, one edit from a re-try.
  AR6a: **the double-pricing answer is per cell, not per tier.** A cell is priced by the forecast
  wherever a forecast has fire for it — `priced_fire` is that fire, the counter this shot invites,
  the threat map's reading, or both — and the stars speak only where none does, because every one of
  those numbers is `CombatResolver`'s resolved through the same terrain, so stars on top would price
  one wood twice (Judgement R3 in a new place). It counts in **tiles** on both paths, the attack path
  converting through `step_cost_penalty`, so one dial says the same thing to the advance and to the
  shot where `threat_aversion` / `advance_threat_tiles` needed two. Nothing in `ai/` reads
  `defense_stars`: what cover a unit gets on a cell is `CombatResolver.cover_stars`' answer, air rule
  included.
  AR6b: **`_unit_value` is the file's only unit valuation.** Five sites priced a unit at `type.cost`
  — the shot's value, the counter's risk, the focus bonus, the threatened cell and the withdrawal —
  and `condition_weight` interpolates every one of them toward `cost × hp/100`, that far end being
  the board's own rate rather than a guess (`TurnRules._repair` sells the missing HP back at
  `cost * heal / 100`). Deliberately **one** dial for a unit as a target and as an asset: it answers
  what a unit is worth, while appetite for the trade already has `counter_weight`, `threat_aversion`
  and `withdraw_weight`. Defined on 0–1 and clamped in `_unit_value` as well as by `@export_range`,
  because past 1 it prices a wounded unit below nothing and inverts the sign of every reader. Move it
  with `kill_bonus`, never alone — that bonus is the other correction to the same valuation. The
  roster's own prices stay untouched: production and `UnitPricing` price a unit not yet owned, and
  `_defend_bonus` / `_consider_captures` price ground.
  AR6c: **a join is a scored candidate, in value, on the HP that survives the merge.**
  `_consider_join` sits beside `_consider_dive` and ahead of `_consider_withdraw` and every
  comparison is strict, so a merge that merely ties with a shot loses to it (Judgement D4); what is
  legal is asked of `JoinCommand.validate` rather than re-listed. The quantity is the carried HP
  because apply caps at 100 and refunds nothing, and the overflow is charged **separately from the
  dial**, at face value — destroyed HP is a funds fact the file can already price, while what
  concentration is worth is the judgement, and without the split a high weight pours fresh units into
  wounded ones. A merge is a positional trade rather than a free win (two 4-HP infantry deal what one
  8-HP does and can chip two properties) and it spends two units' turns, which is why it is weighted
  rather than ruled.
  Known and deliberate: the AR1 cache is inert with fog on, so the live game gets no speedup and
  only the offline tools do.
  AR2 is the pool that plays those matches on more than one core, and its shape is three rules.
  **`tools/balance_pool.py` decides who plays what and when; the Lab plays every match** — the
  driver launches `run_balance_sim.gd` processes and concatenates their rows, adds no loop (balance
  D1) and aggregates nothing, because a merged summary would be a second opinion about numbers
  `BalanceRunSummary` owns. **A shard is one pairing on one board over a slice of the seed range,
  and a shard whose `summary.json` exists is skipped** — the Atlas's resume rule, which holds
  because the Lab writes a shard's artifacts in one go at the end, so the marker is never half
  true. **The seed formula stays the Lab's**: `--seed-offset=` is the one flag added, so a shard
  asks for its slice of the range instead of deriving seeds a second time — which is what makes
  the merge bar hold and what it is: a merged `matches.csv` byte-identical to the same spec played
  as one Lab run (`timeline.csv` too, bar `planning_ms`, the wall-clock column the determinism test
  already excludes), interrupted-and-resumed runs included. Two consequences of that bar are
  durable. A run may only write **under `reports/`**, one policy in two places because the driver
  has to refuse a path before it launches a preset and the preset is what writes:
  `resolve_out` in `tools/balance_pool.py`, and `BalanceReportWriter.resolve_out`, which every
  `--out=` in `tools/` goes through for the write *and* for the line it prints. Godot's `path_join`
  re-roots rather than resolves, so an outside path had the Lab writing inside the repo where the
  driver never looks, and resume, keyed on a shard's `summary.json`, replayed every shard forever
  while calling each one failed. And **never sort
  `StringName`s when the order is observable**: they compare by interned pointer, so
  `BalanceMatchRecorder._tally_text` was ordering the timeline's `built`/`killed`/`lost` cells by
  whatever the process's heap said rather than alphabetically as its own comment promised; it sorts
  as `String` now, which is what makes a timeline merged from many processes reproducible. The plan's threading spike was built
  and **abandoned**: per-match determinism held bit for bit across eight threads, but eight threads
  bought 1.1× against the process pool's 3.0×, so it earns nothing and ships nothing.
  `docs/balance_sim.md` carries the measured scaling curve (peak at 6 workers on a 4+4-core M1;
  8 regresses) and is where a throughput claim about this machine belongs.
  AR3 is the grammar for "play *this* vector", and it is a **third preset over the one match
  loop**: `tools/run_ai_arena.gd` with `--red-profile=`/`--blue-profile=` naming an `AIProfile`
  file, `--pairings=<file.json>` so one process plays a whole shard, and `matches.json` — one
  record per match carrying the `Outcome` facts D4's fitness reads and nothing else, because at
  arena volume the telemetry is the dominant write cost and a pairing worth a closer look is re-run
  through `make balance-sim` with every instrument on. **`BalanceSideSpec` is untouched**: its
  grammar is watch mode's too, so a profile path is a different flag rather than a third field in
  it. Commanders are neutral by default, which makes `doctrine_weight` inert (R8) — and
  seatable per side since 2026-08-07 (`--red-co=`/`--blue-co=`, `red_co`/`blue_co` in a shard
  file), so a campaign can measure a vector with doctrines and powers live; a spec that says
  nothing still plays R8's commander-free measurement, and the pools and leaderboard stay
  commander-blind until a campaign that seats generals owns a pool split for them.
  Two things had to become single authorities for the presets to stay one engine, and both are the
  merge bar reading backwards: `BalanceMatchSchedule` owns which seeds a matchup plays and which
  seatings (including that a mirror is played once), and `BalanceMatchEngine.army_value` owns the
  margin both drivers report — the Lab now asks for both instead of deriving them, and its own
  output is byte-identical across that extraction. The bar itself is that the arena and the Lab
  play the *same matches*: 30 records against 30 rows over two boards and three pairings,
  identical in all 15 fields both emit (`docs/balance_sim.md`, "Seating an arbitrary candidate").
  The pool learned the preset rather than a second driver — `--preset=arena` selects the script,
  the shard's flags, the marker resume reads (`matches.json`) and a JSON merge sibling; the shard
  plan, the digest resume key and every Lab shard name are unchanged, and the arena's pair
  separator is `::` because a side is a path and paths carry the `/` the Lab pairs on.
  AR4 is the ruler laid over those records, and it plays nothing: `ArenaFitness` scores one match,
  `ArenaLeaderboard` tallies, `ArenaPools` says who plays where, and `tools/run_arena_report.gd`
  reads records a driver already wrote — so a finished run is re-scored after the function moves
  without replaying a match. D4: **a match is scored, not counted**, in three ordered classes a
  gradient can never cross — a decisive win is `1.0 + 0.5 × (100 − day)/100`, an unresolved match
  is `0.0` to both sides, a loss is the winner's exact negative. That zero-sum shape is what makes
  D5's "count both seatings" *cancel* the seat rather than report it: two identical vectors played
  from both seats score exactly level, measured at +37.5 pp of first-seat edge on `scrimmage`.
  The property/unit/army-value margins D4 names are **deliberately absent and the reason is
  measured**: elimination clears the loser's board (four-players D3), so in all 569 decisive anchor
  matches the loser held 0 units, 0 properties and 0 value — the margins are a constant on the
  class where they are allowed, and D6 forbids them on the one class where they vary.
  D5's two halves live apart on purpose: `ArenaPools.pairings` never *emits* a self-pairing, while
  `ArenaLeaderboard` refuses to *read* any pairing it did not see from both seats — so a mirror
  stays runnable as a deliberate calibration and unreadable as a leaderboard, which is what the
  Lab's one-seating mirror shortcut (a bias measurement) must never become.
  It refuses a second reading for the same reason: **a pool a candidate never played is the
  absence of a measurement, never a score of zero.** Only a pool *every* candidate played orders
  anything (`ranked_on`), the gaps are named (`uncovered`), and a run holding any is unreadable —
  because reading an unplayed pool as neutral sorts an untested candidate above one that was
  tested and lost, which is the exact inversion the held-out ordering exists to catch, and
  train-many-validate-few is what AR5's search produces.
  D6/D7: the horizon is 100 days, `command_cap` is a hard invariant failure of the run, and the
  pools are split by **board and seed** with the three shipped tiers as never-retuned anchors.
  `ArenaPools.pool_args()` is the one statement of a pool — `make arena-anchors ARENA_POOL=` reads the
  play command out of it and `pool_of()` reads finished matches back against the same split, so a
  leaderboard can never be scored against a split nothing played.
  **AR4's acceptance check failed, and the failure is the finding**: the arena at 100 days ranks
  the tiers Difficult > Normal > Easy on the training pool, the held-out pool and all nine boards
  measured — not the Atlas's inverted Easy > Difficult > Normal. It is not the scorer (raw win
  rate and a gradient-free score give the same order), it *is* board-dependent (Easy beats Normal
  on 3 of 9 boards, and swapping one board of four flipped a whole pool), and the Atlas predates
  the Judgement and Economy dials the shipped planner now carries. Nothing was tuned toward the
  wanted answer. `ironworks` is out of the pools for a measured reason worth knowing:
  it was the only board to reach the match-level command cap at a 100-day horizon (once in 72) —
  a cap then sized for 20-day gates rather than a board to distrust, since corrected (AR5 below),
  so re-admitting it is a measurement no campaign has yet taken.
  AR5 is the search laid over all of it, and its verdict is `docs/ai_arena_results.md`.
  `make arena-search` (`tools/arena_search.py`) proposes on a snapped lattice, plays through the
  pool and scores through the report — **blocks of dials, never one joint optimisation** (R5), and
  `tools/arena/arena_blocks.gd` is the space, GDScript beside `ArenaPools` so a block cannot name
  a dial `AIProfile` does not carry: that coverage rule is what caught `defend_weight`, live at
  2.0, sitting in no block. The campaign's one engine change is the match-level cap:
  the flat `COMMAND_CAP` of 3 000 became `BalanceMatchEngine.command_ceiling(days_cap, teams)`,
  an exact upper bound on legitimate play rather than an estimate of it, after all twelve
  first-campaign stalls replayed clean to the day cap — reaching it now means **the day stopped
  advancing**, never that a match was big, so AR4's hard-invariant rule stands with its trigger
  fixed, and both committed balance reports are byte-identical across the change (balance plan
  D1). D8 held: no `data/` file moved, every champion lives under gitignored `reports/`, and AR7
  is where one gets read at a table.


## `four-players-plan.html`

- `four-players-plan.html` — up to four armies, milestones FP1–FP6, **all shipped**: FP1 (the
  roster becomes data), FP2 (hostility gets one authority), FP3 (an army can fall, a side can win),
  FP4 (four liveries on one board), FP5 (seats and sides at the table) and FP6 (the boards, and the
  proof of play).
  D1: **the map is the roster authority** — `MapData.teams()` / `player_count()`
  are read off the seats a board's `[owners]` and `[units]` name, `GameState.create` copies that
  into `GameState.teams` and starts on `teams[0]`, and how many armies play is never a menu
  setting. Ask `state.teams` for who is playing; `GameState.TEAMS` survives only as the legal
  maximum and is re-exported from `MapData.PLAYER_TEAMS`, which enforces `1..4` per line at parse
  so the bound has one owner. The plan's "contiguous from 1" as a *validated* rule is superseded by
  the rule that replaced it: a roster is a **range** — seat 1 up to the highest seat the board
  names, floored at a duel (`MapData.DEFAULT_TEAMS`) — so contiguity is structural rather than
  breakable, and the many fixtures that name a single team keep playing the duel they always did
  (the exact-set reading seated a one-army roster and moved turn rotation, upkeep and repair).
  The save format is version 9 (`core/save_codec.gd`'s header is the ledger of what arrived when;
  the campaign-depth entry above owns 9's own field): the roster arrived at 4, the grouping at 5,
  the fallen at 6 (the plan's "save v4 carries `eliminated`" is superseded by that ordering), each
  army's home HQ at 7 —
  a save below v7 takes its home HQs from the map it names, which is exact because such a save
  always seated the board's full roster — and Second Wind eligibility at 8; a save below v8
  defaults every unit to ineligible rather than granting an unverifiable extra action. An older save decodes as
  the free-for-all duel it recorded with every army it names still standing, and
  `SaveCodec._teams_error` / `_sides_error` / `_eliminated_error` / `_home_hq_error` refuse a
  roster, grouping, casualty list or home-HQ list no seating could have produced *before* any
  per-side check is derived from it (a roster with a gap, `[1, 3]`, is now an ordinary reduced
  match rather than damage — open-seats D1).
  `tests/unit/test_maps.gd`'s HQ and base lints hold each board to its **own** roster, never a
  global constant. D2: **`GameState.allied(a, b)` is the single hostility authority** — ask it,
  never re-derive `team != mine`; `sides` (empty = free-for-all) is the grouping, `enemies_of` and
  `side_of` are its two readings, and every site that used to compare team ints goes through it:
  attack and capture targeting, movement pass-through and ambush, vision, the AI's enemy set and
  threat map, the doctrines' `_opponents_of`. Allies share sight — `Vision` composes a side's
  visible set as the union over its member armies, so every viewer inherits it without composing
  anything — and purpose, **never infrastructure**: funds, production, repair, resupply, join and
  transports all stay `owner == unit.team`. The grouping is the *match's* choice, not the board's,
  so it rides on `MatchRequest.sides` and `BattleSetup.build` writes it onto the state — the plan's
  "sides from `MatchConfig`" is superseded by the rule that `MatchConfig` carries exactly one typed
  request and nothing else. Its two writers are the menu's seat strip and `--sides=` (D6).
  D3: **elimination is a modelled state and victory belongs to a side** — `GameState.eliminated`,
  `is_eliminated` and `active_teams()` say who is still in; ask them, never infer a fallen army from
  an empty unit list (one with no units on day one has not fallen). An army falls when its last unit
  dies (`_check_rout`, on the shot itself) or its **home** HQ is captured — `GameState.home_hq`,
  recorded by `create` from the map's starting ownership and carried in the save; any other HQ (a
  vacant seat's, or one a survivor conquered) is a high-value property captured like a city — and
  `eliminate()` is the one way
  out: units removed, properties to **neutral** rather than to the conqueror — handing a fallen
  empire to the side already winning would snowball it, while loose ground stays contested and any
  survivor can go and take it — and the capture progress standing on them cleared (that progress is
  a survivor's, so a nearly-finished capture is lost). The match resolves when every survivor
  shares one side. `winner` stays **scalar, the winning side's lead army**, so every `winner != 0`
  gate, the Balance Lab's outcome and watch mode's diffable line are untouched; `winners()` is the
  presentation reading and lists that side's **survivors only** — an ally that fell on the way did
  not win. `next_team()` skips the fallen, the day advances on wrap to the first surviving army, and
  income never runs for one. In a duel the first elimination is still the victory, same day and same
  winner: that parity is the merge bar, pinned by the existing rout and HQ tests plus
  `tests/unit/test_elimination.gd`. Because elimination now clears the loser's units on *both* win
  paths, `BalanceMatchEngine.termination(state, cap_stall, hq_captured)` is **told** an HQ fell
  instead of inferring it from an empty board — the sim gained no telemetry hook (balance plan D2) —
  and a fallen army ending with nothing is why FP3 is the one accepted departure from the byte-diff
  bar: `commander-balance`'s `matches.csv` moves only in `blue_props` / `red_props` / `blue_units`,
  always to 0, always for the loser, with every decision-bearing column and `difficulty-check`
  identical. The AI's `hq_capture_multiplier` was priced when an HQ ended the match and now buys an
  elimination; the FP6 soak looked and left it alone, so it stays as priced. Same answer for
  `ThreatMap`'s cap on incoming damage: it flattens the gradient as rivals multiply, and the soak
  found matches concluding with the AI capturing, building and firing powers throughout, so neither
  number is retuned. If the AI ever does visibly cower on a crowded board the fix is an `AIProfile`
  weight, not code.
  D5: **four armies get four faces, and every face is presentation.** Both of `SideIdentity`'s
  fallback orders hold all four theme keys with their first two entries untouched, so every
  two-army resolution is byte-identical to before and iron/verdant only ever come up on a board
  seating a third or fourth army — which is what makes "no two sides share a colour" *provable*
  (four keys against at most four armies) rather than true so far, and `_fallback`'s neutral escape
  unreachable. Unreachable matters: `BattleView._last_seen_owner` maps an atlas row back to a team,
  so two sides sharing row 0 would name the wrong owner. An army falling is announced through the
  ordinary turn banner — the pipeline reports it on `BattleCommandReceipt.fallen`, the flow layer
  says it: `Battle.conclude_command` awaits the banner **before** the turn hands over, so it lands
  on the board that produced it, and suppresses it while `animator.capturing` like the cut-ins.
  Elimination is public information, fog or no fog. The victory lockup reads `winners()` so a
  victory that belongs to a side names the side, de-duplicated because two allies may share a
  faction ("wins!" for one name, "win!" for several); the standings line under it reads
  `GameState.eliminated` in insertion order — the order of the match, not of the seating — and is
  empty on a duel, where the one elimination *is* the victory. Watch mode's diffable line is
  untouched. The commander info sheet takes the roster whole (`open(commanders_by_team, sides)`),
  one card per seat two to a row with allies adjacent, and `CommanderInfoSheet.layout_error` is what
  the `commander_info` smoke scenario reads the open sheet back against — the sweep's bar is a file
  size, and a sheet with collapsed columns wrote a healthy PNG. The bar's unit card gains one
  allegiance word, asked of `GameState.allied` and relative to `BattlePerspective.viewing_team()`,
  never to whoever holds the turn.
  D7: **`Battle._last_human_team` is the one key for both the viewer and the handoff** — while a
  computer plays, the board renders through the fog of the human who played last, information they
  already had; a human turn blacks out whenever the previous *human* seat was someone else, across
  any number of intervening AI turns. One human at the table is never asked to hand the device to
  themselves, and two humans hot-seating gate exactly as they did before four armies.
  D6: **`scenes/menu/seat_strip.gd` (`SeatStrip`) is the menu's one answer to who sits at the
  table, who plays each army and who stands with whom** — it takes the board's roster and hands
  back `seats()`, `ai_teams()` and `sides()`, and the two mode buttons it replaced are gone, so no
  menu state mirrors any of those facts. A seat's third state is **Empty** (open-seats D4), offered
  only while closing it leaves at least two seats filled — so a duel board never builds the button
  and its setup screen stays pixel-identical, and the last two filled seats of any board cannot
  close. A closed seat wears no side badge: it brings no army, so it stands on no side, and the
  sides re-pack over the filled seats (`normalised_sides` / `reopened_seats`, both static and pure
  so the shrink path is checked without a scene). The presets are tables — Duel and Three-way
  joined the row — each setting a seating *and* a grouping (Duel fills the opposite pair 1+3, the
  fair one under the four-seat boards' authoring convention). A free-for-all
  is the **empty** dictionary, from the strip and from `MatchRequest.parse_sides_flag` alike, because
  that is what `GameState.allied` reads as "every army its own side" and what every match carried
  before groupings existed. `--sides=1+3v2+4` is that flag's grammar, `--red`/`--blue` stay developer
  vocabulary for seats 1–2, and an unreadable grouping is refused out loud and dropped to the
  free-for-all rather than half-applied — as is one allying a seat the same launch closed
  (`BattleSetup._sides_off_the_roster` draws the line: refused only when the board deals the seat
  *and* this match closed it; a grouping naming a seat the board never deals stays tolerated, being
  one written for a wider roster rather than a contradiction). The computer's seats are narrowed to
  the filled table *silently*, unlike the grouping, because nothing a player types can reach
  `ai_teams` — it is the request's own default or `--watch`'s roster, and narrowing a default is
  not discarding an instruction. Whether a grouping leaves anybody hostile is the *board's*
  answer, so `BattleSetup.build` asks `GameState.enemies_of` once a roster is loaded and plays the
  free-for-all if nobody is opposed — no flag can see the seats. Difficulty stays match-wide by the
  ticket's instruction, asked of the seats (a table with no computer has nothing to tune) rather than
  of a mode; per-seat tiers remain the Balance Lab's CLI grammar. Commander select is a slot walk of
  the filled seats — one chip and one confirm per seat that plays, with picks, chips and liveries
  keyed to the seat's own number — emitting `confirmed(picks: Dictionary)`, with Back rewinding one
  seat, and it gained the same kind of capture gate the setup panel has had since COM-5
  (`chrome()`), because
  a bar that grew from two chips to one per seat can run off a 640px frame. `SeatStrip.layout_error`
  is the sibling of `CommanderInfoSheet.layout_error` and exists for the same reason: unsorted rows
  stack at the container's origin, inside every frame and drawn in none of it, so enclosure alone
  photographed the strip as bare panel.
  `maps/compass.txt` (four armies at the compass points), `maps/foursquare.txt` (four seats at the
  corners of a 12×12 build-first board, the four-way answer to Forge — added after this plan by
  COM-128), `maps/heartland.txt` (four corners of a 28×20 great plain, the grand tier's first —
  two bases a seat and a 48-city lattice because the tier scales economy with area, laid out under
  the rectangle's own mirror symmetry since 28×20 cannot quarter-turn, so the fair duel's opposite
  pair is an exact half-turn — added after this plan by COM-133), `maps/pinwheel.txt` (four corners
  on a 14×14 whose road blades run clockwise into the
  next seat's flank around a wooded hub — added after this plan by COM-129), `maps/atoll.txt` (four
  home shores on a closed ring of land around one lagoon, a port each and a neutral island of
  cities in the middle — the four-army naval board, added by COM-131 under the open-seats plan's
  OS3), `maps/trident.txt`
  (three around a central massif), `maps/marchlands.txt` (22×16, the board built for the 2v2 —
  seats 1&2 north of a wooded ridge, 3&4 south, so `--sides=1+2v3+4` is a shared front; a
  non-square board has no quarter turn, so it closes under the rectangle's two flips and half turn
  instead, which its header explains — added by COM-132, the open-seats plan's OS3) and
  `maps/windrose.txt` (COM-130's four-seat air board: 17×17 under an exact quarter turn about its
  centre cell, an airfield per seat plus a contested neutral one on the centre, and the one
  board whose armies started holding cities until Bulwark — air frames are expensive and the soak
  had to show aircraft actually built), `maps/causeway.txt` (30×22, four island homes bridged to a
  neutral mid-sea chain — added after this plan by COM-134), `maps/confluence.txt` (32×24, two
  bases, an airport and a port to a seat, four tidal arms running into one central sea, and a
  harbour island of neutral docks nothing walks to — added after this plan by COM-135),
  `maps/coal_and_crown.txt` (24×16, the second board to declare a `# grouping` and the first 2v2
  authored not level seat by seat: seats 1&2 north with three bases and two cities each, seats 3&4
  south with one base and four cities each, twelve properties to a side either way, mirrored left
  to right so allied seats are exact reflections — the missing factories paid for in broken ground
  and one extra mech a southern seat, never in property, which is what keeps D3's ceiling clear)
  and `maps/bulwark.txt` (49×32, the 3v1 board that is unfair on purpose — the
  `asymmetric-board-plan.html` entry below owns its facts, and it is the named exception to this
  entry's kind-for-kind parity and to D5) are the shipped
  boards that seat more than a duel; Compass was pulled forward into FP5 because without one the
  seat strip is UI no
  player can reach. **Every army has to be able to march on every other** — the AI cannot plan a
  ferry (naval R1) — which is why most of them carry no water at all. Atoll, Causeway and
  Confluence are the three that do, and a four-army water board has to hold that rule *and* keep
  the sea one body every port opens onto, or the fleets it lets you build can never meet: Atoll by
  closing its land into one ring around the lagoon its ports all open onto, Causeway by keeping its
  land a tree with no loop in it and no cell on the board edge, Confluence by stopping every river
  arm short of the edge so the coast walks around it. Their ferry-only prizes — Atoll's island of
  cities, Confluence's harbour of docks — are ground the AI deliberately leaves alone. Both rules
  already have lints — `test_maps.gd` keeps every HQ reachable on foot, every port on one shared
  body of water, every offshore property landable from a dock and no shoal chain quietly bridging
  two landmasses — so none of the three needed a new one; what is authoring rather than lint is the
  *shape* that satisfies them, so keep the ring, the tree and the short arms if you edit one. None
  carries the `# symmetric` tag: that lint is a *duel* instrument — Foursquare's and Windrose's
  layouts close under a quarter turn, not the tag's half turn — and fairness on these is by
  design review instead (rotational or mirrored layout, one HQ and a base per army held by the
  FP1-retargeted lints, every seat
  opening on the same properties kind for kind held by `test_maps.gd`'s property-parity lint —
  because no three- or four-seat board can carry the tag — and the win spread
  across seats in the soak). That last instrument is load-bearing: Compass's first layout passed
  every lint — one HQ and
  one base an army was true of it — and still gave two of the four armies cities 2–3 tiles out while
  the other two walked 5–6, which showed up only as free-for-all wins spanning two seats of four. The
  cities are now a ring closed under a half turn, every army's nearest two at exactly 4 and 5 tiles;
  keep that property if you edit the board, because no lint holds it. 3v1 is deliberately asymmetric
  — a challenge grouping, compensated by commander pick and tier, never by the board.
  `tests/unit/test_alliance_soak.gd` plays the shipped boards in the
  groupings their seat strips offer, not only the fixture: a grouping that ran only on a fixture is
  a capability nobody can pick.
  `maps/fixtures/quartet.txt` stays a fixture, out of the menu and out of the per-map soak — though
  `tests/unit/test_maps.gd`'s *playability* lints do reach every fixture through
  `MapCatalog.fixture_paths()`, so it is held to them like any board — sized to fit
  the battle viewport whole, and the board `make smoke`'s `side_victory` and `mixed_seat_handoff+fog`
  scenarios run on. The plan artifact carries its own milestone pass: FP1–FP6 are marked shipped in
  `.lavish/four-players-plan.html`, whose decisions stay as authored — every supersession is here.


## `asymmetric-board-plan.html`

- `asymmetric-board-plan.html` — Bulwark, the board that is not fair on purpose: one entrenched
  army holding a rampart against three allies, milestones AB1–AB4, **all shipped**. It is the
  named exception to four-players D5 ("3v1 is deliberately asymmetric — a challenge grouping,
  compensated by commander pick and tier, never by the board"), which stays the rule for every
  other board: **a board may compensate a grouping when it is authored for that grouping and
  declares it.** D1: **the handicap is board state and nothing else** — no handicap multiplier, no
  starting-funds field, no per-seat difficulty, no boss flag; the lone army's advantage is entirely
  `[owners]`, `[units]` and terrain. D2: **`# grouping 1+2+3v4` is a claim the lint checks, never
  an instruction the match follows** — read in `MapData._read_comment` beside `SYMMETRIC_TAG` and
  exposed as `MapData.grouping`, which is the **raw declared text and nothing more**: `core/`
  interprets none of it, the tag has no runtime, and a board carrying it plays whatever grouping the
  launch says. Its only reader is `tests/helpers/map_parity.gd`, driven by `tests/unit/test_maps.gd`
  and `tests/unit/test_map_grouping.gd`, and it turns the string into sides through
  **`MatchRequest.parse_sides_flag`** — the shipped authority for that grammar — rather than
  re-reading `1+2+3v4` a second time in `core/`, which is also why the tag is a String: `core/` may
  not reach `scenes/`. Four-player-maps D5 is respected rather than superseded, the tag not being a
  parser feature in the sense it forbids. D3: **parity moves from the seat to the side and is not
  switched off** — `MapParity.error` is the one answer to what "level" means, untagged boards get
  the seat-by-seat kind-for-kind check verbatim (which is every shipped board), and a tagged board
  gets two checks instead: allied seats identical **kind for kind**, and no side out-owning the sum
  of its opponents by **plain total count** — a ceiling rather than a judgement, because a lint
  cannot say whether 30-against-36 is fair. **AB1 settled that ceiling as one-directional**: a side
  is held to it only while it fields no more armies than its opponents combined, because a side with
  more armies is expected to hold more ground and the defect D3 names is one army out-owning three,
  never three out-owning one. Read symmetrically it collapses into "both sides hold exactly equal
  totals" on any two-sided grouping and rejects the plan's own 36-to-30 Bulwark tally. The price is
  paid on an equally seated grouping — in a 2v2 neither side out-seats the other, so neither is
  exempt and the ceiling there *is* equal totals. The rejected alternatives are an `# asymmetric`
  opt-out that skips the lint outright and a filename exemption list inside the test. R5 is the
  guard that keeps the tag from becoming that opt-out anyway and is enforced, not just written
  down: **a tagged board whose seats already open level fails**, as does a tag that reads as a
  free-for-all — if the opening is fair seat by seat the tag is unnecessary and belongs deleted. D4:
  seat 4 is the lone army, so `SeatStrip`'s shipped 3v1 preset fits without a line of UI. D6: the
  lone army's edge is **interior lines** (a lateral road behind the rampart), never a bigger pile,
  which is the failure mode a retune is most likely to drift back into. D7: land only (naval R1).
  `maps/bulwark.txt` is the board, AB2: 49×32 and twice the largest that shipped before it. Its
  **terrain and property ownership mirror exactly about column 24** (not the half turn
  `# symmetric` checks, and **nothing lints that mirror** — keep it if you edit the board), while
  each seat's four starting units are laid out **seat-identically** — translations by 16, not
  reflections — because seat-identical armies are what open the three allies on the same match, and
  seat 2's could not be self-mirrored anyway: a centred recon would stand on its own airport at
  (24,2), and no unit may start on a property. Seats 1/2/3 on the north edge hold 12
  properties each and seat 4 on the south holds 30 against their 36. Its rampart is three rows at
  y 16–18 whose middle row 17 is mountain wall to wall except four two-cell passes — rows 16 and 18
  mix woods a vehicle can enter, so row 17 is the wall — and the rule that makes the board a
  battle rather than a siege was **read out of the terrain data rather than designed in**:
  `data/terrain/mountain.tres` moves `foot`, `boot` and `air` only, so armour must come through 8
  cells of frontage across 49 while infantry (`foot`, 2 a step) and mech (`boot`, 1 a step) climb
  anywhere on a 49-cell front.
  As the largest board in `MapCatalog.ordered()`, Bulwark is now what `main_menu.gd`'s
  `_paint_backdrop` bakes, so the menu's animated backdrop moved from Confluence to Bulwark and its
  drift period grew accordingly — nothing gates on it (no committed golden PNGs), recorded here the
  way the field-overlays entry records frame movement.
  R4: `BalanceMatchEngine` plays two sides, so the board is invisible to `make commander-balance`
  and `make difficulty-check` — both reports staying byte-identical is the merge bar, and the
  fairness number comes from AB3's own instruments and nowhere else. Those are two, and the split
  is R3's: `tests/unit/test_alliance_soak.gd` soaks Bulwark **in its own grouping first** and then
  the free-for-all — the Marchlands treatment, one seeded match each, and a *legality* check (no
  rejected command, no stall) rather than a fairness one — while **`tools/run_bulwark_measure.gd`
  (`make bulwark-measure`) is the win spread**, many seeds at a 100-day horizon, and it lives in
  `tools/` because R3 says the dial when the suite's wall clock bites is the measurement's seed
  count, never the board. It plays `_soak`'s own loop rather than a preset over the balance engine,
  writes through `BalanceReportWriter.resolve_out` like every other tool, seats **no commander** (the
  soak seats doctrines on purpose; this measures the board), and states `sides` directly — never off
  the tag, which stays the lint's alone (D2). **`docs/bulwark_balance.md` is the committed record**
  and the number AB4 reads: at n=20, a direction rather than a magnitude, the alliance takes 73.7%
  of decided matches under the board's own 3v1 and the bulwark 26.3%, while in the reachable
  free-for-all the bulwark takes 89.5% — which is the design working, one concentrated army against
  three separate ones, and not the grouping the board is authored for. AB3 measures and does not
  tune, the same split as the Judgement plan's AJ4.
  **AB4 is the retune, and its finding is that the board did not need one** — `maps/bulwark.txt`'s
  terrain, ownership and starting armies are AB2's unchanged, its header alone gaining the two
  guardrails below, and the milestone's deliverable is `docs/bulwark_balance.md`'s
  AB4 section. Four board-only candidates were measured and every one of them lost to leaving the
  board alone, which also cost AB3's headline its authority: **the unchanged board reads 64.1%
  alliance over 40 seeds**, not the 73.7% the first twenty said, so an edit justified by that figure
  would have been an edit justified by noise. The candidate that looked best (a second mirrored pass
  pair, 4 → 6) is **indistinguishable from the shipped board** — 11–9 to the alliance on both over
  twenty fresh seeds, the whole n=40 gap being one previously-undecided match — and shipping it would
  have widened the rampart's frontage from the 8 cells the header, the plan's §2 and this entry all
  state, for nothing. Two guardrails come out of the losers and are worth more than the retune was:
  **the belt is not a dial that helps the bulwark in either direction** (poorer cost it 11 points,
  richer took it to zero), which refutes R1's own "the dial is the garrison and the belt"; and
  **closing passes is the worst thing that can be done to this board** — halving them gave the
  alliance 20 of 20, because the garrison needs the passes to sortie as much as the alliance needs
  them to push, while infantry ignores them and crosses on a 49-cell front. **Do not narrow the four
  passes.** D6 held throughout: no unit and no base was added to any seat, which is the drift D6
  names AB4 as most likely to fall into, and the one untried lever — the garrison's size or
  placement — is D6's discouraged one, now with measured evidence behind reconsidering it rather
  than an assumption.


## `campaign-depth-plan.html`

- `campaign-depth-plan.html` — what the six shipped campaigns cannot yet say: mission variety
  beyond capture-the-HQ, scripted mid-battle events, a consequence ledger carried between missions,
  the army a mission hands the next one, interludes and optional missions, across all six wars.
  Milestones CD1–CD8, **all shipped**. It is the design of record for the campaign's *depth*;
  the **Campaign mode** entry below stays the record of the campaign layer's own architecture (the
  data shape, `MissionRuntime`'s precedence, `CampaignSession`, the progress file), and the two are
  read together. It retired exactly one clause of that entry — D2's "no evacuate/escort/convoy
  objective exists on purpose", which CD2 made sayable — and supersedes nothing
  else there. The diagnosis was the number: 86 of 108 authored objectives were `CaptureCell`, the
  skirmish win condition with a label on it, and `DayDeadline` the only failure condition in the
  game, so the vocabulary could not express the beats the treatments were written for.
  Its locked decisions are what a future reader must not break; the seven below are the load-bearing
  ones, and the plan carries the rest (D8 the in-battle panel and speech overlay as presentation,
  D9 the content gate).
  D1: **an event effect is a `Command` issued at the one broker, never a direct board write** —
  reinforcements arrive, a garrison defects and a bridge falls through the same
  `BattleCommandPipeline.execute` a player's click reaches, so an event lands in the log, the save
  and the replay with no special case, exactly as the aimed power did (`more-commanders-plan.html`'s
  D2, applied to a script).
  D2: **a trigger is a pure read of the committed board plus the mission's own saved tally** —
  same rule as an objective (Campaign mode's D2), so a trigger cannot depend on a half-applied
  command, on animation, or on anything the sim has not settled.
  D3: **events fire before the verdict, and a boundary settles whole** — `Battle.conclude_command`
  runs fallen-army banner → due events → `CampaignSession.decide`, or a mission ends on the turn
  its own relief column was due; `MissionRuntime`'s own precedence is untouched, events being a
  step in front of that class rather than a case inside it.
  D4: **`Unit.tag` is INERT DATA and the plan's one `core/` waiver** — a `StringName`, empty by
  default, authored as the optional fifth column of a map's `[units]` row and carried in save v9;
  nothing in `core/rules/`, nothing in `ai/` and nothing in the damage chart reads it, so a named
  unit fights, moves, is priced and is planned against identically to an unnamed one, and the
  balance byte bar is what stands in for the waiver (the arena plan's D1 waiver, same shape). The
  rejected alternative is identifying a unit by the cell it started on — a unit that moves stops
  being identifiable, and a protect objective matters precisely when the unit is moving. What a
  tag may *be* is `core/unit_tag.gd` (`UnitTag`) and nowhere else: legal identifier, unique per
  board, asked by `MapData` row by row as it parses and by `SaveCodec.validate` over a decoded unit
  list, because a save is the second door onto the board and a tag naming two units names neither.
  D5: **a flag chooses authored content, never a number** — `CampaignState.flags` is a ledger of
  integers written by a `SetFlag` effect or by mission completion (CD4 settled *when*, below), and
  it reaches the board
  only by picking which authored thing is used (a variant briefing line, a conditional starting
  unit, whether a mission opens); it may not hand a mission more funds or a weaker AI, or a campaign
  becomes a second, invisible balance surface. Nothing in `core/` or `ai/` reads one.
  D6: **the carried army fills authored slots and never appends** — a board authors carry slots and
  the map's own unit stands in any the roster cannot fill, so every board still fields exactly the
  army it was balanced for; what carries forward is HP, tag and identity, never force size. The
  rejected alternative is survivors appended to the map's army, which invalidates the authoring of
  all 108 boards at once and in both directions.
  D7: **`CampaignDefinition.missions` stays the only source of order** — branching is
  `MissionDefinition.unlock_requires` narrowing that list rather than forking it, which makes an
  unreachable mission structurally impossible to author, and `is_complete` counts only missions that
  could have opened.
  **CD2 shipped the objective vocabulary and the in-battle card, and settled what the plan left
  open.**
  `DestroyUnit`, `ProtectUnit`, `ReachCell` and `DefeatTeam` are pure reads of one board;
  **only `HoldCell` and `LossLimit` need the tally**, which is why `MissionProgress` is counters
  rather than a general mission-state bag — CD3's fired beats and revealed objectives are keyed
  counters like any other, which is why the profile format did not move — and why `is_met` /
  `readout` /
  `definition_error` take their extra parameter **required, never defaulted** — a caller that forgot
  the tally would silently read "never held, never lost", a mission nobody can win. Losses are a
  **set difference** over the instance ids of our side's units between two boundaries, never
  "started with, minus have now" (a unit built between them masks a unit killed between them), and
  the consequence is stated on the class rather than special-cased: a `JoinCommand` merge reads as a
  loss, because a board diff cannot see which way a unit left and D2 forbids a hook that would tell
  them apart. **The tally follows the board, not the mission** — `CampaignSession.begin` is handed
  the resumed tally by the caller already reading the profile, so a resume inherits its losses and a
  retry starts clean. `MissionObjective.readout()` is the one addition to `core/` the plan did not
  name: the panel must not re-derive a deadline or a count off an objective's `@export`s, and an
  objective already carries authored presentation copy in `text`.
  **D8 is corrected, not followed**: it said the panel is suppressed while `animator.capturing` and
  under Instant so `make smoke` stays byte-stable, which would hide it in the one scenario that
  exists to photograph it. The shipped gate needs no opt-out — `MissionObjectivesPanel` is down
  unless `CampaignSession.active()`, and no capture stages a mission except its own — and the plan
  artifact carries the amendment. A campaign board is not in `MapCatalog`, so the `objective_panel`
  scenario deploys through the shipped `CampaignSession.begin` → `MatchConfig.stage` pair
  (`BattleMissionScenario`) rather than widening `--map=`, and clears the session after the frame so
  the next `menu_` scenario in the same process opens a menu rather than a campaign hub.
  **The card is the one piece of chrome that covers board, so `O` lowers and raises it** (added
  after CD2): a lens key like `T` and `R`, stated as a chip on the top bar
  (`ControlHints.OBJECTIVES_CHIP`) rather than in the per-context legend, and unlike those two the
  chip is off the bar entirely outside a campaign — a key that would do nothing is never
  advertised, which is also what keeps every skirmish frame byte-identical. Whether the card is up
  is the **panel's own** state, not `Battle`'s: `MissionObjectivesPanel.toggle` flips it and
  `card_changed(available, up)` is what lights the chip, so `Battle` gains one branch in its input
  chain and no mission state, and `BattleView` gains no public method (it sits at the
  `max-public-methods` ceiling). Every mission opens with the card up — the terms are the first
  thing a new board has to say — and it is deliberately not a device preference. `refresh` does
  nothing beyond the chip while the card is down, so the card is redrawn on the way up rather than
  merely shown.
  **CD3 shipped the event system on D1/D2/D3 as written; what a future session must not undo is
  below, and the plan's own "What CD3 settled" carries the rest.**
  A `MissionEvent` is triggers (a **conjunction**, so a small vocabulary stays expressive) plus
  effects plus lines, and the two libraries are `core/campaign/triggers/` and
  `core/campaign/effects/`, one question or one deed a file, on `MissionObjective`'s contract
  verbatim. `BattleCampaign.fire_due` is the seam and it cannot re-enter: `conclude_command` calls
  it and it never calls back, so a beat's own command settles inside the pipeline. The opening board
  is the one boundary with no command behind it, and it is what `DayReached { day: 1 }` is written
  against.
  **The campaign and mission ids ride in the replay *header*, never in the opening** — the opening
  stays `SaveCodec.encode` verbatim as the replay plan's D1 requires, a `MissionEvent` reference is
  not something a file can carry, so an event line names its beat by id and playback resolves the
  pair through `CampaignDB`; a skirmish header names neither and is byte-identical to before.
  `ReplayCodec.FORMAT` is 4 and older recordings are refused outright (replay D3), and a recording
  whose mission no longer resolves is refused **by name in `BattleSetup`** before a single command
  replays, because a playback that runs correctly up to the moment the story happens is worse than
  one that never starts.
  Two rules were read off the shipped design rather than invented: a scripted removal **banks
  nothing to either charge meter** (Hammerfall's D4 — charge is minted inside
  `ChargeLedger.bank_losses` and nowhere else), and **a defection does not rout the army it
  empties**, a rout being reached only through `remove_unit`. `SpawnUnits` **skips an occupied cell**
  rather than clearing it, Hammerfall staying the only thing in the game that removes a unit without
  a shot. A defecting unit takes its cargo, its capture progress and its turn (`acted = true`) with
  it, each with its reason on the class.
  **D8 is exceeded rather than met**: `MissionSpeechCard` reads *nothing* — its lines are handed
  over by the command, the way `_present_power` is handed its commander — which is what makes a
  replay speak the same words. **R7 needed no `ai/` code**: `AIPlanCache` already drops on a board
  diff, so a scripted removal reads as a unit that left and a defection as one that changed team;
  the milestone owed the tests and `tests/unit/test_ai_plan_cache.gd` carries them.
  A hidden objective needs a stable save key, so `MissionObjective` gained `id` beside `hidden` and
  `MissionObjective.is_live` is the one answer to whether a condition is being judged yet:
  `MissionRuntime._live` skips an unrevealed one wherever it walks a list, and
  **`MissionObjectivesPanel` asks that same authority rather than printing the authored lists**, so
  the card shows exactly the conditions the verdict is reached on and a held-back objective — a
  failure most of all, which printed would name the trap — stays off it until a beat reveals it.
  `MissionDefinition` refuses a hidden objective no event reveals, that being a mission that cannot
  be won and has no other symptom. A mission with nothing hidden is judged, and drawn, exactly as
  before.
  `Flag` and `SetFlag` were held back to CD4 — a trigger reading a ledger that does not exist is
  untestable; `DayBefore` was added in their place, because
  `ObjectiveMet` plus `DayBefore` is "did it, and did it fast", which is how a later ledger records
  the player being good rather than only recording damage. Six exemplar events ship, one per
  campaign, all in missions CD2 had already re-authored so they stack rather than spread; the other
  102 are CD7's. `battle.gd` **shrank** 1415 → 1396 by extracting `BattleRecording`, and its budget
  in `tools/check_scripts.sh` fell with it — the answer to a line budget is extraction, never a
  raise.
  **CD4 shipped the consequence ledger on D5, and what a future session must not undo is below;
  the plan's own "What CD4 settled" carries the rest.**
  **A flag-conditional starting unit needed no new mechanism** — CD3 already fires beats on the
  opening board, so "this board opens two defenders short because the bridge went down in mission
  five" is an ordinary event with a `Flag` trigger and a `SpawnUnits` effect. That is the whole of
  D5's board reach, and it is why a flag structurally cannot touch a number: the only thing a flag
  does to a board is decide whether an *authored* beat fires.
  **A flag is staged mid-mission and committed on the win**, which supersedes D5's "written by a
  `SetFlag` effect" read literally: `SetFlagEffect` changes no board and `MissionEventCommand`
  collects it, `CampaignSession.record_event` stages it into the tally, and
  **`CampaignState.complete` is the ledger's one writer** — the same answer CD2 gave the tally, for
  the same reason (a retry must not inherit an abandoned attempt's writes, or an `ADD` flag counts
  twice per attempt). The author-facing rule is one sentence: *a mission reads the war as it stood
  when it began, and writes to it when it is won.* A `Flag` trigger therefore reads the same way
  every time a mission is played, which is what keeps a scripted opening deterministic.
  **A replay of an already-cleared mission does not rewrite the ledger** — `complete` takes the
  staged facts only on the first clear, found by test rather than by reasoning (an `ADD` flag read
  2 after a replay); stars and best day still improve best-not-last, unchanged. `complete` returns
  whether the ledger took, which is the only thing the debrief's `RECORDED` lines are printed off —
  a screen claiming a change that did not happen is worse than one that says nothing.
  **`cleared:` and `stars:` are derived, never stored** — `CampaignState.flag` answers them off
  `records`, so there is no second copy to drift and a later mission asks after a cleared mission in
  the same words it asks after an authored fact; `SetFlagEffect` refuses a derived name and
  `CampaignSaveCodec` refuses a stored one.
  **`FlagCondition` carries both bounds** (`at_least` **and** `at_most`), because a ledger with a
  floor alone can record that something went wrong and never that the player was quick or careful,
  so "the war carries between missions" would only ever mean "it gets worse".
  **Variant `MissionLine`s are independently included, not alternatives** — `MissionLine.spoken`
  is the one filter both the hub briefing and the debrief read through, every line whose condition
  holds is said in authored order, and an either/or is two adjacent lines with opposite conditions;
  a group construct would need a default and an all-failed fallback nobody wrote. A beat's own lines
  may **not** be gated (`story_error`): a recording re-issues the beat and must speak the same
  words, so a beat the war decides is a beat with a `Flag` trigger.
  `MissionTrigger.is_met` grew a **defaulted** `ledger` parameter across all seven shipped triggers
  — GDScript requires an override to match the base signature — and null is a mission played
  outside a campaign profile, where every fact reads zero.
  CD4 took the campaign profile to **VERSION 3**, a section of its own rather than a key smuggled
  into 2, because `validate` refuses a file no writer could have produced and a v2 profile carrying
  flags is one; a v1 or v2 profile loads with an empty ledger. (The current version is the Campaign
  mode entry's, below.)
  `CampaignDefinition.ledger_error` is the one campaign-wide question a mission cannot ask about
  itself — a fact no mission of the campaign writes, or a `cleared:` / `stars:` name for a mission
  it does not run — and `make campaigns` is where it is asked, both slips being otherwise silent.
  CD4's own "no shipped mission authors a flag yet" is superseded by CD7, which wrote 57 of them;
  the fact list per campaign is `docs/campaign_authoring.md`'s.
  **CD5 shipped the carried army on D6, scoped to the one chain the shipped content then had; what
  a future session must not undo is below, and the plan's own "What CD5 settled" carries the rest.**
  **The scope was measured at one pair, and the Furnace Winter rework (2026-08-14) superseded the
  premise, not the mechanism.** The campaigns rotate the player's commander almost every mission —
  the original brief — so at CD5 exactly one consecutive pair shared a player commander (`lf01` →
  `lf02`, both Mara Voss), and that was the one chain authored. The furnace war's third act now
  chains `fw12` → `fw18` under a rotating cast — the column is the act's veteran army rather than
  one general's — so `tests/unit/test_campaign_carry_authoring.gd` pins nine chained missions and
  99 boards carrying no slot and no carry flag.
  **D6's short-roster fallback is the rule rather than the edge**, which is what makes the milestone
  safe: `CampaignRoster.deploy` only ever writes `hp` and `tag` onto units `GameState.create` has
  already built — it creates nothing, removes nothing, moves nothing and changes no type — so the
  empty-roster case is a no-op loop and 99 missions are untouched by construction rather than by a
  branch. **A veteran is identified across the gap by its type**, claiming the first unclaimed slot
  the board authored for that type, order breaking ties only (board order for slots, bank order for
  veterans): an object reference dies with the board, a cell means nothing on a different map, and a
  positional index breaks the moment a unit in the middle dies. A veteran the next board authored no
  slot for is gone from the war. **Cargo banks as itself and arrives alone** — carriage is board
  state, only condition and identity cross, and `[units]` has no cargo syntax anyway. **A carried
  tag fills only a slot the board left unnamed**, and only if that name is not already there: the
  board's authored names are the mission's, because an objective can only name what the board
  authored, and `SaveCodec` refuses two units sharing a tag.
  **The carry mark is `^`, the last column of a `[units]` row, after the optional CD1 tag** — it
  cannot be read as one in either direction, a tag being an ASCII identifier `UnitTag` refuses `^`
  as, and `core/map_data.gd`'s header comment is the authoritative statement of the map format.
  **A failed mission banks nothing**, so a retry redeploys the army the attempt began with (CD4's
  staged flags and CD2's tally, same rule), and a replay of a cleared mission does not re-bank —
  `CampaignState.complete`'s first-clear answer governs the roster as well as the ledger, which is
  why `CampaignSession.record` is handed the finished **board** rather than only its day: what
  survived is on it. `carry_out = false` **clears** the roster rather than merely not adding to it —
  the chain ends and the war forgets the army. The campaign profile is **VERSION 4** for it, on the same rule the ledger's own section
  followed (below); a v1–v3 profile opens with an empty roster and a v3 profile *holding* one is
  refused by name.
  **A resumed mission does not redeploy**: `BattleCampaign.open_board(game, fresh)` stands the army
  only on a board nobody has played, its slots having been filled when the mission first opened. And
  deploy runs **after** `TurnRules.begin_turn` (which `GameState.create` calls), so a carried unit
  standing on a friendly property misses day-one repair — chosen over threading a roster into the
  sim's constructor for one day of one property's repair, deterministic either way, recorded rather
  than hidden.
  **CD6 shipped interludes and optional missions on D7, and the route is the whole of it; the plan's
  own "What CD6 settled" carries the rest.**
  **`CampaignState.open_mission` is the ONE authority for what a war offers next** — the campaign's
  order narrowed by what the war has recorded — and `CampaignDefinition.next_mission_id` is
  **deleted** for being a second answer to it, which is exactly what that class's own header forbids
  ("two sources for what comes after this is how a campaign ends up with a mission nothing
  reaches"). Its one production caller, the debrief's NEXT line, moved onto the route, and three
  readers now share that one walk.
  **The route is derived and its answer is latched, and pure derivation is the wrong answer**:
  `unlock_requires` is **not monotone in the ledger** — `at_most 0` is the ordinary shape of an
  optional mission (the shipped one opens only if you did *not* bloody Morn's vanguard) while flags
  only ever grow — so a freshly-asked gate would **close a mission the player is standing on** the
  moment a later beat wrote that fact. `complete` latches the walk's answer into `unlocked`, which
  nothing ever removes from, and `_opens` is the one line that is the invariant: already-unlocked
  opens whatever the war now records. A naive latch alone cannot skip a closed mission, which is the
  feature, so it is both or neither.
  **The route is forward-only and that is enforced rather than assumed**: `route_error` fails
  `make campaigns` for a gate with `at_least > 0` whose fact no **earlier** mission writes, so a
  gate's value is settled before the route reaches it — which is what makes "derive fresh" and
  "latch once" the same answer. A gate asking for a fact to be *absent* is the road not taken and is
  deliberately unheld. Re-opening a mission behind the frontier was rejected: it drags the route
  backwards into a state nothing in the fiction asked for.
  **`is_complete` means the war has no mission left to offer** (`open_mission == &""`), and
  `offered_count` is its denominator — the list less the roads walked past. **Every surface counting
  progress reads those two**, the hub's headline and the campaign list's row alike, because one
  campaign may have only one notion of finished: a picker counting the authored list read "17/18"
  forever for a war whose eighteenth mission nobody could play.
  **An interlude belongs to the mission that closes the block**, never to "the route left the
  block" — `CampaignDefinition.closes_block`, and only on a win. Chosen because
  every block closer in all three authoring specs is mandatory, and the route-based alternative
  re-fires the page whenever a player replays any earlier mission of a finished block. Its stated
  consequence — an author who gates a block's last mission and has it skipped never plays that
  block's page — is a *refusal* as of CD8 rather than a caveat (`CampaignDefinition.block_error`).
  **The save format did not move** — still profile VERSION 4: a gated route is a pure function of
  records and flags, both already saved, and it latches into `unlocked`, which already round-trips;
  a pre-CD6 profile holding the optional mission open keeps it open by `_opens`' latch clause.
  One mission was touched beyond the milestone's two artifacts and it was forced: an optional mission
  needs a fact and a fact needs a writer or `route_error` refuses it, so `hc01` gained one tag and
  one beat.
  **CD7 retrofitted all 108 missions across six PRs, one per war, and the shipped shape is the
  measurement** (re-measured 2026-08-14, after the Furnace Winter rework deepened that war): every
  mission carries a beat (208 of them), **58 write a ledger fact**, ten missions across five
  campaigns are route-gated where CD6 shipped one, and the vocabulary the plan was written for is
  actually used — seven kinds of primary (`CaptureCell` 75, `OwnProperties` 21, `SurviveUntilDay`
  20, `HoldCell` 14, `AllySurvives` 4, `ReachCell` 4, `DestroyUnit` 4) against the 86-of-108
  `CaptureCell` the plan diagnosed, and **three kinds of failure where `DayDeadline` was the only
  one in the game** (`DayDeadline` 85, `LossLimit` 20, `ProtectUnit` 6). The carried army has
  outgrown CD5's one chain: the furnace war's third act marches one veteran column `fw12` → `fw18`,
  and the CD5 entry above owns that supersession.
  **CD8 is the gate and the record, and the gate is the milestone.** The CD7 review found the same
  authoring traps in campaign after campaign, by six independent authors, each of whom had a green
  `make campaigns`. **`docs/campaign_authoring.md` is the single owner of what the gate refuses**
  and of the traps it deliberately leaves to a hand test — do not restate the list here, in the
  README or in the plan: it drifted in four surfaces inside this one milestone, and a count written
  in four places is re-measured in none. What survives in this index are the three rules a future
  session must not break:
  **a check is a `core/` authority the tool and `tests/unit/test_campaign_content.gd` both ask**,
  never a rule spelled in `tools/check_campaigns.gd`, so a new refusal is a new
  `..._error` beside the shipped ones rather than a branch in the tool;
  **a gate earns its authority by never being wrong**, so a case a machine cannot judge belongs in
  prose — a check that refuses good content would teach authors to distrust the ones that fire
  correctly, which is why a landing-zone check was written, proven unsound (occupancy at fire time
  is not statically knowable, effects running in authored order) and **deleted** along with the
  `MissionTrigger` / `MissionObjective` / `MissionEffect` cell hooks it needed;
  and **the polarity of a fact is not in the file** — a flag's sign and its variability are
  independent properties, so the gate can only ever prove the second.
  **Two checks fired on shipped content and both were real**, which is the milestone paying for
  itself: five missions listed a co-primary beside the enemy's home headquarters (`fw15`–`fw18`,
  `hc18`) that `MissionRuntime` could never judge, and each became that mission's **bonus**
  objective, where it is judged and earns its star (the Furnace Winter rework has since re-authored
  the four fw boards' objectives wholesale); and two Hollow Crown interlude lines were
  conditioned on facts every route writes (`directorate_fallen`, `alliance_debt`), so the
  conditions are gone and the lines play exactly as they always did. No other content moved.
  **`tests/unit/test_campaign_soak.gd` is the soak and its two halves are deliberate**: every
  mission played to a verdict with its script live, through `BattleSetup.build(to_request())` and
  `CampaignSession` itself so the boundary order is `BattleCampaign`'s rather than a second
  spelling of it; and every one of the 208 beats applied to the board its mission opens on, because
  a planner-against-planner game only ever brings about half of them. It asserts **legality, never
  winnability** — no command refused, no beat refused, no stall — and says so at the top, the
  scratch tool it replaces having reported the same fact as `never-decided=0` while firing no beat
  at all. ~30s of the suite's wall clock at a 12-day cap, which is the cap every shipped mission
  already decides inside.
