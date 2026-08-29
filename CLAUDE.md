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
architectural decision in its area.** Each entry below names a plan's scope and the rule file
holding the locked decisions that must survive any change; milestones and the original argument
live in the plans themselves. Nine entries carry more than an index can hold, so **their long
form — the rationale, the measurements, the superseded clauses and the risk registers — is
`docs/design_record.md`**: AI Judgement, AI Economy, the AI Arena, four players, the asymmetric
board, campaign depth, the battle animations, the zoom ladder and the animation milestone, and
the mobile builds. **Read that file's entry before an architectural decision in one of those nine
areas.** Every other plan is stated in full in its rule file and has no copy there.

**The entries themselves live in `.claude/rules/*.md`, and they load by path** — a rule file
carries a `paths:` frontmatter, so its entries enter the session only once a matching file is
read. A session working outside an area therefore has to open that area's rule file by hand
before an architectural decision there, and so does any agent that reads `AGENTS.md` without
`.claude/rules/`.

- `grid-commanders-plan.html` — the base game, M0–M7, the mechanics reference and the damage formula — `.claude/rules/instruments.md`
- `commanders-plan.html` — Commanders and Command Powers, C1–C4 and locked decisions D1–D4 — `.claude/rules/commanders.md`
- `new-commanders-plan.html` — six more generals, NC1–NC7, and Iris Colt's retuned Second Wind — `.claude/rules/commanders.md`
- `more-commanders-plan.html` — four more generals, MC1–MC5, and the aimed power — `.claude/rules/commanders.md`
- `difficulty-modes-plan.html` — the difficulty tiers, DF1–DF4, and the AI-never-cheats lock — `.claude/rules/ai.md`
- `naval-air-units-plan.html` — the air and naval domains, N1–N4, and the no-ferry risk R1 — `.claude/rules/maps.md`
- `map-retrofit-plan.html` — which shipped boards carry a port or airfield — `.claude/rules/maps.md`
- `production-maps-plan.html` — the `forge`/`arsenal`/`steelworks` boards — `.claude/rules/maps.md`
- `balance-simulator-plan.html` — the offline balance instruments, BS1–BS4 — `.claude/rules/instruments.md`
- `game-speed-plan.html` — the game-speed setting, GS1–GS3, and the pacing-free lock over `core/` — `.claude/rules/presentation.md`
- `faction-identity-plan.html` — armies wear their commander's faction, FI1–FI3 — `.claude/rules/presentation.md`
- `tile-info-panel-plan.html` + `.lavish/hud/SPEC.md` — the tile info panel and the docked HUD — `.claude/rules/presentation.md`
- `battle-animations-plan.html` — the combat cut-in, BA1–BA4 — `.claude/rules/presentation.md`
- `capture-animation-plan.html` — the capture cut-in, CP1–CP3 — `.claude/rules/presentation.md`
- `power-quotes-plan.html` — Command Power quotes, PQ1–PQ2 — `.claude/rules/commanders.md`
- `range-preview-plan.html` — the range preview, RP1–RP3 — `.claude/rules/presentation.md`
- **Field overlays** — the threat lens, the arrowed path and the capture pip — `.claude/rules/presentation.md`
- **The zoom ladder is integers above its floor** and the animation milestone's nine slices — `.claude/rules/presentation.md`
- **The next-ready-unit key** — `N` walks the cursor to the next unit that has not acted — `.claude/rules/presentation.md`
- `commander-doctrine-ai-plan.html` — the computer plays each general like that general, CA1–CA4 — `.claude/rules/ai.md`
- `ai-judgement-plan.html` — denial, withdrawal and cohesion, AJ1–AJ4 — `.claude/rules/ai.md`
- `ai-economy-plan.html` — the planner reads the map as an economy, AE1–AE4 — `.claude/rules/ai.md`
- `ai-arena-plan.html` — the self-play arena, AR1–AR7 — `.claude/rules/ai.md`
- **AI logistics** — the planner issues `SupplyCommand` — `.claude/rules/ai.md`
- `menu-revamp-plan.html` — the main-menu and commander-select redress, MN1–MN3, and `UiTheme`/`UiKit` — `.claude/rules/presentation.md`
- `ux-recovery-plan.html` — first contact and the new-player registers, U-01–U-26 — `.claude/rules/presentation.md`
- `focus-steal-plan.html` — the smoke sweep and the desktop's window focus, FS0–FS3 — `.claude/rules/instruments.md`
- `four-players-plan.html` — up to four armies, FP1–FP6 — `.claude/rules/maps.md`
- `four-player-maps-plan.html` — a seat may stay empty, and eight more four-seat boards, OS1–OS4 — `.claude/rules/maps.md`
- `asymmetric-board-plan.html` — Bulwark, the board that is not fair on purpose, AB1–AB4 — `.claude/rules/maps.md`
- `replay-plan.html` — re-watching a finished match and reading the computer's mistakes out of one, RP1–RP4 — `.claude/rules/instruments.md`
- `campaign-depth-plan.html` — mission variety, scripted events, the consequence ledger and the carried army, CD1–CD8 — `.claude/rules/campaign.md`
- **Campaign mode** — the six authored wars and the campaign layer's own architecture — `.claude/rules/campaign.md`
- **Standing terrain is interactive; the ground plane is where ambient variety lives** — `.claude/rules/presentation.md`
- `mobile-builds-plan.html` — the whole command table in two hands, MB1–MB9 — `.claude/rules/presentation.md`

