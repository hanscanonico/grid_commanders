extends GutTest
## The pause menu's Auto row hands a seat to the computer, which only means
## something over a match still being played. A replay is already written, so
## the row goes with the two save rows `savable` also drops — and the way out
## that stays speaks of watching rather than of a match left unsaved.

var difficulty_db: DifficultyDB


func before_each() -> void:
	difficulty_db = DifficultyDB.load_default()


func _ids(rows: Array[Dictionary]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for row in rows:
		ids.append(row["id"])
	return ids


func _game() -> GameState:
	return Fixture.state(Fixture.NEUTRAL_BASE)


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
		(
			[
				&"commanders",
				&"speed",
				&"sound",
				&"end_turn_confirm",
				&"window",
				&"quit",
				&"cancel",
			]
			as Array[StringName]
		),
		"only the rows a recording cannot answer for go — the rest of the menu stays"
	)


## Playtest SK-28: "Main Menu Without Saving" and "Keep Playing" over a match
## nobody is playing, and nothing a save could keep.
func test_a_replay_leaves_in_watching_words() -> void:
	var rows := BattleMenus.map_actions(_game(), false, false, [], {}, difficulty_db)
	var quit: Dictionary = rows.filter(func(row: Dictionary) -> bool: return row["id"] == &"quit")[0]
	assert_eq(quit["label"], "Stop Watching")
	var confirm := BattleMenus.abandon_confirm_actions(true)
	assert_eq(_ids(confirm), [&"cancel", &"abandon"] as Array[StringName], "the safe row leads")
	assert_eq(confirm[0]["label"], "Keep Watching")
	assert_eq(confirm[1]["label"], "Stop Watching")
	assert_eq(BattleMenus.abandon_confirm_actions()[0]["label"], "Keep Playing")


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


## Playtest SK-18: the Auto row read "Auto: Off" and answered nothing to left and
## right, two rows under a Speed row that steps. It now steps through the seat's
## own `auto_step` and only hands over on Enter, and it says what it is for.
func test_auto_row_steps_under_left_and_right_and_says_what_it_does() -> void:
	var picked: Array[int] = []
	var step := func(by: int) -> String:
		picked.append(by)
		return "Auto: Easy"
	var rows := BattleMenus.map_actions(_game(), true, true, [], {}, difficulty_db, true, step)
	var auto: Dictionary = rows.filter(func(row: Dictionary) -> bool: return row["id"] == &"auto")[0]
	assert_eq(auto["label"], "Auto: Off")
	assert_true(auto["chooses"], "Enter takes the level shown rather than stepping it")
	assert_eq((auto["cycle"] as Callable).call(1), "Auto: Easy")
	assert_eq(picked, [1] as Array[int])
	assert_string_contains(auto["detail"], BattleMenus.AUTO_HEADING)


func test_auto_ladder_is_the_lists_own_order() -> void:
	var ladder := BattleMenus.auto_ladder(difficulty_db)
	var listed := _ids(BattleMenus.auto_actions(difficulty_db))
	listed.erase(&"cancel")
	assert_eq(ladder, listed, "the arrows walk the rungs the list offers, Off first")
	assert_eq(BattleMenus.auto_label(ladder[0], difficulty_db), "Auto: Off")


## Playtest SK-29: the leave confirmation named no consequence.
func test_leaving_unsaved_names_what_is_lost() -> void:
	assert_eq(BattleMenus.abandon_consequence(false, 3), "Progress since your Day 3 save is lost.")
	assert_string_contains(BattleMenus.abandon_consequence(false, 0), "never saved")
	assert_eq(BattleMenus.abandon_consequence(true, 3), "", "a replay loses nothing")
