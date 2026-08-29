# CLAUDE.md

Guidance for AI agents (and humans) working in this repository.
`AGENTS.md` is a symlink to this file — edit only `CLAUDE.md`; both names stay in sync.

## Project

**Grid Commanders** — an **Advance Wars-style turn-based tactics game** in **Godot 4.7+**
(`TileMapLayer`, custom `Resource` types) and **typed GDScript**. Grid maps, terrain that shapes
movement and defense, a rock-paper-scissors roster across land, air and sea, property capture and
income, and a computer opponent.

> Legal: this is a *reimplementation of mechanics*, not a copy. No Nintendo sprites, music,
> unit-name trade dress, or the "Advance Wars" name. Use original or freely-licensed assets and
> a different title. Track every third-party license in `assets/LICENSES.md`.

## Designs of record

The plans under `.lavish/` are the designs of record — **read the owning plan before an
architectural decision in its area.** The locked decisions live in `.claude/rules/*.md`, one file
per area, and **they load by path**: a rule file's `paths:` frontmatter admits it only once a
matching file is read, so a session working outside an area must open that file by hand first.

Nine entries carry more than a rule file can hold, so their long form — rationale, measurements,
superseded clauses, risk registers — is `docs/design_record.md`: AI Judgement, AI Economy, the AI
Arena, four players, the asymmetric board, campaign depth, the battle animations, the zoom ladder
and the animation milestone, and the mobile builds. **Read that entry first when deciding in one of
those nine areas.** Its appendix holds the rationale behind the architecture rules below.

The index, by owning file in `.claude/rules/` (plan names drop their `-plan.html` suffix):

- **instruments.md** — grid-commanders (the base game, the mechanics reference and the damage
  formula), balance-simulator, replay, focus-steal (the smoke sweep and window focus).
