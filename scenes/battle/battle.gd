class_name Battle
extends Node2D
## Battle scene root: renders map + units, drives cursor/camera, and runs the
## interaction flow — selection, movement, menus, targeting, transport, AI
## turns, and victory. All rules live in core/; this scene only issues commands
## and animates the results.
##
## `confirm_at`, `set_cursor_cell`, and `leave_handoff` are public because they
## are the entry points player input arrives at, and BattleScenarioDriver
## stands in for a player through exactly those.
##
## `execute_command` and `conclude_command` are the AI runner's committed-action
## seam. The first delegates to BattleCommandPipeline; the second consumes its
## turn/winner facts only after the caller has finished its own interaction-state
## cleanup. `pause_gate` is the runner's third: the one point a computer turn can
## be held at. `start_turn`, `enter_victory`, `refresh_fog`, `refresh_hud`, and
## `refresh_panel` are the remaining public presentation entry points.

## The wake-up a paused computer turn waits on. A signal rather than a flag the
## runner polls, because leaving the match through the pause menu frees this
## scene: the await then dies with the object it was made on, instead of resuming
## into a board that is gone.
signal pause_lifted

enum State {
	IDLE,
	UNIT_SELECTED,
	PREVIEW,
	ANIMATING,
	MENU,
	TARGETING,
	DROP_TARGETING,
	POWER_TARGETING,
	VICTORY,
	AI_TURN,
	PAUSED,
	HANDOFF,
	INFO,
	CONFIRM,
}

## Which key legend the top bar prints in each state. The mapping is Battle's
## because the enum is; the words are ControlHints'. A state added without a row
## here falls back to the resting legend rather than blanking the bar.
const STATE_CONTEXT: Dictionary = {
	State.IDLE: ControlHints.IDLE,
	State.UNIT_SELECTED: ControlHints.UNIT_SELECTED,
	State.PREVIEW: ControlHints.PREVIEW,
	State.ANIMATING: ControlHints.ANIMATING,
	State.MENU: ControlHints.MENU,
	State.TARGETING: ControlHints.TARGETING,
	State.DROP_TARGETING: ControlHints.DROP_TARGETING,
	State.POWER_TARGETING: ControlHints.POWER_TARGETING,
	State.VICTORY: ControlHints.VICTORY,
	State.AI_TURN: ControlHints.AI_TURN,
	State.PAUSED: ControlHints.PAUSED,
	State.HANDOFF: ControlHints.HANDOFF,
	State.INFO: ControlHints.INFO,
	State.CONFIRM: ControlHints.END_TURN_GUARD,
}

const DIR_ACTIONS: Dictionary = {
	&"cursor_up": Vector2i.UP,
	&"cursor_down": Vector2i.DOWN,
	&"cursor_left": Vector2i.LEFT,
	&"cursor_right": Vector2i.RIGHT,
}

# Only the nodes Battle itself drives. Everything the view draws on is handed
# over in _build_view and deliberately kept out of reach here.
@onready var cursor: Sprite2D = $Cursor
@onready var camera: Camera2D = $Camera2D
@onready var action_menu: ActionMenu = %ActionMenu
@onready var victory_screen: VictoryLockup = %VictoryScreen
@onready var handoff_screen: Panel = %HandoffScreen
@onready var handoff_label: Label = %HandoffLabel
@onready var handoff_button: Button = %HandoffButton
@onready var commander_info_sheet: CommanderInfoSheet = %CommanderInfoSheet
@onready var action_feedback: ActionFeedback = %ActionFeedback
@onready var end_turn_guard: EndTurnGuard = %EndTurnGuard

var db: TerrainDB
var unit_db: UnitDB
var commander_db: CommanderDB
var map: MapData
var game: GameState
## team -> AIController, built by BattleSetup at each seat's own tier. One planner
## per team rather than one for the scene: a match on one tier gives every entry
## the same profile and nothing changes, while a per-seat tier, watch mode or the
## Auto row can put a different profile on each and have each plan with its own
## per-turn threat map.
var planners: Dictionary[int, AIController] = {}
## Teams played by the computer. Blue by default; `--hotseat` clears it.
var ai_teams: Array[int] = [2]
## Seats a player has handed to the computer mid-match through the pause menu's
## Auto row, and at which tier — a subset of `ai_teams`, never the whole of it. A
## genuine CPU opponent seated at setup is in `ai_teams` but never here, which is
## what tells the Auto row apart from a real opponent's turn: see BattleMenus.
var auto_tiers: Dictionary[int, StringName] = {}
## The tier each computer seat was launched at, where that is not the match's own
## `difficulty` below (COM-225) — the ids behind the planners, kept because they
## are what a save records and what a rematch replays.
var seat_difficulty: Dictionary[int, StringName] = {}
## A pause the player asked for during a computer turn, not yet taken effect. The
## runner honours it at its next command boundary rather than the press doing it
## here, because a menu opened mid-command would be painted over by the banner or
## turn hand-over that command ends with — and nothing interactive may sit under a
## banner or a cut-in (ux-recovery plan D3).
var _pause_requested := false
## True from the moment that pause takes effect until the board is handed back.
## What makes PAUSED, rather than IDLE, the state everything opened from the pause
## menu comes back to; see rest_state.
var _paused := false
## The last human seat that actually took a turn, or 0 before anyone has. What
## the fogged handoff and the AI-turn viewer are both keyed to (four-players plan
## D7), because with mixed seats the device changes hands across intervening
## computer turns and "the seat before this one" stops meaning "the last person".
## Public, like ai_teams and auto_tiers beside it, for BattleAuto to write when
## Auto hands a seat back mid-turn — the same fact _begin_turn records when an
## ordinary turn opens on a human.
var last_human_team := 0
## The tier this match is being played at, as BattleSetup resolved it — from the
## menu, a `--difficulty=` flag, or the resumed save itself. Held here because
## the scene is what a save asks for it: it is the id SaveGame records, and the
## one a resumed match plays back at.
var difficulty: Difficulty
## Every tier the Auto submenu offers a name and a profile for. Loaded once in
## _ready, the same way db/unit_db/commander_db are — BattleSetup.build keeps
## its own instance for setup-time resolution, but nothing there is held past
## boot, and the Auto row needs one for the life of the scene.
var difficulty_db: DifficultyDB
var cursor_cell := Vector2i.ZERO

## The interaction the player is in. The setter is the whole reason it has one:
## the top bar prints the keys that work *here*, and a legend refreshed from each
## of the dozen places that assign this would be one missed call site away from
## promising a key that does nothing. Everything else about the flow is unchanged
## — the setter only tells the bar.
var state := State.IDLE:
	set(value):
		state = value
		if view != null:  # nothing to tell during _ready, before the view exists
			view.refresh_keys(_legend_for(state))

