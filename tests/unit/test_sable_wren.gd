extends GutTest
## Sable Wren, and with her the reworked Vanish (D4) — the one doctrine that
## makes seeing a cell and seeing the unit on it different questions.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	commander_db = Fixture.commander_db()


func _state(map_text: String, with_sable: bool = true) -> GameState:
	return Fixture.state(map_text, {1: &"sable_wren"} if with_sable else {})


# --- the doctrine ------------------------------------------------------------


## Woods are 2 stars; hers count as 3. Tank vs Infantry in woods:
## 75 * (1 - 0.3) = 52.5 -> 53, against 75 * 0.8 = 60.
func test_her_units_get_an_extra_star_in_woods() -> void:
	var state := _state("[terrain]\n.F\n[units]\n2 t 0 0\n1 i 1 0")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		53
	)


## Roads have no cover to begin with, so the penalty is pure downside:
## 75 * (200 - 90)/100 = 82.5 -> 83, against 75 flat.
func test_her_units_are_softer_on_roads() -> void:
	var state := _state("[terrain]\n==\n[units]\n2 t 0 0\n1 i 1 0")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		83
	)


## A reef conceals exactly like woods (both carry TerrainType.conceals), so her
## cover doctrine has to key on that flag rather than on the woods id — a naval
## board's only cover must not leave her army worth nothing standing in it.
## Land units cannot enter a reef, so this is a ship matchup: Battleship vs
## Cruiser from a reef (1 star, hers count as 2): 95 * (1 - 0.2) = 76,
## against 95 * 0.9 = 85.5 -> 86.
func test_her_units_get_an_extra_star_in_a_reef() -> void:
	var state := _state("[terrain]\nS*\n[units]\n2 B 0 0\n1 c 1 0")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		76
	)


func test_open_ground_is_untouched() -> void:
	var map_text := "[terrain]\n..\n[units]\n2 t 0 0\n1 i 1 0"
	var sable := _state(map_text)
	var neutral := _state(map_text, false)
	assert_eq(
		(
			CombatResolver
			. forecast(sable, sable.units[0], Vector2i(0, 0), sable.units[1])
			. attack_damage
		),
		(
			CombatResolver
			. forecast(neutral, neutral.units[0], Vector2i(0, 0), neutral.units[1])
			. attack_damage
		)
	)


# --- Vanish ------------------------------------------------------------------


## The rework, and the reason for it. Woods already hide a unit from anyone more
## than a tile away, for every commander — so the original wording was a no-op
## and only hiding from an *adjacent* enemy is a real effect.
func test_woods_already_hide_from_range_for_everyone() -> void:
	var state := _state("[terrain]\n..F\n...\n[units]\n1 i 2 0\n2 t 0 0", false)
	state.fog_enabled = true
	var visible := Vision.visible_cells(state, 2)
	assert_false(visible.has(Vector2i(2, 0)), "two tiles away and in woods: already hidden")


func test_vanish_hides_her_woods_units_from_an_adjacent_enemy() -> void:
	var state := _state("[terrain]\n.F\n..\n[units]\n1 i 1 0\n2 t 0 0")
	state.fog_enabled = true
	var hidden := state.units[0]
	var visible := Vision.visible_cells(state, 2)
	assert_true(visible.has(Vector2i(1, 0)), "adjacent, so the cell itself is seen")
	assert_true(Vision.can_see_unit(state, 2, hidden, visible), "and normally so is she")

	assert_eq(Fixture.fire_power(state, 1), "")
	visible = Vision.visible_cells(state, 2)
	assert_true(visible.has(Vector2i(1, 0)), "the cell is still visible")
	assert_false(Vision.can_see_unit(state, 2, hidden, visible), "but the unit on it is not")


func test_vanish_hides_her_reef_units_from_an_adjacent_enemy() -> void:
	var state := _state("[terrain]\nS*\n[units]\n1 c 1 0\n2 c 0 0")
	state.fog_enabled = true
	var hidden := state.units[0]
	var visible := Vision.visible_cells(state, 2)
	assert_true(visible.has(Vector2i(1, 0)), "adjacent, so the cell itself is seen")
	assert_true(Vision.can_see_unit(state, 2, hidden, visible), "and normally so is she")

	assert_eq(Fixture.fire_power(state, 1), "")
	visible = Vision.visible_cells(state, 2)
	assert_true(visible.has(Vector2i(1, 0)), "the cell is still visible")
	assert_false(Vision.can_see_unit(state, 2, hidden, visible), "but the unit on it is not")


func test_vanish_does_not_hide_her_units_in_the_open() -> void:
	var state := _state("[terrain]\n..\n..\n[units]\n1 i 1 0\n2 t 0 0")
	state.fog_enabled = true
	assert_eq(Fixture.fire_power(state, 1), "")
	var visible := Vision.visible_cells(state, 2)
	assert_true(Vision.can_see_unit(state, 2, state.units[0], visible), "no cover, no ambush")


