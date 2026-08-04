# CLAUDE.md

Guidance for AI agents (and humans) working in this repository.
`AGENTS.md` is a symlink to this file — edit only `CLAUDE.md`; both names stay in sync.

## Project

**Grid Commanders** — an **Advance Wars-style turn-based tactics game** built in **Godot 4.7+** with
**GDScript**. Grid maps, terrain that shapes movement and defense, a rock-paper-scissors unit roster
across three movement domains (land, air, sea), property capture and income, and a computer opponent.

- **Engine:** Godot 4.7+ (`TileMapLayer`, custom `Resource` types).
- **Language:** GDScript, **typed everywhere** (`class_name`, typed vars, typed signatures).

> Legal: this is a *reimplementation of mechanics*, not a copy. No Nintendo sprites, music,
> unit-name trade dress, or the "Advance Wars" name. Use original or freely-licensed assets and
> a different title. Track every third-party license in `assets/LICENSES.md`.

## Designs of record

The plans under `.lavish/` are the designs of record — **read the owning plan before an
architectural decision in its area.** The index below names each plan's scope and the invariants
that must survive any change; the full rationale, milestones and risk registers live in the plans.

- `grid-commanders-plan.html` — the base game: milestones M0–M7 (all done), mechanics reference,
  damage formula.