var selected: Unit
var move_range: MovementResolver.MoveRange
var planned_path: Array[Vector2i] = []
## A unit inspected but not commanded — an enemy, or one of ours that has acted.
## Its move range shows in blue; `selected` stays null, so the menu flow keeps its
## meaning of "a unit I am commanding" and no command can act on a previewed one.
var _previewed: Unit
## Whether R's red fire ring is painted; every exit from a range state clears it.
## Setter-backed for the same reason `state` is: half a dozen sites clear it, and a
## chip that only some of them told would advertise a ring that is not on the board.
var _range_shown := false:
	set(value):
		_range_shown = value
		if view != null:  # nothing to tell during _ready, before the view exists
			view.refresh_range_lens(value)
## Whether T's threat lens is up. Unlike the fire ring it belongs to no unit and
## no selection, so nothing clears it but the player: it is a way of looking at
## the board, and one that switched itself off whenever a unit was picked up would
## be off exactly when the question it answers is being asked.
var _threat_shown := false
var _attack_targets: Array[Vector2i] = []
## Viewer-safe cargo choices for the open unit menu, and the one being targeted.
## Each typed option keeps its passenger and cells together.
var _drop_options: Array[BattlePerspective.DropOption] = []
var _drop_option: BattlePerspective.DropOption
var _pending_special_actions: Array[Dictionary] = []
var _menu_context: StringName = &"unit"
var _build_cell := Vector2i.ZERO

## Everything this scene draws. Battle decides what happens; the view decides
## how it looks. Nothing here reaches past it into a TileMapLayer or a sprite.
var view: BattleView
## The transient paint over that board — reach, fire, threat, route, capture
## chips. Its own collaborator rather than more of the view, because it is the
## half of the drawing this flow raises and clears as it moves.
var overlays: BattleOverlays
## Viewer-safe read policy shared by Battle, the renderer and every presentation
## collaborator. Vision and AttackRange remain the rule authorities it asks.
var perspective: BattlePerspective
## Everything this scene animates. Hands it an outcome that is already decided;
## it never picks one.
var animator: BattleAnimator
## The one live owner of command validation, application, and presentation.
## Human flow and the AI runner both enter through execute_command below.
var _command_pipeline: BattleCommandPipeline
## Plays computer turns — the AI's side of the interaction flow. Held for the
## whole scene; `run()` is fired when a computer team's turn opens.
var _ai_runner: BattleAiRunner
## Set only for `--replay=`: the recording being played back, and the runner that
## walks it. Non-null is what makes this scene a viewing of a finished match
## rather than a playing of a live one — nobody plans, nobody may act, and the
## board is drawn omniscient because there is no longer anyone to hide it from.
var _replay: ReplayPlayer
var _replay_runner: BattleReplayRunner
## The file `_replay` was read from, empty while a match is being played:
## restarting a playback opens that recording again, a replay having no live board
## to derive a rematch from. See BattleExit.rematch.
var replay_path := ""
## Whether the pause the runner is about to take was asked for one command at a
## time. Its own fact rather than a second reading of `_pause_requested`: a step
## parks on the frozen board, where an ordinary pause parks under the map menu.
var _stepping := false
## The recording this match is writing as it is played, or null while replaying
## one. Opened by BattleRecording and closed on the way out; the pipeline does the
## observing, and BattleOutcome asks it whether there is a replay worth offering.
var recorder: ReplayRecorder

## Owns the camera zoom level, its clamp against the view, and the zoom keys.
var _zoom: BattleZoom
## Answers "was that one step?" for the board cursor, so an analog stick moves a
## cell per push rather than a cell per axis sample. See DirectionalInput.
var _dirs := DirectionalInput.new()
## Set only when the command line asks for a scripted capture; see _ready.
var _scenario_driver: BattleScenarioDriver
## True for a run that exists to be photographed. Suppresses the presentation's
## two open-ended animations — see BattleAnimator — so captured frames of the
## same scenario can be compared to each other.
var _capturing := false
## Owns how the match ends — the victory lockup and, in watch mode, the day cap
## and the reported result line. Built after the view and animator it draws
## through; see _build_outcome.
var _outcome: BattleOutcome
## Owns every way out of a running match short of winning it — the save slot, the
## two map-menu exits and the confirmation the unsaved one asks for, and the
## rematch and replay the lockup offers. BattleOutcome's sibling; see BattleExit.
var exit: BattleExit
## Owns the pause menu's Auto row and its submenu: handing the seat on turn to
## the computer at a chosen tier, or taking it back. See BattleAuto.
var _battle_auto: BattleAuto


func _ready() -> void:
	db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	commander_db = CommanderDB.load_default()
	difficulty_db = DifficultyDB.load_default()
	_ai_runner = BattleAiRunner.new(self)
	exit = BattleExit.new(self)
	_battle_auto = BattleAuto.new(self)
	BattleCampaign.stage()
	# Which match this is, the request says and BattleSetup builds; from here the
	# scene just runs it. The menu (or a rematch) stages a request; a run that
	# booted this scene directly — a smoke scenario, a capture, a watched Balance
	# Lab row — has none and plays the defaults. Either way the flags are layered
	# on top, which is what keeps a headless capture and a menu launch arriving at
	# the same board by the same route.
	var request := MatchConfig.take()
	if request == null:
		request = MatchRequest.new()
	# In a smoke batch the current scenario's own --map/--fog replace the
	# process-level ones (FS3, COM-118); an ordinary launch gets the process
	# command line unchanged.
	request.apply_cmdline(BattleCaptureBatch.scenario_args())
	var built := BattleSetup.build(request, db, unit_db, commander_db)
	if built == null:
		# BattleSetup has already pushed what failed. There is no match to play, so
		# this scene does nothing at all: disabling it stops every process and input
		# callback, here and in its children, which is what makes "nothing can reach
		# a null map" true by construction rather than a null check per handler.
		process_mode = Node.PROCESS_MODE_DISABLED
		if ScreenshotUtil.requested() != "" or BattleCaptureBatch.requested() != "":
			# Nothing will ever drive the capture, and a headless run with no input
			# to be inert against would otherwise sit here until `make smoke` timed
			# it out. Non-zero, like a capture that fails its own gate.
			get_tree().quit(1)
		return
	Music.play(&"advance")
	map = built.map
	game = built.game
	ai_teams = built.ai_teams
	auto_tiers = built.auto_tiers.duplicate()
	seat_difficulty = built.seat_difficulty.duplicate()
	difficulty = built.difficulty
	planners = built.planners
	_replay = built.replay
	replay_path = built.replay_path
	if _replay != null:
		_replay_runner = BattleReplayRunner.new(self, _replay)
	BattleCampaign.open_board(game, request.campaign_resume == &"")
	perspective = BattlePerspective.new(game, _replay != null)
	view = _build_view()
	view.setup()
	overlays = _build_overlays()
	overlays.setup()
	animator = _build_animator()
	# Dev-only capture flows. Asked this early because whether this run exists to
	# be photographed also decides whether it records itself — a sweep must not
	# leave a recording per scenario in the player's slots. The question is the
	# command line's, so it is asked without building anything.
	_capturing = BattleScenarioDriver.requested()
	recorder = BattleRecording.open(self, _replay == null and not _capturing)
	_command_pipeline = BattleCommandPipeline.new(self, recorder)
	_outcome = _build_outcome()
	_outcome.configure(request.watching, request.days_cap, ai_teams)
	action_menu.action_chosen.connect(_on_menu_action)
	end_turn_guard.review_requested.connect(_review_ready_units)
	end_turn_guard.end_requested.connect(_end_turn_anyway)
	view.fire_pressed.connect(_fire_command_power)
	view.end_turn_pressed.connect(_request_end_turn)
	victory_screen.rematch_button.pressed.connect(_request_rematch)
	victory_screen.menu_button.pressed.connect(_request_main_menu)
	handoff_button.pressed.connect(leave_handoff)
	HandoffScreen.dress(%HandoffBackdrop, handoff_label, %HandoffHint, handoff_button)
	commander_info_sheet.closed.connect(_close_commander_info)
	_zoom = BattleZoom.new(view)
	_zoom.setup()
	set_cursor_cell(Vector2i.ZERO)
	animator.capturing = _capturing
	if _capturing:
		# Held for the whole scene: `run` awaits, and a RefCounted nobody
		# references is freed mid-scenario.
		_scenario_driver = BattleScenarioDriver.new(self)
		# A capture pins its own pace and ignores the device preference: a frame
		# must not depend on which machine took it, or on how fast whoever ran
		# `make smoke` likes to watch their tanks move.
		Settings.pin(GameSpeed.CAPTURE_ID)
		# The teaching strip is pinned for the same reason and one more: whether
		# *this* machine's player has already learned to capture would otherwise
		# decide whether a card sits over the board in every other scenario's
		# frame. Every capture but the strip's own hides it (COM-12).
		Settings.pin_hints(not _scenario_driver.wants_mission_strip())
		# And the ambient beat: rotors and swells alternate on a wall-clock
		# frame, so an unpinned capture would hash differently by shutter time.
		UnitSprite.ambient_frozen = true
	animator.start_cursor_pulse()
	await BattleCampaign.fire_due(self)  # the opening board: the one boundary with no command
	start_turn()  # day 1 gets the same banner/cursor/event as every turn
	camera.position = cursor.position
	if _capturing:
		_scenario_driver.run()


