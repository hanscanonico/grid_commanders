extends GutTest
## AR1's merge bar: the planner that keeps its plans between commands answers
## exactly what the planner that scores every unit from scratch answers.
##
## A missed invalidation is not a crash. It is a *different AI* that passes every
## other test in this suite and quietly re-prices the difficulty ladder, the
## Atlas and every commander number in one commit — the AI Arena plan's R3. So
## this file stays in the tree afterwards, and a milestone that adds a dial to
## the planner adds a run to it.
##
## Two instruments. The differential suite plays whole seeded matches through the
## one match engine with both planners and compares the command logs — the broad
## net, over three boards and the profiles that reach the paths no shipped tier
## does. Then one fixture per invalidation rule, each a board where that rule is
## the only thing standing between the two answers.


## The planner as it stood before the cache: every ready unit scored afresh on
## every call. A new AIUnitActionPlanner starts with an empty cache, so building
## one per command is exactly that — and everything else the controller carries,
## the planning context and its threat map above all, stays where it was.
class UncachedController:
	extends AIController

	func plan_next_command(state: GameState) -> Command:
		_unit_actions = AIUnitActionPlanner.new(profile)
		return super(state)


## Mirrored armies with a base each and room to fight, from test_balance_engine:
## long enough to build, trade and capture, small enough to play many times.
const SKIRMISH := """
[terrain]
QB......
........
..F..F..
........
......BQ
[owners]
1 0 0
1 1 0
2 7 4
2 6 4
[units]
1 i 1 1
1 t 2 1
2 i 6 3
2 t 5 3
"""

## Property-dense, so capture goals, claims and ground changing hands are what
## the match is mostly about.
const PROPERTY_RACE := """
[terrain]
QCCCCCCQ
.C....C.
..C..C..
.C....C.
[owners]
1 0 0
2 7 0
[units]
1 i 0 1
1 i 1 2
1 m 0 3
2 i 7 1
2 i 6 2
2 m 7 3
"""

## Two shores, a port each and open water between them: aircraft, hulls and a
## submarine's dive decision, which the two land boards never reach.
const NARROW_SEA := """
[terrain]
QP.SS.PQ
.B.SS.B.
..SSSS..
[owners]
1 0 0
1 1 0
1 1 1
2 7 0
2 6 0
2 6 1
[units]
1 i 1 2
1 s 3 0
1 h 0 1
2 i 6 2
2 s 4 0
2 h 7 1
"""

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

## The one shipped board the suite plays, and how long for: far enough in that
## both sides have built an army and closed on each other.
const SHIPPED_BOARD := "res://maps/ironworks.txt"
const SHIPPED_SEEDS: Array[int] = [1000, 7]
const SHIPPED_DAYS := 18

## The seeds every differential run plays. Three is enough for the boards to
## diverge in different places; the suite is a gate, not a measurement.
const SEEDS: Array[int] = [7, 4242, 90210]

## Short enough to keep the suite quick, long enough that both sides build,
## capture, trade and fire a power.
const DAYS := 12

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


# --- the differential suite ----------------------------------------------------


func test_the_shipped_profile_plays_every_board_command_for_command() -> void:
	for board: Array in _boards():
		_assert_agrees_over_a_match(board[1], AIProfile.load_default(), board[0])


## The claim path no shipped tier reaches: `capture_claim_depth` is 0 everywhere,
## and it is the one dial that makes a capturer's goal a function of where every
## *other* capturer stands. AR5 turns it on, and a cache that is exact only while
## a dial is zero is exactly the silent divergence this file exists to refuse.
func test_a_live_capture_claim_plays_command_for_command() -> void:
	for depth in [1, 2]:
		var profile := AIProfile.new()
		profile.capture_claim_depth = depth
		for board: Array in _boards():
			_assert_agrees_over_a_match(board[1], profile, "%s at depth %d" % [board[0], depth])


