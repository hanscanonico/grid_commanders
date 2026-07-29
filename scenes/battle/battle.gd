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
## cleanup. `start_turn`, `enter_victory`, `refresh_fog`, `refresh_hud`, and
## `refresh_panel` are the remaining public presentation entry points.

enum State {
	IDLE,
	UNIT_SELECTED,
	PREVIEW,
	ANIMATING,
	MENU,
	TARGETING,
	DROP_TARGETING,
	VICTORY,
	AI_TURN,
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
	State.VICTORY: ControlHints.VICTORY,
	State.AI_TURN: ControlHints.AI_TURN,
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
@onready var victory_screen: PanelContainer = %VictoryScreen
@onready var victory_portrait: TextureRect = %VictoryPortrait
@onready var victory_faction_label: Label = %VictoryFactionLabel
@onready var victory_label: Label = %VictoryLabel
@onready var victory_sub_label: Label = %VictorySubLabel
@onready var rematch_button: Button = %RematchButton
@onready var menu_button: Button = %MenuButton
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
## team -> AIController. One planner per team rather than one for the scene:
## a normal match gives both entries the same tier's planner and nothing changes,
## while watch mode (balance plan BS3) can put a different commander *and* a
## different tier on each side and have each plan with its own profile and its
## own per-turn threat map.
var planners: Dictionary = {}
## Teams played by the computer. Blue by default; `--hotseat` clears it.
var ai_teams: Array[int] = [2]
## The last human seat that actually took a turn, or 0 before anyone has. What
## the fogged handoff and the AI-turn viewer are both keyed to (four-players plan
## D7), because with mixed seats the device changes hands across intervening
## computer turns and "the seat before this one" stops meaning "the last person".
var _last_human_team := 0
## The tier this match is being played at, as BattleSetup resolved it — from the
## menu, a `--difficulty=` flag, or the resumed save itself. Held here because
## the scene is what a save asks for it: it is the id SaveGame records, and the
## one a resumed match plays back at.
var difficulty: Difficulty
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
			view.refresh_keys(STATE_CONTEXT.get(state, ControlHints.IDLE))

var selected: Unit
var move_range: MovementResolver.MoveRange
var planned_path: Array[Vector2i] = []
## A unit inspected but not commanded — an enemy, or one of ours that has acted.
## Its move range shows in blue; `selected` stays null, so the menu flow keeps its
## meaning of "a unit I am commanding" and no command can act on a previewed one.
var _previewed: Unit
## Whether R's red fire ring is painted; every exit from a range state clears it.
var _range_shown := false
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
## rematch the victory lockup offers. BattleOutcome's sibling; see BattleExit.
var _exit: BattleExit


func _ready() -> void:
	db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	commander_db = CommanderDB.load_default()
	_ai_runner = BattleAiRunner.new(self)
	_exit = BattleExit.new(self)
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
	map = built.map
	game = built.game
	ai_teams = built.ai_teams
	difficulty = built.difficulty
	_build_planners(built)
	perspective = BattlePerspective.new(game)
	view = _build_view()
	view.setup()
	animator = _build_animator()
	_command_pipeline = BattleCommandPipeline.new(self)
	_outcome = _build_outcome()
	_outcome.configure(request.watching, request.days_cap)
	action_menu.action_chosen.connect(_on_menu_action)
	end_turn_guard.review_requested.connect(_review_ready_units)
	end_turn_guard.end_requested.connect(_end_turn_anyway)
	view.hud_bottom.fire_button.pressed.connect(_fire_command_power)
	rematch_button.pressed.connect(_request_rematch)
	menu_button.pressed.connect(_request_main_menu)
	handoff_button.pressed.connect(leave_handoff)
	commander_info_sheet.closed.connect(_close_commander_info)
	_zoom = BattleZoom.new(view)
	_zoom.setup()
	set_cursor_cell(Vector2i.ZERO)
	# Dev-only capture flows. The driver is held for the whole scene: `run`
	# awaits, and a RefCounted nobody references is freed mid-scenario.
	var driver := BattleScenarioDriver.new(self)
	_capturing = driver.requested()
	animator.capturing = _capturing
	if _capturing:
		# A capture pins its own pace and ignores the device preference: a frame
		# must not depend on which machine took it, or on how fast whoever ran
		# `make smoke` likes to watch their tanks move.
		Settings.pin(GameSpeed.CAPTURE_ID)
		# The teaching strip is pinned for the same reason and one more: whether
		# *this* machine's player has already learned to capture would otherwise
		# decide whether a card sits over the board in every other scenario's
		# frame. Every capture but the strip's own hides it (COM-12).
		Settings.pin_hints(not driver.wants_mission_strip())
	animator.start_cursor_pulse()
	start_turn()  # day 1 gets the same banner/cursor/event as every turn
	camera.position = cursor.position
	camera.reset_smoothing()
	if _capturing:
		# Smoothing glides the camera toward the cursor over several frames, so
		# how far it has travelled when the shutter opens depends on real
		# elapsed time — enough to shift a whole frame by a pixel between runs.
		# Captures show where the view settles, which is the position UI is
		# already anchored to anyway (see BattleView.screen_pos_for_cell).
		camera.position_smoothing_enabled = false
		_scenario_driver = driver
		_scenario_driver.run()


## Gives every team its planner. The tier is the one lever difficulty pulls —
## which AIProfile weighs the moves, never the economy, vision, damage or luck
## (difficulty plan D2/D3) — so a per-side tier is a per-side profile and nothing
## more. Each team gets its own AIController even when the tiers match, because a
## controller caches a threat map for the turn it is planning and two teams
## sharing one would be reading each other's.
func _build_planners(built: BattleSetup.BuiltMatch) -> void:
	for team in built.game.teams:
		var tier: Difficulty = built.per_team_difficulty.get(team, built.difficulty)
		planners[team] = AIController.new(unit_db, tier.profile())


## The planner for a team. Never null: a team the setup did not name still gets
## the match's tier, so nothing can reach a turn with nobody to plan it.
func planner_for(team: int) -> AIController:
	if not planners.has(team):
		planners[team] = AIController.new(unit_db)
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
	await _announce_fallen(receipt.fallen)
	if receipt.turn_changed:
		start_turn()
	elif receipt.winner != 0:
		enter_victory()


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
		state = State.IDLE


## Hands the view the nodes it draws on. Assignment rather than a constructor
## argument list keeps the dependency one-way: the view never learns what a
## Battle is.
func _build_view() -> BattleView:
	var built := BattleView.new()
	built.terrain_layer = $TerrainLayer
	built.backdrop_layer = $Backdrop
	built.move_overlay = $MoveOverlay
	built.attack_overlay = $AttackOverlay
	built.fog_layer = $FogLayer
	built.path_line = $PathLine
	built.units_root = $Units
	built.cursor = cursor
	built.camera = camera
	built.hud_bottom = %HudBottom
	built.damage_preview = %DamagePreview
	built.atk_label = %AtkLabel
	built.counter_label = %CounterLabel
	built.outcome_label = %OutcomeLabel
	built.hud_top = %HudTop
	built.mission_strip = %MissionStrip
	built.db = db
	built.map = map
	built.game = game
	built.perspective = perspective
	built.ai_teams = ai_teams
	built.identity = SideIdentity.for_game(game)  # the side resolver; Battle reads view.identity
	return built


## Same assignment-not-constructor shape as _build_view, and for the same reason:
## neither the animator nor the cut-in it plays ever learns what a Battle is.
func _build_animator() -> BattleAnimator:
	var built := BattleAnimator.new()
	built.node = self
	built.view = view
	built.perspective = perspective
	built.camera = camera
	built.cursor = cursor
	built.turn_banner = %TurnBanner
	built.banner_label = %BannerLabel
	built.power_banner = %CommanderBanner
	built.cutscene = %Cutscene
	built.cutscene.view = view
	built.capture_cutscene = %CaptureCutscene
	built.capture_cutscene.view = view
	return built


## Same assignment-not-constructor shape as _build_view/_build_animator, plus the
## scene itself: the reporter sets Battle.state and needs get_tree(), so it holds
## the node the way BattleAiRunner does, and is handed the victory screen's nodes.
func _build_outcome() -> BattleOutcome:
	var built := BattleOutcome.new(self)
	built.victory_screen = victory_screen
	built.victory_portrait = victory_portrait
	built.victory_faction_label = victory_faction_label
	built.victory_label = victory_label
	built.victory_sub_label = victory_sub_label
	built.rematch_button = rematch_button
	built.menu_button = menu_button
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
		# The computer's turn refuses play, but it says so rather than going quiet.
		if _is_confirm_press(event):
			confirm_at(cursor_cell)
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
		State.TARGETING:
			if cell in _attack_targets:
				_execute_attack(cell)
		State.DROP_TARGETING:
			if _drop_option != null and cell in _drop_option.cells:
				_execute_drop(cell)
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
		view.paint_move_overlay([])
		_drop_options = []
		_drop_option = null
		_on_move_animation_done()  # back to the unit menu


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
	view.paint_move_overlay(move_range.cells())
	view.update_path_line(planned_path)
	state = State.UNIT_SELECTED


func _clear_selection(refresh_board: bool = true) -> void:
	selected = null
	move_range = null
	planned_path = []
	_attack_targets = []
	_drop_options = []
	_drop_option = null
	_range_shown = false
	view.paint_move_overlay([])
	view.paint_attack_overlay([])
	view.update_path_line([])
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
	view.paint_move_overlay(perspective.move_overlay_cells(unit))
	view.paint_attack_overlay([])
	view.update_path_line([])  # a preview plans no route
	state = State.PREVIEW


func _clear_preview() -> void:
	_previewed = null
	_range_shown = false
	view.paint_move_overlay([])
	view.paint_attack_overlay([])
	state = State.IDLE


## R toggles the red fire ring for whatever unit's move range is on screen. A
## momentary lens; it issues nothing. Public for the same reason `confirm_at` and
## `set_cursor_cell` are: the scenario driver walks the flows a player's input
## reaches, and this is one of them. Painted through the perspective rather than off
## AttackRange directly, because the ring is whole for a unit of the viewer's own side
## and their best reading of another side's — a split by whose unit it is, not by which
## state we are in, and the perspective's to make rather than this call site's.
func toggle_range() -> void:
	# The unit whose range is up: the selected one, or a previewed one.
	var unit: Unit = selected if state == State.UNIT_SELECTED else _previewed
	if unit == null:  # not in a range state
		return
	_range_shown = not _range_shown
	if _range_shown:
		view.paint_attack_overlay(perspective.threat_overlay_cells(unit))
	else:
		view.paint_attack_overlay([])


func _animate_move() -> void:
	state = State.ANIMATING
	_range_shown = false
	view.paint_move_overlay([])
	view.paint_attack_overlay([])  # a fire ring shown with R does not survive the move
	view.update_path_line([])
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
		&"abandon":
			_exit.handle_confirm_action(action)


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
	conclude_command(receipt)


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
	conclude_command(receipt)


func _handle_map_action(action: StringName) -> void:
	state = State.IDLE
	if action == &"power":
		_fire_command_power()
		return
	if action == &"commanders":
		_open_commander_info()
		return
	if action == &"speed":
		# Cycles Slow -> Normal -> Quick -> Instant and persists, so the next
		# animation already obeys it. The banner confirms it the way Save does:
		# the setting is otherwise invisible until something moves.
		Settings.set_speed(GameSpeed.next(Settings.speed.id).id)
		present_banner("Speed: %s" % Settings.speed.display_name)
		return
	if action == &"save":
		_exit.save_match()
		return
	if action == &"save_and_quit":
		_exit.save_and_leave()
		return
	if action == &"quit":
		# The context is Battle's to set — it is what routes the rows that come back
		# — and the confirmation itself is BattleExit's, like the leaving behind it.
		_menu_context = &"abandon"
		_exit.confirm_abandon()
		return
	if action != &"end_turn":
		return
	_request_end_turn()


func _request_end_turn() -> void:
	var ready := _ready_units()
	if not ready.is_empty():
		state = State.CONFIRM
		end_turn_guard.open(game.day, ready, view.identity.theme(game.current_team))
		return
	_commit_end_turn()


func _review_ready_units() -> void:
	state = State.IDLE
	var ready := _ready_units()
	if not ready.is_empty():
		set_cursor_cell(ready[0].cell)


func _end_turn_anyway() -> void:
	state = State.IDLE
	_commit_end_turn()


func _ready_units() -> Array[Unit]:
	var ready: Array[Unit] = []
	for unit in game.units:
		if unit.team == game.current_team and not unit.acted and unit.carrier == null:
			ready.append(unit)
	ready.sort_custom(
		func(a: Unit, b: Unit) -> bool:
			return a.cell.y < b.cell.y or (a.cell.y == b.cell.y and a.cell.x < b.cell.x)
	)
	return ready


func _commit_end_turn() -> void:
	var command := EndTurnCommand.new()
	var receipt := await execute_command(command)
	if receipt.rejected():
		push_error("EndTurnCommand rejected: %s" % receipt.validation_error)
		return
	conclude_command(receipt)


## Fires the current team's Command Power. Reached from the HUD button, the F
## shortcut its charged meter advertises, and the map menu; all three go through
## PowerCommand, like every other action. Guarded rather than assumed legal,
## because the HUD button sits outside the selection flow — it is reachable
## mid-move — and the command is the authority on that. *Who is at the keyboard*
## is the one thing it cannot answer, so the refusal the bar makes by hiding the
## button from a computer commander is made here, once, for all three.
func _fire_command_power() -> void:
	var command := PowerCommand.new()
	if game.current_team in ai_teams or state not in [State.IDLE, State.MENU]:
		return
	# A power may be fired from the HUD while a unit menu is open. Close that
	# interactive layer before the activation card owns the screen.
	action_menu.close()
	state = State.ANIMATING
	var receipt := await execute_command(command)
	if receipt.rejected():
		state = State.IDLE
		return
	# A power can change movement, vision and HP at once, so the whole board is
	# redrawn, and the selection — plus any menu the HUD button fired over, whose
	# rows would otherwise act on it — belongs to rules that no longer apply.
	_clear_selection(false)
	conclude_command(receipt)


## Locks input and shows the already-decided winner. Public because the AI turn
## runner reaches the same terminal flow as a human command.
func enter_victory() -> void:
	_outcome.enter_victory()


func _request_rematch() -> void:
	if _outcome.accepts_action(rematch_button):
		_exit.rematch()


func _request_main_menu() -> void:
	if _outcome.accepts_action(menu_button):
		_exit.to_main_menu()


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
	state = State.MENU
	# Its first row is the Command Power, which is one of the two routes the charged
	# meter in the bottom bar advertises (F is the other). Nothing floats over the
	# board any more, so the menu only has to clamp inside the band between the bars.
	action_menu.open(BattleMenus.map_actions(game), view.screen_pos_for_cell(cursor_cell))


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
		state = State.IDLE


func start_turn() -> void:
	action_feedback.clear_turn()
	view.set_active_team(game.current_team)
	if _needs_handoff():
		_enter_handoff()
		return
	_begin_turn()


## Everything the incoming team is allowed to see, run once the device has
## actually changed hands (immediately, outside fogged hot-seat).
func _begin_turn() -> void:
	# Units can be lost between turns with no shot fired: an air or sea unit that
	# ran its tank dry is already gone from the sim by now, so the board is
	# resynced before it is drawn — and a side wiped out by its own fuel gauge
	# ends the match here, exactly as one shot to pieces does.
	view.sync_sprites()
	refresh_fog()
	refresh_hud()
	refresh_panel()
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
	if game.current_team in ai_teams:
		state = State.AI_TURN
		_ai_runner.run()
	else:
		_last_human_team = game.current_team
		state = State.IDLE


## Says out loud that an army has left the match. Public information, fog or no
## fog — every side learns that a seat emptied, because the board they are playing
## on just changed shape.
##
## Uses the same blocking beat every other banner does, so Instant clamps it and
## any press skips it; suppressed while `capturing`, like the cut-ins, so posed
## frames stay byte-stable. Awaited before the turn hands over, so the banner
## lands on the board that produced it rather than over the next player's.
func _announce_fallen(fallen: Array[int]) -> void:
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
## Keyed to the last human seat rather than to the seat immediately before this
## one (four-players plan D7): with two humans and two computers the device
## changes hands across intervening AI turns, and asking only "was the previous
## turn another person's" would hand player B a board still painted with player
## A's vision. The same player taking two turns in a row — everyone else having
## fallen — is not a handoff and is not asked for one.
func _needs_handoff() -> bool:
	if not game.fog_enabled or game.winner != 0:
		return false
	if game.current_team in ai_teams:
		return false
	return _last_human_team != 0 and _last_human_team != game.current_team


func _enter_handoff() -> void:
	state = State.HANDOFF
	animator.hide_banner()
	refresh_fog()  # blanks the outgoing team's vision before the panel goes up
	handoff_label.text = (
		"%s — press confirm when ready" % view.identity.display_name(game.current_team)
	)
	handoff_screen.show()
	handoff_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	if _last_human_team != 0 and _last_human_team not in ai_teams:
		return _last_human_team
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


func refresh_hud() -> void:
	view.refresh_hud()


## The move was never committed to the sim, so undo is just snapping the
## sprite back and returning to the range view (AW-style B-cancel).
func _undo_move_preview() -> void:
	view.refresh_sprite(selected)
	view.paint_move_overlay(move_range.cells())
	state = State.UNIT_SELECTED
	set_cursor_cell(selected.cell)
	planned_path = [selected.cell]
	view.update_path_line(planned_path)


# --- attack flow -------------------------------------------------------------


func _enter_targeting() -> void:
	state = State.TARGETING
	view.paint_attack_overlay(_attack_targets)
	set_cursor_cell(_attack_targets[0])


func _exit_targeting_to_menu() -> void:
	view.paint_attack_overlay([])
	view.update_damage_preview(null, cursor_cell)
	_on_move_animation_done()  # recomputes targets and reopens the menu


# --- transport flow ----------------------------------------------------------


## The menu row names one typed option; its passenger and viewer-safe drop cells
## stay paired from menu construction through command creation.
func _enter_drop_targeting(index: int) -> void:
	state = State.DROP_TARGETING
	_drop_option = _drop_options[index]
	view.paint_move_overlay(_drop_option.cells)
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
	conclude_command(receipt)


func _execute_attack(target_cell: Vector2i) -> void:
	var command := AttackCommand.new(selected, planned_path, target_cell)
	view.paint_attack_overlay([])
	view.update_damage_preview(null, cursor_cell)
	view.update_path_line([])
	state = State.ANIMATING
	var receipt := await execute_command(command)
	if receipt.rejected():
		# The UI only offers legal attacks, so this is a bug guard.
		push_error("AttackCommand rejected: %s" % receipt.validation_error)
		_exit_targeting_to_menu()
		return
	_clear_selection(false)
	conclude_command(receipt)


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
		view.update_path_line(planned_path)
	elif state == State.TARGETING:
		_update_damage_preview()


func refresh_panel() -> void:
	view.refresh_panel(cursor_cell)
