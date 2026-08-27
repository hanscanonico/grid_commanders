extends GutTest
## The submarine's dive: the one mechanic that touches movement, targeting,
## vision and the save format at once.
##
## Each of those is a place the rule could be half-implemented and look fine. A
## dived boat that is still targetable is a sub with an expensive downside and no
## upside; one that is hidden but still counterattacks gives itself away for free;
## one that saves and reloads on the surface loses a match's worth of position.
## So each is asserted separately here rather than trusted to the one flag they
## all read.

const STRAITS := "res://maps/the_straits.txt"

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()


## The shipped naval board, which deals each fleet a submarine — the state a save
## test needs, because a save is read back against the map it names.
func _straits_state() -> GameState:
	var map := MapData.load_from_file(STRAITS, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	state.map_path = STRAITS
	return state


func _sub_of(state: GameState, team: int) -> Unit:
	for unit in state.units_of(team):
		if unit.type.id == &"sub":
			return unit
	return null


# --- the command --------------------------------------------------------------


## Diving is an ordinary turn: the boat repositions and goes under in one action,
## rather than spending a turn standing still to close a hatch.
func test_a_sub_dives_while_moving() -> void:
	var state := Fixture.state("[terrain]\nSSS\n[units]\n1 s 0 0")
	var sub := state.units[0]
	var command := DiveCommand.new(sub, Fixture.path([Vector2i(0, 0), Vector2i(1, 0)]), true)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_true(sub.dived)
	assert_eq(sub.cell, Vector2i(1, 0))
	assert_true(sub.acted)


func test_surfacing_is_the_same_command_the_other_way() -> void:
	var state := Fixture.state("[terrain]\nSS\n[units]\n1 s 0 0")
	var sub := state.units[0]
	sub.dived = true
	var command := DiveCommand.new(sub, Fixture.path([Vector2i(0, 0)]), false)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_false(sub.dived)


func test_dive_rejections() -> void:
	var state := Fixture.state("[terrain]\nSS\n..\n[units]\n1 s 0 0\n1 c 1 0\n1 t 0 1")
	var sub := state.units[0]
	assert_eq(
		DiveCommand.new(state.units[1], Fixture.path([Vector2i(1, 0)]), true).validate(state),
		"unit cannot dive",
		"a cruiser hunts submarines, it does not become one"
	)
	assert_eq(
		DiveCommand.new(state.units[2], Fixture.path([Vector2i(0, 1)]), true).validate(state),
		"unit cannot dive"
	)
	assert_eq(
		DiveCommand.new(sub, Fixture.path([Vector2i(0, 0)]), false).validate(state),
		"already on the surface"
	)
	sub.dived = true
	assert_eq(
		DiveCommand.new(sub, Fixture.path([Vector2i(0, 0)]), true).validate(state),
		"already submerged"
	)


# --- targeting ----------------------------------------------------------------


## Only a weapon built to hunt a submarine reaches one. That is the whole payoff
## of diving, and it has to hold in the command that validates the shot — the
## planner and the targeting overlay ask the same authority.
func test_only_a_hunter_can_engage_a_dived_sub() -> void:
	var state := Fixture.state("[terrain]\nSSS\n[units]\n1 s 1 0\n2 B 0 0\n2 c 2 0")
	var sub := state.units[0]
	sub.dived = true
	EndTurnCommand.new().apply(state)  # blue's turn
	var battleship := state.units[1]
	var cruiser := state.units[2]
	assert_false(
		AttackRange.can_engage(state, battleship, sub), "a battleship's guns do not reach under"
	)
	assert_true(AttackRange.can_engage(state, cruiser, sub), "a cruiser is built for exactly this")
	assert_eq(
		AttackCommand.new(cruiser, Fixture.path([Vector2i(2, 0)]), Vector2i(1, 0)).validate(state),
		""
	)


func test_surfacing_makes_the_sub_targetable_again() -> void:
	var state := Fixture.state("[terrain]\nSS\n[units]\n1 s 1 0\n2 B 0 0")
	var sub := state.units[0]
	var battleship := state.units[1]
	sub.dived = true
	assert_false(AttackRange.can_engage(state, battleship, sub))
	sub.dived = false
	assert_true(AttackRange.can_engage(state, battleship, sub))


## A boat that shot back would give itself away, so it does not — which is what
## makes attacking from under the water worth the fuel.
func test_a_dived_sub_does_not_counterattack() -> void:
	var state := Fixture.state("[terrain]\nSS\n[units]\n1 s 1 0\n2 c 0 0")
	state.rng.seed = 3
	var sub := state.units[0]
	sub.dived = true
	EndTurnCommand.new().apply(state)
	var result := CombatResolver.resolve(state, state.units[1], sub)
	assert_gt(result.attack_damage, 0, "the cruiser should have hit it")
	assert_false(result.countered)


## And the mirror: a submerged attacker is countered only by something that could
## have engaged it in the first place.
func test_only_a_hunter_counters_a_submerged_attacker() -> void:
	var state := Fixture.state("[terrain]\nSSS\n[units]\n1 s 1 0\n2 B 0 0\n2 c 2 0")
	state.rng.seed = 3
	var sub := state.units[0]
	sub.dived = true
	var against_battleship := CombatResolver.resolve(state, sub, state.units[1])
	assert_false(
		against_battleship.countered, "a battleship cannot shoot back at what it cannot see"
	)
	sub.ammo = sub.type.max_ammo
	var against_cruiser := CombatResolver.resolve(state, sub, state.units[2])
	assert_true(against_cruiser.countered, "the escort can and does")


# --- vision -------------------------------------------------------------------


## Being under the water is not a question of how far anyone can see, so unlike
## every other hiding rule this one holds in a match with no fog at all.
func test_a_dived_sub_is_hidden_without_fog() -> void:
	var state := Fixture.state("[terrain]\nSSSS\n[units]\n1 s 0 0\n2 B 3 0")
	var sub := state.units[0]
	sub.dived = true
	assert_false(state.fog_enabled, "this is the clear-weather case on purpose")
	assert_true(Vision.is_hidden_from(state, 2, sub))
	assert_false(Vision.can_see_unit(state, 2, sub, Vision.visible_cells(state, 2)))
	assert_true(
		Vision.can_see_unit(state, 1, sub, Vision.visible_cells(state, 1)),
		"its own side always knows where it is"
	)


## Hunting a submarine means closing with it: standing next to one gives it up.
func test_an_adjacent_enemy_finds_a_dived_sub() -> void:
	var state := Fixture.state("[terrain]\nSSS\n[units]\n1 s 1 0\n2 c 2 0")
	var sub := state.units[0]
	sub.dived = true
	assert_false(Vision.is_hidden_from(state, 2, sub), "the cruiser is right on top of it")
	MoveCommand.new(state.units[1], Fixture.path([Vector2i(2, 0)])).apply(state)
	assert_false(Vision.is_hidden_from(state, 2, sub))


func test_a_surfaced_sub_hides_from_nobody() -> void:
	var state := Fixture.state("[terrain]\nSSSS\n[units]\n1 s 0 0\n2 B 3 0")
	assert_false(Vision.is_hidden_from(state, 2, state.units[0]))


# --- fuel ---------------------------------------------------------------------


## Staying under costs several times what running on the surface does. That is
## the clock the whole mechanic is played against: hiding is safe and expensive.
func test_staying_under_burns_the_dived_rate() -> void:
	var state := Fixture.state("[terrain]\nSS\n[units]\n1 s 0 0")
	var sub := state.units[0]
	sub.dived = true
	assert_eq(sub.upkeep(), sub.type.dived_fuel_upkeep)
	assert_gt(sub.type.dived_fuel_upkeep, sub.type.fuel_upkeep, "a dive has to cost more than not")
	var before := sub.fuel
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	assert_eq(sub.fuel, before - sub.type.dived_fuel_upkeep)


func test_a_sub_that_stays_under_too_long_is_lost() -> void:
	var state := Fixture.state("[terrain]\nSS\n[units]\n1 s 0 0\n1 c 1 0")
	var sub := state.units[0]
	sub.dived = true
	sub.fuel = sub.type.dived_fuel_upkeep
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	assert_false(sub in state.units, "an empty tank drowns a submarine like any other hull")


# --- saves --------------------------------------------------------------------


func test_a_dive_survives_a_save() -> void:
	# The map is reloaded from res:// on the way back in and every per-board check
	# is then asked of *that* board, so the round trip is played on the real one —
	# a hand-written strait claiming the straits' path is a save whose board and
	# whose map disagree, which the codec is right to refuse.
	var state := _straits_state()
	var sub := _sub_of(state, 1)
	assert_not_null(sub, "the straits deal each fleet a submarine")
	sub.dived = true
	var encoded := SaveCodec.encode(state, [2] as Array[int])
	var loaded := SaveCodec.decode(encoded, terrain_db, unit_db, chart)
	assert_not_null(loaded)
	if loaded == null:
		return
	assert_true(_sub_of(loaded.state, 1).dived, "a submerged boat must not surface on load")


## A save written before the dive existed has no flag to read, and every boat in
## it was on the surface — which is exactly what the default gives. Built off the
## real straits board rather than a hand-written stub, for the reason the sibling
## test above gives: the save is read back against the map it names, so its units
## have to be ones that board could actually seat.
func test_an_older_save_loads_with_every_boat_on_the_surface() -> void:
	var state := _straits_state()
	var encoded := SaveCodec.encode(state, [] as Array[int])
	encoded["version"] = 2
	for entry: Dictionary in encoded["units"]:
		entry.erase("dived")
	var loaded := SaveCodec.decode(encoded, terrain_db, unit_db, chart)
	assert_not_null(loaded, "a version-2 save must still load")
	if loaded == null:
		return
	assert_false(_sub_of(loaded.state, 1).dived)


# --- the planner ----------------------------------------------------------------
#
# Two channels of water either side of a spit of land, with a battleship in the
# far one. Its guns reach across the spit and the submarine cannot row round it,
# so the boat has a dive to make and no shot to weigh against it.

## A pocket wide enough to leave the battleship's ring: the sub sits at the far
## edge of it, and one step west is out of the guns.
const OPEN_CHANNEL := "[terrain]\nSSSSSSSS.SSSSSS\n[units]\n1 s 6 0\n2 B 12 0"

## The same board with the pocket cut down to the two cells the guns already
## cover, so there is nowhere safer to go.
const CLOSED_POCKET := "[terrain]\n......SS.SSSSSS\n[units]\n1 s 6 0\n2 B 12 0"


## A tier that has bought a threat map, so `_best_refuge` has one to rank the
## dive's cells by. COM-200's zero-dial pair below plays the same two boards on
## the tier that has not.
func _threat_weighing_profile() -> AIProfile:
	var profile := AIProfile.new()
	profile.threat_aversion = 0.1
	return profile


## A dive is a whole turn, so the boat spends the movement half of it: it goes
## under somewhere the guns above cannot reach, not where it happened to be
## standing when it decided to. That needs a threat dial live to pay for the map
## the ranking reads — see the zero-dial pair below for the tier that will not.
func test_a_threatened_sub_dives_where_it_is_safer() -> void:
	var state := Fixture.state(OPEN_CHANNEL)
	var command := AIController.new(unit_db, _threat_weighing_profile()).plan_next_command(state)
	assert_true(command is DiveCommand, "expected a dive, got %s" % command)
	if not (command is DiveCommand):
		return
	assert_eq(command.validate(state), "")
	assert_true((command as DiveCommand).submerge)
	assert_eq(
		(command as DiveCommand).path,
		Fixture.path([Vector2i(6, 0), Vector2i(5, 0)]),
		"one step west is out of the battleship's ring"
	)


## And where nothing it can reach is safer, it goes under where it stands: the
## boat's own cell is in the comparison at no cost, so it holds every tie.
func test_a_sub_with_nowhere_safer_dives_in_place() -> void:
	var state := Fixture.state(CLOSED_POCKET)
	var command := AIController.new(unit_db, _threat_weighing_profile()).plan_next_command(state)
	assert_true(command is DiveCommand, "expected a dive, got %s" % command)
	if not (command is DiveCommand):
		return
	assert_eq(command.validate(state), "")
	assert_eq((command as DiveCommand).path, Fixture.path([Vector2i(6, 0)]))


# --- COM-200: a zero-dial tier does not pay for the map ------------------------
#
# threat_aversion, advance_threat_tiles and withdraw_weight are all 0.0 on Normal
# (data/ai/default.tres) — the same threatened boat above, played by the tier
# that has not bought a threat map.


## Two things have to hold at once: nothing here builds the map a lone submarine
## used to turn on for the whole turn, and the dive itself still happens — it
## just does not buy a safer cell first. With no map to rank cells by, a healthy
## direct-fire hull has nothing left that prefers one reachable cell over
## another: `_standoff_rank` only reaches an indirect unit
## (`AttackRange.is_indirect` is false for a submarine's torpedo), and a healthy
## hull has no repair cells either, so cost is the only key still live — and
## staying put is the cheapest cell there is.
func test_a_zero_dial_tier_dives_in_place_without_building_the_threat_map() -> void:
	var state := Fixture.state(OPEN_CHANNEL)
	var context := AIPlanningContext.new(unit_db)
	context.begin(state)
	var command := AIUnitActionPlanner.new(AIProfile.new()).plan_next(context)
	assert_true(command is DiveCommand, "expected a dive, got %s" % command)
	assert_false(
		context.threat_map_built(),
		"a lone submarine must not be what turns ThreatMap.build on for the whole turn"
	)
	if not (command is DiveCommand):
		return
	assert_eq(command.validate(state), "")
	assert_true((command as DiveCommand).submerge)
	assert_eq(
		(command as DiveCommand).path,
		Fixture.path([Vector2i(6, 0)]),
		"no threat dial is live, so nothing ranks the safer cell over this one"
	)


# --- what counts as a threat ----------------------------------------------------
#
# How far an enemy reaches is MovementResolver's and AttackRange's answer, and the
# dive is the one decision that used to guess it: type movement plus gun, for
# everybody. Each of these three is a board where the guess and the authorities
# disagree.

## A sea lane with a coast road beside it. The tank is eight tiles off the boat:
## six of movement and a one-tile gun leave it two cells short, and Cass Orlov's
## No Escape buys exactly the one that closes the gap.
const COAST_ROAD := "[terrain]\nSSSSSSSS\n........\n[units]\n1 s 0 0\n2 t 7 1"


## A commander's move bonus is part of how far the enemy reaches, so it is part of
## what the boat is deciding about. Read off the type instead, the doctrine is
## invisible and the sub sits on the surface waiting for a tank it never saw coming.
func test_a_sub_dives_from_a_threat_a_move_bonus_creates() -> void:
	var state := Fixture.state(COAST_ROAD)
	state.set_commander(2, Fixture.commander_db().by_id(&"cass_orlov"))
	assert_false(
		AIController.new(unit_db).plan_next_command(state) is DiveCommand,
		"without the power the tank stops a cell short of the shore"
	)
	state.commander_state(2).power_active = true
	var command := AIController.new(unit_db).plan_next_command(state)
	assert_true(command is DiveCommand, "expected a dive, got %s" % command)
	if not (command is DiveCommand):
		return
	assert_eq(command.validate(state), "")
	assert_true((command as DiveCommand).submerge)


## And the same authority from the other side: an empty tank is a shorter reach,
## so a grounded bomber is not worth burning the dive rate over.
func test_a_sub_ignores_a_bomber_with_no_fuel_to_reach_it() -> void:
	var state := Fixture.state("[terrain]\nSSSSSS\n[units]\n1 s 0 0\n2 b 5 0")
	var bomber := state.units[1]
	bomber.fuel = 2
	assert_gt(bomber.type.move_points, 4, "the type alone would cross this board")
	assert_false(
		AIController.new(unit_db).plan_next_command(state) is DiveCommand,
		"two points of fuel is two tiles, whatever the airframe is rated for"
	)


## An indirect unit cannot move and fire in the same turn, so eight tiles off a
## battleship is not a threat next turn: it has to spend one closing, and the boat
## goes under then. Adding its movement to its gun is a turn of dived upkeep spent
## on a shot nobody could have taken.
func test_a_sub_ignores_a_battleship_that_must_close_first() -> void:
	var state := Fixture.state("[terrain]\nSSSSSSSSSSSS\n[units]\n1 s 0 0\n2 B 8 0")
	assert_false(
		AIController.new(unit_db).plan_next_command(state) is DiveCommand,
		"the guns reach six; the boat has a turn in hand"
	)


# --- the whole thing at once ---------------------------------------------------


## A staged fleet action played out by both planners: the integration half, where
## the dive's four layers meet each other rather than a test fixture.
##
## The naval soak cannot cover this — it plays a real board, where whether anyone
## buys a submarine is up to production and the treasury. So the fleet is dealt
## here and only the fighting is emergent. The assertion that matters is the first
## one: a command the planner proposed and the rules then refused means two layers
## disagree, which is exactly how a half-applied targeting or vision rule shows up.
##
## Each fleet flies a bomber because on open water a battleship alone never gives
## the boat a dive to make: the guns reach six tiles and the submarine's own move
## and torpedo reach six, so anything that can shell it is something it can shoot
## instead — and a shot outscores the dive by design. The aircraft is the threat it
## has no answer to and cannot be followed under by, which is what a submarine is
## for.
func test_a_staged_fleet_action_dives_and_stays_legal() -> void:
	var state := Fixture.state(
		(
			"[terrain]\nSSSSSSSSSSSSSS\nSSSSSSSSSSSSSS\n[units]\n"
			+ "1 s 0 0\n1 B 0 1\n1 b 1 1\n2 s 13 0\n2 B 13 1\n2 b 12 1"
		)
	)
	state.rng.seed = 77
	var ai := AIController.new(unit_db)
	var dives := 0
	var commands := 0
	for i in 600:
		if state.winner != 0 or state.day > 12:
			break
		var command := ai.plan_next_command(state)
		var error := command.validate(state)
		if error != "":
			fail_test(
				"day %d: the planner proposed a command the rules reject: %s" % [state.day, error]
			)
			return
		if command is DiveCommand:
			dives += 1
		command.apply(state)
		commands += 1
	gut.p("staged fleet action: %d commands, day %d, %d dives" % [commands, state.day, dives])
	assert_lt(commands, 600, "the match never progressed — the planner is probably looping")
	assert_gt(
		dives,
		0,
		(
			"two submarines spent twelve days under an aircraft they cannot shoot "
			+ "and neither went under. The dive is either never scored or never legal."
		)
	)