## Architecture — the rules that matter most

1. **Simulation / presentation split.** The game state (map, units, funds, turn) lives in
   **pure GDScript classes with no `Node` dependency**. Scenes only render state and animate
   changes. This keeps rules unit-testable and lets the AI simulate moves cheaply.
   - **Nothing in `core/` may reference a `Node`, a scene, `get_node`, `SceneTree`, or anything
	 under `scenes/`.** If you reach for a Node inside `core/`, you're in the wrong layer.
2. **Data-driven via Resources.** Unit stats, terrain properties, the damage chart, and the
   match-wide balance levers (`RulesConfig` in `data/rules.tres` — capture speed, income, repair,
   property vision, the charge split, the pricing floor and step, the neutral luck bounds) are
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
├─ core/        # sim: game_state.gd, commands/, rules/, commanders/, campaign/  (NO Node references)
├─ data/        # .tres resources: units/, terrain/, commanders/, ai/, difficulty/,
│              # battle_anim/ (weapon signatures), campaigns/, damage_chart, rules
├─ scenes/
│  ├─ battle/   # battle.tscn, cursor, unit_sprite
│  │  └─ cutscene/  # the combat & capture cut-ins and the BattleStyle they read
│  ├─ menu/     # main_menu.tscn — map and commander select, match options, campaign screens
│  ├─ common/   # helpers shared by both scenes (SideIdentity, GameSpeed, MobileProfile, …)
│  └─ ui/       # HUD bars, menus, damage preview, the first-match mission strip,
│              # the in-battle mission objective card and scripted-beat speech card,
│              # the touch dock and its hit areas (mobile builds only)
├─ autoload/    # singletons: EventBus, MatchConfig, Settings, Sfx, Music, CampaignSession
│              # (project.godot also registers _mcp_game_helper, the godot_ai editor
│              # addon's runtime — it loads in every run today; keeping it out of export
│              # builds is an open decision, recorded here so the extra autoload is
│              # never a surprise)
├─ ai/          # AIController façade + planning context + unit/production planners
│              # ai_profile.gd owns every weight; NO Node references
├─ maps/        # map scenes / map resources (campaign boards under maps/campaign/)
├─ assets/      # sprites, audio, fonts  (+ LICENSES.md)
├─ tools/       # offline scripts: balance harness (tools/balance/), AI arena
│              # (tools/arena/), replay analyser (tools/replay/), the UI-chrome
│              # art pipeline
├─ generators/ # the asset pipelines that live in this repo rather than beside it —
│              # audio/, sprites/ and portraits/ are Python (make audio / make tiles /
│              # make portraits install their output; make audio-test /
│              # make sprites-test / make portraits-test are their gates, and
│              # make portraits-snapshot re-reads the installed art).
│              # generators/.gdignore keeps the engine out entirely
├─ docs/        # the offline instruments' committed records (the Balance Lab, the
│              # commander matrix, the difficulty ladder, the arena, Bulwark's spread,
│              # the mobile soak), and how to author a campaign mission
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
  `tools/balance/`, the arena's grammar, scorer and pools in `tools/arena/`, the replay
  analyser in `tools/replay/`, and the composite legibility metric in `tools/legibility/`
  (`LegibilityMetric` — the arithmetic only; the render sweep it reports in is an offline
  instrument like the Balance Lab and stays out of `make verify`, and `LegibilityBaseline`, the
  committed verdict digest that sweep is diffed against and the rule that only a PASS turning FAIL
  is a failure), all of which are Node-free for
  exactly this reason. That's where the rules
  live and where bugs hurt. Presentation is verified by playing the scene, not by unit tests.
  The narrow exception is the launch layer that was deliberately made Node-free and
  argument-taking so it could be tested at all: `MatchRequest` and `CmdArgs` under
  `scenes/common/` (the flag grammar every `make smoke` scenario and Balance Lab row is launched
  with), and `MatchConfig`'s staging, which is reachable without a scene and is where `take()`
  clearing is held. `TransitionInput` joins them on the same terms: a pure static answer over an
  `InputEvent`, so the boundary convention every banner and the victory lockup obey is checked
  without a scene — and its two `dismissed_by_*` readings, which also stamp the receipt on the
  page's viewport, are checked under a `SubViewport` per case in `test_page_dismissal.gd`
  rather than by booting a scene. `DirectionalInput` joins it on the same terms: a pure answer over an
  `InputEvent` and the `InputMap`, so the one-step-per-gesture convention the board cursor and
  every menu obey is checked without a pad. `SeatStrip.normalised_sides` and
  `SeatStrip.reopened_seats` join them on the same terms and for the same reason: the grouping and
  seating arithmetic a shrinking roster runs through is static and pure, so it is checked without
  building the strip. `CampaignSession` earns `MatchConfig`'s exception the same way: the autoload
  is up for the whole headless run and reachable without a scene, and its lifecycle — armed by
  `begin`, silent for every skirmish, emptied whole by `clear` — is exactly what
  `tests/unit/test_campaign_session.gd` pins. `BattleSetup` joins them too: it takes a request and
  the databases and hands back plain simulation objects with no `Node` and no scene path, so
  `test_seats_flag.gd`, `test_sides_flag.gd` and `test_resume_setup.gd` build a match by calling it
  directly rather than booting the scene. `BattleMenus` is the same shape one layer up — which rows a menu offers is
  content, gated by the same command authorities the rows would run, not scene plumbing — so
  `test_unit_pricing.gd` reads a build row's price and disabled state straight off it.
  `BattleCampaign.objective_cells` joins them on the same terms: a static, pure read over
  `CampaignSession` and a `GameState` with no `Node` in it, so `test_objective_marks.gd` pins which
  objectives put a mark on the board without staging a battle.
  `TutorialHints` and `ControlHints` are Node-free copy registries for the same reason `GameSpeed`
  is: which mission step is next and which key legend a context prints are each a pure function of
  state the suite can hand them without a scene, so `test_tutorial_copy.gd` and
  `test_control_hints.gd` hold each to its character caps directly — one suite each, the two being
  two subjects. `CommanderVisuals` and `SideIdentity` are the single authority for a
  side's presentation — a portrait, a faction theme, an atlas row, resolved once from the match's
  commander picks with no `Node` and no scene path — so `test_side_identity.gd` and
  `test_side_identity_roster.gd` resolve an identity and assert its colours and rows directly.
  `BattleStyle` (a `Resource`) and its `BattleStyleDB` registry (`RefCounted`) are weapon-signature
  data rather than drawing, so `test_battle_styles.gd` checks every unit names a style that exists
  without staging a cut-in. `PathArrow` and `MapThumbnail` are the two exceptions that are not
  themselves Node-free — they extend `Node2D` and `Control` — but neither suite builds one:
  `PathArrow.segments()` and `MapThumbnail.sheet_path()` / `sheet_region()`, the pure functions the
  `_draw` of each only paints, are static, and are all `test_path_arrow.gd` and
  `test_map_thumbnail.gd` call, the same shape `SeatStrip.normalised_sides` and `TransitionInput`
  are. `BattleZoom.floor_for` joins them on the same terms: which rungs the zoom ladder offers is
  arithmetic over a viewport and a board, so `test_texel_stability.gd` checks it without a camera.