func test_she_can_always_see_her_own_hidden_units() -> void:
	var state := _state("[terrain]\n.F\n..\n[units]\n1 i 1 0\n2 t 0 0")
	state.fog_enabled = true
	assert_eq(Fixture.fire_power(state, 1), "")
	var visible := Vision.visible_cells(state, 1)
	assert_true(Vision.can_see_unit(state, 1, state.units[0], visible))


## Fog off means nothing is hidden from anyone, power or not.
func test_vanish_does_nothing_without_fog() -> void:
	var state := _state("[terrain]\n.F\n..\n[units]\n1 i 1 0\n2 t 0 0")
	assert_eq(Fixture.fire_power(state, 1), "")
	var visible := Vision.visible_cells(state, 2)
	assert_true(Vision.can_see_unit(state, 2, state.units[0], visible))


## The ambush half: attacking out of cover while the power runs.
## Infantry vs Tank from woods, base 5: 5 * 1.4 * 0.9 = 6.3 -> 6, against 5.
func test_the_ambush_bonus_applies_from_woods() -> void:
	var state := _state("[terrain]\nF.\n[units]\n1 i 0 0\n2 t 1 0")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		5
	)
	assert_eq(Fixture.fire_power(state, 1), "")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		6
	)


## Cruiser vs Sub from a reef, base 90 against open water (no cover on the
## defender's side): 90 * 1.4 = 126, against 90 flat.
func test_the_ambush_bonus_applies_from_a_reef() -> void:
	var state := _state("[terrain]\n*S\n[units]\n1 c 0 0\n2 s 1 0")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		90
	)
	assert_eq(Fixture.fire_power(state, 1), "")
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		126
	)


func test_the_ambush_bonus_does_not_apply_from_open_ground() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0\n2 t 1 0")
	assert_eq(Fixture.fire_power(state, 1), "")
	var fight := Engagement.create(
		state.units[0], Vector2i(0, 0), 10, state.units[1], Vector2i(1, 0), 10
	)
	assert_eq(state.commander_of(1).attack_bonus(state, fight), 0)


## ROUND, like Hold the Line: an ambush that expired at the end of her own turn
## would never be there when the opponent walked into it.
func test_vanish_covers_the_opponents_turn() -> void:
	var state := _state("[terrain]\n.F\n..\n[units]\n1 i 1 0\n2 t 0 0")
	state.fog_enabled = true
	assert_eq(Fixture.fire_power(state, 1), "")
	EndTurnCommand.new().apply(state)
	var visible := Vision.visible_cells(state, 2)
	assert_false(
		Vision.can_see_unit(state, 2, state.units[0], visible), "still hidden on blue's turn"
	)
	EndTurnCommand.new().apply(state)
	visible = Vision.visible_cells(state, 2)
	assert_true(Vision.can_see_unit(state, 2, state.units[0], visible), "and back as hers opens")


## _has_unit_in_cover keys on the same conceals flag: a reef is the only cover
## on a naval board, and an army standing in it must still be able to fire
## Vanish rather than sit on a banked meter for want of woods.
func test_vanish_fires_when_an_enemy_can_reach_her_line_in_a_reef() -> void:
	var state := _state("[terrain]\n*SSSSSSS\n[units]\n1 c 0 0\n2 s 5 0")
	assert_true(state.commander_of(1).wants_power(state, 1))


# --- ground advice -----------------------------------------------------------

## Fourteen tiles of plains, one woods cell off the march, an enemy Tank too
## far to shoot this turn: the staging board for the Vanish stall.
const STAGING_BOARD := """
[terrain]
..............
.....F........
[units]
1 t 1 0
2 t 9 0
"""


## A banked Vanish with nobody in cover used to be a stall: wants_power
## (rightly) refused to fire, and the planner never put anyone in the woods it
## was waiting for. Stand advice closes the loop in one turn — the tank stages
## into cover, and the very next ask fires the power over it.
func test_a_full_meter_walks_her_into_cover_and_then_fires() -> void:
	var state := _state(STAGING_BOARD)
	state.add_charge(1, state.commander_of(1).power_cost)
	var ai := AIController.new(unit_db)
	var staged := ai.plan_next_command(state)
	assert_true(staged is MoveCommand, "expected the staging move, got %s" % staged)
	var path: Array[Vector2i] = (staged as MoveCommand).path
	assert_eq(path[path.size() - 1], Vector2i(5, 1), "the tank should stop in the woods")
	assert_eq(staged.validate(state), "")
	staged.apply(state)
	var next := ai.plan_next_command(state)
	assert_true(next is PowerCommand, "with her line in cover, Vanish fires")


## The everyday preference is one tile, so an empty meter stays on the march
## rather than trading three tiles of progress for cover.
func test_an_empty_meter_does_not_detour_for_cover() -> void:
	var state := _state(STAGING_BOARD)
	var command := AIController.new(unit_db).plan_next_command(state)
	assert_true(command is MoveCommand, "expected an advance, got %s" % command)
	var path: Array[Vector2i] = (command as MoveCommand).path
	assert_eq(path[path.size() - 1], Vector2i(7, 0), "the march continues on the open row")