## Which key legend context this state prints. The table above is the mapping;
## what a recording and an open menu do to it is BattleLegend's.
func _legend_for(value: State) -> StringName:
	return BattleLegend.context_for(
		STATE_CONTEXT.get(value, ControlHints.IDLE), _replay != null, action_menu.has_value_rows()
	)


func _exit_tree() -> void:
	if recorder != null:
		recorder.close()


## The planner for a team. Never null: a team the setup did not name still gets
## the match's tier, so nothing can reach a turn with nobody to plan it.
func planner_for(team: int) -> AIController:
	if not planners.has(team):
		planners[team] = AIController.new(unit_db, difficulty.profile())
	return planners[team]


## The only live-scene route into validation/application/presentation. The
## computer asks for path animation; a human has already previewed the route.
func execute_command(command: Command, animate_path: bool = false) -> BattleCommandReceipt:
	return await _command_pipeline.execute(command, animate_path)


## Consumes the pipeline's flow facts after the caller has completed any
## human-only selection cleanup. The pipeline deliberately does not choose an
## interaction state or start the next AI planner.
func conclude_command(receipt: BattleCommandReceipt) -> void:
	if not receipt.applied:
		return
	await announce_fallen(receipt.fallen)
	await BattleCampaign.fire_due(self)
	var mission_over := BattleCampaign.decide(self, receipt)
	if receipt.turn_changed and not mission_over:
		start_turn()
	elif mission_over or receipt.winner != 0:
		enter_victory()


## Asks for the board back while the computer is playing. Public because the Esc
## the AI-turn legend advertises is one route to it and a scripted driver is the
## other. The answer is immediate even though the pause is not: the runner stops
## at its next command boundary, up to one animation away, so the press says it
## landed rather than leaving the player pressing it again. A second press re-arms
## nothing, but it is answered again: the chip fades on a clock of its own, and a
## slow command outlives it, so the key would otherwise read as dead.
func request_pause() -> void:
	if _paused:
		return
	_pause_requested = true
	_stepping = false  # this press wants the menu, so a step in flight stops being one
	action_feedback.show_reason("Pausing...", view.screen_pos_for_cell(cursor_cell))


## The AI runner's pause point, awaited between commands. Returns at once unless a
## pause is pending; otherwise it holds the turn with the board exactly as the last
## command left it, and opens the menu the pause was asked for — unless it was
## asked for one command at a time, which parks on the board instead.
func pause_gate() -> void:
	if not _pause_requested:
		return
	_pause_requested = false
	_paused = true
	state = State.PAUSED
	if not _stepping:
		_open_map_menu()
	_stepping = false
	await pause_lifted


## Plays exactly one recorded command and parks again: the whole of a step is
## asking for the pause the runner is about to clear, so playback gains no second
## route in and nothing has to be kept in step with the pause a player asks for.
func step_replay() -> void:
	if _replay != null and _paused:
		_stepping = true
		_pause_requested = true
		resume_turn()


## Hands a paused turn back to the computer. Every way out of the pause menu rests
## on PAUSED; this is the one that leaves it, and the runner picks the turn up
## where it stopped.
func resume_turn() -> void:
	if not _paused:
		return
	_paused = false
	state = State.AI_TURN
	pause_lifted.emit()


## Hands the current turn to the computer right now — _begin_turn's own AI
## branch, and BattleAuto's when the Auto row hands off a turn that was, until
## that press, the player's own. One path into AI_TURN for both.
func start_ai_turn() -> void:
	state = State.AI_TURN
	_ai_runner.run()


## Where a closing menu, sheet or banner lands: the player's own board, or the
## frozen board of a paused computer turn. One answer for all of them, because
## "back to rest" used to be spelled IDLE at each site, and IDLE mid-computer-turn
## hands the player a board they may not play. Public because the abandon
## confirmation BattleExit owns ends the same way.
func rest_state() -> State:
	return State.PAUSED if _paused else State.IDLE


## The banner belongs to the animator, but dismissing it is something a caller
## asks the *scene* to do — the scenario driver clears it before a capture.
func hide_banner() -> void:
	animator.hide_banner()


## Status banners use the same blocking/skip convention as the day and ambush
## cards. Public because BattleExit owns the save result text it presents.
func present_banner(text: String) -> void:
	state = State.ANIMATING
	await animator.show_banner(text)
	if state == State.ANIMATING:
		state = rest_state()


