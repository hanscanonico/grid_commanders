extends GutTest
## The Difficult tier's threat dials (plan DF3): advance_threat_tiles and
## threat_aversion, each on a crafted board, each proved by the same board
## reaching a different command with the dial up than with it down. The Normal
## pin at the foot of the file is here for the same reason: it is a claim about
## what a profile plans.
##
## The threat map those dials read is tests/unit/test_ai_smarts_threat_map.gd's,
## focus fire is tests/unit/test_ai_smarts_focus_fire.gd's and counter-building
## is tests/unit/test_ai_smarts_building.gd's.
##
## Almost every test builds its own profile rather than leaning on
## data/ai/hard.tres: these pin the *behaviour* of each smart, so retuning a
## shipped weight is a balance decision and never a test failure.
##
## The exception is deliberate. A capability suite where every test picks its own
## weight cannot notice a tier that ships a weight too small to do anything —
## which is exactly how Difficult shipped a kill-zone refusal that never refused
## anything. So one test loads the real Difficult profile and asserts the shipped
## configuration reaches the behaviour the tier claims.

## Twin of the const in tests/unit/test_ai_smarts_threat_map.gd.
const ARTILLERY_RING_BOARD := "[terrain]\n..........\n[units]\n1 t 0 0\n2 g 9 0"

## A shot barely worth taking, offered from a cell an artillery has ranged. The
## mountain column is what makes the artillery a pure threat: our tank can reach
## neither of the two cells adjacent to it, so the gun is something to be shot at
## from and never something to shoot, and the only target on the board is the
## infantry beside us — wounded to 5 HP in the test, so the kill is worth 80 to a
## planner that wants 40.
const RANGED_SHOT_BOARD := "[terrain]\n..M.\n..M.\n[units]\n1 t 0 0\n2 i 1 0\n2 g 3 0"

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()


func _profile() -> AIProfile:
	return AIProfile.new()  # every capability off; the Normal baseline


## The tier as shipped, for the two tests that pin a configuration rather than a
## capability.
func _hard_profile() -> AIProfile:
	return load("res://data/ai/hard.tres")


# --- S1 · threat awareness ----------------------------------------------------


## The flagship case. A tank walking at an enemy artillery ends its advance on
## the closest cell it can reach — which is inside the artillery's firing ring.
## With threat awareness on it gives up one tile and stops outside the ring.
##
## Exercised at 2.0, the value data/ai/hard.tres ships, because that is the
## claim: this dial is denominated in tiles precisely so a ladder-safe weight can
## still move a unit. The arithmetic is tight and worth spelling out — the shot
## forecasts 63 damage, so a tile costs 63/100 of the dial, and anything under
## ~1.6 leaves the tank inside the ring however confident the docs sound.
func test_advance_threat_tiles_keeps_a_tank_out_of_the_artillery_ring() -> void:
	var blind := AIController.new(unit_db, _profile())
	var blind_move := blind.plan_next_command(Fixture.state(ARTILLERY_RING_BOARD))
	assert_true(blind_move is MoveCommand, "expected an advance, got %s" % blind_move)
	var blind_path: Array[Vector2i] = (blind_move as MoveCommand).path
	assert_eq(
		blind_path[blind_path.size() - 1],
		Vector2i(6, 0),
		"the base planner spends its whole move, ending 3 tiles out — inside range 2-3"
	)

	var wary_profile := _profile()
	wary_profile.advance_threat_tiles = 2.0
	var wary_state := Fixture.state(ARTILLERY_RING_BOARD)
	var wary_move := AIController.new(unit_db, wary_profile).plan_next_command(wary_state)
	assert_true(wary_move is MoveCommand, "expected an advance, got %s" % wary_move)
	var wary_path: Array[Vector2i] = (wary_move as MoveCommand).path
	assert_eq(
		wary_path[wary_path.size() - 1],
		Vector2i(5, 0),
		"threat awareness gives up a tile to stop outside the artillery's reach"
	)
	assert_eq(wary_move.validate(wary_state), "", "a wary advance is still a legal move")


