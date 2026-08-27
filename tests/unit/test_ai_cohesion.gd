extends GutTest
## AJ3 · the army travels together.
##
## `AIAdvance.goal_for` gave every unit its own goal and never once read where the
## other friendlies were, so a tank, an artillery and a mech handed the same
## objective travelled at their own speeds and the fast one arrived alone. The
## cohesion term is one penalty on the advance path (D5) — no groups, no
## leaders, no waiting state.
##
## Profiles are built here rather than loaded, because what these pin is the
## behaviour of the capability at a chosen weight. What a shipped tier sets it
## to is a balance decision, and retuning one must never break this suite.

## A tank (6 move) and a mech (2 move) side by side, the enemy twenty-two tiles
## east. Blind, the tank is gone by the end of the first turn.
const COLUMN := (
	"[terrain]\n"
	+ "........................\n"
	+ "........................\n"
	+ "[units]\n1 t 1 0\n1 m 0 1\n2 i 23 0"
)

## The same column with a cruiser on open water alongside it. The cruiser marches
## with nobody: it is the only hull on the board.
const MIXED_DOMAINS := (
	"[terrain]\n"
	+ "........................\n"
	+ "SSSSSSSSSSSSSSSSSSSSSSSS\n"
	+ "[units]\n1 t 1 0\n1 m 0 0\n1 c 1 1\n2 i 23 0"
)

## A wounded tank six tiles ahead of its own slow company, its repair city seven
## tiles the other way. The errand pulls west and the column east, which is where
## a taxed errand loses: the tank trailed the column and never repaired.
const WOUNDED_BEHIND_THE_COLUMN := (
	"[terrain]\n"
	+ ".........C..............\n"
	+ "........................\n"
	+ "[owners]\n1 9 0\n"
	+ "[units]\n1 t 16 0\n1 m 17 1\n1 g 18 1\n2 i 23 1"
)

## The same column with our home HQ behind it and an enemy infantry standing on
## it. Every unit is called home, and the fast one must not be held back by the
## slow ones on the way.
const BESIEGED_HOME_HQ := (
	"[terrain]\n"
	+ "..Q.....................\n"
	+ "........................\n"
	+ "[owners]\n1 2 0\n"
	+ "[units]\n1 t 14 1\n1 m 15 1\n1 g 16 1\n2 i 2 0\n2 i 23 1"
)

## An infantry at the western end of a column that is advancing east, the only
## neutral city seven tiles further west. Neither of the units it marches with
## can capture, so nobody else is going, and the enemy is far enough east that
## the column is still walking when the city changes hands.
const CAPTURER_BEHIND_THE_COLUMN := (
	"[terrain]\n"
	+ ".........C..............................\n"
	+ "........................................\n"
	+ "[units]\n1 i 16 0\n1 t 17 1\n1 g 18 1\n2 i 39 1"
)

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()


func _profile(cohesion_tiles: float, defend_weight: float = 0.0) -> AIProfile:
	var profile := AIProfile.new()  # every other capability off; the Normal baseline
	profile.cohesion_tiles = cohesion_tiles
	profile.defend_weight = defend_weight
	return profile


## Plays `days` whole turns for team 1, skipping the opponent, and returns the
## x of each surviving friendly keyed by unit symbol. `wounds` is symbol -> hp,
## applied to our own units before the first turn.
func _march(map_text: String, profile: AIProfile, days: int, wounds: Dictionary = {}) -> Dictionary:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	state.rng.seed = 1701  # COM-206: commands are applied for real below

	for unit in state.units:
		if unit.team == 1 and wounds.has(unit.type.symbol):
			unit.hp = wounds[unit.type.symbol]
	var ai := AIController.new(unit_db, profile)
	for _day in range(days):
		for _step in range(12):
			var command := ai.plan_next_command(state)
			if command is EndTurnCommand:
				command.apply(state)
				break
			if command.validate(state) != "":
				break
			command.apply(state)
		if state.current_team != 1:
			EndTurnCommand.new().apply(state)
	var places: Dictionary = {}
	for unit in state.units:
		if unit.team == 1:
			places[unit.type.symbol] = unit.cell.x
	return places


## The defect, in one turn: the tank spends its whole move and abandons the mech.
func test_cohesion_holds_a_fast_unit_back_with_its_slower_company() -> void:
	var blind := _march(COLUMN, _profile(0.0), 1)
	assert_eq(blind["t"], 7, "blind, the tank spends all six of its move points")
	assert_eq(blind["m"], 1, "and the mech is left five tiles behind on the first day alone")

	var together := _march(COLUMN, _profile(1.0), 1)
	assert_lte(
		absi(int(together["t"]) - int(together["m"])),
		2,
		"with cohesion on, the tank stays inside a radius of its company"
	)


