extends GutTest
## AR1's merge bar, one rule at a time: each fixture below is a board where one
## invalidation rule is the only thing standing between the planner that keeps
## its plans and the planner that scores every unit afresh.
##
## The other instrument is its sibling `test_ai_plan_cache_diff.gd`, which plays
## whole seeded matches and is where a milestone that adds a dial adds its run.
## Both drive the same machinery from `tests/helpers/plan_cache_diff.gd`; what
## lives here is the claims and the boards that make them visible.

const PlanCacheDiff := preload("res://tests/helpers/plan_cache_diff.gd")

## A tank parked on the one neutral city with an infantry beside it, and an enemy
## too far off for either to reach. The tank advances first and steps off the
## city; nothing about the infantry's own square changed, and the property it
## could not stop on is suddenly free.
const OCCUPIED_CITY := """
[terrain]
.C.............
[units]
1 t 1 0
1 i 0 0
2 i 14 0
"""

## Our tank kills the westmost enemy while a copter of ours, far out of every
## envelope in the fight, is flying at that same enemy because it is the nearest
## one. With it gone the copter's goal is the other enemy, in the other
## direction.
const TWO_FRONTS := """
[terrain]
...............................
[units]
1 t 2 0
1 h 14 0
2 i 0 0
2 i 30 0
"""

## An infantry one point from taking the city in the west, and a wounded tank far
## east of it with nothing of ours to repair on. The moment the city is ours the
## tank has somewhere to go, and it is not the enemy it was walking at.
const CITY_AND_A_WOUNDED_TANK := """
[terrain]
C.........................
[units]
1 i 0 0
1 t 12 0
2 i 24 0
"""

## A sea wall with two gates, a city behind the north gate and an enemy HQ behind
## the south one. The infantry east of the wall claims the city — it is nearer —
## but takes the HQ, because an HQ is worth three cities to arrive on. The
## infantry west of the wall was walking to the HQ nobody else had claimed, and
## once it is taken its road is the other gate. Nothing it can see changed.
const TWO_GATES := """
[terrain]
....S......
......C....
....S......
....S......
....S......
....S......
......Q....
....S......
[units]
1 i 6 3
1 i 0 3
"""

## One of our submarines at the west end of a long channel and two hunters at the
## east end of it, fifteen tiles off — further than the boat's own envelope
## reaches, and well inside the reach it judges them by.
const DEEP_WATER := """
[terrain]
SSSSSSSSSSSSSSSS
[units]
1 s 0 0
2 s 15 0
2 c 14 0
"""

## Our tank, an ally sixteen tiles off and an enemy twenty-five tiles off — both
## outside the tank's own envelope, so only the allegiance question is being
## asked: does the ally's flag count as "an enemy moved"?
const ALLY_AND_ENEMY := """
[terrain]
................................
[units]
1 t 4 0
2 i 20 0
3 i 29 0
"""

## Three tanks in a row with nothing to fight: the first moves six tiles east,
## which is another tank's business and not the far one's.
const PROBES := """
[terrain]
..............................
[units]
1 t 4 0
1 t 12 0
1 t 28 0
2 i 29 0
"""

## PROBES with two of its tanks named, so a scripted mission beat can reach them:
## one a mission withdraws, one it hands to the other army.
const SCRIPTED := """
[terrain]
..............................
[units]
1 t 4 0 withdrawn
1 t 12 0 turncoat
1 t 28 0
2 i 29 0
"""

## An APC at the west end and a tank nine tiles east of it. Nine is one tile
## past everything the truck's own envelope buys (six of movement, no weapon and
## the flat tile beyond it) plus a neutral commander's supply radius, and exactly
## on the edge of Gideon Holt's two.
const SUPPLY_LINE := """
[terrain]
..........
[units]
1 p 0 0
1 t 9 0
"""

## A base at the west end, a tank twenty tiles east of it and a copter at the far
## end — both marching, and both far outside the envelope of anything happening
## at the base.
const COLUMN_AND_A_BASE := """
[terrain]
B...............................
[owners]
1 0 0
[units]
1 t 20 0
1 h 31 0
"""

