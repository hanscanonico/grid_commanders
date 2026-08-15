extends GutTest
## What standing together means, asked of the one allegiance authority (COM-45,
## four-players plan FP2/D2).
##
## The menu's seat strip and `--sides=` both write `sides`, but these fixtures set
## it directly so the authority is asked without walking a menu to reach a
## grouping. Every case below has a free-for-all twin that shows the same board
## answering the way it always did.
##
## Allies share sight and purpose: they cannot shoot or capture each other, they
## walk through each other, and they never spring an ambush. They never share
## infrastructure — funds, production, repair, resupply, joining and transports
## stay each army's own, which the last group here pins.

## The defensive doctrine both gating cases below are measured with.
const MARA_VOSS := "res://data/commanders/mara_voss.tres"

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()


## A board with `sides` applied. `allies` is a list of teams sharing side 0; every
## other army is left ungrouped, which makes it its own side.
func _state(map_text: String, allies: Array = []) -> GameState:
	var state := Fixture.state(map_text)
	for team: int in allies:
		state.sides[team] = 0
	return state


# --- the authority itself ----------------------------------------------------


## The empty grouping has to answer exactly what `a == b` answered, because that
## is the expression it replaced at every routed site. Everything else in this
## file rests on it.
func test_a_free_for_all_makes_every_army_its_own_side() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n4 i 3 0")
	assert_true(state.sides.is_empty(), "no grouping is the default")
	for a in state.teams:
		for b in state.teams:
			assert_eq(state.allied(a, b), a == b, "team %d and team %d" % [a, b])
		assert_eq(state.side_of(a), [a] as Array[int])
	assert_eq(state.enemies_of(1), [2, 3, 4] as Array[int])


func test_a_grouping_makes_a_side_of_its_members() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n4 i 3 0", [1, 3])
	assert_true(state.allied(1, 3), "grouped armies stand together")
	assert_true(state.allied(3, 1), "and it reads the same either way round")
	assert_false(state.allied(1, 2), "an ungrouped army stands alone")
	assert_false(state.allied(2, 4), "two ungrouped armies are not a side")
	assert_eq(state.side_of(1), [1, 3] as Array[int], "seat order, itself included")
	assert_eq(state.enemies_of(1), [2, 4] as Array[int])
	assert_eq(state.enemies_of(2), [1, 3, 4] as Array[int], "3v1 seen from the one")


# --- shooting and taking ground ----------------------------------------------


func test_an_ally_cannot_be_fired_on() -> void:
	const BOARD := "[terrain]\n....\n[units]\n1 t 0 0\n2 i 1 0"
	var attack := func(state: GameState) -> String:
		return (
			AttackCommand
			. new(state.units[0], Fixture.path([Vector2i(0, 0)]), Vector2i(1, 0))
			. validate(state)
		)
	assert_eq(attack.call(_state(BOARD)), "", "a free-for-all rival is a target")
	assert_eq(
		attack.call(_state(BOARD, [1, 2])),
		"cannot attack a unit on your own side",
		"an ally is not"
	)


func test_an_allys_property_is_not_capturable_but_neutral_ground_still_is() -> void:
	const BOARD := "[terrain]\nCC\n[owners]\n2 0 0\n[units]\n1 i 0 0"
	# Standing still on the rival's city, then stepping onto the neutral one.
	var here := Fixture.path([Vector2i(0, 0)])
	var next_door := Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])
	var capture := func(state: GameState, at: Array[Vector2i]) -> String:
		return CaptureCommand.new(state.units[0], at).validate(state)
	assert_eq(capture.call(_state(BOARD), here), "", "a rival's ground is takeable")
	assert_eq(
		capture.call(_state(BOARD, [1, 2]), here),
		"property already held by your side",
		"an ally's is not"
	)
	assert_eq(
		capture.call(_state(BOARD, [1, 2]), next_door),
		"",
		"neutral ground stays open — team 0 stands with nobody"
	)


# --- moving through each other -----------------------------------------------