## The same board against the profile the game actually ships as Difficult, not
## a value invented for the test. The one above pins the capability; this pins
## the *configuration*, which is where the claim rotted last time — the tier
## shipped a weight that could not move a unit by a single tile, and every
## capability test passed anyway because each chose its own number.
func test_the_shipped_difficult_profile_refuses_the_artillery_ring() -> void:
	var hard := _hard_profile()
	assert_not_null(hard, "data/ai/hard.tres should load")
	var state := Fixture.state(ARTILLERY_RING_BOARD)
	var move := AIController.new(unit_db, hard).plan_next_command(state)
	assert_true(move is MoveCommand, "expected an advance, got %s" % move)
	var path: Array[Vector2i] = (move as MoveCommand).path
	assert_eq(
		path[path.size() - 1],
		Vector2i(5, 0),
		"Difficult as shipped must actually stop outside the ring, not merely intend to"
	)
	assert_eq(move.validate(state), "")


## The advance dial is denominated in tiles, so its scale is readable: at 1.0 a
## shot that would kill outright is worth exactly one tile of progress and no
## more. Pins the shape of the formula, which is the thing a retune must not
## quietly change.
func test_advance_threat_tiles_are_priced_in_tiles() -> void:
	# The artillery forecasts 63 damage, so a tile costs 0.63 of the dial.
	var timid := _profile()
	timid.advance_threat_tiles = 1.5  # 0.945 tiles: not quite enough to give one up
	var timid_move := AIController.new(unit_db, timid).plan_next_command(
		Fixture.state(ARTILLERY_RING_BOARD)
	)
	var timid_path: Array[Vector2i] = (timid_move as MoveCommand).path
	assert_eq(
		timid_path[timid_path.size() - 1],
		Vector2i(6, 0),
		"under one tile of aversion buys no tiles — the dial is not a veto"
	)

	var timider := _profile()
	timider.advance_threat_tiles = 1.6  # 1.008 tiles: just over the line
	var timider_move := AIController.new(unit_db, timider).plan_next_command(
		Fixture.state(ARTILLERY_RING_BOARD)
	)
	var timider_path: Array[Vector2i] = (timider_move as MoveCommand).path
	assert_eq(
		timider_path[timider_path.size() - 1], Vector2i(5, 0), "just over one tile buys one tile"
	)


## Lethality, not HP loss. The same shot on the same cell is a scratch to a fresh
## tank and certain death to a hurt one, and the dial has to read it that way
## round — a unit already down to its last points is the one that must give
## ground. Measured at a weight deliberately between the two: enough for the
## wounded tank, not enough for the healthy one, so the test fails if the penalty
## ever goes back to being a fraction of a full HP bar.
func test_a_wounded_unit_flinches_harder_than_a_healthy_one() -> void:
	var dial := _profile()
	dial.advance_threat_tiles = 1.2

	var healthy := Fixture.state(ARTILLERY_RING_BOARD)
	var healthy_move := AIController.new(unit_db, dial).plan_next_command(healthy)
	var healthy_path: Array[Vector2i] = (healthy_move as MoveCommand).path
	assert_eq(
		healthy_path[healthy_path.size() - 1],
		Vector2i(6, 0),
		"63 of a full 100 is worth 0.76 tiles at this dial — the fresh tank presses on"
	)

	var hurt := Fixture.state(ARTILLERY_RING_BOARD)
	hurt.units[0].hp = 49  # still above retreat_hp, so it is advancing, not fleeing
	var hurt_move := AIController.new(unit_db, dial).plan_next_command(hurt)
	assert_true(hurt_move is MoveCommand, "expected an advance, got %s" % hurt_move)
	var hurt_path: Array[Vector2i] = (hurt_move as MoveCommand).path
	assert_eq(
		hurt_path[hurt_path.size() - 1],
		Vector2i(5, 0),
		"the same shot takes every point it has left, so it is worth the whole dial"
	)
	assert_eq(hurt_move.validate(hurt), "")


## The two dials are independent: the attack-path one must not move an advancing
## unit, which is exactly the confusion that shipped a Difficult tier whose
## advance never flinched.
func test_the_attack_dial_does_not_steer_the_advance() -> void:
	var attack_only := _profile()
	attack_only.threat_aversion = 5.0
	var wary := AIController.new(unit_db, attack_only).plan_next_command(
		Fixture.state(ARTILLERY_RING_BOARD)
	)
	var blind := AIController.new(unit_db, _profile()).plan_next_command(
		Fixture.state(ARTILLERY_RING_BOARD)
	)
	assert_true(wary is MoveCommand and blind is MoveCommand)
	assert_eq(
		(wary as MoveCommand).path,
		(blind as MoveCommand).path,
		"threat_aversion prices shots, not steps"
	)