## An infantry standing on a neutral city in the west and a tank thirty-one tiles
## east of it, further out than any envelope on the board reaches.
const CITY_AND_A_DISTANT_TANK := """
[terrain]
C...............................
[units]
1 i 0 0
1 t 31 0
"""

## An infantry at the west end, a tank in the middle and a second tank far east,
## all marching on an enemy further east still. The infantry is nine tiles from
## the tank — outside every envelope in play — and the three steps it takes are
## what move the tank's own best cell, because the column it keeps station with
## is the whole army wherever it stands.
const LONG_COLUMN := """
[terrain]
..............................................
[units]
1 i 0 0
1 t 12 0
1 t 34 0
2 i 45 0
"""

var diff: PlanCacheDiff
var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	diff = PlanCacheDiff.new()
	terrain_db = diff.terrain_db
	unit_db = diff.unit_db
	chart = diff.chart


# --- one fixture per invalidation rule -----------------------------------------


## The envelope. A friendly stepping off a property is not a fact about itself:
## it is a cell the unit beside it could not stop on and now can.
func test_a_friendly_stepping_aside_rescores_the_unit_beside_it() -> void:
	var played := _agreeing_commands(OCCUPIED_CITY, AIProfile.load_default(), 3, "freed city")
	assert_string_contains(played[0], "MoveCommand", "the tank advances off the city first")
	assert_string_contains(played[1], "CaptureCommand", "and the infantry takes the city it left")


## A unit leaving the board. The copter is nowhere near the exchange, and the
## enemy that died was the goal it was flying at.
func test_a_death_rescores_a_unit_that_never_saw_the_fight() -> void:
	var played := _agreeing_commands(
		TWO_FRONTS, AIProfile.load_default(), 3, "two fronts", _wound_the_westmost_enemy
	)
	assert_string_contains(played[0], "AttackCommand", "the tank kills the westmost enemy")
	assert_string_contains(played[1], "b_copter", "and the copter answers for the change")


## Ground changing hands. It re-prices every goal on the board: the tank is
## twelve tiles from the capture and it is what sends it home to repair.
func test_a_capture_rescores_a_wounded_unit_across_the_board() -> void:
	var played := _agreeing_commands(
		CITY_AND_A_WOUNDED_TANK, AIProfile.load_default(), 3, "city and tank", _wound_the_tank
	)
	assert_string_contains(played[0], "CaptureCommand", "the infantry finishes the city")
	assert_string_contains(played[1], "tank", "and the tank is the next to move")


## The claim, which is the one rule the envelope cannot state. The infantry east
## of the wall takes the HQ the infantry west of it had claimed, from nine tiles
## away and with nothing between them either can see.
func test_a_capturer_taking_a_claimed_property_rescores_the_capturer_that_claimed_it() -> void:
	var profile := AIProfile.new()
	profile.capture_claim_depth = 1
	var played := _agreeing_commands(TWO_GATES, profile, 3, "two gates")
	assert_string_contains(played[0], "CaptureCommand", "the east infantry takes the HQ")
	assert_string_contains(played[1], "MoveCommand", "and the west one is re-routed")


## The column. Three tiles walked by an infantry nine tiles away moves where the
## tank wants to stand, because the company a unit keeps is the whole army.
func test_a_friendly_marching_out_of_sight_moves_the_column() -> void:
	var profile := AIProfile.new()
	profile.cohesion_tiles = 2.0
	profile.cohesion_radius = 4
	var played := _agreeing_commands(LONG_COLUMN, profile, 3, "long column")
	assert_string_contains(played[0], "infantry", "the infantry marches first")
	assert_string_contains(played[1], "tank", "and the tank answers for where it stopped")


## The supply radius, which is the commander's rather than one tile: a plan is
## priced on who a top-up would reach, so the truck's envelope has to carry that
## reach or Holt's second tile keeps a plan the refill has already moved.
func test_holts_supply_unit_is_rescored_by_a_refill_two_tiles_out() -> void:
	var holt := CommanderDB.load_default().by_id(&"gideon_holt")
	assert_not_null(holt)
	assert_null(
		_supply_plan_after_a_refill({1: holt}), "his trucks are priced on ground two tiles out"
	)


