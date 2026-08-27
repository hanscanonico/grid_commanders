class_name BattleAuto
extends RefCounted
## The pause menu's Auto row: hand the seat currently on turn to the computer at
## a chosen difficulty tier, or take it back. Split out of Battle for the same
## reason BattleExit and BattleAiRunner were — a distinct flow rather than more
## state on the scene — and it leans on both: BattleAiRunner's own pause seam is
## what a live hand-off resumes into, and it is BattleExit's structural sibling
## among the ways a player changes what a seat is doing without winning or
## losing the match.
##
## Reachable only for a seat the player themselves may hand over — see
## BattleMenus.map_actions' own reasoning for the row's eligibility — so every
## method here trusts that `game.current_team` is either the player's own live
## turn or a turn already on Auto that the player put there.

var _battle: Battle


func _init(battle: Battle) -> void:
	_battle = battle


## The Auto row itself, opened from the map menu. Its own submenu the same
## shape "quit" opens "abandon" into: BattleMenus builds the rows, and this
## leaves MENU up rather than the map menu's own rest_state().
func open_menu() -> void:
	_battle.state = Battle.State.MENU
	_battle.action_menu.open(
		BattleMenus.auto_actions(_battle.difficulty_db),
		_battle.view.board_camera.screen_pos_for_cell(_battle.cursor_cell)
	)


## The Auto submenu's row. `_enable`/`_disable` each set `state` explicitly in
## the one case that needs it — handing off a live turn, or resuming one
## already paused on Auto — so the fallback below only fires for the ordinary
## case, the submenu closing with nothing to change underneath.
func handle_action(action: StringName) -> void:
	if action == &"cancel":
		_battle.state = _battle.rest_state()
		return
	var team := _battle.game.current_team
	if action == &"off":
		_disable(team)
	else:
		_enable(team, action)
	if _battle.state == Battle.State.MENU:
		_battle.state = _battle.rest_state()


## Hands `team` to the computer at `tier_id`. Reachable in exactly two
## situations: this is the player's own live turn (not paused, `team` not yet
## in `ai_teams`) — handed off immediately below — or a turn already on Auto,
## paused, and the player is only swapping tiers, which `planner_for` picks up
## on the runner's next planned command with no restart needed.
func _enable(team: int, tier_id: StringName) -> void:
	var tier := _battle.difficulty_db.by_id(tier_id)
	_battle.auto_tiers[team] = tier_id
	_battle.planners[team] = AIController.new(_battle.unit_db, tier.profile())
	if team not in _battle.ai_teams:
		_battle.ai_teams.append(team)
	_battle.refresh_fog()
	_battle.present_banner(
		"%s: Auto (%s)" % [_battle.view.identity.display_name(team), tier.display_name]
	)
	if _battle.rest_state() == Battle.State.IDLE:
		_battle.start_ai_turn()


## Takes `team` off Auto and back under the player's own hand. Only reachable
## while paused mid that team's own Auto turn — the Off row shows only then —
## so `resume_turn()` is always legal here. It wakes BattleAiRunner.run() at
## its pause_gate() await; the runner's own guard there notices `team` has
## left `ai_teams` and returns without planning another command, leaving
## `state` at IDLE (rest_state(), once resume_turn() has cleared the pause).
func _disable(team: int) -> void:
	_battle.ai_teams.erase(team)
	_battle.auto_tiers.erase(team)
	_battle.last_human_team = team
	_battle.refresh_fog()
	_battle.present_banner("%s: Auto off" % _battle.view.identity.display_name(team))
	_battle.resume_turn()
