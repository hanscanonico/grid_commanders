extends GutTest
## The two refusals every command family shares: a decided match, and a unit
## riding inside a transport.
##
## Both are stated once — `Command.decided_error` and `Command.turn_error` — and
## both were near-untested: four of the five families spelling "the match is
## over" asserted it nowhere, and "unit is being transported" had no test at all
## although every move-family command inherits it through
## `MoveCommand.validate_path_steps`.
##
## The board is built so that *every* command below is legal on it, which is what
## makes the assertions mean something: each one is asserted to pass first, so a
## later "the match is over" is the gate answering rather than some other refusal
## the command would have given anyway.

## Base, a neutral city, water for the boat, and open ground for the rest.
const BOARD := """[terrain]
BC....
SS_...
......
[owners]
1 0 0
[units]
1 i 2 0
1 t 3 0
2 t 4 0
1 t 3 2
1 t 4 2
1 p 2 2
1 i 1 2
1 s 0 1
1 p 5 2
"""

const CITY := Vector2i(1, 0)
const BASE := Vector2i(0, 0)

var _state: GameState
## Every family, by the name an assertion failure should print.
var _commands: Dictionary[String, Command] = {}
## The unit riding inside a transport, and the move-family commands built on it.
var _carried: Dictionary[String, Command] = {}


func before_each() -> void:
	_state = Fixture.state(BOARD, {1: &"alina_ward"})
	_state.funds[1] = 100000
	_state.add_charge(1, _state.commander_of(1).power_cost)
	var scout := _state.unit_at(Vector2i(2, 0))
	var gunner := _state.unit_at(Vector2i(3, 0))
	var joiner := _state.unit_at(Vector2i(3, 2))
	var wounded := _state.unit_at(Vector2i(4, 2))
	var truck := _state.unit_at(Vector2i(2, 2))
	var rifles := _state.unit_at(Vector2i(1, 2))
	var boat := _state.unit_at(Vector2i(0, 1))
	var ferry := _state.unit_at(Vector2i(5, 2))
	wounded.hp = 50
	var rider := Unit.create(Fixture.unit_db().by_id(&"infantry"), 1, ferry.cell)
	rider.carrier = ferry
	_state.units.append(rider)

	_commands = {
		"Move": MoveCommand.new(joiner, Fixture.path([joiner.cell, Vector2i(3, 1)])),
		"Attack": AttackCommand.new(gunner, Fixture.path([gunner.cell]), Vector2i(4, 0)),
		"Capture": CaptureCommand.new(scout, Fixture.path([scout.cell, CITY])),
		"Join": JoinCommand.new(joiner, Fixture.path([joiner.cell, wounded.cell])),
		"Load": LoadCommand.new(rifles, Fixture.path([rifles.cell, truck.cell])),
		"Supply": SupplyCommand.new(truck, Fixture.path([truck.cell])),
		"Dive": DiveCommand.new(boat, Fixture.path([boat.cell]), true),
		"Drop": DropCommand.new(ferry, Fixture.path([ferry.cell]), Vector2i(5, 1)),
		"Build": BuildCommand.new(1, Fixture.unit_db().by_id(&"infantry"), BASE),
		"Power": PowerCommand.new(),
		"EndTurn": EndTurnCommand.new(),
		"MissionEvent": MissionEventCommand.new(_subsidy(), 1),
	}

	var here := Fixture.path([rider.cell])
	_carried = {
		"Move": MoveCommand.new(rider, here),
		"Attack": AttackCommand.new(rider, here, Vector2i(4, 0)),
		"Capture": CaptureCommand.new(rider, here),
		"Join": JoinCommand.new(rider, here),
		"Load": LoadCommand.new(rider, here),
		"Supply": SupplyCommand.new(rider, here),
		"Dive": DiveCommand.new(rider, here, true),
		"Drop": DropCommand.new(rider, here, Vector2i(5, 1)),
	}


## The cheapest legal scripted beat: one army gets a subsidy.
func _subsidy() -> MissionEvent:
	var grant := GrantFundsEffect.new()
	grant.team = 1
	grant.amount = 500
	var event := MissionEvent.new()
	event.id = &"subsidy"
	event.effects = [grant] as Array[MissionEffect]
	return event


func test_every_command_family_is_legal_on_this_board() -> void:
	for name: String in _commands:
		assert_eq(_commands[name].validate(_state), "", "%s is legal here" % name)


func test_no_command_family_runs_once_the_match_is_decided() -> void:
	_state.winner = 1
	for name: String in _commands:
		assert_eq(
			_commands[name].validate(_state), "the match is over", "%s is refused outright" % name
		)


## The decided check comes first in `turn_error`, so a command issued by the
## wrong army on a finished board is told the match is over rather than being
## told whose turn it is.
func test_a_decided_match_outranks_the_wrong_turn() -> void:
	var enemy := _state.unit_at(Vector2i(4, 0))
	var walk := MoveCommand.new(enemy, Fixture.path([enemy.cell, Vector2i(5, 0)]))
	assert_eq(walk.validate(_state), "not this team's turn")
	_state.winner = 1
	assert_eq(walk.validate(_state), "the match is over")


func test_no_move_family_command_acts_for_a_carried_unit() -> void:
	for name: String in _carried:
		assert_eq(
			_carried[name].validate(_state),
			"unit is being transported",
			"%s refuses a passenger" % name
		)
