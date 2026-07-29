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
  income, vision, damage or luck. Its DF4 acceptance gate is currently **met** — read
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
- `four-players-plan.html` — up to four armies, milestones FP1–FP6; **FP1 (the roster becomes data),
  FP2 (hostility gets one authority), FP3 (an army can fall, a side can win), FP4 (four liveries
  on one board) and FP5 (seats and sides at the table) are shipped**.
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
  The save format is version 6: the roster arrived at 4, the grouping at 5, the fallen at 6 (the
  plan's "save v4 carries `eliminated`" is superseded by that ordering), an older save decodes as
  the free-for-all duel it recorded with every army it names still standing, and
  `SaveCodec._teams_error` / `_sides_error` / `_eliminated_error` refuse a roster, grouping or
  casualty list no board could deal *before* any per-side check is derived from it.
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
  dies (`_check_rout`, on the shot itself) or its HQ is captured, and `eliminate()` is the one way
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
  elimination; it is deliberately **not** retuned until the FP6 soak says otherwise.
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
  D6: **`scenes/menu/seat_strip.gd` (`SeatStrip`) is the menu's one answer to who plays each army
  and who stands with whom** — it takes the board's roster and hands back `ai_teams()` and `sides()`,
  and the two mode buttons it replaced are gone, so no menu state mirrors either fact. A free-for-all
  is the **empty** dictionary, from the strip and from `MatchRequest.parse_sides_flag` alike, because
  that is what `GameState.allied` reads as "every army its own side" and what every match carried
  before groupings existed. `--sides=1+3v2+4` is that flag's grammar, `--red`/`--blue` stay developer
  vocabulary for seats 1–2, and an unreadable grouping is refused out loud and dropped to the
  free-for-all rather than half-applied. Whether a grouping leaves anybody hostile is the *board's*
  answer, so `BattleSetup.build` asks `GameState.enemies_of` once a roster is loaded and plays the
  free-for-all if nobody is opposed — no flag can see the seats. Difficulty stays match-wide by the
  ticket's instruction, asked of the seats (a table with no computer has nothing to tune) rather than
  of a mode; per-seat tiers remain the Balance Lab's CLI grammar. Commander select is a slot walk of
  N chips and N confirms emitting `confirmed(picks: Dictionary)`, with Back rewinding one seat, and
  it gained the same kind of capture gate the setup panel has had since COM-5 (`chrome()`), because
  a bar that grew from two chips to one per seat can run off a 640px frame. `SeatStrip.layout_error`
  is the sibling of `CommanderInfoSheet.layout_error` and exists for the same reason: unsorted rows
  stack at the container's origin, inside every frame and drawn in none of it, so enclosure alone
  photographed the strip as bare panel.
  `maps/compass.txt` is the shipped four-army board — pulled forward from FP6 because without one
  the seat strip is UI no player can reach — and is land-only (the AI cannot ferry, naval R1).
  `maps/fixtures/quartet.txt` stays a fixture, out of the menu and out of the map lint — sized to fit
  the battle viewport whole, and the board `make smoke`'s `side_victory` and `mixed_seat_handoff+fog`
  scenarios run on. FP6 still owes Trident (a 3-army board), the AI-vs-AI soaks in all three
  groupings at all three tiers, and the plan artifact's own milestone pass.

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
  clearing is held. `TransitionInput` joins them on the same terms: a pure static answer over an
  `InputEvent`, so the boundary convention every banner and the victory lockup obey is checked
  without a scene. `DirectionalInput` joins it on the same terms: a pure answer over an
  `InputEvent` and the `InputMap`, so the one-step-per-gesture convention the board cursor and
  every menu obey is checked without a pad. `SeatStrip.normalised_sides` joins them on the same
  terms and for the same reason: the grouping arithmetic a shrinking roster runs through is static
  and pure, so it is checked without building the strip.
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
- **`AIController` is a façade, not a planning bucket.** It asks for Command Power first, then
  delegates to exactly two coarse collaborators: `AIUnitActionPlanner` and
  `AIProductionPlanner`. `AIPlanningContext` is the one owner of scan-ordered per-decision facts
  (friendlies, visible enemies, properties, unit types, goals and the production roster) and the
  threat map cache shared across decisions in a turn. Preserve strict comparator order and profile
  reads when moving AI code; never tune a `.tres` in an extraction.
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
  `scenes/common/match_request.gd` (`MatchRequest`) states one launch in full — board, seats, how
  they group into sides, fog, tier, commanders, resume, seed, watch, day cap, raw side specs — and
  is built by one of three adapters: `from_menu`, `from_match` (a rematch, derived from the *live*
  `GameState`, so a match resumed from a save replays its own board and commanders) and
  `apply_cmdline`, layered over either on **every** battle boot, which is how a headless capture
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
