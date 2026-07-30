class_name BattleTransitionScenario
extends RefCounted
## Driven acceptance flows for the state boundaries a turn crosses: the input
## convention (COM-15), the mixed-seat viewer and handoff (COM-47), and the pause
## a player may take while the computer plays. They use the same public Battle
## entry points and input events a player does, and return a diagnostic rather
## than owning the smoke run's exit code.

const BUILD_CELL := Vector2i(3, 2)
const OUTCOME_GUARD_SECONDS := 0.55
## The mixed roster `mixed_seat_handoff` poses on the four-army fixture: seats 1
## and 3 at the table, 2 and 4 played by the computer, so a computer turn sits
## between the two people every round. That is the arrangement D7 is about; the
## menu's seat strip can set it up, but this scenario poses it directly so the
## flow gate does not depend on the menu.
const MIXED_AI_SEATS: Array[int] = [2, 4]
const FIRST_HUMAN_SEAT := 1
const SECOND_HUMAN_SEAT := 3
## How long a wait on the other side of a computer turn may take. Generous: an AI
## turn plans, and this only has to catch a flow that will never arrive.
const TURN_WAIT_FRAMES := 1800
## The computer's seat on the default board `ai_pause` runs on — the one side
## Battle plays itself unless `--hotseat` clears it.
const AI_SEAT := 2

var _battle: Battle


func _init(battle: Battle) -> void:
	_battle = battle


func run(mode: String) -> String:
	match mode:
		"turn_banner_build_attempt":
			return await _run_turn_banner_build_attempt()
		"outcome_mash_guard":
			return await _run_outcome_mash_guard()
		"mixed_seat_handoff":
			return await _run_mixed_seat_handoff()
		"ai_pause":
			return await _run_ai_pause()
	return "unknown transition scenario: %s" % mode


## The opening banner must own the interaction state. The first attempted press
## retires that beat, then the next one may open production on an unobscured board.
func _run_turn_banner_build_attempt() -> String:
	if not _battle.animator.turn_banner.visible:
		return "turn banner retired before the build attempt could exercise it"
	_battle.confirm_at(BUILD_CELL)
	await _battle.get_tree().process_frame
	if _battle.action_menu.visible:
		return "build menu opened underneath the turn banner"
	if not _battle.animator.turn_banner.visible:
		return "build attempt hid the banner without travelling through its skip input"

	await _press_key(KEY_ENTER)
	if not await _wait_for_banner(false):
		return "a press during the turn banner was swallowed instead of skipping it"
	if _battle.state != Battle.State.IDLE:
		return "turn banner retired into state %s instead of IDLE" % _battle.state

	_battle.confirm_at(BUILD_CELL)
	await _until_state(Battle.State.MENU)
	if _battle.animator.turn_banner.visible:
		return "build menu opened before the skipped turn banner cleared"
	return ""


## Wins through the real attack flow, then sends the buffered confirm that used
## to land on an already-focused Rematch. It must neither focus nor activate
## anything during the guard; after the guard, one fresh press only highlights.
func _run_outcome_mash_guard() -> String:
	await BattleScenarioDriver.stage_rout(_battle)
	var focused := _battle.get_viewport().gui_get_focus_owner()
	if focused != null and _battle.victory_screen.is_ancestor_of(focused):
		return "outcome appeared with '%s' already focused" % focused.name
	if _battle.rematch_button.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return "outcome buttons accepted pointer input during the mash guard"

	var scene := _battle.get_tree().current_scene
	# A button's pressed signal is the last seam before rematch. Even if a
	# buffered click focused it first, the guarded callback must release it.
	_battle.rematch_button.grab_focus()
	_battle.rematch_button.pressed.emit()
	await _press_key(KEY_ENTER)
	await _battle.get_tree().process_frame
	if _battle.get_tree().current_scene != scene:
		return "buffered outcome press restarted or left the match"
	focused = _battle.get_viewport().gui_get_focus_owner()
	if focused != null and _battle.victory_screen.is_ancestor_of(focused):
		return "buffered outcome press focused '%s' during the guard" % focused.name

	await _battle.get_tree().create_timer(OUTCOME_GUARD_SECONDS).timeout
	if _battle.rematch_button.mouse_filter != Control.MOUSE_FILTER_STOP:
		return "outcome buttons stayed pointer-locked after the mash guard"
	await _press_key(KEY_ENTER)
	await _battle.get_tree().process_frame
	if _battle.get_tree().current_scene != scene:
		return "the first accepted outcome press activated an action"
	focused = _battle.get_viewport().gui_get_focus_owner()
	if focused == null or not _battle.victory_screen.is_ancestor_of(focused):
		return "the first accepted outcome press did not highlight an action"
	return ""