## Hands the view the nodes it draws on. Assignment rather than a constructor
## argument list keeps the dependency one-way: the view never learns what a
## Battle is.
func _build_view() -> BattleView:
	var built := BattleView.new()
	built.ground_layer = $GroundLayer
	built.terrain_layer = $TerrainLayer
	built.backdrop_layer = $Backdrop
	built.fog_layer = $FogLayer
	built.units_root = $Units
	built.cursor = cursor
	built.camera = camera
	built.punch = %BoardPunch
	built.hud_bottom = %HudBottom
	built.damage_preview = %DamagePreview
	built.hud_top = %HudTop
	built.mission_strip = %MissionStrip
	built.mission_panel = %MissionObjectives
	built.db = db
	built.map = map
	built.game = game
	built.perspective = perspective
	built.set_ai_teams(ai_teams)
	built.identity = SideIdentity.for_game(game)  # the side resolver; Battle reads view.identity
	return built


## Same assignment-not-constructor shape as _build_view, and for the same reason.
## The overlays hold no game state at all — every cell they paint is worked out by
## a rule authority and handed over — so the node fields are the whole of it.
func _build_overlays() -> BattleOverlays:
	var built := BattleOverlays.new()
	built.move_layer = $MoveOverlay
	built.attack_layer = $AttackOverlay
	built.threat_layer = $ThreatOverlay
	built.path_arrow = $PathArrow
	built.capture_pips = $CapturePips
	built.objective_marks = $ObjectiveMarks
	return built


## Same assignment-not-constructor shape as _build_view, and for the same reason:
## neither the animator nor the cut-in it plays ever learns what a Battle is.
func _build_animator() -> BattleAnimator:
	var built := BattleAnimator.new()
	built.node = self
	built.view = view
	built.perspective = perspective
	built.cursor = cursor
	built.turn_banner = %TurnBanner
	built.power_banner = %CommanderBanner
	built.power_marks = $PowerMarks
	built.muzzle_flash = $MuzzleFlash
	built.mission_speech = %MissionSpeech
	built.cutscene = %Cutscene
	built.cutscene.view = view
	built.capture_cutscene = %CaptureCutscene
	built.capture_cutscene.view = view
	return built


## Same assignment-not-constructor shape as _build_view/_build_animator, plus the
## scene itself: the reporter sets Battle.state and needs get_tree(), so it holds
## the node the way BattleAiRunner does, and is handed the victory lockup.
func _build_outcome() -> BattleOutcome:
	var built := BattleOutcome.new(self)
	built.bind_screen(victory_screen)
	return built


## The one press the two states that swallow play still listen for: the confirm
## action, or a left click. Shared so the handoff's "I'm ready" and the computer
## turn's refusal can never answer different presses.
func _is_confirm_press(event: InputEvent) -> bool:
	if event.is_action_pressed(&"confirm"):
		return true
	var button := event as InputEventMouseButton
	return button != null and button.button_index == MOUSE_BUTTON_LEFT and button.pressed


func _unhandled_input(event: InputEvent) -> void:
	var dir := _dirs.step(event, DIR_ACTIONS.keys())
	if animator.consume_banner_skip(event):
		get_viewport().set_input_as_handled()
		return
	if state == State.HANDOFF:
		# Only "I'm ready" gets through while the device is being passed over.
		if _is_confirm_press(event):
			leave_handoff()
		return
	if state == State.AI_TURN:
		# Esc is the one key that does something here: it asks for the board back.
		if event.is_action_pressed(&"cancel"):
			request_pause()
			return
		# The computer's turn refuses play, but it says so rather than going quiet.
		if _is_confirm_press(event):
			confirm_at(cursor_cell)
		return
	if state == State.PAUSED:
		# The confirm *key* hands the turn back, Esc reopens the menu, and everything
		# else falls through — the cursor still walks the frozen board and the panel
		# reads it, which is half of what a pause is for. A click is deliberately not
		# a resume: it is how a mouse player places the cursor to read a tile, and
		# handing the turn back for that would take the pause away mid-look.
		if event.is_action_pressed(&"confirm"):
			resume_turn()
			return
		if event.is_action_pressed(&"cancel"):
			_open_map_menu()
			return
		# Only a replay steps: a paused computer turn has no next command yet.
		if _replay != null and event.is_action_pressed(&"replay_step"):
			step_replay()
			return
	if state == State.VICTORY:
		if _outcome.consume_input(event):
			get_viewport().set_input_as_handled()
		return
	if state in [State.ANIMATING, State.MENU, State.CONFIRM, State.VICTORY, State.INFO]:
		return  # the menu, guard and info sheet handle their own input; the rest block it
	if _zoom.handle_input(event):
		return
	if event is InputEventMouseMotion:
		var cell := _mouse_cell()
		if map.in_bounds(cell) and cell != cursor_cell:
			set_cursor_cell(cell)
	elif (
		event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	):
		var cell := _mouse_cell()
		if map.in_bounds(cell):
			if cell != cursor_cell:
				set_cursor_cell(cell)
			confirm_at(cursor_cell)
	elif event.is_action_pressed(&"confirm"):
		confirm_at(cursor_cell)
	elif event.is_action_pressed(&"cancel"):
		_cancel()
	elif event.is_action_pressed(&"show_range"):
		toggle_range()
	elif event.is_action_pressed(&"show_threat"):
		toggle_threat()
	elif event.is_action_pressed(&"next_unit") and state in [State.IDLE, State.PREVIEW]:
		_cycle_ready_unit()  # never with a unit in hand: there the cursor is planning a move
	elif event.is_action_pressed(&"show_objectives"):
		view.mission_panel.toggle(game)  # chrome the card owns; nothing here has state in it
	elif event.is_action_pressed(&"fire_power"):
		_fire_command_power()  # the shortcut the charged meter advertises
	elif not dir.is_empty():
		var next: Vector2i = cursor_cell + DIR_ACTIONS[dir]
		if map.in_bounds(next):
			set_cursor_cell(next)


# --- selection / movement flow -----------------------------------------------


