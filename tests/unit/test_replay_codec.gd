extends GutTest
## ReplayCodec on its own: every command class through the format and back, and
## every way a line can be one this build refuses to rebuild.
##
## The fidelity test beside this one plays a real match, which is the bar — but a
## rule-based planner never issues a Load, a Join, a Dive or a named-passenger
## Drop in eight days on one board, so the classes it does not reach are covered
## here, one at a time and by hand.

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


func _path(cells: Array) -> Array[Vector2i]:
	var typed: Array[Vector2i] = []
	for cell: Vector2i in cells:
		typed.append(cell)
	return typed


## A command through the format and back, as JSON in between — which is where a
## Vector2i stops being one and every number becomes a double.
func _round_trip(state: GameState, command: Command) -> Command:
	var json := JSON.new()
	assert_eq(json.parse(JSON.stringify(ReplayCodec.encode_command(state, command))), OK)
	return ReplayCodec.command_from(state, unit_db, json.data)


# --- one per command class -----------------------------------------------------


func test_a_move_names_its_unit_by_the_cell_it_acted_from() -> void:
	var state := _state("[terrain]\n....\n....\n[units]\n1 i 0 0")
	var mover := state.units[0]
	var path := _path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])

	var line := ReplayCodec.encode_command(state, MoveCommand.new(mover, path))
	assert_eq(line["c"], "move")
	assert_eq(line["path"], [[0, 0], [1, 0], [2, 0]])

	var rebuilt := _round_trip(state, MoveCommand.new(mover, path)) as MoveCommand
	assert_eq(rebuilt.unit, mover, "the cell it acted from is which unit it is")
	assert_eq(rebuilt.path, path)


func test_an_attack_carries_its_target_cell() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n2 i 1 0")
	var attacker := state.units[0]
	var command := AttackCommand.new(attacker, _path([Vector2i(0, 0)]), Vector2i(1, 0))
	var rebuilt := _round_trip(state, command) as AttackCommand
	assert_eq(rebuilt.unit, attacker)
	assert_eq(rebuilt.target_cell, Vector2i(1, 0))
	assert_eq(rebuilt.validate(state), "", "and it is still a legal shot")


func test_a_build_names_a_type_and_takes_its_team_from_the_board() -> void:
	var state := _state("[terrain]\nB.\n..\n[owners]\n1 0 0\n[units]\n")
	state.funds[1] = 9000
	var command := BuildCommand.new(1, unit_db.by_id(&"infantry"), Vector2i(0, 0))
	var line := ReplayCodec.encode_command(state, command)
	assert_eq(line["unit"], "infantry")
	assert_false(line.has("t"), "whose turn it is belongs to the board, never to the line")

	var rebuilt := _round_trip(state, command) as BuildCommand
	assert_eq(rebuilt.team, state.current_team)
	assert_eq(rebuilt.unit_type, unit_db.by_id(&"infantry"))
	assert_eq(rebuilt.cell, Vector2i(0, 0))


func test_a_dive_carries_which_way_the_hatch_goes() -> void:
	var state := _state("[terrain]\nSS\nSS\n[units]\n1 s 0 0")
	var boat := state.units[0]
	var down := _round_trip(state, DiveCommand.new(boat, _path([Vector2i(0, 0)]), true))
	assert_true((down as DiveCommand).submerge)
	boat.dived = true
	var up := _round_trip(state, DiveCommand.new(boat, _path([Vector2i(0, 0)]), false))
	assert_false((up as DiveCommand).submerge)


func test_a_drop_names_the_passenger_by_its_place_in_the_cargo() -> void:
	var state := _state("[terrain]\n._S\nSMS\n[units]\n1 l 1 0")
	var lander := state.units[0]
	var tank := Unit.create(unit_db.by_id(&"tank"), 1, lander.cell)
	tank.carrier = lander
	var infantry := Unit.create(unit_db.by_id(&"infantry"), 1, lander.cell)
	infantry.carrier = lander
	state.units.append(tank)
	state.units.append(infantry)

	var command := DropCommand.new(lander, _path([Vector2i(1, 0)]), Vector2i(1, 1), infantry)
	var line := ReplayCodec.encode_command(state, command)
	assert_eq(line["p"], 1, "the second rider aboard")

	var rebuilt := _round_trip(state, command) as DropCommand
	assert_eq(rebuilt.passenger, infantry, "and it must come back as that same rider")
	assert_eq(rebuilt.drop_cell, Vector2i(1, 1))
	assert_eq(rebuilt.validate(state), "", "the mountain takes the infantry, not the tank")


func test_an_unnamed_passenger_stays_unnamed() -> void:
	var state := _state("[terrain]\n._S\nSMS\n[units]\n1 l 1 0")
	var lander := state.units[0]
	var infantry := Unit.create(unit_db.by_id(&"infantry"), 1, lander.cell)
	infantry.carrier = lander
	state.units.append(infantry)

	var command := DropCommand.new(lander, _path([Vector2i(1, 0)]), Vector2i(1, 1))
	assert_eq(ReplayCodec.encode_command(state, command)["p"], ReplayCodec.NO_PASSENGER)
	assert_null(
		(_round_trip(state, command) as DropCommand).passenger,
		"a single-slot transport drops what it is carrying, and the line says no more"
	)