- **commanders.md** — commanders (C1–C4, D1–D4), new-commanders (Colt's retuned Second Wind),
  more-commanders (the aimed power), power-quotes.
- **ai.md** — difficulty-modes (the AI-never-cheats lock), commander-doctrine-ai, ai-judgement,
  ai-economy, ai-arena, AI logistics (the planner issues `SupplyCommand`).
- **maps.md** — naval-air-units (the no-ferry risk R1), map-retrofit, production-maps,
  four-players, four-player-maps (a seat may stay empty), asymmetric-board (Bulwark, not fair on
  purpose).
- **presentation.md** — game-speed (GS1–GS3, the pacing-free lock over `core/`), faction-identity,
  tile-info-panel + `.lavish/hud/SPEC.md`, battle-animations, capture-animation, range-preview,
  menu-revamp (`UiTheme`/`UiKit`), ux-recovery (U-01–U-26), mobile-builds (MB1–MB9), the field
  overlays, the zoom ladder and the animation milestone's nine slices, the next-ready-unit key
  (`N`), and standing terrain being interactive while the ground plane carries ambient variety.
- **campaign.md** — campaign-depth, campaign mode (the six authored wars and the campaign layer's
  architecture).

## Architecture — the rules that matter most

1. **Simulation / presentation split.** The game state (map, units, funds, turn) lives in
   **pure GDScript classes with no `Node` dependency**; scenes only render it and animate changes.
   **Nothing in `core/` may reference a `Node`, a scene, `get_node`, `SceneTree`, or anything under
   `scenes/`.** If you reach for a Node inside `core/`, you're in the wrong layer.
2. **Data-driven via Resources.** Unit stats, terrain, the damage chart and the match-wide balance
   levers (`RulesConfig` in `data/rules.tres` — capture speed, income, repair, property vision, the
   charge split, pricing, the neutral luck bounds) are `.tres` files under `data/`, not constants.
   Balancing = editing data; adding a unit = adding a file. The damage chart holds two matrices —
   stocked primary, infinite-ammo secondary — and owns which a shot uses (`select_shot`).
   Commanders split the two: the doctrine is a `CommanderType` subclass in
   `core/commanders/`, every number it reads is `@export` on its `.tres` in `data/commanders/`.
3. **Command pattern for all actions.** Every player or AI action is a command object under
   `core/commands/` (`Move`, `Attack`, `Capture`, `Build`, `EndTurn`, …), *validated* then
   *applied* to the sim, which emits typed events the scene layer animates — giving undo of
   uncommitted moves, an AI issuing the player's commands, and a log for save/replay.
4. **Determinism.** RNG (combat luck) is **seeded**. Same seed + same commands ⇒ same result.
   Never call global `randf()`/`randi()` in `core/`; thread a seeded RNG through the sim.

Flow: `input → Command → sim validates & applies → typed events → scenes animate`. The AI plugs in
at exactly the same point as player input.

## Project layout

```
res://
├─ core/       # sim: game_state.gd, commands/, rules/, commanders/, campaign/ (NO Node refs)
├─ data/       # .tres: units/, terrain/, commanders/, ai/, difficulty/, battle_anim/,
│             # campaigns/, damage_chart, rules
├─ scenes/     # battle/ (+ cutscene/ = the two cut-ins), menu/, ui/ (HUD, menus, damage
│             # preview, mission card, touch dock), common/ (MatchRequest, CmdArgs, …)
├─ autoload/   # EventBus, MatchConfig, Settings, Sfx, Music, CampaignSession
├─ ai/         # AIController façade + context + planners; ai_profile.gd owns every weight
├─ maps/       # map scenes / resources (campaign boards under maps/campaign/)
├─ assets/     # sprites, audio, fonts  (+ LICENSES.md)
├─ tools/      # offline scripts: balance/, arena/, replay/, plus the checks and runners
├─ generators/ # Python pipelines: audio/, sprites/, portraits/ (make audio / tiles / portraits
│             # install, make *-test gate them); .gdignore hides them from the engine
├─ docs/       # the instruments' committed records; how to author a campaign mission
└─ tests/      # GUT tests — target the Node-free layers only (see Testing)
```

## GDScript conventions

Follow the official Godot GDScript style guide. Key points:

- **Indentation: tabs**, not spaces. **Typed GDScript everywhere** (`var hp: int = 10`,
  `func attack(target: Unit) -> void:`); prefer explicit types over `:=` when it aids readability.
- **Naming:** `snake_case` files/vars/functions, `PascalCase` for `class_name` and node names,
  `CONSTANT_CASE` for constants and enums; `_` prefixes private members. **One `class_name` per
  file**, matching the file name (`game_state.gd` → `GameState`).
- **Signals** are past tense (`unit_moved`, `turn_ended`) with typed parameters. Emit domain events
  from the sim; the presentation layer subscribes.
- Prefer **composition and small resolvers** (`MovementResolver`, `CombatResolver`, `AttackRange`)
  over god-objects. `@export` inspector fields, but validate in code — don't trust them.
- Never `preload`/`load` a scene or Node type inside `core/`.

## Testing

- Tests use **GUT** (Godot Unit Test) and live in `tests/`, mirroring `core/` and `ai/`.
- **Test the Node-free layers only** — `core/`, `ai/`, and the offline instruments under `tools/`.
  Presentation is verified by playing the scene. A few launch-layer, pure-function and
  content-registry classes earn a narrow exception; **`docs/testing_exceptions.md` is the list and
  why each earns it** — read it before adding a suite outside `core/` or `ai/`.
- Every bugfix in `core/` or `ai/` comes with a failing test the fix makes pass.
- Keep tests deterministic: seed the RNG explicitly. `tests/helpers/fixture.gd` (`Fixture`) is
  where a board, a path, a command line and the shared databases come from, and it seeds every
  state it builds — build one through it rather than re-rolling a local `_state` helper, and set
  `state.rng.seed` only when the test wants a different stream.

`make test` runs the suite headless (README.md has its two-engine split). Before a change is done,
run `make verify` — it chains `check` (`tools/check_scripts.sh`), `lint` (`gdlint`), `format-check`
(`gdformat --check`), the GUT suite, then `determinism` (the ~1s pinned-match replay, byte-diffed
against its golden), in that order. `make format` satisfies `format-check`, and any gate runs alone.
Let `gdformat` settle whitespace rather than hand-aligning; a green `make verify` is the bar.

`check` enforces the repository invariants rather than only stating them: the Node-free, RNG-free
and pacing-free rules over `core/` and `ai/`, the per-file line budgets, the one-apply/one-validate
seam, no class reaching another's `_`-prefixed member, and every path cited by this file, README.md
or `docs/*.md` existing. It is parallel (`CHECK_JOBS=1` for serial).

## Running the game

`make run` boots the main menu; `make screenshot` boots the battle scene, saves `screenshot.png`
and quits (README.md has engine setup and the other targets). Prefer the running game or a GUT test
over reasoning alone when verifying a change.

## Working in this repo

- **Match the plan's milestones.** Ship something playable each one; don't pull scope forward —
  scope creep is the named top risk.
- **Balance numbers live in `data/`.** Don't hardcode a stat you could put in a `.tres`.
- **Dense commenting is a smell — fix the code, not the commentary.** A block that needs a running
  narration has the wrong names, split or shape: extract, rename, or drop the confusing branch. A
  comment earns its place explaining *why*, never *what*; a paragraph defending a workaround means
  the code is wrong rather than under-explained.
- **Don't hand-edit** `.import` files or the binary/UID bits of `.tscn`/`.tres` — let Godot
  regenerate them; prefer editing resource *data* over scene plumbing. `project.godot`, autoloads
  and the input map go through the editor when practical.
- **Single authorities — ask them, never re-derive.** `core/rules/attack_range.gd` owns who a unit
  may shoot, how far and with which weapon (`ready_shot` is the one selector; nobody asks a unit
  whether it has ammo). `core/movement_resolver.gd` owns the budget, per-step cost and where a move
  may end — including inside `MoveCommand.validate`, via `MoveCommand.move_error`.
  `LoadCommand.carriage_error` owns whether a rider may ride a transport at all;
  `core/rules/vision.gd` what a player can see; `core/grid.gd` distance — four-directional here.
- **Doctrine hooks take an `Engagement`, not two `Unit`s.** `core/rules/engagement.gd` carries the
  effective cell and HP a shot resolves with, keeping the preview and the resolved attack on
  identical numbers; `CombatResolver.forecast_at` takes the defender's cell for the same reason.
  Forecasting is a pure read — a query that must mutate the board is wrong.
- **Movement domains are data, not code.** A move class is a key in each terrain's `move_costs`,
  and what a property builds or refits is `TerrainType.builds` / `services` — never a terrain id
  checked in three places.
- **Fog is enforced in the presentation layer.** The sim stays permissive; the UI refuses to target
  or inspect what the viewer cannot see. The AI sees everything **except** units a doctrine hides
  (`Vision.is_hidden_from`) — don't widen that without a plan decision. `BattlePerspective` is the
  scene's one adapter from that authority to viewer policy.
- **A live command applies once.** `scenes/battle/battle_command_pipeline.gd` is the only
  live-scene owner of command validation, application and result presentation; `Battle` and
  `BattleAiRunner` both enter through `Battle.execute_command`. Input transitions, AI pacing, saves
  and victory presentation stay with the callers.
- **Which match to play is a typed request, not an autoload's fields.** `MatchRequest` states one
  launch in full, built by `from_menu`, `from_match`, `from_replay` or `apply_cmdline`.
  `BattleSetup.build` reads no autoload and writes nothing back; `MatchConfig` stages one request
  and its `take()` clearing is load-bearing.
- **The command line is parsed in one place.** `scenes/common/cmd_args.gd` — `value()` is
  last-wins, `flag()` matches a bare switch, and `has()` exists because an *empty* flag is not an
  *absent* one, so gate an override on `has`, not on a non-empty value.
- **The battle cut-in replays; it never decides.** `BattleAnimator.animate_combat` is the one seam
  and returns exactly once; inside `scenes/battle/cutscene/` everything is a pure function of one
  clock, `CutscenePlayback`. Every number shown was handed to it.
- **A computer turn is held between commands, never inside one.** `Battle.pause_gate` is the one
  point `BattleAiRunner` stops at; `Battle.rest_state()` is where a closing menu or banner lands.
  The pause is presentation only — no rule under `core/` or `ai/` learns it happened.
- **`AIController` is a façade, not a planning bucket.** It asks for Command Power, then delegates
  to `AIUnitActionPlanner` and `AIProductionPlanner`; `AIPlanningContext` owns per-decision facts
  and the turn's threat map, `AIPlanCache` drops what a **board diff** says could have moved.
  Preserve comparator order and profile reads; never tune a `.tres` in an extraction.

The long form of these — the full seams, the bugs behind them, what may not move — is in
`.claude/rules/presentation.md`, `.claude/rules/ai.md` and the appendix of `docs/design_record.md`.
Read the one that owns an area before changing it.

## Communication

- **Be concise.** Lead with the answer, cut background nobody asked for, and skip restating what
  the diff already shows. Same for commit messages, PR bodies and code comments.
- **Speak simply.** Plain words, short sentences; when a technical term is needed, say what it
  means in a few words.

## Commits

- Small, focused commits scoped to one milestone task, present-tense imperative subject
  (`Add Dijkstra movement range`).
- Don't commit generated import caches or engine temp files (`.godot/` is ignored).