- Every bugfix in `core/` or `ai/` should come with a failing test that the fix makes pass.
- Keep tests deterministic: seed the RNG explicitly. `tests/helpers/fixture.gd` (`Fixture`) is where
  a board, a path, a command line and the shared databases come from — it seeds every state it
  builds — so build one through it rather than re-rolling a local `_state` helper, and set
  `state.rng.seed` yourself only when the test wants a different stream.

Run the suite with `make test` — `tools/run_tests.sh` runs GUT headless as two engines (the two
soaks in one, everything else in the other), a partition of `tests/unit` it checks is complete
before launching; `TEST_JOBS=1` is the verbatim single-engine `.gutconfig.json` pass.
See README.md for engine setup and the other `make` targets.

Before a change is done, run `make verify` — the aggregate gate it chains, in order: `check`
(`tools/check_scripts.sh`, a lightweight script audit), `lint` (`gdlint`), `format-check`
(`gdformat --check`), the GUT suite, then `determinism` (the ~1s pinned-match replay, byte-diffed
against its committed golden). `make format` rewrites files to satisfy `format-check`,
and any gate also runs alone (`make lint`, `make test`, …). GDScript is tab-indented — let
`gdformat` settle whitespace rather than hand-aligning, and a green `make verify` is the bar a
change clears before it ships. `check`'s full-project run is where the repository invariants are
enforced rather than only stated here — the Node-free, RNG-free and pacing-free rules over
`core/` and `ai/`, the per-file line budgets, the one-apply/one-validate seam, and two lints a
contributor otherwise meets blind: no class may reach another's `_`-prefixed member, and every
file path this file, README.md or `docs/*.md` cites must exist. `tools/check_scripts.sh` is the
list; the sweep itself is parallel (`CHECK_JOBS=1` for the serial path).

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
  movement budget, the per-step terrain cost and **where a move may end** (`can_stop`) — all three
  **including inside `MoveCommand.validate`**, which reaches them through `MoveCommand.move_error`,
  the seam a move-and-then command uses when it already holds the mover's sight. Both
  exist because independent second opinions were real bugs here: a fourth opinion on movement made
  the range overlay offer cells the command then refused, and asking the damage chart directly was
  the whole answer only until a submarine could be under the water. Countering is the one
  deliberate exception on distance, documented on `CombatResolver._counter_shot`.
  `LoadCommand.carriage_error` joined them for the same reason: it owns **may this rider be
  inside this transport at all** (transport, cargo class, capacity, no second level of nesting,
  same team), asked by `LoadCommand.validate` before a board and by `SaveCodec` per wired carrier
  link — while the codec kept its own opinion, a hand-edited save could seat a battleship in an
  infantry. `core/grid.gd` (`Grid.manhattan`, and `Grid.ring_offsets` for the Manhattan diamond
  every ring is cut to) is the smallest of them and the one every layer touches: this board
  measures distance four-directionally everywhere — movement, every firing
  ring, sight, supply reach, the planner's goals — so ask it rather than spelling the arithmetic
  again.
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
  and fire ring an overlay may show (that rule is the range-preview plan's, in
  `.claude/rules/presentation.md`). `Battle`, `BattleView`, `BattleAnimator`,
  `BattleCommandPipeline`, `BattleTargeting`, `BattleHandoff` and
  `BattleScenarioDriver` ask it; none re-derives visibility or reaches through a sibling's private
  helper, and the runner drives AI
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
