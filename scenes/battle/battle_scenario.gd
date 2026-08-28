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
