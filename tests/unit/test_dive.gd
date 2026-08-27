extends GutTest
## The submarine's own rules: the dive command, the fuel it burns down there, and
## the save that has to bring it back under.
##
## Targeting and vision are tests/unit/test_dive_detection.gd's, and what the
## computer does with the dive is tests/unit/test_dive_planner.gd's.
##
## Each of those is a place the rule could be half-implemented and look fine. A
## boat that saves and reloads on the surface loses a match's worth of position.
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
	# A dive is a move first, so the move rules answer before the hatch does.
	var moored := Fixture.state("[terrain]\nSS\n[units]\n1 s 0 0\n1 s 1 0")
	var boat := moored.units[0]
	assert_eq(
		DiveCommand.new(boat, Fixture.path([Vector2i(0, 0), Vector2i(1, 0)]), true).validate(
			moored
		),
		"destination is occupied",
		"the boat may not submerge into the one moored beside it"
	)
	boat.acted = true
	assert_eq(
		DiveCommand.new(boat, Fixture.path([Vector2i(0, 0)]), true).validate(moored),
		"unit has already acted"
	)


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
