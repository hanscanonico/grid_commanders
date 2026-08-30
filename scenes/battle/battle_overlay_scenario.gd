class_name BattleOverlayScenario
extends BattleScenario
## The field overlays, posed together: a capture chip counting down on the city,
## the arrowed route from a selected unit to the cell under the cursor, and the
## threat lens shading everywhere the other side could shoot.
##
## Together on purpose. Each is legible alone, and the question the slice has to
## answer is whether they are legible *at once* — three reds and a mint over the
## same terrain — which no per-overlay capture can show.
##
## Its own class rather than more methods on BattleScenarioDriver, the way
## BattleVictoryScenario and BattleFeedbackScenario are: that file is at its
## length ratchet. Returns an error string rather than reporting one, because the
## driver's `_fail` owns the push_error and the exit-code flag together.

## The city the default board's `capture` demo takes and the infantry that takes
## it — BattleScenarioDriver's CAPTURE_CELL / CAPTURER_CELL, restated here so the
## two scenario files do not import each other in a circle.
const CAPTURE_CELL := Vector2i(3, 4)
const CAPTURER_CELL := Vector2i(4, 3)
## The route: the red tank on the top road, and a stop six road tiles away round
## a corner. A turn is the whole reason the arrow replaced a polyline, so the
## frame has to contain one.
const MOVER_CELL := Vector2i(5, 2)
const MOVER_STOP := Vector2i(8, 5)


func run() -> String:
	# The same capture the `capture` demo runs, on the same city: it leaves the
	# board with a property mid-flip, which is the only state a chip exists in.
	_battle.confirm_at(CAPTURER_CELL)  # select the red infantry
	_battle.confirm_at(CAPTURE_CELL)  # move onto the neutral city
	await _until_state(Battle.State.MENU)
	_battle.action_menu.choose(&"capture")
	await _until_state(Battle.State.IDLE)
	if not _battle.game.capture_progress.has(CAPTURE_CELL):
		return "field_overlays: the capture left no progress, so there is no chip to draw"
	# Raised through the key rather than by calling `toggle_threat` — this is the
	# one scenario that can prove the new binding reaches the flow at all, and a
	# lens nothing on a keyboard opens is a lens nobody has.
	await _push_key(KEY_T)
	# Checked, not trusted: an overlay that paints nothing photographs as a
	# perfectly good board, so every claim this frame makes is asserted first.
	if _battle.overlays.threat_layer.get_used_cells().is_empty():
		return "field_overlays: T did not raise the threat lens, or it is shading nothing"
	# A second unit picked up and the cursor walked off it, so the arrow has a
	# route to draw rather than the single cell a fresh selection starts on.
	_battle.confirm_at(MOVER_CELL)
	await _until_state(Battle.State.UNIT_SELECTED)
	_battle.set_cursor_cell(MOVER_STOP)
	if _battle.planned_path.size() < 2:
		return (
			"field_overlays: %s is not a reachable stop from %s, so no route is drawn"
			% [MOVER_STOP, MOVER_CELL]
		)
	return ""


## Pushes one press of `key` straight at the viewport, the way a keyboard would:
## it reaches Battle's `_unhandled_input` past every guard in front of it, and it
## is resolved to an action by the InputMap rather than named as one — so what
## this proves is the whole chain from the keycode, project.godot's binding
## included.
##
## Its own mechanism rather than the inherited `_press_key`, which goes through
## Input.parse_input_event and sends the release as well: the lens `T` raises is
## held down here for the frame the scenario photographs, and the two press paths
## are left apart rather than unified behind one name that would hide it.
func _push_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	_battle.get_tree().root.push_input(event)
	await _battle.get_tree().process_frame
