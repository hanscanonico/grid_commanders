---
paths:
  - "ai/**"
  - "data/ai/**"
  - "data/difficulty/**"
  - "tools/arena/**"
  - "tools/balance/**"
  - "docs/difficulty_check.md"
  - "docs/ai_arena*.md"
  - "docs/causeway_measure.md"
---

# The computer opponent — designs of record

These are the `## Designs of record` entries of `CLAUDE.md` that own the planner, its dials, the
difficulty tiers and the arena that measures them. Read the owning entry before an architectural
decision in its area; the plans themselves are under `.lavish/`, and the long forms named in the
root index are in `docs/design_record.md`.

- `difficulty-modes-plan.html` — difficulty tiers DF1–DF4. Locked: **the AI never cheats at any
  tier** — difficulty may only change which `AIProfile` the planner weighs moves with, never
  income, vision, damage or luck. Its DF4 acceptance gate is currently **failing, knowingly**
  (76.7% / 53.3% at 30 seeds, §4e, against a required 70%) — the AI Judgement dials went live,
  the Causeway vector followed them, and closing that gap
  is the balance retune's BL2, which must do it by making Difficult better rather than Normal
  worse. Read
  `docs/difficulty_check.md` before touching an AI weight or a tier `.tres`.
  The plan's three tiers are four as of 2026-08-06: **Brutal** (`brutal`,
  `data/ai/brutal.tres`) is the AI Arena's searched champion seated verbatim — see the arena
  plan's entry below, which is where that decision lives. It is deliberately **outside the DF4
  ladder**: `DIFFICULTY_PAIRINGS` still steps `easy → normal → hard`, so every number in
  `docs/difficulty_check.md` and both committed balance reports are untouched by its existence,
  and its evidence is the arena's held-out pool instead. Hanging a fourth rung on a gate that is
  already failing its margin would make both readings harder rather than either one clearer;
  adding `[hard, brutal]` is a future measurement, not an oversight. Nothing about D2 bends —
  a tier is still only an `AIProfile` and a label, which is exactly all Brutal is.
- `commander-doctrine-ai-plan.html` — each general's army, played by the computer, plays like
  that general: milestones CA1–CA4, all shipped. Half of it was already true and the plan's first
  job is saying so: the planners score through the same resolvers the rules run, so every combat
  and movement passive steers the AI with no AI code, and `wants_power` timing was already
  doctrine-owned. What shipped is the other half. D1/D3: three advisory hooks on `CommanderType`
  beside `wants_power` — `stand_value` (tiles, the advance path only), `build_bias` (build-list
  places, the priority tier only: a negative bias may pull an unlisted *combat* unit onto the
  list's tail, which is how a doctrine buys the recon, and no bias reaches a transport the list
  omits or outranks the air-answer and capture-shortage tiers — the one transport a bias does move
  is the supply truck, whose want COM-180 clamped as a sum like every sibling tier, so a doctrine
  pulls it earlier or later within the priority tier and never past its floor),
  `retreat_hp_delta` (the repair gate) —
  every number `@export` on the general's `.tres`. D2: `AIProfile.doctrine_weight` is the one
  planner dial, written into every tier and on at every tier — a commander's personality is a
  match fact, not a difficulty smart — and 0 skips the hooks entirely, restoring the
  doctrine-blind planner byte for byte, which is how the difficulty lock survives. D4: advice
  reads only what the planner already reads (enemies through `Vision.is_hidden_from`), is pure,
  integer and RNG-free — pure to the board and the caller, an instance being free to memoise under
  a key any relevant board change moves — and **never reads the damage chart** — the forecasts
  already carry every combat hook, so advice that re-priced one would count the same doctrine
  twice; Lyra Quill's luck floor stays unpriced by the same rule from the other side, because
  forecasts are deliberately luck-free. Wren valuing cover more as Vanish banks is what broke the Vanish stall
  (full meter, nobody in woods, forever — `test_sable_wren.gd` pins the stage-then-fire turn).
  The plan's Rook clause ("no good fight this turn") is superseded by the shipped gate:
  Redeployment fires for ground its movement can buy, *regardless* of the fight, because the
  commander match soak showed an army in constant contact otherwise banks the meter all match —
  the banked-meter failure the toolkit exists to avoid. **Which generals advise nothing is
  `tests/unit/test_commander_ai_advice.gd`'s to say, never this entry's** — its `ADVICE_COVERAGE`
  records a yes-or-no per hook for every commander on the roster, with a one-line reason for each
  silent one, so a general cannot be seated without answering and a silent doctrine can never be
  read as a forgotten one. Orlov, Quill and Rowan were the first three: forecasts already play them
  right, and a silent doctrine is the seam working, not missing. `retreat_hp_delta` is **internal
  HP** (10 = one displayed pip), the scale `AIProfile.retreat_hp` is on, pinned in that same file.
  `core/commander_type.gd` carries the repo's one `max-public-methods`
  ignore — its width is the hook contract twenty-two subclasses override, so the split the ratchet
  usually buys would be the mirror hook tree the commanders plan's D1 rejects; the ceiling stays
  21 for every facade-shaped class. D5: `make difficulty-check` stays byte-stable (it seats no
  commanders, and neutral advice is structurally zero); `make commander-balance` moved by design
  and was regenerated and read — `docs/commander_balance.md` records the measurement.