func confirm_at(cell: Vector2i) -> void:
	match state:
		State.IDLE:
			var unit := perspective.visible_unit_at(cell)
			if unit != null and unit.team == game.current_team:
				if unit.acted:
					_reject_acted(unit, cell)
				else:
					_select(unit)
			elif _is_own_empty_factory(cell):
				_open_build_menu(cell)
			elif unit != null and perspective.can_see_unit(unit):
				# A click that did nothing before now previews a unit we cannot
				# command, gated by the same sight rule targeting uses (so fog and a
				# dived sub stay unclickable).
				_enter_preview(unit)
			else:
				_open_map_menu()  # empty, or an unseen occupant — same face, never probe fog
		State.PREVIEW:
			var unit := game.unit_at(cell)
			if unit == null or not perspective.can_see_unit(unit):
				_clear_preview()  # empty, or an unseen occupant — dismiss, never probe fog
			elif unit.team == game.current_team and not unit.acted:
				_clear_preview()
				_select(unit)  # intel never blocks play — a ready unit still selects
			elif unit.team == game.current_team:
				_reject_acted(unit, cell)
			else:
				_enter_preview(unit)  # a visible other unit: switch the preview to it
		State.UNIT_SELECTED:
			if move_range.has(cell) and move_range.can_stop_at(cell):
				planned_path = move_range.path_to(cell)
				_animate_move()
			elif move_range.has(cell):
				# Occupied but reachable: maybe a Load or Join destination.
				var special := BattleMenus.destination_actions(
					game, selected, move_range.path_to(cell)
				)
				if not special.is_empty():
					_pending_special_actions = special
					planned_path = move_range.path_to(cell)
					_animate_move()
				else:
					_reject("Occupied.", cell)
			else:
				_reject("Out of reach.", cell)
		State.TARGETING:
			if cell in _attack_targets:
				_execute_attack(cell)
			else:
				_reject("No target there.", cell)
		State.DROP_TARGETING:
			if _drop_option != null and cell in _drop_option.cells:
				_execute_drop(cell)
			else:
				_reject("Cannot unload there.", cell)
		State.POWER_TARGETING:
			_fire_aimed_power(cell)
		State.AI_TURN:
			_reject("CPU turn.", cell)


func _reject(reason: String, cell: Vector2i) -> void:
	action_feedback.show_reason(reason, view.screen_pos_for_cell(cell))


## One of ours that cannot be commanded: it says why, then falls back to the
## preview so the refusal still shows what the unit can do. Both arms that can
## reach an acted friendly unit come through here, so the two reasons are picked
## in one place and a third can only be added once.
func _reject_acted(unit: Unit, cell: Vector2i) -> void:
	_reject(
		"Ready next day." if action_feedback.was_built_this_turn(unit) else "Already acted.", cell
	)
	_enter_preview(unit)


func _cancel() -> void:
	if state == State.IDLE:
		_open_map_menu()  # nothing to back out of; what the resting legend's ESC names
	elif state == State.UNIT_SELECTED:
		_clear_selection()
	elif state == State.PREVIEW:
		_clear_preview()
	elif state == State.TARGETING:
		_exit_targeting_to_menu()
	elif state == State.DROP_TARGETING:
		overlays.paint_move([])
		_drop_options = []
		_drop_option = null
		_on_move_animation_done()  # back to the unit menu
	elif state == State.POWER_TARGETING:
		# Nothing to back out *to*: aiming already abandoned whatever the HUD
		# button was pressed over, and the meter has not been spent.
		overlays.paint_attack([])
		state = rest_state()


func _select(unit: Unit) -> void:
	Sfx.play(&"select")
	# Picking a unit up is the one step of the loop no committed command marks, so
	# it gets the event the rest already had. MissionStrip is the only listener
	# today; the flow below is untouched by it either way.
	EventBus.unit_selected.emit(unit)
	selected = unit
	move_range = MovementResolver.reachable(game, unit)
	planned_path = [unit.cell]
	_range_shown = false
	overlays.paint_move(move_range.cells())
	overlays.trace_path(planned_path)
	state = State.UNIT_SELECTED


func _clear_selection(refresh_board: bool = true) -> void:
	selected = null
	move_range = null
	planned_path = []
	_attack_targets = []
	_drop_options = []
	_drop_option = null
	_range_shown = false
	overlays.paint_move([])
	overlays.paint_attack([])
	overlays.trace_path([])
	view.update_damage_preview(null, cursor_cell)
	state = State.IDLE
	if refresh_board:
		refresh_fog()


## Previews a unit we cannot command. Its move range shows in blue and R adds the
## fire ring; `selected` stays clear so the command flow never touches it.
func _enter_preview(unit: Unit) -> void:
	Sfx.play(&"select")
	_previewed = unit
	# Asked of the perspective, never of the resolver directly: this reach may belong
	# to either side, and both whose sight fills it and how much of it the viewer may
	# be shown are viewer policy.
	_range_shown = false
	overlays.paint_move(perspective.move_overlay_cells(unit))
	overlays.paint_attack([])
	overlays.trace_path([])  # a preview plans no route
	state = State.PREVIEW


func _clear_preview() -> void:
	_previewed = null
	_range_shown = false
	overlays.paint_move([])
	overlays.paint_attack([])
	state = State.IDLE


## R toggles the red fire ring for the unit the cursor is on. A momentary lens; it
## issues nothing. Public for the same reason `confirm_at` and `set_cursor_cell` are:
## the scenario driver walks the flows a player's input reaches, and this is one of
## them. Painted through the perspective rather than off AttackRange directly, because
## the ring is whole for a unit of the viewer's own side and their best reading of
## another side's — a split by whose unit it is, not by which state we are in.
##
## The cursor names the subject, through the preview and so through the same sight gate
## a click goes through: reading what an enemy or an already-acted unit threatens costs
## one key, and walking onto a second unit re-aims R rather than putting the first one's
## ring down. A unit in hand is the exception — there the cursor is planning a move.
func toggle_range() -> void:
	if state == State.IDLE or state == State.PREVIEW:
		var under := perspective.visible_unit_at(cursor_cell)
		if under != null and (under != _previewed or state == State.IDLE):
			_enter_preview(under)
		elif state == State.IDLE:
			return  # nothing under the cursor to ask about
	# The unit whose range is up: the selected one, or the one the cursor named.
	var unit: Unit = selected if state == State.UNIT_SELECTED else _previewed
	if unit == null:  # not in a range state
		return
	_range_shown = not _range_shown
	if _range_shown:
		overlays.paint_attack(perspective.threat_overlay_cells(unit))
	else:
		overlays.paint_attack([])


## T raises and lowers the threat lens: every cell the hostile sides could bring
## under fire, all of them at once. R's sibling and its opposite in scope — R asks
## "what does *this* unit reach", the lens asks "where is it unsafe to stand" —
## which is why they paint on separate layers and read as different shading.
##
## Public for the same reason toggle_range is: the scenario driver walks the flows
## a player's input reaches. It issues nothing and belongs to no unit, so unlike
## the fire ring it survives selection, movement and the turn.
func toggle_threat() -> void:
	_threat_shown = not _threat_shown
	_refresh_threat()


## Repaints the lens from the current viewer. Cheap while it is down — the sweep
## is skipped entirely — which is what lets refresh_fog run it after every
## committed command without pricing a board-wide firing walk nobody asked for.
func _refresh_threat() -> void:
	var cells: Array[Vector2i] = []
	if _threat_shown:
		cells = perspective.all_threat_overlay_cells()
	overlays.paint_threat(cells)
	# The chip is told the state rather than left to infer it from an empty list: a
	# raised lens with nothing under it is not a lowered one, and the player who
	# just pressed T needs to see that the answer was "nowhere", not that the key
	# did nothing.
	view.refresh_threat_lens(_threat_shown)