## A rival is a wall; an ally is walked through exactly like your own units. Both
## still block *stopping*, which is what keeps two units off one cell.
func test_an_ally_is_walked_through_but_not_stopped_on() -> void:
	const BOARD := "[terrain]\n....\n[units]\n1 i 0 0\n2 i 1 0"
	var through := Fixture.path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	var onto := Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])
	var rivals := _state(BOARD)
	assert_eq(
		MoveCommand.new(rivals.units[0], through).validate(rivals),
		"path is blocked by an enemy",
		"a rival walls the path"
	)
	var allies := _state(BOARD, [1, 2])
	assert_eq(MoveCommand.new(allies.units[0], through).validate(allies), "", "an ally does not")
	assert_eq(
		MoveCommand.new(allies.units[0], onto).validate(allies),
		"destination is occupied",
		"but nobody stands on anybody"
	)


## The flood fill and the command have to agree cell for cell — a preview that
## offered a cell the command then refused is the bug this repo already paid for.
func test_the_movement_fill_walks_past_an_ally_and_refuses_to_stop_there() -> void:
	const BOARD := "[terrain]\n....\n[units]\n1 i 0 0\n2 i 1 0"
	var reach := MovementResolver.reachable(_state(BOARD, [1, 2]), _state(BOARD).units[0])
	assert_true(reach.costs.has(Vector2i(2, 0)), "the cell beyond an ally is reachable")
	assert_false(reach.stoppable[Vector2i(1, 0)], "the ally's own cell is not")
	var walled := MovementResolver.reachable(_state(BOARD), _state(BOARD).units[0])
	assert_false(walled.costs.has(Vector2i(2, 0)), "a rival walls the same fill")


## `advance_unit` cuts a move short at an enemy the mover could not see. An ally
## is never that enemy, whatever the fog.
func test_an_ally_never_springs_an_ambush() -> void:
	const BOARD := "[terrain]\n....\n[units]\n1 i 0 0\n2 i 1 0"
	var allies := _state(BOARD, [1, 2])
	allies.fog_enabled = true
	assert_false(
		allies.advance_unit(
			allies.units[0], Fixture.path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
		),
		"walking past an ally is not an ambush"
	)
	assert_eq(allies.units[0].cell, Vector2i(2, 0), "and the move runs its full length")
	var rivals := _state(BOARD)
	rivals.fog_enabled = true
	assert_true(
		rivals.advance_unit(
			rivals.units[0], Fixture.path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
		),
		"an unseen rival still does"
	)


# --- shared sight ------------------------------------------------------------


## A side sees as one. Composed inside Vision, so every caller that asks about a
## viewer — the overlays, BattlePerspective, the AI's fog-limited pathing —
## inherits it without composing anything itself.
func test_allies_share_one_fog() -> void:
	const BOARD := "[terrain]\n..........\n..........\n[units]\n1 i 0 0\n2 i 9 1"
	var far := Vector2i(9, 1)
	var alone := _state(BOARD)
	alone.fog_enabled = true
	assert_false(Vision.visible_cells(alone, 1).has(far), "team 1 alone cannot see that far")
	var allies := _state(BOARD, [1, 2])
	allies.fog_enabled = true
	assert_true(Vision.visible_cells(allies, 1).has(far), "its ally's eyes reach it")
	assert_true(
		Vision.visible_cells(allies, 2).has(Vector2i(0, 0)),
		"and the union reads the same from the other seat"
	)


func test_an_ally_is_never_hidden_and_never_jammed() -> void:
	const BOARD := "[terrain]\nSSSSSSSSS.\n[units]\n1 s 0 0\n2 i 9 0"
	var allies := _state(BOARD, [1, 2])
	allies.fog_enabled = true
	allies.units[0].dived = true
	assert_false(
		Vision.is_hidden_from(allies, 2, allies.units[0]),
		"a side does not lose track of its own submarine"
	)
	var rivals := _state(BOARD)
	rivals.fog_enabled = true
	rivals.units[0].dived = true
	assert_true(Vision.is_hidden_from(rivals, 2, rivals.units[0]), "a rival's is under the water")


# --- doctrine ----------------------------------------------------------------


## The powers that fire on being attacked used to be gated against "the first
## team that is not this one". With three armies that is one arbitrary rival, so
## a commander could sit on a full meter while the army actually closing on her
## walked in from the other side.
func test_a_defensive_power_is_gated_against_every_rival_not_the_first() -> void:
	# Team 2 is out of everyone's reach; team 3's tank is on top of team 1.
	const BOARD := "[terrain]\n..........\n[units]\n1 i 0 0\n2 i 9 0\n3 t 1 0"
	var state := _state(BOARD)
	var mara: CommanderType = load(MARA_VOSS)
	state.set_commander(1, mara)
	assert_true(mara.wants_power(state, 1), "the third army's guns count")
	# Regrouped so team 3 stands with her, nobody left in reach is hostile.
	var friendly := _state(BOARD, [1, 3])
	friendly.set_commander(1, mara)
	assert_false(mara.wants_power(friendly, 1), "an ally's guns do not")


