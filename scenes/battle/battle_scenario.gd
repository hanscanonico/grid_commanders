class_name BattleScenario
extends RefCounted
## What every driven scenario is made of: the Battle it drives, the wait it
## advances by, and the two presses it sends.
##
## Dev-only, like every class that extends it. Each of them used to spell these
## for itself, so "how does a scenario wait" had two answers and "how does it
## press a key" had three — a scenario that drifted from its siblings drifted
## silently. Stated once here, a subclass owns only its staged boards and the
## checks it makes of them.
##
## `until_state_of` is static because BattleScenarioDriver.stage_rout is: shared
## staging is handed a Battle rather than an instance.

var _battle: Battle


func _init(battle: Battle) -> void:
	_battle = battle


## Scenarios advance by waiting on the scene's own state machine rather than a
## fixed frame count, so they stay correct when animation timings change.
func _until_state(wanted: Battle.State) -> void:
	await until_state_of(_battle, wanted)


static func until_state_of(battle: Battle, wanted: Battle.State) -> void:
	while battle.state != wanted:
		await battle.get_tree().process_frame


## A control built in code measures and places itself a frame after its children
## were added: the seat strip centres itself, the info sheet's grid sizes its
## columns. The action menu is not one of them — ActionMenu.open sizes and clamps
## the panel before it returns.
func _settle_layout() -> void:
	await _battle.get_tree().process_frame


## One press and its release, resolved to an action by the InputMap rather than
## named as one — so what a check proves is the whole chain from the keycode down,
## project.godot's binding included. Released as well as pressed, or the board's
## held-direction repeat would keep walking the cursor after the flow moved on.
func _press_key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await _battle.get_tree().process_frame


## Sends an action down the player's own input path, so the flow under test is the
## one a keyboard reaches — not a handler called directly.
func _press_action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await _battle.get_tree().process_frame


## Raised by any mid-scenario check that fails, and read before anything is
## written: a capture saved after a failed check would take the exit code down
## with it — ScreenshotUtil quits zero — and that code is the entire signal the
## smoke sweep reads.
var _failed := false


## Reports a scenario failure. The push_error and the flag are not separable: an
## error printed without the flag photographs a board the scenario never staged
## and still passes.
func _fail(message: String) -> void:
	push_error(message)
	_failed = true


## Reports whatever a scenario class handed back, which is its complaint or ""
## for a clean run.
func _fail_if(error: String) -> void:
	if error != "":
		_fail(error)


## A live control sits inside the *board band* — the strip of the 640x360 frame the
## docked bars leave over, which is what ActionMenu clamps against and what
## MissionStrip centres itself in. Read off the live rects rather than recomputed.
## The touch dock is one of those bars, so the band is MobileDock.board_band's
## answer and a --mobile run of this check measures the band a finger plays in.
## Static and complaint-returning so the scenario classes, which report by return
## value, share the one measurement rather than keeping a second copy of it.
static func band_error(battle: Battle, what: String, control: Control) -> String:
	var rect := control.get_global_rect()
	var frame := battle.get_viewport().get_visible_rect().size
	var band := MobileDock.board_band(frame)
	if band.encloses(rect):
		return ""
	return "the %s %s does not fit the board band %s" % [what, rect, band]
