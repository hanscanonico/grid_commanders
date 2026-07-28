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
- `difficulty-modes-plan.html` — difficulty tiers DF1–DF4. Locked: **the AI never cheats at any
  tier** — difficulty may only change which `AIProfile` the planner weighs moves with, never
  income, vision, damage or luck. Its DF4 acceptance gate is currently **unmet** — read
  `docs/difficulty_check.md` before touching an AI weight or a tier `.tres`.
- `naval-air-units-plan.html` — air and naval domains N1–N4. Standing risk R1: the AI cannot plan
  a ferry, so it never builds transports — a naval map has to let fleets reach each other without
  one.
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
  `defender_hp_before`. D5: how a weapon looks is a `BattleStyle` under `data/battle_anim/`,
  `UnitType.battle_style` is a presentation key like `atlas_col`, and no gameplay number may ever
  appear in a style.
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
  per-enemy attribution), so the red overlay and the planner's fear are one computation.
  Everything else is presentation-only, gated by the same `perspective.can_see_unit` fog rule
  targeting uses; `make screenshot` stays byte-stable.
- `menu-revamp-plan.html` — main-menu and commander-select redress MN1–MN3, shipped. D1:
  **design-system tokens live in one code authority, `scenes/common/ui_theme.gd` (`UiTheme`),
  never a `.tres` Theme** — it re-exports colours that already have an authority (faction hues,
  cream/ink) so there is exactly one value per colour. Map thumbnails
  (`scenes/menu/map_thumbnail.gd`) draw from `TerrainType.atlas_col` × `SideIdentity.atlas_row` —
  a miniature can never be a second opinion. The shared `CommanderCard` keeps its dress until a
  named follow-up (it is also the in-battle info sheet, so restyling it moves commander selection
  too). Fonts (Pixelify Sans, Silkscreen) are vendored, OFL, recorded in `assets/LICENSES.md`.
- `ux-recovery-plan.html` — first-contact and new-player registers U-01–U-26; the onboarding
  slice (COM-12), the rejected-confirm feedback (COM-13, `scenes/ui/action_feedback.gd`) and the
  end-turn ready-unit guard (COM-14/U-10, `scenes/ui/end_turn_guard.gd`) are shipped. D1:
  everything in it is presentation-only, and tutorial state is a device preference
  (`user://settings.cfg`, never the match request, never a save). D6: the tutorial
  owns no rule and observes rather than instruments — steps retire off existing `EventBus`
  signals, filtered to human sides so the computer cannot retire a hint; nothing in `core/` or
  `ai/` gained a hook. A capture pins the hint set (`Settings.pin_hints`, from `Battle._ready`) so
  `make smoke` frames don't depend on play history; `--reset-hints` is the one `Settings` flag
  that deliberately writes. The key legend (`scenes/ui/control_hints.gd`) is printed by
  **`Battle.state`'s setter** via `Battle.STATE_CONTEXT` — never refreshed from the dozen sites
  that assign the state.
- `focus-steal-plan.html` — developer ergonomics: the smoke sweep and the desktop's window
  focus, FS0–FS3; FS0–FS2 shipped, FS3 pending. The instrument is `tools/focus_timeline.sh`
  (FS0) and every claim about focus is a measurement with it, never an anecdote. FS1: the
  watcher in `tools/godot_gui.sh` lives as long as the engine it launched — its only exit
  conditions are the child dying and a human clicking into the game — and restores on every
  activation, never onto the game itself or transient system UI. FS2: the sweep boots **once per
  boot configuration** — scene · fog · map, `group_key` in `tools/smoke_scenarios.sh` — and
  `scenes/battle/battle_capture_batch.gd` (`BattleCaptureBatch`) runs the group in that one
  process, its queue held in statics because a `reload_current_scene` between scenarios is what
  gives each a fresh `Battle` in the same window. Per-scenario diagnosis is preserved by re-running
  a failed group one process each (R2), the per-scenario deadline lives in the driver where the
  stuck scenario's name is known (R3), and `SMOKE_ISOLATE=1` still runs the verbatim
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
  net, batching (FS2) is the fix. Nothing under `core/` or `ai/` learns the sweep exists.

## Architecture — the rules that matter most

1. **Simulation / presentation split.** The game state (map, units, funds, turn) lives in
   **pure GDScript classes with no `Node` dependency**. Scenes only render state and animate
   changes. This keeps rules unit-testable and lets the AI simulate moves cheaply.
   - **Nothing in `core/` may reference a `Node`, a scene, `get_node`, `SceneTree`, or anything
     under `scenes/`.** If you reach for a Node inside `core/`, you're in the wrong layer.
