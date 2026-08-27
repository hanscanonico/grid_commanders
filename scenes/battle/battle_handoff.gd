class_name BattleHandoff
extends RefCounted
## The hot-seat blackout and the viewer it decides: who is being handed the
## device, and whose eyes the board is drawn through (four-players plan D7).
##
## Split out of Battle the way BattleExit, BattleAuto and BattlePowerFlow were:
## one idea, holding the scene rather than state of its own. Battle keeps
## State.HANDOFF, the confirm arm that reaches `leave`, and `_begin_turn` — what
## the incoming team is allowed to see once the device has actually changed
## hands is the turn's, not the blackout's.
##
## Fogged hot-seat only: two humans sharing one screen must not see each other's
## vision, so the incoming player confirms before anything is painted. AI turns
## and fog-off matches never gate.

var _battle: Battle
var _screen: Panel
var _label: Label
var _button: Button


func _init(battle: Battle) -> void:
	_battle = battle


## The modal's five nodes, handed over rather than looked up here — the shape
## HandoffScreen.dress already takes, and the reason this class needs no scene
## paths of its own. The button's press is wired to Battle's public delegate,
## which is what the scenario driver stands in for a player through.
func setup(screen: Panel, backdrop: ColorRect, label: Label, hint: Label, button: Button) -> void:
	_screen = screen
	_label = label
	_button = button
	button.pressed.connect(_battle.leave_handoff)
	HandoffScreen.dress(backdrop, label, hint, button)


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
func needed() -> bool:
	# Nobody is being handed the device during a replay, and the board is drawn
	# omniscient anyway — a blackout would blank a match that has no secrets left.
	if _battle.replay_path != "":
		return false
	var game := _battle.game
	if not game.fog_enabled or game.winner != 0:
		return false
	if game.current_team in _battle.ai_teams:
		return false
	var humans := 0
	for team in game.teams:
		if team not in _battle.ai_teams:
			humans += 1
	if humans <= 1:
		return false
	return _battle.last_human_team != game.current_team


## Puts the panel up over a blacked-out board. The order is load-bearing: the
## blackout is keyed on `state == HANDOFF` while refresh_fog runs, so the state
## is set before the fog pass and the panel goes up after it.
func enter() -> void:
	_battle.state = Battle.State.HANDOFF
	_battle.animator.hide_banner()
	_battle.refresh_fog()  # blanks the outgoing team's vision before the panel goes up
	_label.text = (
		"%s — press confirm when ready"
		% _battle.view.identity.display_name(_battle.game.current_team)
	)
	_screen.show()
	_button.grab_focus()


## Takes the panel down, and answers whether the device actually changed hands —
## Battle opens the incoming team's turn on a true, and a press that reached here
## from anywhere but a blackout gets nothing.
func leave() -> bool:
	if _battle.state != Battle.State.HANDOFF:
		return false
	_screen.hide()
	# Not a blackout any more: the turn about to open paints the incoming team's
	# own vision.
	_battle.state = Battle.State.IDLE
	return true


## The perspective fog is drawn from: the human whose turn it is, or — while the
## computer plays — the human who played last (four-players plan D7). Information
## they already had, which is the whole test: rendering through *any other*
## human's fog while an AI turn runs would show one player what another had
## scouted. With one human at the table this is their fog all match, exactly as
## before. The AI sees everything bar one thing: a unit a doctrine hides is hidden
## from it too — see Vision.is_hidden_from.
func viewing_team() -> int:
	var game := _battle.game
	var ai_teams := _battle.ai_teams
	if game.current_team not in ai_teams:
		return game.current_team
	var last_human := _battle.last_human_team
	if last_human != 0 and last_human not in ai_teams:
		return last_human
	for team in game.teams:
		if team not in ai_teams:
			return team
	return game.current_team