## Threat is a discount on the score, not a veto: a worthwhile attack still
## happens from a threatened cell. This is the R2 guard — an AI that refuses
## every trade and orbits is worse than one that loses.
func test_threat_aversion_still_takes_a_worthwhile_attack() -> void:
	var map_text := "[terrain]\n....\n[units]\n1 t 0 0\n2 g 1 0\n2 t 3 0"
	var wary_profile := _profile()
	wary_profile.threat_aversion = 0.5
	var state := Fixture.state(map_text)
	var command := AIController.new(unit_db, wary_profile).plan_next_command(state)
	assert_true(command is AttackCommand, "a profitable shot survives the threat discount")
	assert_eq((command as AttackCommand).target_cell, Vector2i(1, 0))
	assert_eq(command.validate(state), "")


## And the other half of that guard, which nothing pinned: threat_aversion at
## 0.0 must take a shot the same board refuses at the dial's shipped Difficult
## value. Every other test in this suite exercises the dial at one weight only,
## so a tier that shipped it at zero would read as a passing suite.
##
## Three profiles because the claim is two: 0.0 against 0.1 pins the
## *capability*, and data/ai/hard.tres pins the *configuration* — the same split
## the artillery-ring pair above makes, in one function because this file is at
## the lint's public-method ceiling.
func test_threat_aversion_at_zero_takes_the_shot_the_wary_profile_refuses() -> void:
	var blind_state := _ranged_shot_state()
	var blind := AIController.new(unit_db, _profile()).plan_next_command(blind_state)
	assert_true(blind is AttackCommand, "expected the kill, got %s" % blind)
	assert_eq((blind as AttackCommand).target_cell, Vector2i(1, 0))
	assert_eq(blind.validate(blind_state), "")

	var wary_profile := _profile()
	wary_profile.threat_aversion = 0.1  # data/ai/hard.tres as shipped
	var wary := AIController.new(unit_db, wary_profile).plan_next_command(_ranged_shot_state())
	assert_false(wary is AttackCommand, "the ranged cell prices the kill out, got %s" % wary)

	var shipped := AIController.new(unit_db, _hard_profile()).plan_next_command(
		_ranged_shot_state()
	)
	assert_false(
		shipped is AttackCommand, "Difficult as shipped must refuse it too, got %s" % shipped
	)


## RANGED_SHOT_BOARD with the target wounded to where the kill is worth just over
## the planner's min_useful_score, which is what leaves the threat penalty room
## to decide.
func _ranged_shot_state() -> GameState:
	var state := Fixture.state(RANGED_SHOT_BOARD)
	state.units_of(2)[0].hp = 5
	return state


# --- the Normal pin -----------------------------------------------------------


## The guarantee the whole plan rests on: an install whose profile file is
## missing plays the same game as one with it, because AIProfile's own defaults
## and data/ai/default.tres carry the same numbers. Played out over a full AI
## turn on a real map, command for command.
func test_capability_defaults_plan_exactly_like_the_shipped_profile() -> void:
	var shipped := _plan_a_turn(AIController.new(unit_db, AIProfile.load_default()))
	var defaults := _plan_a_turn(AIController.new(unit_db, AIProfile.new()))
	assert_gt(shipped.size(), 3, "the reference turn should be more than a formality")
	assert_eq(defaults, shipped, "profile defaults must plan a Normal turn command for command")


## Plays Blue's whole opening turn on first_steps and returns one string per
## command, which is what "identical planning" is checked on.
func _plan_a_turn(ai: AIController) -> Array[String]:
	var map := MapData.load_from_file("res://maps/first_steps.txt", terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.rng.seed = 7
	EndTurnCommand.new().apply(state)  # hand the turn to Blue, the AI side
	var log: Array[String] = []
	for i in 60:
		var command := ai.plan_next_command(state)
		log.append(_describe(command))
		command.apply(state)
		if command is EndTurnCommand:
			break
	return log


func _describe(command: Command) -> String:
	if command is AttackCommand:
		var attack := command as AttackCommand
		return "attack %s from %s" % [attack.target_cell, attack.path]
	if command is CaptureCommand:
		return "capture %s" % [(command as CaptureCommand).path]
	if command is JoinCommand:
		return "join %s" % [(command as JoinCommand).path]
	if command is SupplyCommand:
		return "supply %s" % [(command as SupplyCommand).path]
	if command is MoveCommand:
		return "move %s" % [(command as MoveCommand).path]
	if command is BuildCommand:
		var build := command as BuildCommand
		return "build %s at %s" % [build.unit_type.id, build.cell]
	if command is PowerCommand:
		return "power"
	return "end turn"
