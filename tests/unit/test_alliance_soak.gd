extends GutTest
## Four AI armies playing out every grouping on one board (COM-45, four-players
## plan FP2).
##
## The unit tests beside this one ask the authority a question at a time. This
## one asks the whole engine at once, because the rule it guards lives in two
## places at every routed site: `MovementResolver` decides where a unit may go and
## `MoveCommand.validate` decides whether it may — and an alliance that reached
## only one of them produces a planner proposing moves the rules turn down. That
## split is exactly what an AI-vs-AI soak catches and a unit test cannot: the same
## lesson `test_commander_match_soak.gd` was written for.
##
## Every grouping runs on `maps/fixtures/quartet.txt`, whose four armies are what
## makes a 2v2 and a 3v1 expressible at all. Nothing a player can reach writes
## `sides` yet (FP5), so the groupings are set directly here.

const FIXTURE := "res://maps/fixtures/quartet.txt"
## Long enough for four armies to bank income, build and meet, without making the
## suite pay for a full match per grouping.
const DAYS := 10
## A stall shows up as a planner that keeps proposing without the day ever
## ending, so this only has to sit above "a real match" — a deadlock detector.
const COMMAND_CAP := 900

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


## Free-for-all, 2v2 each way round, and a 3v1 — the three groupings the plan
## ships, plus the one that has to stay identical to how the board played before
## groupings existed.
func test_the_ai_plays_every_grouping_without_the_rules_refusing_it() -> void:
	_soak("free-for-all", {}, 610)
	_soak("2v2 alternating", {1: 0, 3: 0, 2: 1, 4: 1}, 611)
	_soak("2v2 in blocks", {1: 0, 2: 0, 3: 1, 4: 1}, 612)
	_soak("3v1", {1: 0, 2: 0, 3: 0}, 613)


## Plays the board out with `sides` applied and a planner per army. Fails on the
## first command the rules turn down — which is the whole point — and on a run
## that never ends.
func _soak(label: String, sides: Dictionary, rng_seed: int) -> void:
	var map := MapData.load_from_file(FIXTURE, terrain_db)
	assert_not_null(map, "the four-army fixture should parse")
	if map == null:
		return
	var state := GameState.create(map, unit_db, chart)
	state.sides = sides
	state.rng.seed = rng_seed
	state.fog_enabled = rng_seed % 2 == 1  # so the shared-sight path is walked too
	# One controller per army: a controller caches a threat map for the turn it is
	# planning, and two armies sharing one would read each other's.
	var planners: Dictionary = {}
	for team in state.teams:
		planners[team] = AIController.new(unit_db)
	var commands := 0
	while state.winner == 0 and state.day <= DAYS and commands < COMMAND_CAP:
		var ai: AIController = planners[state.current_team]
		var command := ai.plan_next_command(state)
		var error := command.validate(state)
		if error != "":
			fail_test(
				(
					"%s (day %d, team %d): the planner proposed a command the rules reject: %s."
					% [label, state.day, state.current_team, error]
				)
			)
			return
		command.apply(state)
		commands += 1
	gut.p("%-16s %4d commands, day %d" % [label, commands, state.day])
	assert_lt(commands, COMMAND_CAP, "%s: the match never progressed" % label)
	_assert_no_friendly_fire(label, state, sides)


## Nobody on a side ever took ground off it. Asked of the board rather than of the
## command stream, because a capture the rules allowed but should not have leaves
## its evidence in the ownership map and nowhere else.
func _assert_no_friendly_fire(label: String, state: GameState, sides: Dictionary) -> void:
	for cell: Vector2i in state.property_owners:
		var owner_team: int = state.property_owners[cell]
		if owner_team == MapData.NEUTRAL:
			continue
		var started_as := int(state.map.initial_owners().get(cell, MapData.NEUTRAL))
		if started_as == MapData.NEUTRAL or started_as == owner_team:
			continue
		assert_false(
			state.allied(started_as, owner_team),
			(
				"%s: %s passed from team %d to team %d, which stands with it — sides %s"
				% [label, cell, started_as, owner_team, sides]
			)
		)