## Every profile that weighs a threat map: the two shipped tiers that carry one,
## and the withdrawal dial no tier carries. Their plans are read off a map built
## once per turn against the board at the moment of first need, so these are the
## runs that prove the cache never moved that moment. The withdrawal profile is
## here for a second reason as well — AR6d gave its refuge a key read off the
## unit's *advance goal*, which is a fact about the whole board rather than about
## the ground around the unit, and a threat map is the only thing holding it.
func test_threat_weighing_profiles_play_command_for_command() -> void:
	var withdrawing := AIProfile.new()
	withdrawing.withdraw_weight = 0.5
	var profiles := {
		&"easy": load("res://data/ai/easy.tres"),
		&"hard": load("res://data/ai/hard.tres"),
		&"withdrawing": withdrawing,
	}
	for tier: StringName in profiles:
		var profile: AIProfile = profiles[tier]
		assert_not_null(profile, "the %s profile must load" % tier)
		for board: Array in _boards():
			_assert_agrees_over_a_match(board[1], profile, "%s on %s" % [board[0], tier])


## A shipped board, at the width the Balance Lab plays on. The three fixtures
## above are small enough to keep the suite quick and they all agreed while the
## diff was still dropping half its invalidations on the floor: an army only
## marches into everybody else's envelope when there is a board wide enough to
## march across, and armies only reach that size some days in.
func test_a_shipped_board_plays_command_for_command() -> void:
	var map := MapData.load_from_file(SHIPPED_BOARD, terrain_db)
	assert_not_null(map, "the shipped board must load")
	_assert_agrees_over(map, AIProfile.load_default(), "ironworks", SHIPPED_SEEDS, SHIPPED_DAYS)


## The withdrawal dial, which no shipped tier carries either. AR6d gave the
## refuge a key read off the unit's *advance goal* — a fact about the whole
## board rather than the ground around the unit — so the plan a withdrawal is
## cached as now depends on something no envelope bounds. Every profile that
## lives this dial also weighs a threat map, which is what makes the cache keep
## nothing while it is on; this run is what holds that together.
func test_a_live_withdrawal_plays_command_for_command() -> void:
	var profile := AIProfile.new()
	profile.withdraw_weight = 0.5
	for board: Array in _boards():
		_assert_agrees_over_a_match(board[1], profile, "%s withdrawing" % board[0])


## Focus fire prices a shot by what every other ready friendly could still add to
## the same target, which no envelope around one unit bounds.
func test_live_focus_fire_plays_command_for_command() -> void:
	var profile := AIProfile.new()
	profile.focus_fire_bonus = 1.0
	_assert_agrees_over_a_match(SKIRMISH, profile, "focus fire")


## Commanders seated, so the meter moves under the planner all match: charge is
## banked on every exchange, powers fire mid-turn, and Sable Wren prices ground
## off the meter itself.
func test_commanders_play_command_for_command() -> void:
	var db := CommanderDB.load_default()
	for pairing: Array in [[&"sable_wren", &"gideon_holt"], [&"iris_colt", &"mara_voss"]]:
		var seated := {1: db.by_id(pairing[0]), 2: db.by_id(pairing[1])}
		assert_not_null(seated[1], "commander %s must load" % pairing[0])
		assert_not_null(seated[2], "commander %s must load" % pairing[1])
		_assert_agrees_over_a_match(
			SKIRMISH, AIProfile.load_default(), "%s vs %s" % pairing, seated
		)


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


## The cache is not vacuously empty. A milestone that only ever cleared would
## pass every differential above and buy nothing, so this asks the cache itself:
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
	for board: Array in _boards():
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


# --- helpers -------------------------------------------------------------------


## The three boards every differential run plays, as [name, board] pairs.
static func _boards() -> Array[Array]:
	return [["skirmish", SKIRMISH], ["property race", PROPERTY_RACE], ["narrow sea", NARROW_SEA]]


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


func _controller(cached: bool, profile: AIProfile) -> AIController:
	if cached:
		return AIController.new(unit_db, profile)
	return UncachedController.new(unit_db, profile)