- `ai-judgement-plan.html` — the three things the planner cannot see: what the enemy is
  *achieving*, what it will *do next turn*, and what our own other units are doing. AJ1–AJ4, **all
  shipped**. D2: **this plan owns planner *capabilities*, the balance retune's BL2 owns Normal's
  *numbers*** — no AJ milestone edits a shipped value in `data/ai/`, and AJ4's deliverable is a
  probe band in `docs/difficulty_check.md`, never a tier value. D1: **`0.0` skips a capability
  entirely** rather than evaluating to zero, pinned by per-capability suites that build zeroed
  profiles; the merge bar is a fixed-seed byte-diff of both balance reports. D1's *inert* half is
  superseded — the dials went live 2026-08-01 and `ai/ai_profile.gd`'s class defaults moved with
  `data/ai/default.tres`, so what that parity test pins is that an install with no profile file
  plays the same game. D3: **denial is priced at the price of capture, read backwards** —
  `_defend_bonus` reuses `_consider_captures`' own arithmetic so the two compete in one
  `AIUnitPlan`; only a **capture-capable** enemy earns it, the ground is our *side's* through
  `GameState.allied`, and the HQ multiplier is asked of `GameState.home_hq`, never
  `terrain_at(cell).id == "hq"`. **Only a besieged home HQ diverts the advance path** — a city is a
  setback, an HQ is the match. D4: **withdrawal is a scored candidate priced in value, never the
  fallback** — `_consider_withdraw` sits beside `_consider_attacks` / `_consider_captures` /
  `_consider_dive` and is called **last**, so a withdrawal that merely ties with a shot loses to it;
  the refuge is least `ThreatMap.incoming_damage`, then the arena plan's AR6d weapon-position rank,
  then ground that repairs, then the shortest walk, and **safety outranks both** — standing still
  enters at cost zero, so a merely-equal cell never pulls a unit off its own square. D5:
  **cohesion is a term on the advance path, not a formation manager** — `_cohesion_penalty` charges
  tiles adrift of the nearest unit in the unit's **own movement domain** (an army keeps company with
  what can keep up with it) and its **own team**, not the side, formation being the army's while
  defended ground is the side's. No groups, no leaders, **no waiting state**: the goal term still
  pulls forward, so the equilibrium is a column advancing at the speed of its rear. It taxes only
  the advance on the enemy — `AdvanceGoal.keeps_formation` defaults **false**, so every errand
  (refit, repair, besieged HQ, a property to capture) is untaxed by construction rather than by a
  list of exceptions. D6: nothing under `core/` is touched and no telemetry is added.
  **Three dials now read one `ThreatMap`** (`threat_aversion`, `advance_threat_tiles`,
  `withdraw_weight`) and can price one enemy three times — R3 — so **tune them together, never
  alone**. Shipped positions: `defend_weight` at the top of AJ4's probe (2.0 Normal, 2.5
  Difficult) and it *reduces* the HQ defect rather than ending it — the bonus is linear on the same
  scale as a kill, so a rich enough target still outbids a match-ending capture at any weight;
  `withdraw_weight` and `focus_fire_bonus` are shipped at `0.0`, both measured worthless, each one
  edit from a re-try. The DF4 ladder now **fails knowingly** because making Normal competent closes
  the gap the gate measures. `docs/difficulty_check.md` §4b is the measured band and §4c
  downgrades §4b's cohesion headline to a hypothesis; R1 (the column as artillery bait) is
  **unobserved rather than refuted** — both sides are the same planner, so the instrument is blind
  to it and it belongs to a human playtest.