func test_end_turn_names_nothing_but_itself() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0")
	assert_eq(ReplayCodec.encode_command(state, EndTurnCommand.new()), {"c": "end_turn"})
	assert_true(_round_trip(state, EndTurnCommand.new()) is EndTurnCommand)


## Which side fires is the board's answer; *where* it was aimed is nobody's but
## the line's, so a power carries its target and nothing else. An unaimed power
## records the origin, which is what its command carried and what every commander
## but Radek Morn ignores.
func test_a_power_names_the_cell_it_was_aimed_at() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0")
	var aimed := PowerCommand.new()
	aimed.target = Vector2i(1, 0)
	assert_eq(ReplayCodec.encode_command(state, aimed), {"c": "power", "target": [1, 0]})
	assert_eq((_round_trip(state, aimed) as PowerCommand).target, Vector2i(1, 0))
	assert_eq(
		ReplayCodec.encode_command(state, PowerCommand.new()), {"c": "power", "target": [0, 0]}
	)
	assert_eq((_round_trip(state, PowerCommand.new()) as PowerCommand).target, Vector2i.ZERO)


func test_every_movement_command_round_trips() -> void:
	var state := _state("[terrain]\n....\n....\n[units]\n1 i 0 0\n1 i 1 0\n1 p 2 0")
	var mover := state.units[0]
	var here := _path([Vector2i(0, 0)])
	var onto_twin := _path([Vector2i(0, 0), Vector2i(1, 0)])
	var onto_apc := _path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	for pair: Array in [
		[JoinCommand.new(mover, onto_twin), "join"],
		[LoadCommand.new(mover, onto_apc), "load"],
		[SupplyCommand.new(state.units[2], here), "supply"],
		[MoveCommand.new(mover, here), "move"],
	]:
		var command: Command = pair[0]
		assert_eq(ReplayCodec.name_of(command), pair[1])
		var rebuilt := _round_trip(state, command)
		assert_eq(ReplayCodec.name_of(rebuilt), pair[1], "%s must come back as itself" % pair[1])
		assert_eq(rebuilt.get("path"), command.get("path"))


# --- lines this build refuses --------------------------------------------------


func test_a_kind_this_build_does_not_know_is_refused() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0")
	assert_null(ReplayCodec.command_from(state, unit_db, {"c": "teleport"}))
	assert_push_error("'teleport' is not a command")


func test_a_line_missing_a_field_is_refused_rather_than_guessed() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0")
	assert_null(ReplayCodec.command_from(state, unit_db, {"c": "move"}), "no path")
	assert_push_error("a move line names no path")
	assert_null(
		ReplayCodec.command_from(state, unit_db, {"c": "attack", "path": [[0, 0]]}), "no target"
	)
	assert_push_error("names no target")
	assert_null(ReplayCodec.command_from(state, unit_db, {"c": "build", "cell": [0, 0]}), "no type")
	assert_push_error("names no unit")


func test_a_line_acting_from_an_empty_cell_is_refused() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0")
	assert_null(ReplayCodec.command_from(state, unit_db, {"c": "move", "path": [[1, 0]]}))
	assert_push_error("where nothing stands")


func test_a_build_of_a_type_this_build_no_longer_has_is_refused() -> void:
	var state := _state("[terrain]\nB.\n[owners]\n1 0 0\n[units]\n")
	assert_null(
		ReplayCodec.command_from(state, unit_db, {"c": "build", "cell": [0, 0], "unit": "mecha"})
	)
	assert_push_error("unknown unit type 'mecha'")


# --- the header ----------------------------------------------------------------


func test_a_header_states_the_format_and_the_opening() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 i 0 0")
	var head := ReplayCodec.header(SaveCodec.encode(state, [2] as Array[int]), "a label", "now")
	assert_eq(ReplayCodec.header_error(head), "")
	assert_eq(head["label"], "a label")
	assert_eq(int(head["replay"]), ReplayCodec.FORMAT)


func test_a_header_that_is_not_one_says_which_part_is_missing() -> void:
	assert_string_contains(ReplayCodec.header_error({}), "replay")
	assert_string_contains(ReplayCodec.header_error({"replay": 1}), "opening")
	assert_string_contains(
		ReplayCodec.header_error({"replay": "one", "opening": {}}), "not a number"
	)


## The tripwire on the format number, in the tradition of the save version's:
## bumping it is a decision, and this is where it gets noticed. A replay is
## disposable, so the line under it is the whole migration policy — an older
## format is refused, out loud, rather than read.
func test_an_older_format_is_refused_rather_than_read() -> void:
	assert_eq(ReplayCodec.FORMAT, 2)
	assert_string_contains(ReplayCodec.header_error({"replay": 1, "opening": {}}), "format 1")