func _animate_move() -> void:
	state = State.ANIMATING
	_range_shown = false
	overlays.paint_move([])
	overlays.paint_attack([])  # a fire ring shown with R does not survive the move
	overlays.trace_path([])
	await animator.animate_path(view.sprite_for(selected), planned_path)
	_on_move_animation_done()


func _on_move_animation_done() -> void:
	state = State.MENU
	_menu_context = &"unit"
	var dest: Vector2i = planned_path[planned_path.size() - 1]
	if not _pending_special_actions.is_empty():
		# Load/Join destination: only the special action (and Cancel) applies.
		var special := _pending_special_actions
		_pending_special_actions = []
		special.append(BattleMenus.CANCEL)
		action_menu.open(special, view.screen_pos_for_cell(dest))
		return
	_attack_targets = perspective.attackable_cells(selected, dest, planned_path.size() > 1)
	_drop_options = perspective.drop_options(selected, dest)
	var actions := BattleMenus.unit_actions(
		game, selected, planned_path, not _attack_targets.is_empty(), _drop_options
	)
	action_menu.open(actions, view.screen_pos_for_cell(dest))


func _on_menu_action(action: StringName) -> void:
	action_menu.close()
	match _menu_context:
		&"unit":
			_handle_unit_action(action)
		&"base":
			_handle_build_action(action)
		&"map":
			_handle_map_action(action)
		&"auto":
			_battle_auto.handle_action(action)
		&"abandon":
			exit.handle_confirm_action(action)


func _handle_unit_action(action: StringName) -> void:
	if String(action).begins_with("drop_"):
		# The row's id carries which passenger it unloads (see BattleMenus).
		_enter_drop_targeting(String(action).trim_prefix("drop_").to_int())
		return
	match action:
		&"fire":
			_enter_targeting()
		&"load":
			# The refresh inside _commit hides the boarded sprite.
			_commit(action, LoadCommand.new(selected, planned_path))
		&"supply":
			_commit(action, SupplyCommand.new(selected, planned_path))
		&"dive", &"surface":
			# Going under changes what the *other* side can see, so the fog pass
			# the command pipeline ends with is load-bearing here rather than incidental:
			# without it the boat would keep the look it had.
			_commit(action, DiveCommand.new(selected, planned_path, action == &"dive"))
		&"wait":
			_commit(action, MoveCommand.new(selected, planned_path))
		&"join":
			_commit(action, JoinCommand.new(selected, planned_path))
		&"capture":
			_commit(action, CaptureCommand.new(selected, planned_path))
		&"cancel":
			_undo_move_preview()


## Every committed unit-menu action shares this interaction wrapper. Validation,
## application, snapshots, and presentation belong to the pipeline; this method
## only decides how the human menu recovers or closes around its receipt.
##
## ANIMATING before the await, exactly as _execute_attack sets it, because the
## pipeline's presentation can hold this flow for seconds — the capture cut-in
## does — and MENU is a state the HUD's Fire button reaches a command from. Left
## in MENU, a power fired mid-cut-in entered the pipeline re-entrantly and cleared
## the selection this flow comes back to (COM-50).
func _commit(action: StringName, command: Command) -> void:
	state = State.ANIMATING
	var receipt := await execute_command(command)
	if receipt.rejected():
		push_error("%s rejected: %s" % [action, receipt.validation_error])
		_undo_move_preview()
		return
	_clear_selection(false)
	await conclude_command(receipt)


func _handle_build_action(action: StringName) -> void:
	if action == &"cancel":
		state = State.IDLE
		return
	var command := BuildCommand.new(game.current_team, unit_db.by_id(action), _build_cell)
	var receipt := await execute_command(command)
	if receipt.rejected():
		push_error("BuildCommand rejected: %s" % receipt.validation_error)
		state = State.IDLE
		return
	state = State.IDLE
	await conclude_command(receipt)


func _handle_map_action(action: StringName) -> void:
	state = rest_state()
	if action == &"power":
		_fire_command_power()
		return
	if action == &"commanders":
		_open_commander_info()
		return
	if await BattleCampaign.run_row(self, action):
		return  # Briefing and Objectives: the campaign's rows are the campaign's
	if action == &"auto":
		# Its own submenu, the same shape "quit" opens "abandon" into below: the
		# context is Battle's to set, the rows and the handoff are BattleAuto's.
		_menu_context = &"auto"
		_battle_auto.open_menu()
		return
	if action == &"save":
		exit.save_match()
		return
	if action == &"save_and_quit":
		exit.save_and_leave()
		return
	if action == &"quit":
		# The context is Battle's to set — it is what routes the rows that come back
		# — and the confirmation itself is BattleExit's, like the leaving behind it.
		_menu_context = &"abandon"
		exit.confirm_abandon()
		return
	if action != &"end_turn":
		return
	_request_end_turn()


func _request_end_turn() -> void:
	var ready := ReadyUnits.of(game)
	# Whether the guard opens at all is a device preference (COM-124); who is ready
	# is ReadyUnits' answer either way, which is what N and Review still walk.
	if Settings.end_turn_confirm and not ready.is_empty():
		state = State.CONFIRM
		end_turn_guard.open(game.day, ready, view.identity.theme(game.current_team))
		return
	_commit_end_turn()


func _review_ready_units() -> void:
	state = State.IDLE
	_cycle_ready_unit()  # Review walks the guard's list rather than pinning its first entry


func _end_turn_anyway() -> void:
	state = State.IDLE
	_commit_end_turn()


## Walks the cursor to the next unit that can still act — the whole of what N
## does. It moves the cursor and nothing else: selecting stays the player's
## confirm press, so no command is issued and nothing under `core/` learns it
## happened. A board with none left says so rather than going quiet.
func _cycle_ready_unit() -> void:
	var unit := ReadyUnits.after(game, cursor_cell)
	if unit == null:
		_reject("No unit ready.", cursor_cell)
		return
	set_cursor_cell(unit.cell)


func _commit_end_turn() -> void:
	var command := EndTurnCommand.new()
	var receipt := await execute_command(command)
	if receipt.rejected():
		push_error("EndTurnCommand rejected: %s" % receipt.validation_error)
		return
	await conclude_command(receipt)


## Fires the current team's Command Power, or says why it cannot: which refusal a
## press has earned is BattlePower's, settled up front for aimed and unaimed powers
## alike so nobody is sent off to aim a meter they have not filled. Only a board
## the player is playing gets the chip; the rest of them get nothing.
func _fire_command_power() -> void:
	if state not in [State.IDLE, State.MENU]:
		if state in [State.UNIT_SELECTED, State.PREVIEW, State.TARGETING, State.DROP_TARGETING]:
			_reject(BattlePower.MID_ACTION, cursor_cell)
		return
	var refusal := BattlePower.refusal_for(game, ai_teams)
	if refusal != "":
		_reject(refusal, cursor_cell)
		return
	# Close the menu the HUD button may sit over before the card or the aim takes it.
	action_menu.close()
	if game.commander_of(game.current_team).aims_power():
		_enter_power_targeting()
		return
	await _fire_power(PowerCommand.new())