## The radius is what "company" means, and nothing else read it: every test
## around this one fixes cohesion_tiles and leaves the radius wherever the
## profile put it, so a tier that quietly moved it shipped green.
##
## Same board, same weight, two radii. The penalty is free inside the radius and
## linear outside it, so the *narrow* one is the tight leash — the tank finishes
## the day beside the mech — and the wider one buys the tank two tiles of slack
## it spends walking east.
func test_cohesion_radius_decides_who_counts_as_company() -> void:
	var narrow := _march(COLUMN, _profile_at(2.0, 1), 1)
	assert_eq(narrow["t"], 0, "inside a radius of 1 the tank has to finish beside the mech")

	var wide := _march(COLUMN, _profile_at(2.0, 3), 1)
	assert_eq(wide["t"], 2, "a radius of 3 is two tiles of slack, and the tank spends them")


## `_profile` with the cohesion radius named too, which only this test varies.
func _profile_at(cohesion_tiles: float, cohesion_radius: int) -> AIProfile:
	var profile := _profile(cohesion_tiles)
	profile.cohesion_radius = cohesion_radius
	return profile


## The R1 worry answered with the board rather than with prose: a term that pulls
## units toward each other could stall the army in place. It does not, because
## the goal term still pulls forward — the equilibrium is a column advancing at
## the speed of its slowest member, which is the whole point.
func test_the_column_still_advances() -> void:
	var after_six := _march(COLUMN, _profile(1.0), 6)
	assert_gte(
		int(after_six["m"]), 10, "six days at the mech's two tiles a day must cover real ground"
	)
	assert_lte(
		absi(int(after_six["t"]) - int(after_six["m"])),
		2,
		"and the tank must still be with it at the end, not parked at the start"
	)


## Cohesion is measured against units that can actually keep company. A lone hull
## must not be dragged toward a land column it can never join, so its turn is
## identical with the dial on and off.
func test_a_lone_hull_is_not_dragged_toward_the_land_column() -> void:
	var blind := _march(MIXED_DOMAINS, _profile(0.0), 1)
	var together := _march(MIXED_DOMAINS, _profile(2.0), 1)
	assert_eq(
		together["c"],
		blind["c"],
		"the cruiser marches with nobody, so cohesion must not move it one tile"
	)
	assert_true(
		absi(int(together["t"]) - int(together["m"])) <= 2,
		"while the land column it shares a board with still closes up"
	)


## Cohesion shapes the advance on the enemy and nothing else. An errand — refit,
## repair, a besieged home HQ, a property to take — is denominated in the same
## tiles the goal term is, and the column's pull is the stronger of the two, so
## taxing an errand cancels it: the unit sits at the column's edge and never
## arrives.
func test_a_wounded_unit_still_walks_home_to_repair() -> void:
	var wounds := {"t": 30}
	var blind := _march(WOUNDED_BEHIND_THE_COLUMN, _profile(0.0), 2, wounds)
	assert_lte(int(blind["t"]), 10, "blind, the wounded tank reaches its city")

	var together := _march(WOUNDED_BEHIND_THE_COLUMN, _profile(1.5), 2, wounds)
	assert_eq(together["t"], blind["t"], "and cohesion must not pull it back toward the column")


## The cross-milestone case: AJ1's besieged home HQ calls the army back, and the
## fast unit answering that call must not be held at the pace of the column.
func test_a_besieged_home_hq_still_turns_the_army_around() -> void:
	var blind := _march(BESIEGED_HOME_HQ, _profile(0.0, 1.0), 2)
	assert_lte(int(blind["t"]), 5, "blind, the tank runs the whole way home")

	var together := _march(BESIEGED_HOME_HQ, _profile(1.5, 1.0), 2)
	assert_eq(together["t"], blind["t"], "and cohesion must not slow the defence to a walk")


## Taking ground is how the game is won, and the ground is routinely nowhere near
## the column. A taxed capturer trails its company east instead and the army
## never earns a thing.
func test_a_capturer_still_walks_out_to_its_property() -> void:
	var blind := _march(CAPTURER_BEHIND_THE_COLUMN, _profile(0.0), 3)
	assert_lte(int(blind["i"]), 9, "blind, the infantry reaches the neutral city")

	var together := _march(CAPTURER_BEHIND_THE_COLUMN, _profile(1.5), 3)
	assert_eq(together["i"], blind["i"], "and cohesion must not hold it back with the column")
	assert_lte(
		absi(int(together["t"]) - int(together["g"])),
		2,
		"while the units actually advancing on the enemy still close up"
	)