## The sibling half, and what keeps the widening from being applied to everybody:
## the same board with nobody seated drops nothing, because a neutral truck's
## reach stops one tile short of that same refill.
func test_a_neutral_supply_unit_keeps_its_plan_over_the_same_refill() -> void:
	assert_not_null(_supply_plan_after_a_refill({}), "one tile of reach does not price that cell")


## The column, from the one direction a walk cannot reach it: a unit a base has
## just put on the board never moved, and it is still new company for its own
## domain wherever it stands.
func test_a_freshly_built_unit_moves_its_own_domains_column() -> void:
	var state := _seated(COLUMN_AND_A_BASE, {})
	var context := AIPlanningContext.new(unit_db)
	var marcher := state.unit_at(Vector2i(20, 0))
	var flyer := state.unit_at(Vector2i(31, 0))
	var cache := AIPlanCache.new(AIProfile.new())
	context.begin(state)
	cache.sync(context)
	cache.keep(marcher, _marching_plan())
	cache.keep(flyer, _marching_plan())

	state.funds[1] = 100000
	var build := BuildCommand.new(1, unit_db.by_id(&"infantry"), Vector2i(0, 0))
	assert_eq(build.validate(state), "", "the fixture must be able to buy an infantry")
	build.apply(state)
	_resync(cache, context, state)
	assert_true(cache.advance_is_stale(marcher), "a new infantry is company the land column keeps")
	assert_false(cache.advance_is_stale(flyer), "and the air column is not the land one")


## Ground changing hands re-prices every goal and every refit on the board, so it
## is the whole cache rather than an envelope: this tank is thirty-one tiles from
## the city and nothing else about the board moved.
func test_a_property_changing_hands_keeps_nothing() -> void:
	var state := _seated(CITY_AND_A_DISTANT_TANK, {})
	var context := AIPlanningContext.new(unit_db)
	var probe := state.unit_at(Vector2i(31, 0))
	var cache := _holding(state, context, probe, AIProfile.new())

	var city := Vector2i(0, 0)
	state.capture_progress[city] = 10
	var capture := CaptureCommand.new(state.unit_at(city), [city])
	assert_eq(capture.validate(state), "", "the fixture's infantry must be able to finish the city")
	capture.apply(state)
	assert_eq(state.owner_at(city), 1, "and the capture must actually flip it")
	_resync(cache, context, state)
	assert_null(cache.plan_for(probe), "ground changing hands is a fact about the whole board")


## The cache is not vacuously empty. A milestone that only ever cleared would
## pass every run in the sibling file and buy nothing, so this asks the cache
## itself:
## a plan survives a command at the other end of the board, and does not survive
## one inside its envelope.
func test_a_plan_survives_a_distant_command_and_not_a_near_one() -> void:
	var state := _state(PROBES, Callable())
	var context := AIPlanningContext.new(unit_db)
	var cache := AIPlanCache.new(AIProfile.load_default())
	context.begin(state)
	cache.sync(context)
	var near := state.unit_at(Vector2i(12, 0))
	var far := state.unit_at(Vector2i(28, 0))
	var near_plan := AIUnitPlan.new()
	var far_plan := AIUnitPlan.new()
	cache.keep(near, near_plan)
	cache.keep(far, far_plan)
	var walk: Array[Vector2i] = []
	for x in range(4, 11):
		walk.append(Vector2i(x, 0))
	MoveCommand.new(state.unit_at(Vector2i(4, 0)), walk).apply(state)
	context.begin(state)
	cache.sync(context)
	assert_eq(
		cache.plan_for(far), far_plan, "a march sixteen tiles off is not this tank's business"
	)
	assert_null(cache.plan_for(near), "the one that stopped two tiles away is")