- `ai-economy-plan.html` — the planner reads the map as an *economy* rather than as the fight in
  front of it: enough infantry to race for the board, capture goals that fan out across it, and a
  price on the ground that builds tanks. AE1–AE3 shipped, **AE4 (the probe band) outstanding**. It
  inherits the AI Judgement boundaries verbatim — D1: **every dial ships inert and inert skips the
  code**, merge bar both balance reports byte-identical with no accepted departure. **D1's inert
  half is superseded for one dial as of 2026-08-16**: `capture_units_per_property` went live at
  0.15 on Normal, Difficult and Brutal (Easy stays 0) with `goal_engageability` and
  `spend_ceiling_turns`, the three of them being `docs/causeway_measure.md`'s V4 — measured
  together, and no dial of the three carries the effect alone. Inert still skips the code, and what
  the seating cost the ladder and the commander matrix is `docs/difficulty_check.md` §4e's. D2:
  **this plan owns capabilities, BL2 owns the tier numbers**; D7: nothing under `core/` and no telemetry, every
  read through an authority that already exists (`MapData.property_cells`,
  `GameState.properties_of` / `allied` / `home_hq`, `TerrainType.builds`, `UnitPricing.cost_for`).
  D5: **the capture roster scales with what is left to take, floored at what the tier already
  ships** — `max(capture_unit_target, ceil(capture_units_per_property × unowned))`, `unowned` being
  property cells this team's **side** does not hold. It counts what is *left* rather than the size
  of the board, which is what makes it self-damping. D5's own "the floor stays at 3 in every tier"
  is superseded by D2: the floor is whatever a tier ships, and `easy.tres` has carried 2 since
  COM-120. D6: **`_worth_waiting_for` already refuses to bank whenever something urgent is
  wanted**, so a short capture roster is urgent and the same branch banks on a small board and
  spends on a big one — no banking code moved, and `save_up_turns` is deliberately left alone
  (its comment carries the first-side-bias measurement a retune would trade away). D3: **a capture
  goal is claimed by derivation, never by stored state** — `capture_claim_depth` is how many units
  may claim one property, `AIAdvance._claimed_property` is the one place that answers,
  and at 0 it is the shipped `_nearest` call untouched. **D3's arithmetic is superseded and its
  decision is not**: what ships is an **assignment** — closest unit-property pair settles first —
  settled once per command into `AIPlanningContext.capture_claims` and cleared by `begin`, exactly
  `goals`' lifetime, so nothing about a claim survives a command. **Every tie is settled by scan
  order** over the whole (distance, unit, property) triple, so the sort needs no stability and
  replans off one board always agree. A unit left unplaced falls back to the same priced walk an
  unclaimed capturer takes, so claiming can never send a capturer at the enemy instead.
  `MovementResolver` is untouched. D4: **a property is priced by what it produces, in the currency
  captures are already in** — `production_capture_multiplier` multiplies `capture_score` **beside**
  `hq_capture_multiplier`, on the same line of arithmetic, so the two compose rather than compete.
  On the shipped terrain they never both apply (`hq.tres` builds nothing), which supersedes the
  plan's AE3 card. **One judgement, two readings, and they cannot disagree**: the same multiplier
  feeds the goal side through `capture_goal_value_tiles`, because a unit that walks to a factory
  because it is valuable must still want it when it arrives. `AIAdvance.produces` asks
  `TerrainType.builds`, so **AE3 adds no terrain id to `ai/`**.