2. **Data-driven via Resources.** Unit stats, terrain properties, and the damage chart are
   `.tres` `Resource` files under `data/`, not constants in code. Balancing = editing data;
   adding a unit = adding a file. The damage chart is one resource holding the attacker × defender
   base-damage matrix. Commanders split the two: the doctrine is a `CommanderType` subclass in
   `core/commanders/`, every number it reads is `@export` on its `.tres` in `data/commanders/`.
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
├─ ai/          # ai_controller.gd — plans Commands; ai_profile.gd — its weights
│              (NO Node references)
├─ maps/        # map scenes / map resources
├─ assets/      # sprites, audio, fonts  (+ LICENSES.md)
├─ tools/       # offline scripts: balance harness (tools/balance/), art & sfx pipeline
├─ docs/        # balance_sim.md, commander_balance.md, difficulty_check.md
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
- **Test the Node-free layers only** — `core/`, plus `ai/` and the offline balance harness in
  `tools/balance/`, all of which are Node-free for exactly this reason. That's where the rules
  live and where bugs hurt. Presentation is verified by playing the scene, not by unit tests.
  The narrow exception is the launch layer that was deliberately made Node-free and
  argument-taking so it could be tested at all: `MatchRequest` and `CmdArgs` under
  `scenes/common/` (the flag grammar every `make smoke` scenario and Balance Lab row is launched
  with), and `MatchConfig`'s staging, which is reachable without a scene and is where `take()`
  clearing is held.
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
- **Doctrine hooks take an `Engagement`, not two `Unit`s.** `core/rules/engagement.gd` carries the
  effective values a shot is resolved with: the cell it is *actually* fired from and the HP the
  formula should use — which is what keeps the damage preview and the resolved attack on
  identical numbers. `CombatResolver.forecast_at` takes the defender's cell for the same reason,
  so the AI can ask "how hard am I hit if I stop here?" without standing a live unit somewhere to
  ask it. Forecasting is a pure read — if a query has to mutate the board, it is wrong.
- **Single authorities — ask them, never re-derive.** `core/rules/attack_range.gd` owns **who** a
  unit may shoot and **how far** (`can_engage`, `covers`); `core/movement_resolver.gd` owns the
  movement budget and per-step terrain cost, **including inside `MoveCommand.validate`**. Both
  exist because independent second opinions were real bugs here: a fourth opinion on movement made
  the range overlay offer cells the command then refused, and asking the damage chart directly was
  the whole answer only until a submarine could be under the water. Countering is the one
  deliberate exception on distance, documented on `CombatResolver._defender_can_counter`.
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
  geometry delegated to `AttackRange`, typed transport drop options. `Battle`, `BattleView`,
  `BattleAnimator`, `BattleCommandPipeline` and `BattleScenarioDriver` ask it; none re-derives
  visibility or reaches through a sibling's private helper, and the runner drives AI turns through
  `Battle`'s own named entry points.
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
  `scenes/common/match_request.gd` (`MatchRequest`) states one launch in full — board, sides, fog,
  tier, commanders, resume, seed, watch, day cap, raw side specs — and is built by one of three
  adapters: `from_menu`, `from_match` (a rematch, derived from the *live* `GameState`, so a match
  resumed from a save replays its own board and commanders) and `apply_cmdline`, layered over
  either on **every** battle boot, which is how a headless capture and a menu launch reach the same
  board by the same route. `BattleSetup.build(request, …)` reads no autoload, scans no command line
  and writes nothing back; it returns `null` with a pushed error when the board or the state cannot
  be built (`assert` is stripped from a release build), and `Battle` disables itself rather than
  dereferencing a null map. `MatchConfig` carries exactly one staged request, and `take()` clearing
  is load-bearing rather than tidy: it is what makes a resume that found no save on disk unable to
  latch into the next boot.
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

## Communication

- **Be concise.** Keep responses, summaries, and explanations short — lead with the answer, cut
  background the reader didn't ask for, and skip restating what the diff or the conversation
  already shows. Same goes for commit messages, PR bodies, and code comments.

## Commits

- Small, focused commits scoped to one milestone task.
- Present-tense, imperative subject (`Add Dijkstra movement range`).
- Don't commit generated import caches or engine temp files (`.godot/` is ignored).
