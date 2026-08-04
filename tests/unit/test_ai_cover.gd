extends GutTest
## AR6a · the planner can see cover.
##
## `_advance_value` was −distance − threat − cohesion + doctrine, and nothing in
## ai/ read a defence star at all, so the AI parked a unit on the road beside an
## empty wood and could not notice. The one path terrain reached the planner by
## was CombatResolver inside the threat map — which Normal does not build.
##
## Every test is one board reached twice, with the dial off and on. The off runs
## are the inertness pin the Judgement contract owes: they are what makes "0
## skips the code" a fact about the board rather than about a guard clause.

## A road east with one wood on it, the enemy seven tiles off. Our infantry can
## walk three: blind it spends every point and stands in the open at (3, 0), one
## tile past the only cover on the board.
const WOOD_ON_THE_ROAD := "[terrain]\n==F=====\n[units]\n1 i 0 0\n2 i 7 0"

## An enemy transport at (2, 0) with two cells to shoot it from: the road at
## (2, 1), two steps away, and the mountain at (1, 0), three. It carries no
## weapon, so nothing counters and no forecast prices where we fire from.
const TRANSPORT_BESIDE_A_MOUNTAIN := "[terrain]\n=M==\n====\n[units]\n1 i 0 1\n2 p 2 0"

## The same wood and road, with an enemy tank close enough east that its reach
## and its gun cover every cell our infantry could stop on. The threat map has an
## opinion about all of them, so the stars have nothing left to say.
const WOOD_UNDER_A_TANK := "[terrain]\n==F=====\n[units]\n1 i 0 0\n2 t 6 0"

## The same road and wood under a copter instead of an infantry: six tiles of
## reach with the only cover on the board one tile short of the last of them, and
## the enemy far beyond both.
const WOOD_UNDER_A_COPTER := "[terrain]\n=====F=====\n[units]\n1 h 0 0\n2 i 10 0"

const WOOD := Vector2i(2, 0)
const OPEN_ROAD := Vector2i(3, 0)
const MOUNTAIN := Vector2i(1, 0)
const AIR_WOOD := Vector2i(5, 0)
const AIR_OPEN_ROAD := Vector2i(6, 0)

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


## Normal's shipped numbers with one dial moved, built here rather than loaded:
## which value a tier ships is a balance fact and must never be a test failure.
func _profile(cover_tiles: float, threat_aversion := 0.0, advance_threat_tiles := 0.0) -> AIProfile:
	var profile := AIProfile.new()
	profile.cover_tiles = cover_tiles
	profile.threat_aversion = threat_aversion
	profile.advance_threat_tiles = advance_threat_tiles
	return profile


func _plan(map_text: String, profile: AIProfile) -> Command:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	return AIController.new(unit_db, profile).plan_next_command(state)


## Where the unit ends up, whether it walked there or shot from there.
func _destination(command: Command) -> Vector2i:
	var path: Array[Vector2i] = []
	if command is MoveCommand:
		path = (command as MoveCommand).path
	elif command is AttackCommand:
		path = (command as AttackCommand).path
	else:
		fail_test("expected a move or an attack, got %s" % command)
	assert_false(path.is_empty(), "a planned walk must carry a path")
	return path[path.size() - 1]


## The ticket's own case: the advance walks past cover it cannot see.
func test_a_unit_advancing_stops_in_the_wood_rather_than_past_it() -> void:
	assert_eq(
		_destination(_plan(WOOD_ON_THE_ROAD, _profile(0.0))),
		OPEN_ROAD,
		"blind, the infantry spends its whole move and ends in the open"
	)
	assert_eq(
		_destination(_plan(WOOD_ON_THE_ROAD, _profile(1.0))),
		WOOD,
		"with cover on it gives up the last tile of advance for two stars"
	)


## The dial is a price and not a preference. The wood here costs one tile of
## advance to stand in, so at 0.4 its two stars are worth 0.8 of that tile and
## the unit walks past it exactly as the blind planner does.
func test_cover_is_bought_by_the_tile_and_not_at_any_price() -> void:
	assert_eq(
		_destination(_plan(WOOD_ON_THE_ROAD, _profile(0.4))),
		OPEN_ROAD,
		"two stars at 0.4 tiles each do not pay for the tile of advance they cost"
	)


## The second site: where to fire from was priced by the walk and the threat map
## alone, so a unit shooting something that cannot shoot back took the nearest
## cell every time.
func test_a_unit_fires_from_cover_when_the_walk_is_worth_it() -> void:
	var blind := _plan(TRANSPORT_BESIDE_A_MOUNTAIN, _profile(0.0))
	assert_true(blind is AttackCommand, "expected an attack, got %s" % blind)
	assert_eq(
		_destination(blind), Vector2i(2, 1), "blind, the shot is taken from the cheapest cell"
	)

	var wary := _plan(TRANSPORT_BESIDE_A_MOUNTAIN, _profile(1.0))
	assert_true(wary is AttackCommand, "cover must re-site the shot, never call it off")
	assert_eq(
		_destination(wary),
		MOUNTAIN,
		"with cover on it spends the extra step to fire from four stars"
	)
	assert_eq(
		(wary as AttackCommand).target_cell,
		Vector2i(2, 0),
		"and it is still the same transport being shot at"
	)


## R3, on the reading that can decide a turn: the threat map's number is
## forecast_at's, and that forecast already resolved the damage through this same
## terrain. Where it has one the stars are silent, or one wood is priced twice.
##
## The counter this dial also stands down for cannot be pinned the same way, and
## for a reason worth knowing: where a counter lands it is priced in what the unit
## costs, which dwarfs anything cover_tiles can be set to, so the shot is already
## being taken from the cover and the gate has nothing left to move.
func test_cover_stands_down_where_the_threat_map_has_already_priced_the_ground() -> void:
	var without_cover := _destination(_plan(WOOD_UNDER_A_TANK, _profile(0.0, 0.1, 2.0)))
	assert_ne(
		without_cover, WOOD, "the board has to be one the threat dials do not pick the wood on"
	)
	assert_eq(
		_destination(_plan(WOOD_UNDER_A_TANK, _profile(1.0, 0.1, 2.0))),
		without_cover,
		"every cell in reach is under fire, so cover must not move the turn one tile"
	)


## A plane is over the tile rather than on it and keeps none of what is under it.
## That is CombatResolver's rule and this planner asks it for the answer rather
## than keeping a copy, so the two can never come to disagree about what a wood is
## worth — the price the AI pays for ground is the discount the damage formula
## gives for standing on it, or it is buying something that does not exist.
func test_ground_under_a_plane_is_never_bought() -> void:
	assert_eq(
		_destination(_plan(WOOD_UNDER_A_COPTER, _profile(0.0))),
		AIR_OPEN_ROAD,
		"blind, the copter spends its whole move and ends past the wood"
	)
	for weight in [1.0, 10.0]:
		assert_eq(
			_destination(_plan(WOOD_UNDER_A_COPTER, _profile(weight))),
			AIR_OPEN_ROAD,
			(
				"at %s tiles a star the wood at %s outbids the whole board for anything on the ground"
				% [weight, AIR_WOOD]
			)
		)
