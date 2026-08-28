extends GutTest
## Nia Rowan: the terrain discount (and the fuel that must match it), and
## Ghost March's vision.

var terrain_db: TerrainDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()


func _state(map_text: String, with_nia: bool = true) -> GameState:
	return Fixture.state(map_text, {1: &"nia_rowan"} if with_nia else {})


# --- the terrain discount ----------------------------------------------------


## Mountains cost 2 for foot; Nia's infantry pay 1, so a 3-point move that
## stalls on the first peak for anyone else crosses two.
func test_infantry_climb_mountains_at_half_price() -> void:
	var state := _state("[terrain]\n.MM\n[units]\n1 i 0 0")
	var mountain := terrain_db.by_symbol("M")
	assert_eq(MovementResolver.step_cost(state, state.units[0], mountain), 1)
	assert_true(
		MovementResolver.reachable(state, state.units[0]).has(Vector2i(2, 0)),
		"two peaks on 3 movement points"
	)
	var neutral := _state("[terrain]\n.MM\n[units]\n1 i 0 0", false)
	assert_false(
		MovementResolver.reachable(neutral, neutral.units[0]).has(Vector2i(2, 0)),
		"without her, two peaks cost 4"
	)


## Pinned because it is a finding, not a bug: this project's terrain data
## already lets foot units into Woods for 1, so the Woods half of her written
## doctrine cannot bite here and only the Mountains half does. Worth revisiting
## in the balance pass — it needs a terrain-data decision, not a number on her.
##
## The floor at 1 belongs to MovementResolver, not to her, and holds for every
## doctrine: a discount may never make a step free.
func test_woods_are_already_cheap_for_foot_so_the_discount_floors_at_one() -> void:
	var state := _state("[terrain]\n.F\n[units]\n1 i 0 0")
	var woods := terrain_db.by_symbol("F")
	assert_eq(woods.move_cost(TerrainType.FOOT), 1, "the terrain data, not the doctrine")
	assert_eq(MovementResolver.step_cost(state, state.units[0], woods), 1, "never free")
	var plains := terrain_db.by_symbol(".")
	assert_eq(MovementResolver.step_cost(state, state.units[0], plains), 1, "untouched terrain")


func test_vehicles_pay_the_full_price() -> void:
	var state := _state("[terrain]\n.FFF\n[units]\n1 r 0 0")
	var woods := terrain_db.by_symbol("F")
	assert_eq(MovementResolver.step_cost(state, state.units[0], woods), 3, "tires: unchanged")


func test_impassable_terrain_stays_impassable() -> void:
	var state := _state("[terrain]\n.S\n[units]\n1 i 0 0")
	var sea := terrain_db.by_symbol("S")
	assert_eq(MovementResolver.step_cost(state, state.units[0], sea), TerrainType.IMPASSABLE)
	assert_false(MovementResolver.reachable(state, state.units[0]).has(Vector2i(1, 0)))


## The fuel spent has to match the path the player was shown, or the range
## overlay and the tank disagree about the same move.
func test_fuel_spent_matches_the_discounted_path() -> void:
	var state := _state("[terrain]\n.MM\n[units]\n1 i 0 0")
	var infantry := state.units[0]
	var before := infantry.fuel
	state.advance_unit(infantry, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	assert_eq(before - infantry.fuel, 2, "two peaks at the discounted cost of 1 each")
	var neutral := _state("[terrain]\n.MM\n[units]\n1 i 0 0", false)
	var plain := neutral.units[0]
	var plain_before := plain.fuel
	neutral.advance_unit(plain, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	assert_eq(plain_before - plain.fuel, 4, "and the undiscounted path still bills 2 each")


# --- Ghost March -------------------------------------------------------------


func test_the_power_moves_and_sights_foot_units_and_recon() -> void:
	var state := _state("[terrain]\n.....\n.....\n.....\n[units]\n1 i 0 0\n1 r 0 1\n1 t 0 2")
	var infantry := state.units[0]
	var recon := state.units[1]
	var tank := state.units[2]
	assert_eq(Fixture.fire_power(state, 1), "")
	assert_eq(MovementResolver.move_budget(state, infantry), infantry.type.move_points + 1)
	assert_eq(MovementResolver.move_budget(state, recon), recon.type.move_points + 1)
	assert_eq(MovementResolver.move_budget(state, tank), tank.type.move_points, "treads sit it out")


## Woods normally hide anything more than one tile from a viewer. Under Ghost
## March her scouts see straight through them.
func test_the_power_reveals_woods_at_range() -> void:
	var state := _state("[terrain]\n..F..\n.....\n[units]\n1 i 0 0")
	state.fog_enabled = true
	var woods := Vector2i(2, 0)
	assert_false(Vision.visible_cells(state, 1).has(woods), "two tiles away, so hidden")
	assert_eq(Fixture.fire_power(state, 1), "")
	assert_true(Vision.visible_cells(state, 1).has(woods), "Ghost March sees into it")


func test_the_power_does_not_reveal_woods_for_the_other_side() -> void:
	var state := _state("[terrain]\n..F..\n.....\n[units]\n1 i 0 0\n2 i 4 0")
	state.fog_enabled = true
	assert_eq(Fixture.fire_power(state, 1), "")
	assert_false(Vision.visible_cells(state, 2).has(Vector2i(2, 0)))


func test_the_power_expires_with_the_turn() -> void:
	var state := _state("[terrain]\n..F..\n.....\n[units]\n1 i 0 0")
	state.fog_enabled = true
	var infantry := state.units[0]
	assert_eq(Fixture.fire_power(state, 1), "")
	assert_true(Vision.visible_cells(state, 1).has(Vector2i(2, 0)))
	EndTurnCommand.new().apply(state)
	assert_false(Vision.visible_cells(state, 1).has(Vector2i(2, 0)))
	assert_eq(MovementResolver.move_budget(state, infantry), infantry.type.move_points)


## The passive is not part of the power and must survive it.
func test_the_terrain_discount_outlives_the_power() -> void:
	var state := _state("[terrain]\n.M\n[units]\n1 i 0 0")
	var mountain := terrain_db.by_symbol("M")
	assert_eq(Fixture.fire_power(state, 1), "")
	EndTurnCommand.new().apply(state)
	assert_eq(MovementResolver.step_cost(state, state.units[0], mountain), 1)


## Ghost March grants +1 move, and the AI's gate weighs the ground that movement
## would open rather than the ground she can reach without firing — a city four
## plains from an infantry that moves three is exactly the case it buys.
func test_the_gate_counts_the_move_the_power_would_grant() -> void:
	var state := _state("[terrain]\n....C\n[units]\n1 i 0 0")
	assert_false(MovementResolver.reachable(state, state.units[0]).has(Vector2i(4, 0)))
	assert_true(state.commander_of(1).wants_power(state, 1))


## Two thirds of Ghost March is sight, and sight is worth nothing with the lights
## on — so a fight in reach and no ground to take is not a reason to fire.
func test_ghost_march_refuses_a_pure_fight_with_the_lights_on() -> void:
	var map_text := "[terrain]\n.....\n[units]\n1 t 0 0\n2 t 2 0"
	var neutral := _state(map_text, false)
	assert_true(neutral.commander_of(1).wants_power(neutral, 1), "the offensive default fires")
	var state := _state(map_text)
	assert_false(state.commander_of(1).wants_power(state, 1), "Rowan holds")


func test_ghost_march_still_fires_to_scout_a_fogged_enemy() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 t 0 0\n2 t 2 0")
	state.fog_enabled = true
	assert_true(state.commander_of(1).wants_power(state, 1))