## The mirror of the case above, and the one a single "is anyone in a fight?"
## filter got wrong: two rivals brawling at the far end of the board is not a
## threat to a third army nobody can reach.
func test_a_defensive_power_ignores_a_fight_between_two_other_armies() -> void:
	# Teams 2 and 3 are on top of each other, and both are a board away from team 1.
	const BOARD := "[terrain]\n....................\n[units]\n1 i 0 0\n2 t 18 0\n3 t 19 0"
	var state := _state(BOARD)
	var mara: CommanderType = load(MARA_VOSS)
	assert_false(mara.wants_power(state, 1), "a fight she is not in is not her fight")
	assert_true(mara.wants_power(state, 2), "the army actually in range of one does want it")


## The doctrines measured in capture points ask the same question `CaptureCommand`
## answers, so they have to get the same answer: ground an ally already holds is
## not ground to march on, and a power spent reaching it buys nothing.
func test_a_capture_power_does_not_march_on_an_allys_ground() -> void:
	# The infantry stands on its own city; the only other property is team 2's.
	const BOARD := "[terrain]\nCC..\n[owners]\n2 0 0\n1 1 0\n[units]\n1 i 1 0"
	var tomas: CommanderType = load("res://data/commanders/tomas_reed.tres")
	assert_true(tomas.wants_power(_state(BOARD), 1), "a rival's city is ground to take")
	assert_false(tomas.wants_power(_state(BOARD, [1, 2]), 1), "an ally's is already the side's")


## Signal Jam is the one power that reaches across the table, and both of its
## halves have to agree on where the table ends. Sight asks the authority through
## Vision's hostile loop; movement has to ask it too, through move_budget's.
func test_a_jamming_power_slows_a_rival_and_leaves_an_ally_alone() -> void:
	const BOARD := "[terrain]\n====\n[units]\n1 r 0 0\n2 t 2 0\n3 t 3 0"
	var orin: OrinFlux = load("res://data/commanders/orin_flux.tres")
	var jam := func(state: GameState) -> void:
		state.set_commander(1, orin)
		state.add_charge(1, orin.power_cost)
		var command := PowerCommand.new()
		assert_eq(command.validate(state), "", "the meter is full and the power is legal")
		command.apply(state)
	var allies := _state(BOARD, [1, 3])
	var rival := allies.units[1]
	var ally := allies.units[2]
	var full_move := ally.type.move_points
	jam.call(allies)
	assert_eq(MovementResolver.move_budget(allies, rival), full_move - 1, "a rival is slowed")
	assert_eq(MovementResolver.move_budget(allies, ally), full_move, "an ally keeps its points")
	# The twin: with nobody allied, the same third army is jammed like any other.
	var rivals := _state(BOARD)
	jam.call(rivals)
	assert_eq(MovementResolver.move_budget(rivals, rivals.units[2]), full_move - 1, "a point goes")


# --- deliberately not shared -------------------------------------------------


## Allies share sight and purpose, never infrastructure (D2). Each of these is a
## place an ally might plausibly be expected and deliberately is not.
func test_allies_share_no_infrastructure() -> void:
	var state := _state("[terrain]\nCC\n[owners]\n2 0 0\n[units]\n1 i 0 0\n2 i 1 0", [1, 2])
	state.funds[1] = 5000
	state.funds[2] = 0
	assert_eq(state.funds[2], 0, "an ally's treasury is its own")
	assert_eq(
		JoinCommand.new(state.units[0], Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])).validate(
			state
		),
		"can only join an identical friendly unit",
		"two armies' units do not merge"
	)
	var lander := Unit.create(unit_db.by_symbol("l"), 2, Vector2i(1, 0))
	assert_ne(
		LoadCommand.carriage_error(state, lander, state.units[0]),
		"",
		"and one army's rider does not board another's hull"
	)
	# Team 1's infantry stands on team 2's city; a wounded unit is not repaired
	# there, because services stay `owner == unit.team`.
	state.units[0].hp = 50
	TurnRules.begin_turn(state)
	assert_eq(state.units[0].hp, 50, "an ally's city does not repair your infantry")