## The mixed-seat viewer and handoff (COM-47, four-players plan D7), driven on the
## four-army fixture with fog on. The roster is posed here rather than launched
## through the menu, the way side_victory poses `sides`; without this flow the
## whole policy rests on a reading of the code.
##
## Three claims, every one of which photographs exactly like its opposite:
##  - the blackout fires for the incoming person even though the turn before theirs
##    was a computer's, because the device still changed hands;
##  - while a computer plays, the board is drawn through the fog of the person who
##    just played, not through the first human seat on the board;
##  - the same person taking two turns in a row, the other having fallen, is not a
##    handoff and is not asked for one.
func _run_mixed_seat_handoff() -> String:
	var game := _battle.game
	if game.teams.size() < 4 or not game.fog_enabled:
		return "mixed_seat_handoff needs the four-army board with fog on"
	_battle.ai_teams = MIXED_AI_SEATS.duplicate()
	await _until_state(Battle.State.IDLE)  # the driver already left the opening handoff

	var error := await _end_turn_into(MIXED_AI_SEATS[0])
	if error != "":
		return error
	error = _expect_viewer(FIRST_HUMAN_SEAT)
	if error != "":
		return error

	error = await _wait_for_handoff(SECOND_HUMAN_SEAT)
	if error != "":
		return error
	_battle.leave_handoff()
	await _until_state(Battle.State.IDLE)

	error = await _end_turn_into(MIXED_AI_SEATS[1])
	if error != "":
		return error
	error = _expect_viewer(SECOND_HUMAN_SEAT)
	if error != "":
		return error

	error = await _wait_for_handoff(FIRST_HUMAN_SEAT)
	if error != "":
		return error
	_battle.leave_handoff()
	await _until_state(Battle.State.IDLE)

	# The other person falls, so seat 1 takes every human turn left. Nobody to hand
	# the device to means nobody to black the board out for. Eliminating from
	# outside the pipeline leaves the forfeited ground unpainted, so the pose
	# repaints it for itself, exactly as the side_victory pose does.
	game.eliminate(SECOND_HUMAN_SEAT)
	_battle.view.sync_sprites()
	for cell: Vector2i in game.property_owners:
		_battle.view.repaint_property(cell)
	error = await _end_turn_into(MIXED_AI_SEATS[0])
	if error != "":
		return error
	error = await _wait_for_team(FIRST_HUMAN_SEAT)
	if error != "":
		return error
	if _battle.state == Battle.State.HANDOFF:
		return "the last player at the table was asked to hand the device to themselves"
	return ""


## The board a player may take back while the computer plays. In a watched match
## every turn is a computer's, so without this there is no route to a menu — or out
## of the match — at all; in an ordinary one it is the same route, one turn early.
##
## Every claim here photographs exactly like its opposite, which is why the frame
## is not the check:
##  - Esc during the computer's turn reaches a menu at all;
##  - that menu is missing the two rows that would act for the side on turn, and the
##    side on turn is not the player's;
##  - closing it leaves the turn *held* rather than handing it back, so the pause is
##    a place to stand and not a flicker;
##  - and confirming hands it back to a runner that picks up where it stopped. That
##    last one is the failure worth catching: a pause that never resumes is a match
##    frozen for good, and it looks exactly like a pause that does.
##
## Ends back in the pause menu, so the capture is of the screen the mode is named
## for. The second pause lands on the same turn as the first — a computer turn on
## this board runs to many commands, and the pause is honoured at any boundary
## between two of them.
func _run_ai_pause() -> String:
	var error := await _end_turn_into(AI_SEAT)
	if error != "":
		return error
	error = await _wait_for_state(Battle.State.AI_TURN, "the computer taking its turn")
	if error != "":
		return error
	await _press_key(KEY_ESCAPE)
	error = await _wait_for_state(Battle.State.MENU, "Esc during the computer's turn")
	if error != "":
		return error
	error = _check_pause_rows()
	if error != "":
		return error

	_battle.action_menu.choose(&"cancel")
	error = await _wait_for_state(Battle.State.PAUSED, "closing the pause menu")
	if error != "":
		return error
	var acted := _acted_count(AI_SEAT)
	await _press_key(KEY_ENTER)
	# The state is read two frames after the press, and an instant-speed runner can
	# have finished the turn by then. That case has its own diagnostic below; this
	# check answers only for a turn that is still the computer's.
	if _battle.state != Battle.State.AI_TURN and _battle.game.current_team == AI_SEAT:
		return "confirming a paused turn left state %s, not the computer's" % _battle.state
	for frame in TURN_WAIT_FRAMES:
		if _acted_count(AI_SEAT) != acted or _battle.game.current_team != AI_SEAT:
			break
		await _battle.get_tree().process_frame
	if _acted_count(AI_SEAT) == acted and _battle.game.current_team == AI_SEAT:
		return "the resumed computer turn never issued another command"

	if _battle.game.current_team != AI_SEAT:
		return "the computer's turn ended before the pause could be posed"
	await _press_key(KEY_ESCAPE)
	error = await _wait_for_state(Battle.State.MENU, "a second Esc")
	if error != "":
		return error
	# The press is answered before the pause itself lands, and the chip that says so
	# fades on a real-time clock of its own. Waited out rather than posed, so the
	# frame this mode leaves behind is the same one every run.
	for frame in TURN_WAIT_FRAMES:
		if not _battle.action_feedback.visible:
			return ""
		await _battle.get_tree().process_frame
	return "the pause notice never cleared"


