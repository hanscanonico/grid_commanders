## Machinery for AR1's merge bar: one seeded match played by the planner that
## keeps its plans and by the planner that scores every unit afresh, and the
## comparison of what the two did.
##
## No claim lives here — every assertion belongs to the suites that drive this,
## `test_ai_plan_cache_diff.gd` (whole matches) and `test_ai_plan_cache.gd` (one
## fixture per invalidation rule). They share the machinery and nothing else, and
## a later instrument that wants the same comparison — the arena's own search
## reaches for it first — drives it the same way.
##
## Preloaded by its path rather than registered as a `class_name`: it is test
## scaffolding, and the global class list is the shipped game's.

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


## What one differential run found.
class Diff:
	## The first command the two planners disagreed on, and what each of them
	## chose there. Empty when they agreed all the way through.
	var divergence := ""
	## How many commands the shorter of the two logs holds, so a caller can tell
	## a fixture that agreed from one that never played a match to disagree in.
	var commands := 0


## What the two planners did, step by step, on one board.
class Steps:
	## Every command they agreed on, in order, as `describe` spells them.
	var commands: Array[String] = []
	## The first step they parted company on. Empty when they agreed throughout.
	var divergence := ""


func _init() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


## The three boards every differential run plays, as [name, board] pairs.
static func boards() -> Array[Array]:
	return [["skirmish", SKIRMISH], ["property race", PROPERTY_RACE], ["narrow sea", NARROW_SEA]]


## One board as a match about to be played, at a fixed seed so two runs of it are
## the same match. `prepare` is the fixture's own hand on the board — a wound, a
## capture already begun, the fog — applied before anybody plans.
func state(board: String, prepare := Callable()) -> GameState:
	var built := GameState.create(MapData.parse(board, terrain_db), unit_db, chart)
	if built == null:
		return null
	built.rng.seed = 1234
	if prepare.is_valid():
		prepare.call(built)
	return built


## `board` parsed and played at the suite's own seeds and horizon.
func over_a_match(board: String, profile: AIProfile, commanders: Dictionary = {}) -> Diff:
	return over(MapData.parse(board, terrain_db), profile, SEEDS, DAYS, commanders)


## Every seed played twice — once with the cache, once without — stopping at the
## first command the two disagree on.
func over(
	map: MapData, profile: AIProfile, seeds: Array[int], days: int, commanders: Dictionary = {}
) -> Diff:
	var result := Diff.new()
	for seed_val in seeds:
		var uncached := command_log(map, seed_val, profile, false, commanders, days)
		var cached := command_log(map, seed_val, profile, true, commanders, days)
		var shortest := mini(cached.size(), uncached.size())
		result.commands = shortest if result.commands == 0 else mini(result.commands, shortest)
		var parted := divergence(cached, uncached)
		if parted != "":
			result.divergence = "seed %d, %s" % [seed_val, parted]
			return result
	return result


## One seeded match, played through the one match engine, as the log of every
## command it issued.
func command_log(
	map: MapData,
	seed_val: int,
	profile: AIProfile,
	cached: bool,
	commanders: Dictionary = {},
	days: int = DAYS
) -> Array[Dictionary]:
	var setup := BalanceMatchEngine.Setup.new()
	setup.map = map
	setup.unit_db = unit_db
	setup.chart = chart
	setup.seed_val = seed_val
	setup.days_cap = days
	setup.commanders = commanders
	setup.planners = {1: _planner(cached, profile), 2: _planner(cached, profile)}
	var recorder := BalanceMatchRecorder.new()
	BalanceMatchEngine.play(setup, recorder)
	return recorder.command_log()


## Plays `count` commands of one turn twice on two copies of one board — once
## through a controller that lives across the turn, once through a fresh one for
## every command — and reports what they both did.
func steps(board: String, profile: AIProfile, count: int, prepare := Callable()) -> Steps:
	var result := Steps.new()
	var kept := state(board, prepare)
	var fresh := state(board, prepare)
	var controller := AIController.new(unit_db, profile)
	for step in count:
		var with_cache := controller.plan_next_command(kept)
		var without := UncachedController.new(unit_db, profile).plan_next_command(fresh)
		var described := describe(with_cache)
		if described != describe(without):
			result.divergence = (
				"command %d: cached %s, uncached %s" % [step, described, describe(without)]
			)
			return result
		result.commands.append(described)
		if with_cache is EndTurnCommand:
			return result
		with_cache.apply(kept)
		without.apply(fresh)
	return result


func _planner(cached: bool, profile: AIProfile) -> AIController:
	if cached:
		return AIController.new(unit_db, profile)
	return UncachedController.new(unit_db, profile)


## `sides` grouping more than two armies, played by hand rather than through
## `BalanceMatchEngine.play()` — which plays exactly two sides (the
## asymmetric-board plan's R4) — the same way `test_alliance_soak.gd`'s own loop
## does: one controller per army, held across the whole match. This is COM-177's
## run: an ally changing is not "an enemy moved," and the only way to prove the
## cache never under-drops on that distinction is to play a grouped match twice,
## cached and not, and demand the same commands.
func over_grouped_match(
	map: MapData, sides: Dictionary, profile: AIProfile, seed_val: int, days: int
) -> Diff:
	var result := Diff.new()
	var cached := _grouped_command_log(map, sides, profile, true, seed_val, days)
	var uncached := _grouped_command_log(map, sides, profile, false, seed_val, days)
	result.commands = mini(cached.size(), uncached.size())
	result.divergence = divergence(cached, uncached)
	return result


## One seeded grouped match's command log, as `describe` spells it — there is no
## recorder here, because the comparison is between two logs rather than a
## report.
func _grouped_command_log(
	map: MapData, sides: Dictionary, profile: AIProfile, cached: bool, seed_val: int, days: int
) -> Array[String]:
	var built := GameState.create(map, unit_db, chart)
	built.sides = sides.duplicate()
	built.rng.seed = seed_val
	var planners: Dictionary = {}
	for team in built.teams:
		planners[team] = _planner(cached, profile)
	var cap := BalanceMatchEngine.command_ceiling(days, built.teams.size())
	var log: Array[String] = []
	while built.winner == 0 and built.day <= days and log.size() < cap:
		var planner: AIController = planners[built.current_team]
		var command := planner.plan_next_command(built)
		log.append(describe(command))
		command.apply(built)
	return log


## The first command the two logs disagree on, or "" when they are identical.
## Reported rather than asserted whole, because a match is hundreds of commands
## and only the first divergence says anything about the rule that went missing.
static func divergence(cached: Array, uncached: Array) -> String:
	for i in mini(cached.size(), uncached.size()):
		if cached[i] != uncached[i]:
			return "command %d: cached %s, uncached %s" % [i, cached[i], uncached[i]]
	if cached.size() != uncached.size():
		return "command counts differ: cached %d, uncached %d" % [cached.size(), uncached.size()]
	return ""


## A command as the two planners have to agree on it: what it is, who does it,
## and every cell it names.
static func describe(command: Command) -> String:
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