# --- the wide guards, asked of the cache itself --------------------------------
#
# Each of these drops every plan on the board, and each is asked of the cache
# rather than played out on one because what it guards is a read no short game
# makes visible: a doctrine pricing ground off its own meter, the threat map
# reading a wounded enemy from as far away as that enemy can shoot, a turn
# handing over. They still fail the moment the rule goes.


func test_a_new_turn_keeps_nothing() -> void:
	var state := _state(PROBES, Callable())
	var context := AIPlanningContext.new(unit_db)
	var probe := state.unit_at(Vector2i(28, 0))
	var cache := _holding(state, context, probe, AIProfile.load_default())
	# One controller lives as long as the match, and the same army comes back to
	# a board that looks like this one after everyone else has played.
	state.day += 1
	_resync(cache, context, state)
	assert_null(cache.plan_for(probe), "a plan belongs to the turn it was made in")


## An enemy's condition is priced where it stands, so it is an ordinary cell —
## until a threat dial is live, when the map reads that enemy from as far away as
## it can shoot and a wound anywhere re-prices ground everywhere.
func test_a_wounded_enemy_keeps_nothing_while_a_threat_dial_is_live() -> void:
	var profile := AIProfile.new()
	profile.threat_aversion = 0.1
	var state := _state(PROBES, Callable())
	var context := AIPlanningContext.new(unit_db)
	# The tank at the far end, twenty-five tiles from the enemy that takes the hit:
	# no envelope of its own reaches it, and the threat map does.
	var probe := state.unit_at(Vector2i(4, 0))
	var cache := _holding(state, context, probe, profile)
	context.threat_map()
	var kept := AIUnitPlan.new()
	cache.keep(probe, kept)
	_resync(cache, context, state)
	assert_eq(cache.plan_for(probe), kept, "the turn's map is built and the board has not moved")
	state.unit_at(Vector2i(29, 0)).hp = 40
	_resync(cache, context, state)
	assert_null(cache.plan_for(probe), "and a wounded enemy is read from wherever it could shoot")


## Allegiance is the question, not team id (COM-177): an ally can no more reach
## the threat map than it can `visible_enemies`, so its own flag flipping is not
## "an enemy moved" — while a true enemy, unallied, still is.
func test_an_allys_flag_flip_keeps_a_distant_plan_but_an_enemys_move_still_drops_it() -> void:
	var profile := AIProfile.new()
	profile.threat_aversion = 0.1
	var state := _state(ALLY_AND_ENEMY, _ally_sides)
	var context := AIPlanningContext.new(unit_db)
	var probe := state.unit_at(Vector2i(4, 0))
	var cache := _holding(state, context, probe, profile)
	context.threat_map()
	var kept := AIUnitPlan.new()
	cache.keep(probe, kept)
	_resync(cache, context, state)
	assert_eq(cache.plan_for(probe), kept, "the turn's map is built and the board has not moved")
	state.unit_at(Vector2i(20, 0)).acted = true
	_resync(cache, context, state)
	assert_eq(cache.plan_for(probe), kept, "an ally's own flag is not the enemy's business")
	MoveCommand.new(state.unit_at(Vector2i(29, 0)), [Vector2i(29, 0), Vector2i(28, 0)]).apply(state)
	_resync(cache, context, state)
	assert_null(cache.plan_for(probe), "a true enemy is still read from as far as it could shoot")


func test_the_meter_moving_keeps_nothing() -> void:
	var wren := CommanderDB.load_default().by_id(&"sable_wren")
	assert_not_null(wren)
	var map := MapData.parse(PROBES, terrain_db)
	var state := GameState.create(map, unit_db, chart, {1: wren})
	assert_not_null(state)
	var context := AIPlanningContext.new(unit_db)
	var probe := state.unit_at(Vector2i(28, 0))
	var cache := _holding(state, context, probe, AIProfile.load_default())
	state.add_charge(1, 1)
	_resync(cache, context, state)
	assert_null(cache.plan_for(probe), "her army values cover by what the meter holds")