- `commanders-plan.html` — Commanders and Command Powers: milestones C1–C4, locked decisions D1–D4
  (subclassed `CommanderType`, asymmetric charge accrual, C1 scope, Sable Wren's reworked Vanish),
  risk register R1–R6.
- `new-commanders-plan.html` — six more generals, milestones NC1–NC7, **all shipped**: Ines Calder
  and Konrad Vale share the one `UnitPricing.cost_for` purchase authority while base cost remains
  charge/target/value currency; Perrin Ash and Halden Marr are domain-only and exactly neutral on
  land-only boards; Dane Ferrow's kill bounty is stolen through `CombatResolver.bank_losses`,
  never minted; Iris Colt's `AFTER_ACTIONS` Second Wind refreshes non-attack actions. The plan's
  D4 “no new state/save” claim is superseded by the safe rule: `Unit.refreshable` records that
  eligibility and save v8 carries it, because `acted` alone cannot distinguish an attack from a
  non-attack after loading. Older saves default it false. The roster is deliberately 5 / 5 / 4 /
  4, and the full balance gate is 18 × 18 × five scenarios × four seeds.
- `difficulty-modes-plan.html` — difficulty tiers DF1–DF4. Locked: **the AI never cheats at any
  tier** — difficulty may only change which `AIProfile` the planner weighs moves with, never
  income, vision, damage or luck. Its DF4 acceptance gate is currently **failing, knowingly**
  (68.3% / 53.3% against a required 70%) — the AI Judgement dials went live and closing that gap
  is the balance retune's BL2, which must do it by making Difficult better rather than Normal
  worse. Read
  `docs/difficulty_check.md` before touching an AI weight or a tier `.tres`.
- `naval-air-units-plan.html` — air and naval domains N1–N4. Standing risk R1: the AI cannot plan
  a ferry, so it never builds transports — a naval map has to let fleets reach each other without
  one. Its one-weapon simplification is superseded: Tank, Md Tank and Mech carry an infinite-ammo
  secondary the damage chart selects; every other unit stays single-weapon.
- `map-retrofit-plan.html` — which shipped boards carry a port or airfield and which stay
  land-only on purpose. Its byte-identical clause is superseded by the rule that replaced it: a
  map edit **converts** cells, never carves — land stays passable to every land class, no cell
  becomes sea, no coastline is redrawn — because a save stores its board by `map_path` and reloads
  the edited file from `res://`.
- `production-maps-plan.html` — the `forge`/`arsenal`/`steelworks` boards. D1: zero starting units
  is an omitted `[units]` section, not a flag and not a parser change. D3 keeps them land-only
  (naval R1).
- `balance-simulator-plan.html` — offline balance instruments BS1–BS4, all shipped. D2: **the
  telemetry observes, it never instruments the sim** — nothing under `core/` or `ai/` gained a
  hook for it. D1: `tools/balance/match_engine.gd` is the one match loop; `make commander-balance`
  and `make difficulty-check` are byte-stable presets over it, and the merge bar for touching it
  is a fixed-seed byte-diff of both reports. `docs/balance_sim.md` is how to run and read it.
- `game-speed-plan.html` — the game-speed setting GS1–GS3. D1: a device preference in
  `user://settings.cfg`, never the `MatchRequest` a launch is staged as and never a save. Standing
  invariant: **nothing under `core/` or `ai/` may import `GameSpeed` or read `Settings`** — pacing
  can never move an outcome, a save or a replay. Instant is an explicit branch, not an animation
  scale of zero. The GS3 subjective retune is **not done** — tier numbers are still the plan's
  starting values.
- `faction-identity-plan.html` — armies wear their commander's faction, FI1–FI3 shipped. D1:
  **identity is presentation-only** — the sim keeps its team ints; `scenes/common/side_identity.gd`
  (`SideIdentity`) resolves `team → {theme, display name, atlas row}` once per match from the
  commander picks and is the single authority every surface reads — ask it, never re-derive a
  side's colour or name. Its fallbacks are load-bearing and total: a no-CO match is
  board-identical to before factions. The atlas-row order (`0 neutral, 1 meridian, 2 aurora,
  3 iron, 4 verdant`) is a contract between `SideIdentity._ROW_FOR_KEY` and the art pipeline
  (`build_pixvoxel_atlases.sh`, `generate_tiles.gd`); rows 0–2 stay byte-for-byte the shipped
  red/blue art. D5: **"Red"/"Blue" survive only as developer slot vocabulary** (the Balance Lab's
  `--red`/`--blue` grammar, identifiers, comments) — never on a screen a player sees.
- `tile-info-panel-plan.html` + `.lavish/hud/SPEC.md` — the tile info panel and the docked HUD
  (`HudTopBar`, `HudBottomBar` under `scenes/ui/`, built in code; `show_tile()` is the bottom
  bar's). Presentation-only; the fog/doctrine gate stays in `battle_view.gd`'s `refresh_panel`,
  which nulls units the viewer cannot see before the panel gets them. Bar heights, colour tokens
  and the shared builders (`hud_divider`, `hud_spacer`, `hud_label`) live in `UiTheme` — the bar
  scripts hardcode no colour and no size. `BattleView._apply_board_offset` is the **only writer**
  of `camera.offset` (the combat shake composes through `BattleView.shake_offset`), and both bars
  swallow the pointer (`MOUSE_FILTER_STOP`) so events can't fall through to cells rendered behind
  them.
- `battle-animations-plan.html` — the combat cut-in BA1–BA4, all shipped. D1: **the cut-in replays
  a snapshot, it computes nothing** — `core/` gained only `CombatResult.attacker_hp_before` /
  `defender_hp_before` and, with secondary weapons, the two weapon slots the rules selected
  (`attacker_weapon_slot` / `counter_weapon_slot`), which the cut-in maps to a style through
  `BattleStyleDb.for_weapon` and never re-decides. D5: how a weapon looks is a `BattleStyle`
  under `data/battle_anim/`, `UnitType.battle_style` / `secondary_battle_style` are presentation keys
  like `atlas_col`, and no gameplay number may ever appear in a style.
  D2 ("board art, blown up; nothing redrawn") holds for the ground plane and the figures, and has
  **one recorded departure, the cut-in's scenery**: in the cut-in a terrain either *paves* the ground
  or *stands* on it, said by two presentation keys on `TerrainType` beside `atlas_col` —
  `cutin_ground` (the surface a standing terrain is paved with) and `cutin_scenery` (the shape it
  stands), asked through `stands_in_cutin()` and never by terrain id. Paving with an object's own
  art carpets the frame in tiny repeated towers, and standing the atlas cell as-is brings its
  opaque ground plate with it and reads as a framed picture — so the shape is **drawn**, with its
  colour still sampled off that same cell (over `OBJECT_WINDOW`, the middle, because a peak is grey
  on a green square and the whole-cell average returns grass). The two keys are one decision in two
  fields and nothing at draw time can see them disagree, so `tests/unit/test_terrain_db.gd` lints
  them together: set together or not at all, a known shape, and a pavement that exists and does not
  itself stand. `cutin_scenery:mech:mech` in the smoke sweep is the frame trees and peaks are drawn
  in; `cutin_iron_commander` is the buildings'.
- `capture-animation-plan.html` — the capture cut-in CP1–CP3, the combat cut-in's structural
  sibling: same D1 (replays a snapshot), same gate (`capturing`, Instant, viewer visibility via
  `BattlePerspective`). `core/` gained only the `CaptureCommand.result` snapshot; the mash chips
  are a presentation split of `points_before − points_after`, never a call back into
  `capture_strength`; the property flip is a `SideIdentity.atlas_row` swap. Deliberately does not
  tier-scale (structural parity with the combat sibling). Faction tinting for its buildings and
  all art families has one authority — see `assets/LICENSES.md` "Design-system faction tints".
- `power-quotes-plan.html` — Command Power quotes PQ1–PQ2, shipped. D1: a quote is presentation
  data — `power_quotes` is exported on `CommanderType`, the words live on each general's `.tres`,
  nothing in `core/` or `ai/` reads one. D2: rotation is by a per-team activation counter, never
  RNG, so a replayed match speaks the same words. A quote-less commander renders the banner
  pixel-identical to before. `tests/unit/test_commander_quotes.gd` enforces coverage and the
  60-character cap. Text only — no voice audio, no settings toggle.
- `range-preview-plan.html` — the range preview RP1–RP3, shipped. D1: **the fire ring is the
  single authority's geometry, never a second opinion** — `AttackRange.threat_cells` /
  `firing_cells` / `ring_cells` in `core/rules/` own "every cell a unit could bring under fire
  this turn", and `ai/threat_map.gd` is rebuilt on them (keeping only its dry/unarmed filter and
  per-enemy attribution), so the red overlay and the planner's fear are one computation. That one
  computation answers for two sets of eyes: `MovementResolver.reachable` takes a `sight_team`
  (default `MOVER_SIGHT`, threaded down through `firing_cells` / `threat_cells`) naming whose
  knowledge of **occupancy** fills it — the planner and every committed move keyed to the mover's
  own sight, a preview of **another side's** unit keyed to the **viewer's**, because a
  fill keyed to the mover is walled by the units that mover can see and planned through the ones it
  cannot, so a previewed silhouette alone would report which of the viewer's own pieces that unit
  has spotted (COM-57). Terrain, budget and doctrine stay the mover's throughout. So this slice
  does reach into `core/` and that parameter is the whole of it — a second, fog-redacted board for
  the fill to walk is still the rejected answer. Everything else is presentation, gated by the same
  `perspective.can_see_unit` fog rule targeting uses and then masked to scouted ground by
  `BattlePerspective._viewer_safe`; `make screenshot` stays byte-stable.
- **Field overlays** (no plan artifact; the *Field Overlays* design handoff, and this entry is its
  record) — the threat lens, the arrowed movement path and the capture pip. **Nothing under `core/`
  or `ai/` was touched, because the handoff's rules helpers already existed**: its `threat()` /
  `ring()` / `pathTo()` are `AttackRange.threat_cells` / `ring_cells` and
  `MovementResolver.Reach.path_to`, same indirect rule and all. So the whole slice is presentation,
  and its four decisions are:
  D1: **the lens is a union over the one per-unit authority, never a second walk** —
  `BattlePerspective.all_threat_overlay_cells` calls `threat_overlay_cells` once per hostile unit
  the viewer can see, so it inherits both the sight rule the fill is keyed to and the scouted-ground
  mask, and the range preview's D1 keeps holding without being restated. It repaints from
  `Battle.refresh_fog`, the pass that already reruns after every committed command and turn change,
  and costs nothing while the lens is down. It belongs to no unit and no selection: nothing clears
  it but the player, because a lens that switched itself off when a unit was picked up would be off
  exactly when the question it answers is being asked.
  D2: **the lens gets its own layer, striped** — `attack_layer` is already two things (R's fire ring
  *and* the pickable targets during `TARGETING`), so a lens sharing it would either erase a target
  list or be mistaken for one. `T` raises it; `R` still shows one unit's ring, indirect units
  included, which is why the handoff's separate min–max ring needed no code at all.
  D3: **`scenes/battle/battle_overlays.gd` (`BattleOverlays`) owns the transient paint** — reach,
  fire, threat, route, capture chips — and `BattleView` keeps the board itself. The split is what
  the `max-public-methods` ratchet bought rather than a raise; ask `overlays` for anything laid
  *over* the board and `view` for the board.
  D4: **the two board marks are drawn, and every number in them was handed over.** `PathArrow`
  splits into a pure `segments(path)` (checked by `tests/unit/test_path_arrow.gd`, no scene) and a
  `_draw` that only paints what it returns; `CapturePips` is dumb like `UnitSprite` and never calls
  back into `capture_strength` — Battle puts `GameState.capture_progress` through the same fog gate
  the board uses and hands the result over. Both wear outlined marks rather than filled panels: the
  handoff's ink chip is trim on its 44px tile and covers the building being captured on this
  board's 16. Every captured battle frame shifts, because the threat chip is permanent top-bar
  chrome and so is in all of them; the `capture` and new `field_overlays` frames additionally move
  on the board itself, the path no longer being a yellow polyline and capturing tiles now carrying
  a pip.
- `commander-doctrine-ai-plan.html` — each general's army, played by the computer, plays like
  that general: milestones CA1–CA4, all shipped. Half of it was already true and the plan's first
  job is saying so: the planners score through the same resolvers the rules run, so every combat
  and movement passive steers the AI with no AI code, and `wants_power` timing was already
  doctrine-owned. What shipped is the other half. D1/D3: three advisory hooks on `CommanderType`
  beside `wants_power` — `stand_value` (tiles, the advance path only), `build_bias` (build-list
  places, the priority tier only: a negative bias may pull an unlisted *combat* unit onto the
  list's tail, which is how a doctrine buys the recon, and no bias reaches a transport or
  outranks the air-answer and capture-shortage tiers), `retreat_hp_delta` (the repair gate) —
  every number `@export` on the general's `.tres`. D2: `AIProfile.doctrine_weight` is the one
  planner dial, written into every tier and on at every tier — a commander's personality is a
  match fact, not a difficulty smart — and 0 skips the hooks entirely, restoring the
  doctrine-blind planner byte for byte, which is how the difficulty lock survives. D4: advice
  reads only what the planner already reads (enemies through `Vision.is_hidden_from`), is pure,
  integer and RNG-free, and **never reads the damage chart** — the forecasts already carry every
  combat hook, so advice that re-priced one would count the same doctrine twice; Lyra Quill's
  luck floor stays unpriced by the same rule from the other side, because forecasts are
  deliberately luck-free. Wren valuing cover more as Vanish banks is what broke the Vanish stall
  (full meter, nobody in woods, forever — `test_sable_wren.gd` pins the stage-then-fire turn).
  The plan's Rook clause ("no good fight this turn") is superseded by the shipped gate:
  Redeployment fires for ground its movement can buy, *regardless* of the fight, because the
  commander match soak showed an army in constant contact otherwise banks the meter all match —
  the banked-meter failure the toolkit exists to avoid. Three generals advise nothing on purpose
  (Orlov, Quill, Rowan): forecasts already play them right, and a silent doctrine is the seam
  working, not missing. `core/commander_type.gd` carries the repo's one `max-public-methods`
  ignore — its width is the hook contract eighteen subclasses override, so the split the ratchet
  usually buys would be the mirror hook tree the commanders plan's D1 rejects; the ceiling stays
  21 for every facade-shaped class. D5: `make difficulty-check` stays byte-stable (it seats no
  commanders, and neutral advice is structurally zero); `make commander-balance` moved by design
  and was regenerated and read — `docs/commander_balance.md` records the measurement.
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
  Arena plan's AR6d fixed the refuge's price (see that entry), so the dial is now waiting on a
  measurement rather than on a fix.
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
- `ai-arena-plan.html` — the self-play arena: thousands of headless matches between candidate
  AIs, so a planner weight is *measured* rather than argued. Milestones AR1–AR7 (AR1 make a match
  cheap, AR2 make the machine busy, AR3 seat an arbitrary candidate, AR4 decide what "better"
  means, AR5 calibrate, AR6 widen the shelf, AR7 the verdict). **AR1–AR4 and AR6d are
  shipped** — the harness seats any candidate and the ruler exists; nothing searches yet, so
  `tools/` still runs no tournament. **`docs/ai_arena.md` is the committed record of what
  "better" means** and is the document to read before any arena claim.
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
  **D1's "nothing under `core/` gains a field, hook or branch" carries one recorded waiver**, the
  user's, taken in AR1 when the cache alone came in under the plan's own speedup floor:
  `MovementResolver._occupants` (one occupancy index per movement fill, never stored — a
  longer-lived one would need every writer that moves, kills, builds, loads or unloads a unit to
  maintain it, and the one that forgot would answer wrong rather than fail) and
  `AttackRange.band` / `reaches` (a unit's firing ring resolved once per unit instead of once per
  candidate-cell × enemy pair). Both are pure reads that decide nothing, and **D2's byte bar is
  what stands in for D1 here** — both reports byte-identical over 6,480 matches, plus
  `tests/unit/test_ai_plan_cache.gd` asserting command-for-command identity with the cache on and
  off. Read the `core/` changes as a waived departure, not a rule violation. AR6d is the other
  shipped card and it departs from its own ticket in the same recorded way: the ticket asks for a
  boolean "can it still fire" key, which scores maximum standoff and one tile short of it
  identically and so would not have fixed the reported board — what ships is a **rank**
  (`_position_rank` against the enemy the unit is orienting on), under safety and over repair,
  reaching indirect units only. `withdraw_weight` keeps its shipped `0.0` throughout (the
  difficulty plan's D2 owns tier numbers), so AR6d is inert in every shipped tier.
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
  durable. A run may only write **under `reports/`** and the driver refuses anything else at
  startup, because `BalanceReportWriter.prepare_dir` resolves the Lab's `--out` against the
  *project* root and Godot's `path_join` re-roots an absolute path under it — so an outside path
  has the Lab writing inside the repo where the driver never looks, and resume, keyed on a shard's
  `summary.json`, replays every shard forever while calling each one failed. And **never sort
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
  it. Commanders are neutral throughout, which makes `doctrine_weight` inert (R8).
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
  `ArenaPools.pool_args()` is the one statement of a pool — `make arena-anchors POOL=` reads the
  play command out of it and `pool_of()` reads finished matches back against the same split, so a
  leaderboard can never be scored against a split nothing played.
  **AR4's acceptance check failed, and the failure is the finding**: the arena at 100 days ranks
  the tiers Difficult > Normal > Easy on the training pool, the held-out pool and all nine boards
  measured — not the Atlas's inverted Easy > Difficult > Normal. It is not the scorer (raw win
  rate and a gradient-free score give the same order), it *is* board-dependent (Easy beats Normal
  on 3 of 9 boards, and swapping one board of four flipped a whole pool), and the Atlas predates
  the Judgement and Economy dials the shipped planner now carries. Nothing was tuned toward the
  wanted answer. `ironworks` is out of the pools for a measured reason worth knowing:
  it is the only board that reaches `BalanceMatchEngine.COMMAND_CAP` at a 100-day horizon (once in
  72), which is a cap sized for 20-day gates rather than a board to distrust.
- `menu-revamp-plan.html` — main-menu and commander-select redress MN1–MN3, shipped. D1:
  **design-system tokens live in one code authority, `scenes/common/ui_theme.gd` (`UiTheme`),
  never a `.tres` Theme** — it re-exports colours that already have an authority (faction hues,
  cream/ink) so there is exactly one value per colour. Map thumbnails
  (`scenes/menu/map_thumbnail.gd`) draw from `TerrainType.atlas_col` × `SideIdentity.atlas_row` —
  a miniature can never be a second opinion. The shared `CommanderCard` keeps its dress until a
  named follow-up (it is also the in-battle info sheet, so restyling it moves commander selection
  too). Fonts (Pixelify Sans, Silkscreen) are vendored, OFL, recorded in `assets/LICENSES.md`.
- `ux-recovery-plan.html` — first-contact and new-player registers U-01–U-26; the onboarding
  slice (COM-12), the rejected-confirm feedback (COM-13, `scenes/ui/action_feedback.gd`), the
  end-turn ready-unit guard (COM-14/U-10, `scenes/ui/end_turn_guard.gd`), the transition-input
  convention (COM-15/U-11) and the visible match setup (COM-19/U-15) are shipped. The setup slice's
  one durable fact: **`MapCatalog.TUTORIAL_MAP_PATH` is the single authority for which board leads**
  — `ordered()` pins it at item zero and the menu reads the same key for its Tutorial badge, so
  order and explanation cannot drift; everything else it added (the caption, the per-option help,
  Difficulty dimmed while no computer is seated — asked of the seat strip since FP5, not of a mode)
  is presentation, gated by the `menu_setup_context` capture. D3 is the transition-input convention
  and it has one authority:
  `scenes/common/transition_input.gd` (`TransitionInput`) answers "was that a press?" for every
  boundary — a banner is an awaited blocking beat any press skips, no interactive menu may sit
  under a banner or cut-in, and the victory lockup (`scenes/battle/battle_outcome.gd`) opens
  unfocused and eats input for `INPUT_GUARD_MS` so a buffered press cannot restart a match. D1:
  everything in it is presentation-only, and tutorial state is a device preference
  (`user://settings.cfg`, never the match request, never a save). D6: the tutorial
  owns no rule and observes rather than instruments — steps retire off existing `EventBus`
  signals, filtered to human sides so the computer cannot retire a hint; nothing in `core/` or
  `ai/` gained a hook. **The strip runs on the tutorial board and nowhere else** (COM-122,
  superseding the plan's "no tutorial map"): `MapCatalog.teaches` is the one answer to which board
  that is, and the gate covers *retirement* as well as visibility, so an ordinary match can never
  burn steps of a tutorial its player has not opened. `maps/boot_camp.txt` is shaped to the promise
  — turn one can reach a neutral property and afford a build, checked by `tests/unit/test_maps.gd`.
  A capture pins the hint set (`Settings.pin_hints`, from `Battle._ready`) so
  `make smoke` frames don't depend on play history; `--reset-hints` is the one `Settings` flag
  that deliberately writes. The key legend (`scenes/ui/control_hints.gd`) is printed by
  **`Battle.state`'s setter** via `Battle.STATE_CONTEXT` — never refreshed from the dozen sites
  that assign the state.
- `focus-steal-plan.html` — developer ergonomics: the smoke sweep and the desktop's window
  focus, FS0–FS3, all shipped. The instrument is `tools/focus_timeline.sh`
  (FS0) and every claim about focus is a measurement with it, never an anecdote. FS1: the
  watcher in `tools/godot_gui.sh` lives as long as the engine it launched — its only exit
  conditions are the child dying and a human clicking into the game — and restores on every
  activation, never onto the game itself or transient system UI. FS2/FS3: the sweep boots **once
  for the whole run** — `run_batched_sweep` in `tools/smoke_scenarios.sh` passes every scenario as
  one `--demos=` queue and **scene, fog and map are per-entry boot facts** (`+fog` stays in the
  mode name, `@<map>` is appended; neither the label nor the capture filename changes) — and
  `scenes/battle/battle_capture_batch.gd` (`BattleCaptureBatch`) runs the queue in that one
  process, held in statics because a `reload_current_scene` between scenarios is what gives each a
  fresh `Battle` in the same window, and `change_scene_to_file` is what lets the `menu_` pair join
  the same boot. `BattleCaptureBatch.scenario_args()` is the one seam: it hands `Battle` the
  process command line with the current entry's `--map`/`--fog` swapped in, so
  `MatchRequest.apply_cmdline` and the documented CLI grammar are unchanged — only where the values
  are read from moved. It parses the queue lazily and idempotently, because the first scenario's
  boot facts are asked for before any driver has adopted it. Per-scenario diagnosis is preserved by
  re-running a failed sweep one process each (R2), the per-scenario deadline lives in the driver
  where the stuck scenario's name is known (R3), and `SMOKE_ISOLATE=1` still runs the verbatim
  one-process-per-scenario path (R1). `ScreenshotUtil.save_frame` is the one shutter both the batch
  and the classic quit path share, and it forces a draw before reading the viewport: macOS stops
  presenting an occluded window, and the viewport texture then hands back a stale or blank frame.
  D2: **engine-bundle metadata tricks are refuted** — `LSUIElement` and `LSBackgroundOnly`
  clones each still stole focus 3/3;
  do not re-litigate without new evidence. D3: an interactive (tty) launch still `exec`s Godot
  directly and comes up focused; only tty-less launches get the restore watcher. D1: the sweep's
  captures staying byte-identical is the merge bar for any change here — it is what keeps the two
  text-heavy scenarios a batch runs first (the process-wide font atlas shifts them otherwise)
  honest as the roster moves. D6: fewer windows beats faster restores — the wrapper is the safety
  net, batching is the fix. Nothing under `core/` or `ai/` learns the sweep exists.
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
  The save format is version 8: the roster arrived at 4, the grouping at 5, the fallen at 6 (the
  plan's "save v4 carries `eliminated`" is superseded by that ordering), each army's home HQ at 7 —
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
  shipped board whose armies start holding cities — air frames are expensive and the soak had to
  show aircraft actually built), `maps/causeway.txt` (30×22, four island homes bridged to a neutral
  mid-sea chain — added after this plan by COM-134) and `maps/confluence.txt` (32×24, two bases, an
  airport and a port to a seat, four tidal arms running into one central sea, and a harbour island
  of neutral docks nothing walks to — added after this plan by COM-135) are the shipped
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
  `maps/fixtures/quartet.txt` stays a fixture, out of the menu and out of the map lint — sized to fit
  the battle viewport whole, and the board `make smoke`'s `side_victory` and `mixed_seat_handoff+fog`
  scenarios run on. The plan artifact carries its own milestone pass: FP1–FP6 are marked shipped in
  `.lavish/four-players-plan.html`, whose decisions stay as authored — every supersession is here.
- `four-player-maps-plan.html` — a seat may stay empty, and eight more four-seat boards: OS1 (the
  sim), OS2 (the table), OS3 and OS4 (the shelf). Builds on four-players and never duplicates it.
  D1: **the map's roster authority bends downward only** — the board still owns how many seats
  exist and where they sit, the match owns which of them are filled, any two or more.
  `GameState.create` gains a defaulted `p_seats` (empty = every seat, today's behaviour verbatim)
  and a closed seat **never enters the state**: no purse, no commander, no turn, no banner, its
  `[units]` rows skipped and its `[owners]` rows opened to neutral, so its HQ and base become ground
  anyone may take. Modelling it as a day-0 *elimination* is the rejected alternative and stays
  rejected — a ghost in the standings, the liveries, the banner and every save is a ghost that
  leaks. So is a menu-side preprocessor handing the sim a doctored `MapData`: that is a second
  opinion about the roster between the file and the state, which is the drift four-players D1
  exists to prevent. The invariant to hold onto, and why nothing downstream needed changing: **a
  reduced match on a big board produces exactly the state a small board would have produced.**
  Seats keep their own numbers — closing seat 2 of four leaves `[1, 3, 4]`, never a renumber,
  because `[owners]`, `[units]`, the liveries and the commander picks are all keyed by the seat's
  team id — and `create` is the one authority that refuses a seating, out loud and with no guessing:
  a seat the board never dealt, a seat named twice, or fewer than `MIN_SEATS` armies left.
  D3: **`GameState.home_hq` is the single authority for what an army can be beheaded through** —
  ask it, never `terrain_at(cell).id == "hq"`. "Capturing an HQ eliminates its owner" is exact only
  while every HQ has a living owner and no army holds two, and this milestone breaks the first while
  a conqueror already broke the second: a vacant seat's HQ has nobody to fell, and a survivor
  holding a conquered HQ must not be beheadable through it. Recorded by `create` from the map's
  starting ownership (`GameState.home_hqs`, the one derivation, read off the *map* because
  mid-match "the HQ this team owns" has two answers exactly when it matters), and carried in save
  v7 — the map derives the same answer, so what persisting it buys is the **pin**: a save whose
  board has since moved an HQ is refused rather than silently re-homed, which
  `SaveCodec._home_hq_board_error` enforces cell by cell. Every other HQ is a high-value property
  with HQ terrain stars, captured like a city.
  D2: **seats are the match's fourth setup fact** — `MatchRequest.seats` (empty = all) through all
  three adapters: `from_menu` reads the strip, `from_match` copies the live `state.teams` so a
  rematch of a reduced match is that match again, `apply_cmdline` reads `--seats=1,3,4` and reads it
  **before `--co=`**, because a commander list is positional over the seats that *play*. The request
  parses and does not vet; the board is where a seating is refused.
  D4 is the seat strip's third state and lives in the four-players D6 entry above, beside the rest
  of the strip. D5: **boards are authored full and reduced fairness is a convention, not a parser
  feature** — every four-seat board lints as a four-army map, and the authoring convention is that
  **opposite seats (1&3, 2&4) make the fair duel**, which the Duel preset encodes and a
  90°-rotational layout makes true by construction. No map-file metadata for seatings, no
  recommended-pairs syntax: the convention lives in the boards' header comments and in the preset.
- `replay-plan.html` — re-watching a finished match, and reading the computer's mistakes out of
  one: milestones RP1 (the format and the recorder), RP2 (playback), RP3 (the menu), RP4 (the
  offline analyser), **all shipped**. D1: **a replay is an opening envelope and a command
  log** — the opening is `SaveCodec.encode` verbatim (so it carries the roster, the grouping, the
  commanders' charge and `rng_state`, and a resumed save records correctly), and the format owns
  only the command list; map + seed rebuilt through `create` is the rejected alternative, being a
  second opinion about what a match opens as. A line names its actor by the cell it acted from,
  which is unambiguous because a carried unit can never act. D2: **the recorder observes at the two
  brokers that already exist** — `BattleCommandPipeline.execute` and `BalanceMatchEngine.play`,
  each side of `apply` exactly as `BalanceMatchRecorder` is already handed a command; nothing under
  `core/` or `ai/` gains a hook, and `tools/check_scripts.sh` already enforces that the live broker
  is the only one. D3: **a replay verifies itself** — every line carries a 48-bit board digest
  (48 because JSON has one number type and a double holds integers exactly only to 2^53), and
  playback halts at the first mismatch naming the command, because the one thing a command log
  cannot survive is the game changing underneath it; a replay is disposable, so a stale one is
  deleted rather than migrated. D4: **playback is presentation** — `BattleReplayRunner` is
  `BattleAiRunner`'s sibling driving `Battle.execute_command`, no planner is built, and
  **`game.fog_enabled` is untouched** (fog is an input to `MoveCommand.validate` and to the ambush,
  so switching it off would resolve the recorded moves differently), which is why the omniscient
  viewer is a `BattlePerspective` flag and nothing else. Playback borrows `State.AI_TURN` and its
  pause seam, so the replay controls are the pause menu's: Esc parks the runner between commands,
  `replay_step` (S) takes exactly one more command and re-parks on the board rather than under that
  menu, and the menu itself drops the two save rows (`BattleMenus.map_actions`'s `savable`) because a
  playback seats no computer — saved and resumed, a recorded AI match would come back as a hot-seat
  one. For the same reason the victory lockup's rematch button reads **Restart** over a playback and
  re-stages `MatchRequest.from_replay` off `Battle.replay_path` rather than deriving a live match
  from the recorded board. D5: omniscient viewer, always-on recording into ten rotating slots under
  `user://replays/`, appended per command so a crash costs the last line rather than the file — and
  the slot is claimed by the **first command**, never the boot, because the slots rotate and a match
  nobody played must not evict one somebody did. D6: **the analyser asks the rules, never the
  planner** —
  counterfactuals come from `AttackRange` / `MovementResolver` / `CombatResolver.forecast_at`, no
  why-hook is threaded out of `ai/`, and a finding is evidence rather than a gate, so
  `make replay-report` stays out of `make verify`. D7: `--watch` (re-plan from a seed, the balance
  plan's BS3 fidelity instrument) and `--replay=` (immune to AI changes by design) are two
  instruments, not one; a `--replay=` naming no file is a viewing that named nothing and is refused
  out loud (`MatchRequest.replay_requested` is the fact `BattleSetup` reads), never quietly played
  as an ordinary match on the default board. The merge bar is `tests/unit/test_replay_fidelity.gd`: a seeded headless
  match, recorded and re-issued, reproducing every checkpoint and an identical final board. The
  analyser's nine detectors each have a fixture that fires them exactly once
  (`tests/unit/test_replay_analysis.gd` over `maps/fixtures/analysis.txt`), because a false positive
  costs more than a miss — it sends the reader looking at a doctrine that was playing correctly.
  `walk_into_fire` carries the shape that rule takes: it fires only when **staying put was
  survivable**, since a unit already inside the same fire did not walk into anything and reporting
  it buries the moves that did. `oscillation` carries the same shape from the other side: it says
  "having fought nothing", so it fires only when nothing was fought or captured across **both**
  turns the walk spans — a unit that went out, took its shot and came home is not walking in a
  circle, and a finding whose own detail line the board contradicts is worse than a miss.

## Architecture — the rules that matter most

1. **Simulation / presentation split.** The game state (map, units, funds, turn) lives in
   **pure GDScript classes with no `Node` dependency**. Scenes only render state and animate
   changes. This keeps rules unit-testable and lets the AI simulate moves cheaply.
   - **Nothing in `core/` may reference a `Node`, a scene, `get_node`, `SceneTree`, or anything
     under `scenes/`.** If you reach for a Node inside `core/`, you're in the wrong layer.
2. **Data-driven via Resources.** Unit stats, terrain properties, and the damage chart are
   `.tres` `Resource` files under `data/`, not constants in code. Balancing = editing data;
   adding a unit = adding a file. The damage chart is one resource holding two attacker × defender
   base-damage matrices — the stocked primary and the infinite-ammo secondary — and it owns which
   of them a shot uses (`select_shot`); a matchup that appears only in the secondary matrix is one
   the secondary is always preferred for. Commanders split the two: the doctrine is a
   `CommanderType` subclass in `core/commanders/`, every number it reads is `@export` on its
   `.tres` in `data/commanders/`.
3. **Command pattern for all actions.** Every player or AI action is a command object under
   `core/commands/` (`Move`, `Attack`, `Capture`, `Build`, `EndTurn`, …) that is *validated* then
   *applied* to the sim, which emits typed events the scene layer animates. This gives us undo of
   uncommitted moves, an AI that issues the same commands as the player, and a serializable log
   for save/replay.
4. **Determinism.** RNG (combat luck) is **seeded**. Same seed + same commands ⇒ same result.
   Never call global `randf()`/`randi()` in `core/`; thread a seeded RNG through the sim.

Flow: `input → Command → sim validates & applies → typed events → scenes animate`.
The AI plugs in at the exact same point as player input.

## Project layout

```
res://
├─ core/        # sim: game_state.gd, commands/, rules/, commanders/  (NO Node references)
├─ data/        # .tres resources: units/, terrain/, commanders/, ai/, difficulty/,
│              # battle_anim/ (weapon signatures), damage_chart
├─ scenes/
│  ├─ battle/   # battle.tscn, cursor, unit_sprite
│  │  └─ cutscene/  # the combat & capture cut-ins and the BattleStyle they read
│  ├─ menu/     # main_menu.tscn — map and commander select, match options
│  ├─ common/   # helpers shared by both scenes (SideIdentity, GameSpeed, …)
│  └─ ui/       # HUD bars, menus, damage preview, the first-match mission strip
├─ autoload/    # singletons: EventBus, MatchConfig, Settings, Sfx
├─ ai/          # AIController façade + planning context + unit/production planners
│              # ai_profile.gd owns every weight; NO Node references
├─ maps/        # map scenes / map resources
├─ assets/      # sprites, audio, fonts  (+ LICENSES.md)
├─ tools/       # offline scripts: balance harness (tools/balance/), AI arena
│              # (tools/arena/), replay analyser (tools/replay/), art & sfx pipeline
├─ docs/        # balance_sim.md, commander_balance.md, difficulty_check.md, ai_arena.md
└─ tests/       # GUT tests — target the Node-free layers only (see Testing)
```

## GDScript conventions

Follow the official Godot GDScript style guide. Key points:

- **Indentation: tabs**, not spaces (Godot standard).
- **Typed GDScript everywhere.** `var hp: int = 10`, `func attack(target: Unit) -> void:`.
  Prefer explicit types over inferred `:=` when it aids readability.
- **Naming:** `snake_case` for files, variables, and functions; `PascalCase` for `class_name`
  and node names; `CONSTANT_CASE` for constants and enum values.
- **One `class_name` per file**, matching the file name (`game_state.gd` → `class_name GameState`).
- **Private** members and methods are prefixed with `_` (`_recalculate_range()`).
- **Signals** are named in past tense (`unit_moved`, `unit_damaged`, `turn_ended`) and declared
  with typed parameters. Emit domain events from the sim; the presentation layer subscribes.
- Prefer **composition and small resolvers** (`MovementResolver`, `CombatResolver`, `AttackRange`)
  over god-objects.
- Use `@export` for inspector-editable fields on Resources/Nodes; validate in code, don't trust it.
- Don't `preload`/`load` scene or Node types inside `core/`.

## Testing

- Tests use **GUT** (Godot Unit Test) and live in `tests/`, mirroring `core/` and `ai/`.
- **Test the Node-free layers only** — `core/`, plus `ai/`, the offline balance harness in
  `tools/balance/`, the arena's grammar, scorer and pools in `tools/arena/`, and the replay
  analyser in `tools/replay/`, all of which are Node-free for
  exactly this reason. That's where the rules
  live and where bugs hurt. Presentation is verified by playing the scene, not by unit tests.
  The narrow exception is the launch layer that was deliberately made Node-free and
  argument-taking so it could be tested at all: `MatchRequest` and `CmdArgs` under
  `scenes/common/` (the flag grammar every `make smoke` scenario and Balance Lab row is launched
  with), and `MatchConfig`'s staging, which is reachable without a scene and is where `take()`
  clearing is held. `TransitionInput` joins them on the same terms: a pure static answer over an
  `InputEvent`, so the boundary convention every banner and the victory lockup obey is checked
  without a scene. `DirectionalInput` joins it on the same terms: a pure answer over an
  `InputEvent` and the `InputMap`, so the one-step-per-gesture convention the board cursor and
  every menu obey is checked without a pad. `SeatStrip.normalised_sides` and
  `SeatStrip.reopened_seats` join them on the same terms and for the same reason: the grouping and
  seating arithmetic a shrinking roster runs through is static and pure, so it is checked without
  building the strip.
- Every bugfix in `core/` or `ai/` should come with a failing test that the fix makes pass.
- Keep tests deterministic: seed the RNG explicitly.

Run the suite with `make test` — it runs GUT headless against `tests/unit` via `.gutconfig.json`.
See README.md for engine setup and the other `make` targets.

Before a change is done, run `make verify` — the aggregate gate it chains, in order: `check`
(`tools/check_scripts.sh`, a lightweight script audit), `lint` (`gdlint`), `format-check`
(`gdformat --check`), then the GUT suite. `make format` rewrites files to satisfy `format-check`,
and any gate also runs alone (`make lint`, `make test`, …). GDScript is tab-indented — let
`gdformat` settle whitespace rather than hand-aligning, and a green `make verify` is the bar a
change clears before it ships.

## Running the game

Play with `make run` (boots the main menu); `make screenshot` boots the battle scene directly,
saves `screenshot.png`, and quits. See README.md for engine setup and the other `make` targets.

Prefer the running game (or a GUT test) over reasoning alone when verifying a change.

## Working in this repo

- **Match the plan's milestones.** Ship something playable each milestone; don't pull scope
  forward — the plan artifacts track which milestones are done and what each one owes.
  Scope creep is the named top risk.
- **Balance numbers live in `data/`.** Don't hardcode stats you could put in a `.tres`.
- **Dense commenting is a smell — fix the code, not the commentary.** If a block needs a running
  narration to follow, the names, the split, or the shape are wrong: extract it into a well-named
  function, rename what it walks, or drop the branch that made it confusing. A comment earns its
  place explaining *why* — a constraint, a non-obvious ordering, a source of truth — never *what*
  the line already says.
- **A paragraph defending a workaround means the code is wrong.** If you need to write one to
  explain or justify an implementation, treat that as the signal — don't document around an
  avoidable design problem. Fix the underlying code so the implementation is straightforward and
  idiomatic and needs no lengthy justification. A short comment noting a genuine constraint is
  fine; a long defence of unusual code is a prompt to reconsider and simplify.
- **Don't hand-edit** `.import` files or the binary/UID bits of `.tscn`/`.tres` unless you know
  exactly what you're doing — let Godot regenerate them. Do read `.tscn`/`.tres` to understand a
  scene, and prefer editing resource *data* over scene graph plumbing.
- **`project.godot`, autoloads, and the input map** are edited through the editor when practical;
  if editing by hand, keep changes minimal and reviewable.
- **`AIController` is a façade, not a planning bucket.** It asks for Command Power first, then
  delegates to exactly two coarse collaborators: `AIUnitActionPlanner` and
  `AIProductionPlanner`. `AIPlanningContext` is the one owner of scan-ordered per-decision facts
  (friendlies, visible enemies, properties, unit types, goals, capture claims and the production
  roster) and the threat map cache shared across decisions in a turn. `AIPlanCache` is the planner's
  own, keeping each ready unit's `AIUnitPlan` between the commands of one turn and dropping what a
  **board diff** — never the returned `Command` — says could have moved; rescoring every survivor
  after every command is load-bearing (it is how a wounded target's kill reaches the next attacker),
  so the cache may drop a plan that still held and may never keep one that did not (arena plan AR1).
  Preserve strict comparator order and profile reads when moving AI code; never tune a `.tres` in
  an extraction.
- **Doctrine hooks take an `Engagement`, not two `Unit`s.** `core/rules/engagement.gd` carries the
  effective values a shot is resolved with: the cell it is *actually* fired from and the HP the
  formula should use — which is what keeps the damage preview and the resolved attack on
  identical numbers. `CombatResolver.forecast_at` takes the defender's cell for the same reason,
  so the AI can ask "how hard am I hit if I stop here?" without standing a live unit somewhere to
  ask it. Forecasting is a pure read — if a query has to mutate the board, it is wrong.
- **Single authorities — ask them, never re-derive.** `core/rules/attack_range.gd` owns **who** a
  unit may shoot, **how far**, and **with which weapon** (`can_engage`, `covers`, and `ready_shot`
  — the one selector, over `DamageChart.select_shot`, that every caller from `AttackCommand` to the
  overlays, the forecast, the counter, the AI and the threat map goes through; `can_fire` is its yes
  or no). Nobody asks a unit whether it has ammo: `Unit.ammo` is the primary pool alone, and only
  the selector knows a dry primary can still fall back to an infinite secondary.
  `core/movement_resolver.gd` owns the
  movement budget and per-step terrain cost, **including inside `MoveCommand.validate`**. Both
  exist because independent second opinions were real bugs here: a fourth opinion on movement made
  the range overlay offer cells the command then refused, and asking the damage chart directly was
  the whole answer only until a submarine could be under the water. Countering is the one
  deliberate exception on distance, documented on `CombatResolver._counter_shot`.
  `LoadCommand.carriage_error` joined them for the same reason: it owns **may this rider be
  inside this transport at all** (transport, cargo class, capacity, no second level of nesting,
  same team), asked by `LoadCommand.validate` before a board and by `SaveCodec` per wired carrier
  link — while the codec kept its own opinion, a hand-edited save could seat a battleship in an
  infantry.
- **Movement domains are data, not code.** A move class is a key in each terrain's `move_costs`
  (`air` on every terrain, `ship`/`lander` on the water) — aircraft and hulls needed no
  `MovementResolver` change. What a property builds and refits is `TerrainType.builds` /
  `services`, read by `BuildCommand`, the build menu and the AI's production alike — never a
  terrain id checked in three places.
- **Vision/fog:** `core/rules/vision.gd` is the single authority for "what can this player see?" —
  ask it, never re-derive visibility. Fog is enforced in the presentation layer (the sim stays
  permissive, the UI refuses to target or inspect what the viewer cannot see). The AI deliberately
  sees everything **except** units a doctrine hides — it asks `Vision.is_hidden_from` for that one
  case; don't widen the exception without a matching plan decision. The one made widening:
  a committed path is planned and walked with the mover's *own* visibility, so a unit hidden from
  the AI can spring an ambush on its move exactly as one can on a human's — the AI's *pathing* is
  fog-limited, its *targeting* stays omniscient-except-doctrine-hidden. A submerged submarine is
  hidden through the same hook even with fog off.
  In the live scene, `scenes/battle/battle_perspective.gd` (`BattlePerspective`) is the one
  adapter from that rule authority to viewer policy: viewing team plus hot-seat blackout, firing
  geometry delegated to `AttackRange`, typed transport drop options, and how much of a unit's reach
  and fire ring an overlay may show (that rule is the range-preview plan's, above). `Battle`,
  `BattleView`, `BattleAnimator`, `BattleCommandPipeline` and `BattleScenarioDriver` ask it; none
  re-derives visibility or reaches through a sibling's private helper, and the runner drives AI
  turns through `Battle`'s own named entry points.
- **A live command applies once.** `scenes/battle/battle_command_pipeline.gd`
  (`BattleCommandPipeline`) is the only live-scene owner of command validation, application and
  result presentation; both `Battle` and `BattleAiRunner` enter through `Battle.execute_command`.
  It captures combat/join/drop references before apply, replays `AttackCommand.result` and
  `CaptureCommand.result`, gates AI movement through `BattlePerspective`, and reconciles sprites,
  properties, fog, the panel and the HUD. Its typed `BattleCommandReceipt` returns validation,
  turn, winner, watch and ambush facts. The callers still own selection/input transitions, AI
  planning and pacing, save policy, and victory presentation — do not move those into the
  pipeline. The headless `BalanceMatchEngine` stays separate.
- **Which match to play is a typed request, not an autoload's fields.**
  `scenes/common/match_request.gd` (`MatchRequest`) states one launch in full — board, which of its
  seats play (`seats`, empty = every one; `--seats=` is read before `--co=` because the commander
  list is positional over the seats that play), who plays them, how they group into sides, fog,
  tier, commanders, resume, seed, watch, day cap, raw side specs, the recording to watch — and
  is built by one of four adapters: `from_menu`, `from_match` (a rematch, derived from the *live*
  `GameState`, so a match resumed from a save replays its own board and commanders),
  `from_replay` (a recording, which states its own board, seating, grouping, commanders and fog in
  its opening envelope, so naming the file is the whole request) and
  `apply_cmdline`, layered over any of them on **every** battle boot, which is how a headless capture
  and a menu launch reach the same board by the same route. `BattleSetup.build(request, …)` reads
  no autoload, scans no command line and writes nothing back; it returns `null` with a pushed error
  when the board or the state cannot be built (`assert` is stripped from a release build), and
  `Battle` disables itself rather than dereferencing a null map. `MatchConfig` carries exactly one
  staged request, and `take()` clearing is load-bearing rather than tidy: it is what makes a resume
  that found no save on disk unable to latch into the next boot.
- **The command line is parsed in one place.** `scenes/common/cmd_args.gd` (`CmdArgs`) — `user()`
  is the only `OS.get_cmdline_user_args()` call outside `tools/`, and the six inline scans it
  replaced are why one flag was last-wins and another first-wins with nobody deciding either.
  `value()` is last-wins, `flag()` matches a bare switch, and `has()` exists because an *empty*
  flag is not an *absent* one — `--co=` clears the commanders the menu picked and `--seed=` pins
  seed 0 — so gate an override on `has`, never on a non-empty value. `autoload/settings.gd`
  deliberately keeps its own ordered walk (its `pin()` latches, so there the *first* `--speed=`
  lands and `--reset-hints` must see the flags before it); a comment there says so.
- **The battle cut-in replays; it never decides.** `BattleAnimator.animate_combat` is the one
  seam — its one live call site, `BattleCommandPipeline`, `await`s it, and it returns exactly
  once, full-screen cut-in or on-map hit. Inside `scenes/battle/cutscene/` everything is a pure
  function of one clock: skipping sets the clock to the end rather than cancelling tweens, which
  makes "any press, at any beat, lands on the right board" true by construction. That clock is
  literally one object — `cutscene_playback.gd` (`CutscenePlayback`), the shell both directors
  compose: it owns the clock, the letterbox, the camera's return to rest, the cue ledger and what
  counts as a skip press, so no cut-in gets a second opinion on any of them. A director owns only
  its beat sheet and what it paints in the band. Every number the cut-in shows was handed to it
  (the result's two HP snapshots, the units themselves); none is recomputed from the damage chart
  or the RNG. It is suppressed while `capturing` — so
  `make screenshot` stays byte-stable, posed cut-ins go through `pose_at` — and it only plays when
  the *viewer* can see both combatants, asked of `BattlePerspective` (and so of `Vision`), never
  re-derived.
- **A computer turn is held between commands, never inside one.** `Battle.pause_gate` is the one
  point `BattleAiRunner` stops at, so Esc during an AI turn is *requested* and honoured at the next
  boundary — where the board has settled and nothing of that turn's own is on screen, which is what
  keeps "no interactive menu sits under a banner or a cut-in" (ux-recovery D3) true here rather
  than by luck. The press still gets an answer of its own, so a pause never reads as a dead key.
  `Battle.rest_state()` is the single answer to where a closing menu, sheet or banner lands — the
  player's board, or the frozen board of a paused turn — because IDLE mid-computer-turn hands over
  a board nobody may play; ask it, never spell `State.IDLE` for "back to rest" again. The pause is
  presentation and nothing else: no rule, no command and nothing under `core/` or `ai/` learns it
  happened, the runner picks its turn up where it stopped, and the only thing the menu itself
  changes is `BattleMenus.map_actions(game, commandable)` dropping the two rows that would act for
  the side on turn. The wake-up is a signal rather than a flag the runner polls, so leaving the
  match from the pause menu takes the parked await with the scene instead of resuming into a board
  that is gone. It matters most in a watched match, where every turn is a computer's and there was
  otherwise no route to a menu — or out — at all; `ai_pause` in `BattleTransitionScenario` is the
  driven proof, and the claim it exists for is that a resumed turn really resumes.

## Communication

- **Be concise.** Keep responses, summaries, and explanations short — lead with the answer, cut
  background the reader didn't ask for, and skip restating what the diff or the conversation
  already shows. Same goes for commit messages, PR bodies, and code comments.
- **Speak simply.** Use plain words and short sentences. Prefer everyday language over jargon, and
  when a technical term is needed, say what it means in a few words.

## Commits

- Small, focused commits scoped to one milestone task.
- Present-tense, imperative subject (`Add Dijkstra movement range`).
- Don't commit generated import caches or engine temp files (`.godot/` is ignored).