## The rows the pause menu was opened with, read back off the live buttons rather
## than recomputed: what is under test is which menu Battle asked for, and the
## builder answers that question with itself.
func _check_pause_rows() -> String:
	var expected := BattleMenus.map_actions(_battle.game, false)
	for row: Dictionary in expected:
		if row.id == &"power" or row.id == &"end_turn":
			return "the pause menu offers '%s', which would act for the computer" % row.id
	var buttons := _battle.action_menu.rows.get_children()
	if buttons.size() != expected.size():
		return (
			"the pause menu shows %d rows against the %d it should have"
			% [buttons.size(), expected.size()]
		)
	for i in expected.size():
		# ActionMenu prints a two-character arm marker ("> " or two spaces) ahead of
		# every label, so the row is compared from behind it.
		var text := (buttons[i] as Button).text.substr(2)
		if text != String(expected[i].label):
			return "pause menu row %d reads '%s', not '%s'" % [i, text, expected[i].label]
	return ""


## How much of a side has already moved this turn — the cheapest thing a command
## the computer issues is certain to change, so the resumed turn can be watched for
## one without waiting the whole turn out.
func _acted_count(team: int) -> int:
	var acted := 0
	for unit: Unit in _battle.game.units:
		if unit.team == team and unit.acted:
			acted += 1
	return acted


## Ends the human turn in hand through the live map menu — the same helper the
## endturn and aiturn modes use, guard and all — and waits for `team` to take it.
func _end_turn_into(team: int) -> String:
	await BattleFeedbackScenario.new(_battle).end_turn_anyway()
	return await _wait_for_team(team)


## Read off the live perspective, which is the one the fog is actually drawn from.
func _expect_viewer(team: int) -> String:
	var viewer := _battle.perspective.viewing_team()
	if viewer == team:
		return ""
	return (
		"team %d's turn is drawn through team %d's fog, not team %d's who played last"
		% [_battle.game.current_team, viewer, team]
	)


## Bounded twin of `_until_state`: a flow that never arrives is named rather than
## left to the sweep's own deadline, which only knows the scenario.
func _wait_for_state(wanted: Battle.State, what: String) -> String:
	for frame in TURN_WAIT_FRAMES:
		if _battle.state == wanted:
			return ""
		await _battle.get_tree().process_frame
	return "%s left the scene in state %s, not %s" % [what, _battle.state, wanted]


func _wait_for_team(team: int) -> String:
	for frame in TURN_WAIT_FRAMES:
		if _battle.game.current_team == team:
			return ""
		await _battle.get_tree().process_frame
	return "team %d never came up to play" % team


## The incoming team's turn must open blacked out. A turn that opened straight
## onto the board is the leak, so IDLE is a failure rather than something to
## keep waiting through.
func _wait_for_handoff(team: int) -> String:
	for frame in TURN_WAIT_FRAMES:
		if _battle.game.current_team == team:
			if _battle.state == Battle.State.HANDOFF:
				return ""
			if _battle.state == Battle.State.IDLE:
				return "team %d took the device over with no handoff" % team
		await _battle.get_tree().process_frame
	return "team %d never came up for its handoff" % team


func _press_key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await _battle.get_tree().process_frame


func _wait_for_banner(visible: bool) -> bool:
	for frame in 120:
		if _battle.animator.turn_banner.visible == visible:
			return true
		await _battle.get_tree().process_frame
	return false


func _until_state(wanted: Battle.State) -> void:
	while _battle.state != wanted:
		await _battle.get_tree().process_frame