- `ai-arena-plan.html` — the self-play arena: thousands of headless matches between candidate
  AIs, so a planner weight is *measured* rather than argued. AR1–AR6 shipped (the harness seats any
  candidate, the ruler exists, the shelf is in the tree, `make arena-search` is the search loop);
  only **AR7's human verdict remains**. **`docs/ai_arena.md` is the committed record of what
  "better" means** and the document to read before any arena claim; **`docs/ai_arena_results.md` is
  what the first campaign found** (93,744 matches, 2026-08-05) — a dated measurement a later
  campaign supersedes wholesale rather than edits. D1: **the arena is an instrument and the game
  never learns it exists** — the driver lives in `tools/`; nothing in `ai/` gains an "arena mode",
  because the moment the sim can see the measurement the measured game stops being the shipped one.
  It carries **one recorded waiver**, the user's, taken in AR1: `MovementResolver._occupants` and
  `AttackRange.band` / `reaches`, both pure reads that decide nothing (AR6a's
  `CombatResolver.cover_stars` is a private static made public, not a second waiver). D2: **a
  performance change is proven byte-identical, never argued** — both balance reports across the
  change with no accepted departure, plus a differential test keeping the two planners agreeing
  command for command (`tests/unit/test_ai_plan_cache.gd`, `..._diff.gd`), and **a milestone that
  adds a dial to the planner adds a run** to the second. D3: **a candidate is an `AIProfile` and
  nothing else**, so anything the arena finds ships as an edit to one `.tres`. D4: **a match is
  scored, not counted** — three ordered classes a gradient can never cross (a decisive win is
  `1.0 + 0.5 × (100 − day)/100`, an unresolved match `0.0` to both, a loss the winner's exact
  negative); that zero-sum shape is what makes counting both seatings *cancel* the seat rather than
  report it (+37.5 pp of first-seat edge measured on `scrimmage`). The property/unit/army-value
  margins the plan names are **deliberately absent** — elimination clears the loser's board, so
  they are a constant on the one class that allows them. D5's two halves live apart on purpose:
  `ArenaPools.pairings` never *emits* a self-pairing while `ArenaLeaderboard` refuses to *read* any
  pairing it did not see from both seats, so a mirror stays runnable as a calibration and
  unreadable as a leaderboard. It refuses a second reading for the same reason: **a pool a
  candidate never played is the absence of a measurement, never a score of zero** — only a pool
  *every* candidate played orders anything (`ranked_on`), the gaps are named (`uncovered`), and a
  run holding any is unreadable. D6/D7: the horizon is 100 days, `command_cap` is a hard invariant
  failure of the run, the pools are split by **board and seed** with the three shipped tiers as
  never-retuned anchors, and **the opponent is the archive, not the champion** — this game is
  measurably intransitive, so progress is the anchor score. `ArenaPools.pool_args()` is the one
  statement of a pool, read both to play and to score finished matches back. D8: **the arena
  recommends and a human ships** — no milestone and no `make` target writes a searched number into
  `data/ai/`. **D8 has been exercised**: on 2026-08-06 the campaign's `everything` vector was seated
  verbatim as the fourth tier **Brutal**, sixteen dials off Normal with none retuned on the way in,
  pinned to the results doc by value in `tests/unit/test_difficulty.gd` and deliberately **outside
  the DF4 ladder**, so every committed difficulty number is untouched by its existence.
  **AR4's acceptance check failed, and the failure is the finding**: the arena ranks the tiers
  Difficult > Normal > Easy on every pool and all nine boards measured, not the Atlas's inverted
  order — not the scorer, board-dependent, and the Atlas predates the dials the planner now
  carries. Nothing was tuned toward the wanted answer. `ironworks` is out of the pools for a
  measured reason (the only board to hit the match-level cap), so re-admitting it is a measurement
  no campaign has taken. AR5 is the search: **blocks of dials, never one joint optimisation** (R5),
  `tools/arena/arena_blocks.gd` is the space, in GDScript beside `ArenaPools` so a block cannot
  name a dial `AIProfile` does not carry — the coverage rule that caught `defend_weight` sitting in
  no block. Its one engine change is `BalanceMatchEngine.command_ceiling(days_cap, teams)`, an exact
  upper bound on legitimate play, so reaching the cap now means **the day stopped advancing**.
  AR6a–d are the shelf, `cover_tiles` / `condition_weight` / `join_weight` plus AR6d's position
  rank, all on the Judgement D1 contract (`0.0` on every tier, and `0.0` skips the code), shipped
  **unmeasured on purpose** until AR5 priced them — cover and condition earned places in the
  champion, `join_weight` measured worthless and stayed at zero. AR6a: **the double-pricing answer
  is per cell, not per tier** — a cell is priced by the forecast wherever one has fire for it and
  the stars speak only where none does, counted in **tiles** on both paths, and nothing in `ai/`
  reads `defense_stars`. AR6b: **`_unit_value` is the file's only unit valuation**, interpolating
  five sites toward `cost × hp/100` (the board's own rate, since `TurnRules._repair` sells missing
  HP back at it); deliberately one dial for a unit as a target and as an asset, clamped to 0–1
  because past 1 it inverts the sign of every reader — **move it with `kill_bonus`, never alone**.
  AR6c: **a join is a scored candidate, in value, on the HP that survives the merge**, with the
  overflow charged **separately from the dial** at face value, because without the split a high
  weight pours fresh units into wounded ones. AR2 is the pool: **`tools/balance_pool.py` decides
  who plays what and when; the Lab plays every match**, adding no loop and aggregating nothing; **a
  shard whose `summary.json` exists is skipped**, which holds because the Lab writes a shard's
  artifacts in one go; **the seed formula stays the Lab's** (`--seed-offset=` is the one flag
  added). Two durable consequences of its merge bar: **a run may only write under `reports/`**, one
  policy in two places (`resolve_out` in the driver *and* `BalanceReportWriter.resolve_out`,
  because Godot's `path_join` re-roots rather than resolves); and **never sort `StringName`s when
  the order is observable** — they compare by interned pointer. The threading spike was built and
  **abandoned** (1.1× against the process pool's 3.0×); `docs/balance_sim.md` carries the measured
  scaling curve. AR3 is the grammar for "play *this* vector", a **third preset over the one match
  loop**: `--red-profile=` / `--blue-profile=`, `--pairings=<file.json>`, and `matches.json`
  carrying only the `Outcome` facts fitness reads. `BalanceSideSpec` is untouched — a profile path
  is a different flag rather than a third field in it. Commanders are neutral by default (which
  makes `doctrine_weight` inert, R8) and seatable per side since 2026-08-07 (`--red-co=` /
  `--blue-co=`). Two things became single authorities so the presets stay one engine:
  `BalanceMatchSchedule` owns which seeds and seatings a matchup plays (a mirror once) and
  `BalanceMatchEngine.army_value` owns the margin both drivers report. Known and deliberate: **the
  AR1 cache is inert with fog on**, so the live game gets no speedup and only the offline tools
  do.
- **AI logistics** (no plan artifact; COM-65, and this entry is its record) — the planner issues
  `SupplyCommand`, which the rules had always offered and it had never asked for. It is a scored
  candidate in `_best_unit_plan` beside `_consider_dive` and the arena shelf's `_consider_join`,
  priced in VALUE like every other candidate there, and it carries one `AIProfile` dial. Three
  decisions:
  **`supply_weight` ships live on every tier**, unlike the Judgement, Economy and arena-shelf
  blocks — an inert dial here is a command type nobody can reach, which is the whole defect — while
  `0.0` still skips the capability's code entirely, pinned by `tests/unit/test_ai_logistics.gd`.
  **Supply asks `SupplyCommand.friendlies_in_reach` who a top-up would reach** rather than
  re-deriving adjacency, since the radius is the commander's (Gideon Holt's is two) — which is also
  why `AIPlanCache._drop_inside` widens a supply unit's envelope by that radius. What is worth
  refilling is graded ammo plus the yes-or-no `Unit.running_dry` already answers, so a land unit's
  half-empty tank is worth nothing here, exactly as it is to the refit errand.
  **The truck is asked for above `build_priority`**, the way the air answer is: nothing on that
  list refills anything, so `supply_unit_target` is what puts one in the roster, and it is 1 on
  every tier because the planner has no route to a second.
  **Merging is not this entry's**, though COM-65 shipped a rival for it: the arena plan's AR6c
  `_consider_join` is the one in the tree, so a merge is priced by `join_weight` on the shelf's
  contract — `0.0` on every tier, and measured worthless by the arena's first search campaign —
  rather than live like supply.
  **Load and Drop stay out**, on the naval plan's standing R1: the planner cannot plan a ferry.
