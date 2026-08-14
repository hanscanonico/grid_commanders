class_name BattleExit
extends RefCounted
## Owns every way out of a running match that is not winning or losing it: writing
## the single save slot, going back to the main menu with or without doing so, the
## confirmation the unsaved route asks for, and the rematch and replay the victory
## lockup offers.
##
## BattleOutcome's sibling, and split out of Battle for the same reason: that class
## owns how a match *ends*, this owns how a player *leaves* one. Until COM-16 there
## was barely such a thing — the map menu offered no route back and the only exits
## were winning, losing or killing the application — so what is now one
## responsibility lived as the victory screen's two buttons and a Save row.
##
## Holds the scene like BattleAiRunner and BattleOutcome do: it changes scenes,
## sets Battle.state and opens Battle's own action menu, and decides nothing the
## rules own. Whether a save landed is SaveGame's answer, read rather than guessed;
## which scene the way out leads to is spelled once, here.

const MAIN_MENU_SCENE := "res://scenes/menu/main_menu.tscn"

var _battle: Battle


func _init(battle: Battle) -> void:
	_battle = battle


## Writes the single save slot and says on the banner what it just stored, or that
## it could not. Reports whether the write landed, which is the whole reason it
## reports at all: `save_and_leave` may only go once the match is on disk.
func save_match() -> bool:
	var game := _battle.game
	# A campaign mission saves into its campaign's profile, never the skirmish
	# slot: Continue means one unambiguous thing, and a mission in progress is the
	# campaign hub's to resume — with the session armed, so the mission can still
	# be decided and recorded.
	if CampaignSession.active():
		return _save_mission(game)
	if not SaveGame.save(
		game, _battle.ai_teams, SaveGame.SAVE_PATH, _battle.difficulty.id, _battle.auto_tiers
	):
		# SaveGame has already pushed the disk error; this is the player's half of
		# it, and it says where they still are as well as what failed.
		_battle.present_banner("Save failed — still in the match")
		return false
	# Named, because the slot is single: the banner has to say what it just
	# overwrote the last save with. Same words the menu's Continue caption will read
	# back, through the one formatter (SaveCodec.describe).
	_battle.present_banner("Saved %s" % SaveCodec.describe(game.day, game.map_path))
	return true


## The campaign half of `save_match`: the whole board rides inside the profile as
## `SaveCodec.encode`'s envelope, so the mission keeps the one encoder every save
## has. Named by the mission rather than the board, because that is what the hub
## offers to resume.
func _save_mission(game: GameState) -> bool:
	var envelope := SaveCodec.encode(
		game, _battle.ai_teams, _battle.difficulty.id, _battle.auto_tiers
	)
	if not CampaignSession.save_battle(envelope):
		_battle.present_banner("Save failed — still in the match")
		return false
	_battle.present_banner("Saved %s — Day %d" % [CampaignSession.mission.title, game.day])
	return true


## The "Save & Main Menu" row. The write has to land before the scene does: a
## failed save under a row that promised to keep the match would throw it away on
## the way out, and the banner that failure raises is only readable while the board
## is still up.
func save_and_leave() -> void:
	if save_match():
		to_main_menu()


## The second press "Main Menu Without Saving" asks for, opened on the cell the map
## menu it replaces was. Deliberately the same ActionMenu rather than a modal of
## its own: the confirmation is then reachable by every route that reached the row
## it came from — keyboard, mouse, and the Esc that backs out — and it clamps
## inside the board band like every other menu. What makes it a confirmation rather
## than another menu is its rows; see BattleMenus.abandon_confirm_actions for why
## the safe one leads.
func confirm_abandon() -> void:
	_battle.state = Battle.State.MENU
	_battle.action_menu.open(
		BattleMenus.abandon_confirm_actions(), _battle.view.screen_pos_for_cell(_battle.cursor_cell)
	)


## A row chosen on that confirmation. Anything that is not the abandon — the Keep
## Playing row, Esc, a click past the menu — lands back on the board with nothing
## changed, which is the whole point of asking twice.
func handle_confirm_action(action: StringName) -> void:
	_battle.state = _battle.rest_state()
	if action == &"abandon":
		to_main_menu()


func to_main_menu() -> void:
	_battle.get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## Replays the match actually running — including one resumed from a save, whose
## map, sides and commanders the menu never saw — rather than whatever the menu
## last chose. Derived from the live GameState rather than from what was staged
## for this scene, which is why a resumed match rematches its own board; see
## MatchRequest.from_match.
##
## A replay restarts the *recording* instead, which is the only thing it could
## honestly do: a playback seats no computer, so a request derived from its board
## would open the recorded match as a hot-seat game nobody was playing.
##
## A campaign mission retries the *mission* for the same kind of reason: a
## request derived from the finished board would be a skirmish the session still
## thinks is the mission — its objectives dead and its verdict already written,
## ready to be recorded a second time. Re-entering through `CampaignSession.begin`
## re-arms the runtime and clears the verdict, exactly as the hub's Deploy does.
func rematch() -> void:
	MatchConfig.stage(_rematch_request())
	_battle.get_tree().reload_current_scene()


## Watches the recording the match just wrote — `rematch()`'s sibling, and the
## victory lockup's third way out. A recording states its own board, seating,
## grouping and commanders in its opening envelope, so naming the file is the
## whole request; whether there is one to name is BattleOutcome's question, asked
## of the recorder before the button is offered at all.
func watch_replay() -> void:
	MatchConfig.stage(MatchRequest.from_replay(_battle.recorder.path()))
	_battle.get_tree().reload_current_scene()


func _rematch_request() -> MatchRequest:
	if _battle.replay_path != "":
		return MatchRequest.from_replay(_battle.replay_path)
	if CampaignSession.active():
		return CampaignSession.begin(
			CampaignSession.campaign, CampaignSession.mission, CampaignSession.progress
		)
	return MatchRequest.from_match(_battle.game, _battle.ai_teams, _battle.difficulty.id)
