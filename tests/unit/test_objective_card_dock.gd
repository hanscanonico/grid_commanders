extends GutTest
## Which corner the mission objectives card parks in. Pure and static, like
## PathArrow.segments and SeatStrip.normalised_sides, so the dodge is checked
## without standing up a battle.
##
## It is geometry and nothing else — no mission, no session — so what the card
## says can never move where it sits.

const CELL := 16
const VIEWPORT := Vector2(640, 360)
const CARD := Vector2(168, 60)
const LEFT := 0
const RIGHT := 1
const BOTTOM_LEFT := 2

## The board laid out so cell (0, 0) is the left card's own top-left corner: every
## cell of the card's footprint is then a small non-negative cell.
var _origin := Vector2(4, UiTheme.HUD_TOP_H + 4)


func _dock(cell: Vector2i, current: int, goals: Array[Vector2i] = []) -> int:
	return MissionObjectivesPanel.dock_for(cell, goals, CELL, _origin, VIEWPORT, CARD, current)


## Well clear of both corners: eight cells right of the left card's edge and below
## it, and nowhere near the right card.
func _clear_cell() -> Vector2i:
	return Vector2i(15, 8)


## Inside the right card's footprint: its left edge is a viewport width less the
## card and the margin.
func _right_cell() -> Vector2i:
	return Vector2i(int((VIEWPORT.x - CARD.x) / CELL), 1)


func test_card_dodges_when_the_cursor_walks_under_it() -> void:
	assert_eq(_dock(Vector2i(1, 1), LEFT), RIGHT)


func test_card_stays_home_while_the_cursor_is_elsewhere() -> void:
	assert_eq(_dock(_clear_cell(), LEFT), LEFT)


func test_dodged_card_holds_while_the_cursor_works_that_corner() -> void:
	assert_eq(_dock(Vector2i(1, 1), RIGHT), RIGHT)


func test_dodged_card_comes_home_once_the_cursor_leaves() -> void:
	assert_eq(_dock(_clear_cell(), RIGHT), LEFT)


## Followed into the right corner it goes home rather than sitting under the
## cursor there — the dodge read the other way round.
func test_dodged_card_goes_home_rather_than_cover_the_cursor() -> void:
	assert_eq(_dock(_right_cell(), RIGHT), LEFT)


## And a cursor in the right corner is no reason to leave the left one.
func test_card_at_home_ignores_the_far_corner() -> void:
	assert_eq(_dock(_right_cell(), LEFT), LEFT)


## On a window too narrow to hold both corners apart the two footprints overlap,
## and a cursor in the overlap is under the card wherever it sits. There the dock
## it is already in wins, so the card cannot be handed back and forth between two
## corners that are both covered.
func test_overlapping_corners_hold_whichever_dock_the_card_is_in() -> void:
	var narrow := Vector2(200, 150)
	var both := Vector2i(2, 1)
	var none: Array[Vector2i] = []
	assert_eq(MissionObjectivesPanel.dock_for(both, none, CELL, _origin, narrow, CARD, LEFT), LEFT)
	assert_eq(
		MissionObjectivesPanel.dock_for(both, none, CELL, _origin, narrow, CARD, RIGHT), RIGHT
	)


## The ground the mission still wants is no place for the card either: it leaves
## a corner sitting on a goal square for one that covers none (playtest CA-01, the
## west gate under the card on The Lantern Hall).
func test_card_steps_off_the_ground_the_mission_wants() -> void:
	var gate: Array[Vector2i] = [Vector2i(1, 2)]
	assert_eq(_dock(_clear_cell(), LEFT, gate), RIGHT)


## Goals under both top corners send it under them, to the bottom of the band.
func test_card_drops_to_the_bottom_when_both_top_corners_hold_goals() -> void:
	var goals: Array[Vector2i] = [Vector2i(1, 2), _right_cell()]
	assert_eq(_dock(_clear_cell(), LEFT, goals), BOTTOM_LEFT)


## Where every corner covers something, the cursor is what it must not cover.
func test_the_cursor_outweighs_any_goal() -> void:
	var goals: Array[Vector2i] = [Vector2i(1, 2), _right_cell()]
	var bottom := Vector2i(1, int((VIEWPORT.y - UiTheme.HUD_BOTTOM_H - _origin.y) / CELL) - 1)
	var right_bottom := Vector2i(_right_cell().x, bottom.y)
	goals.append(right_bottom)
	assert_ne(_dock(bottom, LEFT, goals), BOTTOM_LEFT)


## Goals half-way down both edges of the band: a card tall enough that its top and
## bottom corners overlap across the middle covers one of them wherever it sits.
func _mid_goals() -> Array[Vector2i]:
	return [Vector2i(1, 8), Vector2i(_right_cell().x, 8)]


func _compact(card: Vector2, goals: Array[Vector2i]) -> bool:
	return MissionObjectivesPanel.compact_for(_clear_cell(), goals, CELL, _origin, VIEWPORT, card)


## Every corner of a tall card covers a goal, so it falls back to the compact form
## rather than parking on the cheapest one (playtest CA-01, the review of the west
## gate on The Lantern Hall and Morn's HQ on Five Flags).
func test_card_falls_back_to_compact_when_every_corner_covers_a_goal() -> void:
	assert_true(_compact(Vector2(168, 200), _mid_goals()))


## The same goals leave a short card's top corners clear, so it keeps its rows.
func test_card_keeps_its_rows_while_a_corner_is_clear() -> void:
	assert_false(_compact(Vector2(168, 60), _mid_goals()))


## The cursor counts as much as a goal: a card it and the goals shut out of every
## corner is printed compact too.
func test_the_cursor_can_shut_the_last_clear_corner() -> void:
	var goals: Array[Vector2i] = [Vector2i(1, 2), _right_cell()]
	var bottom := Vector2i(1, int((VIEWPORT.y - UiTheme.HUD_BOTTOM_H - _origin.y) / CELL) - 1)
	goals.append(Vector2i(_right_cell().x, bottom.y))
	assert_false(_compact(CARD, goals))
	assert_true(MissionObjectivesPanel.compact_for(bottom, goals, CELL, _origin, VIEWPORT, CARD))
