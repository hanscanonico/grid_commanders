class_name BattlePowerFlow
extends RefCounted
## Aiming and firing a Command Power: the F key, the HUD's Fire button and the map
## menu's Power row all arrive here, aimed and unaimed powers alike.
##
## BattlePower's flow half — that class is the one authority on why a press cannot
## fire, this is what a press that can do. Split out of Battle the same way
## BattleExit, BattleAuto and BattleCampaign were: one idea, holding the scene
## rather than state of its own, with Battle keeping State.POWER_TARGETING and the
## three input arms that reach the aim.

var _battle: Battle


func _init(battle: Battle) -> void:
	_battle = battle


## Fires the current team's Command Power, or says why it cannot: which refusal a
## press has earned is BattlePower's, settled up front for aimed and unaimed powers
## alike so nobody is sent off to aim a meter they have not filled. Only a board
## the player is playing gets the chip; the rest of them get nothing.
func fire() -> void:
	var state := _battle.state
	if state not in [Battle.State.IDLE, Battle.State.MENU]:
		if (
			state
			in [
				Battle.State.UNIT_SELECTED,
				Battle.State.PREVIEW,
				Battle.State.TARGETING,
				Battle.State.DROP_TARGETING
			]
		):
			_refuse(BattlePower.MID_ACTION)
		return
	var refusal := BattlePower.refusal_for(_battle.game, _battle.ai_teams)
	if refusal != "":
		_refuse(refusal)
		return
	# Close the menu the HUD button may sit over before the card or the aim takes it.
	_battle.action_menu.close()
	if _battle.game.commander_of(_battle.game.current_team).aims_power():
		_enter_targeting()
		return
	await _fire(PowerCommand.new())


## Fires the aim at the named square (plan D2), the arm confirm_at hands over in
## POWER_TARGETING.
func fire_at(cell: Vector2i) -> void:
	var command := PowerCommand.new()
	command.target = cell
	_battle.overlays.paint_attack([])
	await _fire(command)


## Repaints the square under the aim. Asked of the doctrine every time (plan D3):
## the overlay shows exactly what the strike will take, because it is the same
## function that takes it. Unfogged on purpose — every cell of the board is a legal
## aim, and what fog costs the player is knowing what was standing there.
func repaint(cell: Vector2i) -> void:
	var team := _battle.game.current_team
	var blast := _battle.game.commander_of(team).power_blast_cells(_battle.game, team, cell)
	_battle.overlays.paint_attack(blast)


## Backing out of the aim. Nothing to back out *to*: aiming already abandoned
## whatever the HUD button was pressed over, and the meter has not been spent.
func cancel_aim() -> void:
	_battle.overlays.paint_attack([])
	_battle.state = _battle.rest_state()


## Applies a Command Power and settles the board around it. A power can change
## movement, vision and HP at once, so the whole board is redrawn, and the
## selection — plus any menu the HUD button fired over, whose rows would otherwise
## act on it — belongs to rules that no longer apply.
##
## ANIMATING before the await, because the pipeline's presentation can hold this
## flow for seconds and MENU is a state the HUD's Fire button reaches a command
## from: left in MENU, a power fired mid-cut-in entered the pipeline re-entrantly
## (COM-50).
func _fire(command: PowerCommand) -> void:
	_battle.state = Battle.State.ANIMATING
	var receipt := await _battle.execute_command(command)
	if receipt.rejected():
		_battle.state = _battle.rest_state()
		return
	_battle.clear_selection(false)
	await _battle.conclude_command(receipt)


## Aims a Command Power at a square of ground (plan D2). The power abandons
## whatever move the HUD button was pressed over exactly as firing an unaimed one
## does — and it does so now rather than after the strike, so cancelling the aim
## lands on a board with nothing half-moved on it.
func _enter_targeting() -> void:
	if _battle.selected != null:
		# The previewed move is off; put the sprite back.
		_battle.view.refresh_sprite(_battle.selected)
	_battle.clear_selection()
	_battle.state = Battle.State.POWER_TARGETING
	repaint(_battle.cursor_cell)


func _refuse(reason: String) -> void:
	_battle.action_feedback.show_reason(
		reason, _battle.view.screen_pos_for_cell(_battle.cursor_cell)
	)