## Applies a Command Power and settles the board around it. A power can change
## movement, vision and HP at once, so the whole board is redrawn, and the
## selection — plus any menu the HUD button fired over, whose rows would otherwise
## act on it — belongs to rules that no longer apply.
func _fire_power(command: PowerCommand) -> void:
	state = State.ANIMATING
	var receipt := await execute_command(command)
	if receipt.rejected():
		state = rest_state()
		return
	_clear_selection(false)
	await conclude_command(receipt)


## Aims a Command Power at a square of ground (plan D2). The power abandons
## whatever move the HUD button was pressed over exactly as firing an unaimed one
## does — and it does so now rather than after the strike, so cancelling the aim
## lands on a board with nothing half-moved on it.
func _enter_power_targeting() -> void:
	if selected != null:
		view.refresh_sprite(selected)  # the previewed move is off; put the sprite back
	_clear_selection()
	state = State.POWER_TARGETING
	_paint_blast(cursor_cell)


## Repaints the square under the aim. Asked of the doctrine every time (plan D3):
## the overlay shows exactly what the strike will take, because it is the same
## function that takes it. Unfogged on purpose — every cell of the board is a legal
## aim, and what fog costs the player is knowing what was standing there.
func _paint_blast(cell: Vector2i) -> void:
	var team := game.current_team
	overlays.paint_attack(game.commander_of(team).power_blast_cells(game, team, cell))


func _fire_aimed_power(cell: Vector2i) -> void:
	var command := PowerCommand.new()
	command.target = cell
	overlays.paint_attack([])
	await _fire_power(command)


## Locks input and shows the already-decided winner. Public because the AI turn
## runner reaches the same terminal flow as a human command.
func enter_victory() -> void:
	_outcome.enter_victory()


func _request_rematch() -> void:
	if _outcome.accepts_action(victory_screen.rematch_button):
		exit.rematch()


func _request_main_menu() -> void:
	if _outcome.accepts_action(victory_screen.menu_button):
		exit.to_main_menu()


## A production property of ours standing empty. Which terrains those are is the
## terrain's own data, so a port and an airport open the build menu through this
## same check — and offer only what they build, see _open_build_menu.
func _is_own_empty_factory(cell: Vector2i) -> bool:
	return (
		not map.terrain_at(cell).builds.is_empty()
		and game.owner_at(cell) == game.current_team
		and perspective.visible_unit_at(cell) == null
	)


func _open_build_menu(cell: Vector2i) -> void:
	_menu_context = &"base"
	_build_cell = cell
	state = State.MENU
	var actions := BattleMenus.build_actions(
		game, unit_db, map.terrain_at(cell), game.current_team, view.identity
	)
	action_menu.open(actions, view.screen_pos_for_cell(cell))


func _open_map_menu() -> void:
	_menu_context = &"map"
	# Its first row is the Command Power, which is one of the two routes the charged
	# meter in the bottom bar advertises (F is the other). Nothing floats over the
	# board any more, so the menu only has to clamp inside the band between the bars.
	# Opened over a paused computer turn it drops the rows that would act for that
	# turn — the menu is the same, whose turn it is is not — and over a replay the
	# two that write the save slot as well; see BattleMenus.map_actions.
	#
	# Opened before the state is set: the legend that setter prints asks the menu
	# whether its rows answer to left and right, and this is the menu that carries
	# the device settings they step.
	var card := view.mission_panel.is_up()  # the Objectives row's label; the card owns it
	action_menu.open(
		BattleMenus.map_actions(
			game, not _paused, _replay == null, ai_teams, auto_tiers, difficulty_db, card
		),
		view.screen_pos_for_cell(cursor_cell)
	)
	state = State.MENU


## Opens the both-sides commander reference over the board. A modal, like the
## victory and handoff screens: the INFO state blocks board input, and the sheet
## takes focus and closes itself. Reached from the map menu, never from a hover.
func _open_commander_info() -> void:
	state = State.INFO
	var picks: Dictionary = {}
	for team in game.teams:
		picks[team] = game.commander_of(team)
	commander_info_sheet.open(picks, game.sides)


func _close_commander_info() -> void:
	if state == State.INFO:
		state = rest_state()


func start_turn() -> void:
	action_feedback.clear_turn()
	# An air or sea unit that ran its tank dry is already gone from the sim, so
	# the sprite table is resynced before set_active_team walks it.
	view.sync_sprites()
	view.set_active_team(game.current_team)
	if _needs_handoff():
		_enter_handoff()
		return
	_begin_turn()


## Everything the incoming team is allowed to see, run once the device has
## actually changed hands (immediately, outside fogged hot-seat).
func _begin_turn() -> void:
	refresh_fog()
	refresh_hud()
	refresh_panel()
	# A side wiped out by its own fuel gauge ends the match here, exactly as one
	# shot to pieces does.
	if game.winner != 0:
		enter_victory()
		return
	if _outcome.end_watch_on_day_cap():
		return
	Sfx.play(&"fanfare", -8.0)
	state = State.ANIMATING
	var homes := game.properties_of(game.current_team)
	if not homes.is_empty():
		set_cursor_cell(homes[0])
	EventBus.turn_started.emit(game.current_team, game.day)
	await animator.show_banner(
		"Day %d - %s" % [game.day, view.identity.display_name(game.current_team)]
	)
	if state != State.ANIMATING:
		return
	if _replay != null:
		# Every seat is the recording's, whoever played it. AI_TURN is the state for
		# "somebody else is playing" and carries the pause seam this needs, so the
		# runner and the legend are the only things that differ.
		state = State.AI_TURN
		_replay_runner.run()
		return
	if game.current_team in ai_teams:
		start_ai_turn()
	else:
		last_human_team = game.current_team
		# A pause asked for on the computer's last command has been answered by the
		# turn itself; carrying it forward would stop the *next* computer turn on
		# a press made two turns ago.
		_pause_requested = false
		state = State.IDLE


## Says out loud that an army has left the match. Public information, fog or no
## fog — every side learns that a seat emptied, because the board they are playing
## on just changed shape. Public because a scripted mission beat can empty a seat
## too, and BattleCampaign announces that one the same way.
##
## Uses the same blocking beat every other banner does, so Instant clamps it and
## any press skips it; suppressed while `capturing`, like the cut-ins, so posed
## frames stay byte-stable. Awaited before the turn hands over, so the banner
## lands on the board that produced it rather than over the next player's.
func announce_fallen(fallen: Array[int]) -> void:
	if fallen.is_empty() or animator.capturing:
		return
	var was := state
	state = State.ANIMATING
	for team: int in fallen:
		await animator.show_banner("%s eliminated" % view.identity.display_name(team))
	if state == State.ANIMATING:
		state = was


