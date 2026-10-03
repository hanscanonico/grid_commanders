extends GutTest
## Who commands each seat (`SeatGenerals`), the seat strip's general column held
## apart from its widgets: what survives a smaller board, and what a match takes.


func _dealt(picks: Dictionary, count: int) -> SeatGenerals:
	var generals := SeatGenerals.new()
	generals.assign(picks, count)
	return generals


## A board dealing fewer seats takes the generals of the seats it no longer deals
## with them, and keeps the rest where they sat.
func test_a_shrinking_roster_drops_the_generals_of_the_seats_it_lost() -> void:
	var generals := _dealt({1: &"alina_ward", 3: &"gideon_holt", 4: &"halden_marr"}, 4)
	generals.keep(2)
	assert_eq(generals.of(1), &"alina_ward", "seat 1 keeps its general")
	assert_eq(generals.of(3), CommanderType.NEUTRAL_ID, "seat 3 is gone, and its pick")
	assert_eq(generals.besides(2), {1: &"alina_ward"})


## A closed seat keeps its pick on its row but brings no army, so it commands
## nobody in the match — the match asks over the seats that play.
func test_an_empty_seat_brings_no_general_to_the_match() -> void:
	var generals := _dealt({1: &"alina_ward", 2: &"gideon_holt", 3: &"halden_marr"}, 3)
	var playing: Array[int] = [1, 3]
	assert_eq(generals.over(playing), {1: &"alina_ward", 3: &"halden_marr"})
	assert_eq(generals.of(2), &"gideon_holt", "the closed seat's row still shows it")
	assert_true(generals.besides(1).has(2), "and it still counts as taken")


func test_a_pick_for_a_seat_the_board_does_not_deal_is_nobodys() -> void:
	var generals := _dealt({0: &"alina_ward", 3: &"gideon_holt"}, 2)
	var both: Array[int] = [0, 1, 2, 3]
	assert_eq(generals.over(both), {})