## One seeded match, played through the one match engine, as the log of every
## command it issued.
func _play(
	map: MapData,
	seed_val: int,
	profile: AIProfile,
	cached: bool,
	commanders: Dictionary,
	days: int = DAYS
) -> Array[Dictionary]:
	var setup := BalanceMatchEngine.Setup.new()
	setup.map = map
	setup.unit_db = unit_db
	setup.chart = chart
	setup.seed_val = seed_val
	setup.days_cap = days
	setup.commanders = commanders
	setup.planners = {1: _controller(cached, profile), 2: _controller(cached, profile)}
	var recorder := BalanceMatchRecorder.new()
	BalanceMatchEngine.play(setup, recorder)
	return recorder.command_log()


func _assert_agrees_over_a_match(
	board: String, profile: AIProfile, hint: String, commanders: Dictionary = {}
) -> void:
	_assert_agrees_over(MapData.parse(board, terrain_db), profile, hint, SEEDS, DAYS, commanders)


func _assert_agrees_over(
	map: MapData,
	profile: AIProfile,
	hint: String,
	seeds: Array[int],
	days: int,
	commanders: Dictionary = {}
) -> void:
	for seed_val in seeds:
		var uncached := _play(map, seed_val, profile, false, commanders, days)
		var cached := _play(map, seed_val, profile, true, commanders, days)
		assert_gt(
			uncached.size(),
			10,
			"%s seed %d: the fixture should play a real match" % [hint, seed_val]
		)
		assert_eq(
			_first_divergence(cached, uncached),
			"",
			"%s, seed %d: the cache must not change a command" % [hint, seed_val]
		)


## The first command the two logs disagree on, or "" when they are identical.
## Reported rather than asserted whole, because a match is hundreds of commands
## and only the first divergence says anything about the rule that went missing.
static func _first_divergence(cached: Array, uncached: Array) -> String:
	for i in mini(cached.size(), uncached.size()):
		if cached[i] != uncached[i]:
			return "command %d: cached %s, uncached %s" % [i, cached[i], uncached[i]]
	if cached.size() != uncached.size():
		return "command counts differ: cached %d, uncached %d" % [cached.size(), uncached.size()]
	return ""


## Plays `steps` commands of one turn twice on two copies of one board — once
## through a controller that lives across the turn, once through a fresh one for
## every command — and returns what they both did. Asserts on the way, so a
## fixture that diverges names the command it diverged on.
func _agreeing_commands(
	board: String, profile: AIProfile, steps: int, hint: String, prepare := Callable()
) -> Array[String]:
	var kept := _state(board, prepare)
	var fresh := _state(board, prepare)
	var controller := AIController.new(unit_db, profile)
	var played: Array[String] = []
	for step in steps:
		var with_cache := controller.plan_next_command(kept)
		var without := UncachedController.new(unit_db, profile).plan_next_command(fresh)
		var described := _describe(with_cache)
		assert_eq(described, _describe(without), "%s: command %d" % [hint, step])
		if described != _describe(without):
			return played
		played.append(described)
		if with_cache is EndTurnCommand:
			return played
		with_cache.apply(kept)
		without.apply(fresh)
	return played


func _state(board: String, prepare: Callable) -> GameState:
	var state := GameState.create(MapData.parse(board, terrain_db), unit_db, chart)
	assert_not_null(state)
	state.rng.seed = 1234
	if prepare.is_valid():
		prepare.call(state)
	return state


## A command as the two planners have to agree on it: what it is, who does it,
## and every cell it names.
static func _describe(command: Command) -> String:
	if command == null:
		return "<none>"
	var parts: Array[String] = [str(command.get_script().get_global_name())]
	for key: String in ["unit", "unit_type", "path", "target_cell", "cell", "drop_cell", "diving"]:
		var value: Variant = command.get(key)
		if value == null:
			continue
		if value is Unit:
			var mover: Unit = value
			parts.append("%s@%s" % [mover.type.id, mover.cell])
		elif value is UnitType:
			parts.append(str((value as UnitType).id))
		else:
			parts.append(str(value))
	return " ".join(parts)