## Whether to be under the water is judged against every enemy's own reach, which
## is further than ours, so a submarine's plan cannot survive the list changing.
func test_a_submarine_keeps_nothing_when_the_enemy_list_changes() -> void:
	var state := _state(DEEP_WATER, Callable())
	var context := AIPlanningContext.new(unit_db)
	var sub := state.unit_at(Vector2i(0, 0))
	assert_true(sub.type.can_dive, "the fixture's boat must be the one that dives")
	var cache := _holding(state, context, sub, AIProfile.load_default())
	state.remove_unit(state.unit_at(Vector2i(15, 0)))
	_resync(cache, context, state)
	assert_null(cache.plan_for(sub), "one fewer hunter is one fewer reason to stay under")


## Fog makes a unit's own reach a fact about its whole side's sight — which
## enemies wall it off moves with every friendly that walks — so nothing can be
## kept at all. Asked of the cache, then played out on the same three boards.
func test_a_fogged_board_keeps_nothing_and_plays_command_for_command() -> void:
	var state := _state(PROBES, _fog)
	var context := AIPlanningContext.new(unit_db)
	var probe := state.unit_at(Vector2i(28, 0))
	var cache := _holding(state, context, probe, AIProfile.load_default())
	_resync(cache, context, state)
	assert_null(cache.plan_for(probe), "blind, a unit's own reach is a fact about its whole side")
	for board: Array in PlanCacheDiff.boards():
		_agreeing_commands(board[1], AIProfile.load_default(), 8, "fogged %s" % board[0], _fog)


func test_live_focus_fire_keeps_nothing() -> void:
	var profile := AIProfile.new()
	profile.focus_fire_bonus = 1.0
	var state := _state(PROBES, Callable())
	var context := AIPlanningContext.new(unit_db)
	var probe := state.unit_at(Vector2i(28, 0))
	var cache := _holding(state, context, probe, profile)
	_resync(cache, context, state)
	assert_null(cache.plan_for(probe), "a shot priced by every friendly is bounded by no envelope")


## The threat map is built once a turn against the board at the moment of first
## need, so nothing is kept until that moment has passed — otherwise skipping a
## replan could move it, and every reading of it with it.
func test_a_threat_weighing_profile_keeps_nothing_until_its_map_exists() -> void:
	var profile := AIProfile.new()
	profile.threat_aversion = 0.1
	var state := _state(PROBES, Callable())
	var context := AIPlanningContext.new(unit_db)
	var probe := state.unit_at(Vector2i(28, 0))
	var cache := _holding(state, context, probe, profile)
	_resync(cache, context, state)
	assert_null(cache.plan_for(probe), "no map yet, so no plan was made against one")
	context.threat_map()
	var kept := AIUnitPlan.new()
	cache.keep(probe, kept)
	_resync(cache, context, state)
	assert_eq(cache.plan_for(probe), kept, "with the turn's map built its contents are frozen")


## Campaign-depth R7, and the reason this milestone owed a test rather than cache
## code: a scripted beat is a board diff like any other. What the cache reads is
## the board between two calls, never the Command that changed it, so a unit a
## mission takes off the board and a unit a mission hands to the other army both
## lose their plans without anything in `ai/` knowing what a mission is.
func test_a_scripted_beat_keeps_no_plan_for_the_unit_it_moved() -> void:
	var state := _state(SCRIPTED, Callable())
	var context := AIPlanningContext.new(unit_db)
	var doomed := state.unit_at(Vector2i(4, 0))
	var far := state.unit_at(Vector2i(28, 0))
	var cache := _holding(state, context, doomed, AIProfile.load_default())
	var untouched := AIUnitPlan.new()
	cache.keep(far, untouched)

	var removal := RemoveUnitsEffect.new()
	removal.tags = [&"withdrawn"]
	_fire(state, [removal])
	_resync(cache, context, state)
	assert_null(cache.plan_for(doomed), "the unit the beat withdrew has no plan left to serve")
	assert_eq(cache.plan_for(far), untouched, "and a withdrawal 24 tiles off is not this tank's")


