extends GutTest
## The pause menu's Auto row hands a seat to the computer, which only means
## something over a match still being played. A replay is already written, so
## the row goes with the two save rows `savable` also drops.

var difficulty_db: DifficultyDB


func before_each() -> void:
	difficulty_db = DifficultyDB.load_default()


func _ids(rows: Array[Dictionary]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for row in rows:
		ids.append(row["id"])
	return ids


func _game() -> GameState:
	return Fixture.state("[terrain]\nB.")


func test_live_turn_offers_auto() -> void:
	var rows := BattleMenus.map_actions(_game(), true, true, [], {}, difficulty_db)
	assert_true(_ids(rows).has(&"auto"), "a live turn may be handed to the computer")


func test_replay_drops_auto_with_the_save_rows() -> void:
	var rows := BattleMenus.map_actions(_game(), false, false, [], {}, difficulty_db)
	var ids := _ids(rows)
	assert_false(
		ids.has(&"auto"), "a recording seats no computer, so there is no seat to hand over"
	)
	assert_false(ids.has(&"save"), "a replay drops the save rows")
	assert_eq(
		ids,
		[&"commanders", &"speed", &"sound", &"quit", &"cancel"] as Array[StringName],
		"only the rows a recording cannot answer for go — the rest of the menu stays"
	)


func test_paused_computer_turn_keeps_auto_gated_on_the_seat() -> void:
	var game := _game()
	var ai_teams: Array[int] = [game.current_team]
	var rows := BattleMenus.map_actions(game, false, true, ai_teams, {}, difficulty_db)
	assert_false(
		_ids(rows).has(&"auto"), "a genuine CPU opponent's seat is not the player's to take"
	)


func test_seat_already_on_auto_keeps_the_row() -> void:
	var game := _game()
	var ai_teams: Array[int] = [game.current_team]
	var auto_tiers := {game.current_team: &"normal"}
	var rows := BattleMenus.map_actions(game, false, true, ai_teams, auto_tiers, difficulty_db)
	assert_true(_ids(rows).has(&"auto"), "a seat the player lent out may be taken back")
