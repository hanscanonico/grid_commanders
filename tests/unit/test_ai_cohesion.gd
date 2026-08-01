extends GutTest
## AJ3 · the army travels together.
##
## `_advance_goal` gave every unit its own goal and never once read where the
## other friendlies were, so a tank, an artillery and a mech handed the same
## objective travelled at their own speeds and the fast one arrived alone. The
## cohesion term is one penalty on the advance path (D5) — no groups, no
## leaders, no waiting state.
##
## Profiles are built here rather than loaded, so the shipped tiers staying at 0
## (D2 — BL2 sets the live value) is a balance fact and never a test failure.

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

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _profile(cohesion_tiles: float) -> AIProfile:
	var profile := AIProfile.new()  # every other capability off; the Normal baseline
	profile.cohesion_tiles = cohesion_tiles
	return profile


## Plays `days` whole turns for team 1, skipping the opponent, and returns the
## x of each surviving friendly keyed by unit symbol.
func _march(map_text: String, cohesion_tiles: float, days: int) -> Dictionary:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	var ai := AIController.new(unit_db, _profile(cohesion_tiles))
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
	var blind := _march(COLUMN, 0.0, 1)
	assert_eq(blind["t"], 7, "blind, the tank spends all six of its move points")
	assert_eq(blind["m"], 1, "and the mech is left five tiles behind on the first day alone")

	var together := _march(COLUMN, 1.0, 1)
	assert_lte(
		absi(int(together["t"]) - int(together["m"])),
		2,
		"with cohesion on, the tank stays inside a radius of its company"
	)


## The R1 worry answered with the board rather than with prose: a term that pulls
## units toward each other could stall the army in place. It does not, because
## the goal term still pulls forward — the equilibrium is a column advancing at
## the speed of its slowest member, which is the whole point.
func test_the_column_still_advances() -> void:
	var after_six := _march(COLUMN, 1.0, 6)
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
	var blind := _march(MIXED_DOMAINS, 0.0, 1)
	var together := _march(MIXED_DOMAINS, 2.0, 1)
	assert_eq(
		together["c"],
		blind["c"],
		"the cruiser marches with nobody, so cohesion must not move it one tile"
	)
	assert_true(
		absi(int(together["t"]) - int(together["m"])) <= 2,
		"while the land column it shares a board with still closes up"
	)