func test_a_scripted_defection_keeps_no_plan_for_the_unit_that_changed_sides() -> void:
	var state := _state(SCRIPTED, Callable())
	var context := AIPlanningContext.new(unit_db)
	var turncoat := state.unit_at(Vector2i(12, 0))
	var cache := _holding(state, context, turncoat, AIProfile.load_default())

	var defection := DefectEffect.new()
	defection.from_team = 1
	defection.to_team = 2
	defection.tags = [&"turncoat"]
	_fire(state, [defection])
	_resync(cache, context, state)
	assert_eq(turncoat.team, 2, "the fixture's beat has to actually move it")
	assert_null(cache.plan_for(turncoat), "a plan made for our army is not the enemy's to keep")


# --- helpers -------------------------------------------------------------------


## One scripted beat, applied the way the live scene applies one: a
## `MissionEventCommand` validated and applied, and nothing else.
func _fire(state: GameState, effects: Array[MissionEffect]) -> void:
	var event := MissionEvent.new()
	event.id = &"probe_beat"
	event.effects = effects
	var command := MissionEventCommand.new(event, 1)
	assert_eq(command.validate(state), "", "the fixture's beat must be applicable")
	command.apply(state)


## The commands both planners issued on `board`. The assertion is here rather
## than in the harness, and it carries the fixture's own name, so a board that
## diverges says which one and on which command.
func _agreeing_commands(
	board: String, profile: AIProfile, count: int, hint: String, prepare := Callable()
) -> Array[String]:
	var played := diff.steps(board, profile, count, prepare)
	assert_eq(played.divergence, "", hint)
	return played.commands


## The truck's plan after the tank nine tiles east of it spends a round — the one
## fact a supply plan is priced on, on a square nothing else touches.
func _supply_plan_after_a_refill(commanders: Dictionary) -> AIUnitPlan:
	var state := _seated(SUPPLY_LINE, commanders)
	var context := AIPlanningContext.new(unit_db)
	var truck := state.unit_at(Vector2i(0, 0))
	assert_true(
		truck.type.can_resupply, "the fixture's truck must be the one that carries supplies"
	)
	var cache := _holding(state, context, truck, AIProfile.new())
	var thirsty := state.unit_at(Vector2i(9, 0))
	thirsty.ammo -= 1
	_resync(cache, context, state)
	return cache.plan_for(truck)


func _seated(board: String, commanders: Dictionary) -> GameState:
	var state := GameState.create(MapData.parse(board, terrain_db), unit_db, chart, commanders)
	assert_not_null(state, "the fixture board must build a match")
	return state


## A plan whose command is the advance on the enemy, which is the only half of a
## plan cohesion shapes.
static func _marching_plan() -> AIUnitPlan:
	var plan := AIUnitPlan.new()
	plan.advances = true
	plan.keeps_formation = true
	return plan


func _state(board: String, prepare := Callable()) -> GameState:
	var built := diff.state(board, prepare)
	assert_not_null(built, "the fixture board must build a match")
	return built


## A cache holding one plan for `unit`, ready for the board to move under it.
func _holding(
	state: GameState, context: AIPlanningContext, unit: Unit, profile: AIProfile
) -> AIPlanCache:
	var cache := AIPlanCache.new(profile)
	context.begin(state)
	cache.sync(context)
	cache.keep(unit, AIUnitPlan.new())
	return cache


func _resync(cache: AIPlanCache, context: AIPlanningContext, state: GameState) -> void:
	context.begin(state)
	cache.sync(context)


## One shot short of dead, so the tank's attack is what takes it off the board.
func _wound_the_westmost_enemy(state: GameState) -> void:
	state.unit_at(Vector2i(0, 0)).hp = 10


func _wound_the_tank(state: GameState) -> void:
	state.capture_progress[Vector2i(0, 0)] = 10
	for unit in state.units:
		if unit.type.id == &"tank":
			unit.hp = 30


func _fog(state: GameState) -> void:
	state.fog_enabled = true


## Teams 1 and 2 grouped onto one side, team 3 left off it and so hostile to
## both — the same `sides` a seat strip or `--sides=` would write.
func _ally_sides(state: GameState) -> void:
	state.sides = {1: 0, 2: 0}
