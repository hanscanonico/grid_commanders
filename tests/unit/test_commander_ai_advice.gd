extends GutTest
## The advisory seam between a commander's doctrine and the AI planner: the
## stand_value / build_bias / retreat_hp_delta hooks on CommanderType, scaled by
## AIProfile.doctrine_weight.
##
## Checked with test-local advisers rather than shipped generals, so the seam is
## pinned independently of any doctrine's numbers: the neutral commander must
## advise nothing, a zero weight must restore the doctrine-blind planner, and
## each hook must be able to move the decision it is wired to.


## Prefers standing in woods, strongly enough to give up five tiles for it.
class WoodsAdviser:
	extends CommanderType

	func stand_value(state: GameState, _unit: Unit, cell: Vector2i) -> int:
		var terrain := state.map.terrain_at(cell)
		return 5 if terrain != null and terrain.id == &"woods" else 0


## Pulls artillery to the top of the build list and nudges the md tank down.
class ArtilleryAdviser:
	extends CommanderType

	func build_bias(_state: GameState, _team: int, unit_type: UnitType) -> int:
		if unit_type.id == &"artillery":
			return -9
		if unit_type.id == &"md_tank":
			return 1
		return 0


## Tries to talk the planner into transports and out of its air answer —
## advice the ranking must refuse to follow.
class SaboteurAdviser:
	extends CommanderType

	func build_bias(_state: GameState, _team: int, unit_type: UnitType) -> int:
		if unit_type.id == &"apc":
			return -20
		if unit_type.id == &"anti_air":
			return 50
		return 0


## Rotates wounded units home a pip and a half earlier than the profile does.
class EarlyRepairAdviser:
	extends CommanderType

	func retreat_hp_delta(_state: GameState, _unit: Unit) -> int:
		return 15


var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _state(map_text: String) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	return state


func _blind_profile() -> AIProfile:
	var profile := AIProfile.new()
	profile.doctrine_weight = 0.0
	return profile


# --- the neutral commander ---------------------------------------------------


func test_the_neutral_commander_advises_nothing() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	var co := state.commander_of(1)
	var tank := state.units[0]
	assert_eq(co.stand_value(state, tank, Vector2i(1, 0)), 0)
	assert_eq(co.build_bias(state, 1, tank.type), 0)
	assert_eq(co.retreat_hp_delta(state, tank), 0)


# --- stand_value -------------------------------------------------------------

## A tank with no shot this turn and a distant enemy to march on. The
## doctrine-blind planner closes the distance; the adviser gives up four tiles
## of that march to hold the woods; turning the dial to zero blinds it again.
const QUIET_WOODS_BOARD := """
[terrain]
.F..................
[units]
1 t 0 0
2 i 19 0
"""


func _advance_destination(state: GameState, profile: AIProfile) -> Vector2i:
	var command := AIController.new(unit_db, profile).plan_next_command(state)
	assert_true(command is MoveCommand, "expected an advance, got %s" % command)
	var path: Array[Vector2i] = (command as MoveCommand).path
	return path[path.size() - 1]


func test_stand_advice_moves_a_quiet_advance() -> void:
	var advised := _state(QUIET_WOODS_BOARD)
	advised.set_commander(1, WoodsAdviser.new())
	assert_eq(
		_advance_destination(advised, AIProfile.new()),
		Vector2i(1, 0),
		"five tiles of woods preference should beat four tiles of progress"
	)


func test_a_zero_doctrine_weight_ignores_stand_advice() -> void:
	var advised := _state(QUIET_WOODS_BOARD)
	advised.set_commander(1, WoodsAdviser.new())
	var neutral := _state(QUIET_WOODS_BOARD)
	assert_eq(
		_advance_destination(advised, _blind_profile()),
		_advance_destination(neutral, AIProfile.new()),
		"weight zero must plan exactly as the neutral commander does"
	)


# --- build_bias --------------------------------------------------------------

## A funded base with the capture roster already filled, so production reaches
## the priority tier where doctrine bias applies.
const FUNDED_BASE_BOARD := """
[terrain]
B....
.....
[owners]
1 0 0
[units]
1 i 1 0
1 i 2 0
1 i 3 0
2 i 4 1
"""


func _planned_build(state: GameState, profile: AIProfile) -> StringName:
	for unit in state.units:
		unit.acted = true
	state.funds[1] = 99999
	var command := AIController.new(unit_db, profile).plan_next_command(state)
	assert_true(command is BuildCommand, "expected a build, got %s" % command)
	return (command as BuildCommand).unit_type.id


func test_build_bias_reranks_the_priority_tier() -> void:
	var neutral := _state(FUNDED_BASE_BOARD)
	assert_eq(_planned_build(neutral, AIProfile.new()), &"md_tank")

	var advised := _state(FUNDED_BASE_BOARD)
	advised.set_commander(1, ArtilleryAdviser.new())
	assert_eq(_planned_build(advised, AIProfile.new()), &"artillery")

	var blinded := _state(FUNDED_BASE_BOARD)
	blinded.set_commander(1, ArtilleryAdviser.new())
	assert_eq(_planned_build(blinded, _blind_profile()), &"md_tank")


## The urgent tiers stay urgent: with an enemy bomber overhead the planner
## builds its air answer whatever the doctrine thinks of it, and no bias pulls
## a transport into production.
func test_urgent_tiers_and_transports_ignore_the_bias() -> void:
	var bombed := _state("[terrain]\nB....\n.....\n[owners]\n1 0 0\n[units]\n1 i 1 0\n2 b 4 1")
	bombed.set_commander(1, SaboteurAdviser.new())
	assert_eq(
		_planned_build(bombed, AIProfile.new()),
		&"anti_air",
		"the air-answer tier outranks any doctrine bias"
	)

	var quiet := _state(FUNDED_BASE_BOARD)
	quiet.set_commander(1, SaboteurAdviser.new())
	assert_eq(
		_planned_build(quiet, AIProfile.new()),
		&"md_tank",
		"an unarmed transport has no rank for a bias to move"
	)


# --- retreat_hp_delta --------------------------------------------------------

## A tank at 55 HP sits between the profile's line (45) and the advised one
## (60): the neutral planner advances on the distant enemy, the advised one
## turns for the repair city behind it.
const WOUNDED_TANK_BOARD := """
[terrain]
C.............
[owners]
1 0 0
[units]
1 t 4 0
2 i 13 0
"""


func test_retreat_advice_moves_the_repair_line() -> void:
	var neutral := _state(WOUNDED_TANK_BOARD)
	neutral.units[0].hp = 55
	assert_gt(
		_advance_destination(neutral, AIProfile.new()).x,
		4,
		"at 55 HP the neutral tank still advances"
	)

	var advised := _state(WOUNDED_TANK_BOARD)
	advised.units[0].hp = 55
	advised.set_commander(1, EarlyRepairAdviser.new())
	assert_lt(
		_advance_destination(advised, AIProfile.new()).x,
		4,
		"the advised tank turns for the repair city"
	)