## Fogged hot-seat only: two humans sharing one screen must not see each other's
## vision, so the incoming player confirms before anything is painted. AI turns
## and fog-off matches never gate.
##
## Two halves. The seat count is why a solo player is never asked: one human at
## the table means nobody to hand the device to, so that match gates exactly as
## it did before four armies. The last-human comparison on top of it is the
## four-players plan's D7 refinement: with two humans and two computers the
## device still changes hands across intervening AI turns, and asking only "was
## the previous turn another person's" would hand player B a board still painted
## with player A's vision. Nobody having played yet counts as a change of hands —
## `last_human_team` is 0 there, which differs from any seat — so a fresh match
## gates on day one and a resumed save gates for whoever loaded it. The same
## player taking two turns in a row, everyone else having fallen, is not a
## handoff and is not asked for one.
func _needs_handoff() -> bool:
	# Nobody is being handed the device during a replay, and the board is drawn
	# omniscient anyway — a blackout would blank a match that has no secrets left.
	if _replay != null:
		return false
	if not game.fog_enabled or game.winner != 0:
		return false
	if game.current_team in ai_teams:
		return false
	var humans := 0
	for team in game.teams:
		if team not in ai_teams:
			humans += 1
	if humans <= 1:
		return false
	return last_human_team != game.current_team


func _enter_handoff() -> void:
	state = State.HANDOFF
	animator.hide_banner()
	refresh_fog()  # blanks the outgoing team's vision before the panel goes up
	handoff_label.text = (
		"%s — press confirm when ready" % view.identity.display_name(game.current_team)
	)
	handoff_screen.show()
	handoff_button.grab_focus()


func leave_handoff() -> void:
	if state != State.HANDOFF:
		return
	handoff_screen.hide()
	state = State.IDLE  # _begin_turn paints the incoming team's vision, not a blackout
	_begin_turn()


## The perspective fog is drawn from: the human whose turn it is, or — while the
## computer plays — the human who played last (four-players plan D7). Information
## they already had, which is the whole test: rendering through *any other*
## human's fog while an AI turn runs would show one player what another had
## scouted. With one human at the table this is their fog all match, exactly as
## before. The AI sees everything bar one thing: a unit a doctrine hides is hidden
## from it too — see Vision.is_hidden_from.
func _viewing_team() -> int:
	if game.current_team not in ai_teams:
		return game.current_team
	if last_human_team != 0 and last_human_team not in ai_teams:
		return last_human_team
	for team in game.teams:
		if team not in ai_teams:
			return team
	return game.current_team


## Refreshes the shared perspective and repaints fog after every committed
## action and turn change (not per cursor move). During a hot-seat handoff
## nobody may look, so the board is blacked out entirely — whose eyes and
## whether they are shut are flow decisions, so they are made here and handed to
## the perspective; working out what is visible is Vision's job, deciding what
## this viewer may act on is the perspective's, and drawing it is the view's.
func refresh_fog() -> void:
	perspective.refresh(_viewing_team(), state == State.HANDOFF)
	view.refresh_fog()
	# Every mark below rides this one pass rather than growing a refresh path of
	# its own: it already reruns after every committed command and turn change,
	# which is exactly when what is seen — and what the mission still wants —
	# changes. A blackout empties the fogged ones without a special case: that
	# viewer can see no cell and no unit.
	overlays.show_capture_pips(game.capture_progress, perspective)
	_refresh_threat()
	BattleCampaign.refresh_marks(self)


func refresh_hud() -> void:
	view.refresh_hud()


## The move was never committed to the sim, so undo is just snapping the
## sprite back and returning to the range view (AW-style B-cancel).
func _undo_move_preview() -> void:
	view.refresh_sprite(selected)
	overlays.paint_move(move_range.cells())
	state = State.UNIT_SELECTED
	set_cursor_cell(selected.cell)
	planned_path = [selected.cell]
	overlays.trace_path(planned_path)


# --- attack flow -------------------------------------------------------------


func _enter_targeting() -> void:
	state = State.TARGETING
	overlays.paint_attack(_attack_targets)
	set_cursor_cell(_attack_targets[0])


func _exit_targeting_to_menu() -> void:
	overlays.paint_attack([])
	view.update_damage_preview(null, cursor_cell)
	_on_move_animation_done()  # recomputes targets and reopens the menu


# --- transport flow ----------------------------------------------------------


## The menu row names one typed option; its passenger and viewer-safe drop cells
## stay paired from menu construction through command creation.
func _enter_drop_targeting(index: int) -> void:
	state = State.DROP_TARGETING
	_drop_option = _drop_options[index]
	overlays.paint_move(_drop_option.cells)
	set_cursor_cell(_drop_option.cells[0])


func _execute_drop(drop_cell: Vector2i) -> void:
	var command := DropCommand.new(selected, planned_path, drop_cell, _drop_option.passenger)
	var receipt := await execute_command(command)
	if receipt.rejected():
		# The UI only offers legal drops, so this is a bug guard.
		push_error("DropCommand rejected: %s" % receipt.validation_error)
		_cancel()
		return
	_drop_options = []
	_drop_option = null
	_clear_selection(false)
	await conclude_command(receipt)


func _execute_attack(target_cell: Vector2i) -> void:
	var command := AttackCommand.new(selected, planned_path, target_cell)
	overlays.paint_attack([])
	view.update_damage_preview(null, cursor_cell)
	overlays.trace_path([])
	state = State.ANIMATING
	var receipt := await execute_command(command)
	if receipt.rejected():
		# The UI only offers legal attacks, so this is a bug guard.
		push_error("AttackCommand rejected: %s" % receipt.validation_error)
		_exit_targeting_to_menu()
		return
	_clear_selection(false)
	await conclude_command(receipt)


## Whether a damage forecast applies at all is a flow question — only the
## targeting state, with a real target under the cursor, has one to show.
func _update_damage_preview() -> void:
	var target := game.unit_at(cursor_cell)
	if state != State.TARGETING or target == null or cursor_cell not in _attack_targets:
		view.update_damage_preview(null, cursor_cell)
		return
	var dest: Vector2i = planned_path[planned_path.size() - 1]
	view.update_damage_preview(CombatResolver.forecast(game, selected, dest, target), cursor_cell)


# --- cursor ------------------------------------------------------------------


func _mouse_cell() -> Vector2i:
	return Vector2i((get_global_mouse_position() / BattleView.TILE).floor())


func set_cursor_cell(cell: Vector2i) -> void:
	cursor_cell = cell
	view.move_cursor_to(cell)
	refresh_panel()
	if state == State.UNIT_SELECTED:
		if move_range.has(cell) and move_range.can_stop_at(cell):
			planned_path = move_range.path_to(cell)
		overlays.trace_path(planned_path)
	elif state == State.TARGETING:
		_update_damage_preview()
	elif state == State.POWER_TARGETING:
		_paint_blast(cell)


func refresh_panel() -> void:
	view.refresh_panel(cursor_cell)
