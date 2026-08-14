extends GutTest
## Fog ambush: a unit plans its move with only what its side can see, so an enemy
## it cannot see — fogged, or a dived sub it is not standing next to — is planned
## through as if the cell were empty. The trap springs on commit: GameState
## .advance_unit cuts the move short at the last free cell before the hidden unit,
## still spends the turn, and any follow-on bound to the move (attack, capture, …)
## is dropped. No RNG anywhere: the whole mechanic is deterministic.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()


func _state(map_text: String, fog: bool = true) -> GameState:
	var state := Fixture.state(map_text)
	state.fog_enabled = fog
	return state


## Fires Sable Wren's Vanish for team 2, the doctrine that hides a unit even from
## an adjacent viewer — a hidden enemy whose position does not depend on distance.
func _vanish(state: GameState) -> void:
	state.set_commander(2, CommanderDB.load_default().by_id(&"sable_wren"))
	state.add_charge(2, state.commander_of(2).power_cost)
	state.current_team = 2
	assert_eq(PowerCommand.new().validate(state), "")
	PowerCommand.new().apply(state)
	state.current_team = 1


# --- reachability plans with the mover's knowledge ---------------------------


## An enemy the mover cannot see is planned through as if the cell were empty, so
## the movement overlay no longer has an unexplained hole where it stands.
func test_reachable_includes_a_fogged_enemy_cell() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n2 i 3 0")
	var far := state.units[1]
	assert_false(
		Vision.can_see_unit(state, 1, far, Vision.visible_cells(state, 1)),
		"the enemy three tiles off is outside infantry vision, so it is fogged"
	)
	var reach := MovementResolver.reachable(state, state.units[0])
	assert_true(reach.has(Vector2i(3, 0)), "the fogged enemy's cell is reachable")
	assert_true(reach.can_stop_at(Vector2i(3, 0)), "and looks like a place to stop")


## A visible enemy is a wall exactly as before — the fog-aware rule only frees the
## ones the mover has no way to know about.
func test_reachable_excludes_a_visible_enemy_cell() -> void:
	var state := _state("[terrain]\n......\n[units]\n1 i 0 0\n2 i 2 0")
	var reach := MovementResolver.reachable(state, state.units[0])
	assert_true(reach.has(Vector2i(1, 0)))
	assert_false(reach.has(Vector2i(2, 0)), "the enemy two tiles off is in sight and blocks")
	assert_false(reach.has(Vector2i(3, 0)), "and cannot be passed through")


# --- or with a named onlooker's knowledge ------------------------------------


## `sight_team` names whose knowledge the fill plans occupancy with. The overlay
## that previews an enemy asks for the *viewer's*, so a unit the viewer can see is
## a wall even where the mover has no idea it is there (COM-57).
func test_a_named_sight_team_walls_at_what_that_team_sees() -> void:
	var state := _state("[terrain]\n......\n[units]\n1 i 3 0\n2 i 0 0")
	var mover := state.units[1]
	assert_true(
		MovementResolver.reachable(state, mover).has(Vector2i(3, 0)),
		"the mover cannot see the picket three tiles off, so its own fill plans through it"
	)
	assert_false(
		MovementResolver.reachable(state, mover, 0, 1).has(Vector2i(3, 0)),
		"team 1 can see its own picket, so a fill keyed to team 1 stops at it"
	)


## And the reason it has to: keyed to the mover, the shape of the fill changes with
## what the mover has spotted, so a previewed outline would report which of the
## onlooker's pieces it has found. Keyed to the onlooker, it cannot.
func test_a_named_sight_team_hides_what_the_mover_has_spotted() -> void:
	var unspotted := _state("[terrain]\n......\n......\n[units]\n1 i 3 0\n2 i 0 0")
	# The same board plus a team 2 spotter next to the picket, close enough to see
	# it. Off the mover's reach, so nothing but that sighting differs.
	var spotted := _state("[terrain]\n......\n......\n[units]\n1 i 3 0\n2 i 0 0\n2 i 3 1")
	assert_ne(
		MovementResolver.reachable(unspotted, unspotted.units[1]).cells().size(),
		MovementResolver.reachable(spotted, spotted.units[1]).cells().size(),
		"the mover's own fill changes shape the moment it spots the picket"
	)
	assert_eq(
		MovementResolver.reachable(unspotted, unspotted.units[1], 0, 1).cells().size(),
		MovementResolver.reachable(spotted, spotted.units[1], 0, 1).cells().size(),
		"a fill keyed to team 1 does not, so a preview of it reports nothing"
	)


# --- the trap springs on commit ----------------------------------------------


func test_a_move_is_cut_short_at_the_hidden_enemy() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n2 i 3 0")
	var mover := state.units[0]
	var command := MoveCommand.new(
		mover, Fixture.path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])
	)
	assert_eq(
		command.validate(state), "", "a hidden occupant must not be refused — that is the probe"
	)
	command.apply(state)
	assert_true(command.ambushed, "walking onto a hidden enemy springs the trap")
	assert_eq(mover.cell, Vector2i(2, 0), "the unit stops on the last free cell before it")
	assert_true(mover.acted, "and its turn is spent")
	assert_eq(mover.fuel, mover.type.max_fuel - 2, "fuel is charged only for the two steps taken")


func test_the_attack_bound_to_an_ambushed_move_is_aborted() -> void:
	# The path stops on a hidden enemy at (3, 0); a second enemy at (3, 1) is the
	# shot it lined up. The move is cut short, so the shot never fires.
	var state := _state("[terrain]\n....\n....\n[units]\n1 i 0 0\n2 i 3 0\n2 i 3 1")
	var mover := state.units[0]
	var obstacle := state.units[1]
	var target := state.units[2]
	var command := AttackCommand.new(
		mover,
		Fixture.path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]),
		Vector2i(3, 1)
	)
	assert_eq(command.validate(state), "", "the shot is legal on paper, from the intended cell")
	command.apply(state)
	assert_true(command.ambushed)
	assert_null(command.result, "no combat was resolved")
	assert_eq(mover.cell, Vector2i(2, 0), "the attacker stopped short")
	assert_eq(target.hp, 100, "the target is untouched")
	assert_eq(obstacle.hp, 100, "and so is the hidden unit that stopped it")


func test_a_friendly_on_the_path_is_not_an_ambush() -> void:
	# Passing through a friendly is legal and never a trap: the move runs its full
	# length and nothing is cut short.
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n1 i 1 0", false)
	var mover := state.units[0]
	var command := MoveCommand.new(
		mover, Fixture.path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_false(command.ambushed)
	assert_eq(mover.cell, Vector2i(2, 0), "it passes the friendly and reaches its cell")


func test_a_capture_bound_to_an_ambushed_move_is_aborted() -> void:
	# A doctrine-cloaked enemy (hidden in woods by Vanish) sits between the
	# infantry and the city it means to take. The mover plans through it, is
	# stopped on commit, and the capture it lined up never begins.
	var state := _state("[terrain]\n.FC\n[units]\n1 i 0 0\n2 i 1 0")
	_vanish(state)
	var mover := state.units[0]
	var command := CaptureCommand.new(
		mover, Fixture.path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_true(command.ambushed)
	assert_eq(mover.cell, Vector2i(0, 0), "stopped before the cloaked enemy at (1, 0)")
	assert_false(state.capture_progress.has(Vector2i(2, 0)), "no capture was begun")


## Every move-and-then command below is staged the same way: a cloaked enemy on
## the woods at (2, 0), a path that walks past it, and the thing the command
## meant to do on the far side. The move stops at (1, 0) and the second half is
## the assertion.
func test_a_join_bound_to_an_ambushed_move_is_aborted() -> void:
	var state := _state("[terrain]\n..F.\n[units]\n1 i 0 0\n2 i 2 0\n1 i 3 0")
	_vanish(state)
	var mover := state.units[0]
	var target := state.units[2]
	target.hp = 50
	var command := JoinCommand.new(
		mover, Fixture.path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])
	)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_true(command.ambushed)
	assert_eq(mover.cell, Vector2i(1, 0), "stopped before the cloaked enemy at (2, 0)")
	assert_eq(state.units.size(), 3, "the two are still two units")
	assert_eq(mover.hp, 100, "and neither gave up its HP")
	assert_eq(target.hp, 50)
	assert_eq(target.cell, Vector2i(3, 0), "the target never moved")
	assert_false(target.acted, "nor was it exhausted by a merge that did not happen")


func test_a_load_bound_to_an_ambushed_move_is_aborted() -> void:
	var state := _state("[terrain]\n..F.\n[units]\n1 i 0 0\n2 i 2 0\n1 p 3 0")
	_vanish(state)
	var rider := state.units[0]
	var command := LoadCommand.new(
		rider, Fixture.path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])
	)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_true(command.ambushed)
	assert_null(rider.carrier, "it did not board from a distance")
	assert_eq(rider.cell, Vector2i(1, 0), "it stands on the cell the ambush stopped it at")


func test_a_drop_bound_to_an_ambushed_move_is_aborted() -> void:
	var state := _state("[terrain]\n..F.\n....\n[units]\n1 p 0 0\n2 i 2 0\n1 i 0 1")
	_vanish(state)
	var apc := state.units[0]
	var rider := state.units[2]
	rider.carrier = apc
	rider.cell = apc.cell
	var command := DropCommand.new(
		apc,
		Fixture.path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]),
		Vector2i(3, 1)
	)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_true(command.ambushed)
	assert_false(command.drop_blocked, "the drop never came up, so nothing blocked it")
	assert_eq(apc.cell, Vector2i(1, 0), "the transport stopped short")
	assert_eq(rider.carrier, apc, "its passenger is still cargo")
	assert_eq(rider.cell, apc.cell, "riding where the transport stopped")
	assert_null(state.unit_at(Vector2i(3, 1)), "and nothing was put down on the drop cell")


## The one staged with a dived submarine rather than Vanish — a boat two tiles
## off is hidden by being under the water, which is the other half of this file.
func test_a_dive_bound_to_an_ambushed_move_is_aborted() -> void:
	var state := _state("[terrain]\nSSSS\n[units]\n1 s 0 0\n2 s 2 0", false)
	state.units[1].dived = true
	var mover := state.units[0]
	var command := DiveCommand.new(
		mover, Fixture.path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]), true
	)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_true(command.ambushed)
	assert_eq(mover.cell, Vector2i(1, 0), "stopped before the submerged boat at (2, 0)")
	assert_false(mover.dived, "the hatch is as it was")


func test_a_supply_bound_to_an_ambushed_move_is_aborted() -> void:
	# Two thirsty mechs, one beside each cell: (4, 0) beside the APC's intended
	# (3, 0), so the abort is what costs it its refill rather than there being
	# nobody to refill; (1, 1) beside the cell the ambush stops the APC on, so a
	# top-up that ran from where the APC actually ended up would show here.
	var state := _state("[terrain]\n..F..\n.....\n[units]\n1 p 0 0\n2 i 2 0\n1 m 4 0\n1 m 1 1")
	_vanish(state)
	var apc := state.units[0]
	var intended := state.units[2]
	var beside_the_ambush := state.units[3]
	for mech in [intended, beside_the_ambush]:
		mech.fuel = 10
		mech.ammo = 1
	var command := SupplyCommand.new(
		apc, Fixture.path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])
	)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_true(command.ambushed)
	assert_eq(apc.cell, Vector2i(1, 0), "stopped before the cloaked enemy at (2, 0)")
	assert_true(
		command.friendlies_in_reach(state, Vector2i(3, 0)).has(intended),
		"the far mech would have been in reach from the cell the APC meant to stand on"
	)
	assert_true(
		command.friendlies_in_reach(state, apc.cell).has(beside_the_ambush),
		"and the near one is in reach from the cell it was stopped at"
	)
	assert_eq(intended.fuel, 10, "the intended mech is still short of fuel")
	assert_eq(intended.ammo, 1, "and of ammo")
	assert_eq(beside_the_ambush.fuel, 10, "and no free fuel was handed out where the APC stopped")
	assert_eq(beside_the_ambush.ammo, 1, "nor free ammo")


# --- a dived submarine, fog or no fog -----------------------------------------


## The adjacency reveal is untouched: a mover standing next to a dived sub sees
## it, so it walls — the same rule that already lets an escort hunt one down.
func test_an_adjacent_dived_sub_still_blocks() -> void:
	var state := _state("[terrain]\nSSS\n[units]\n1 s 0 0\n2 s 1 0", false)
	state.units[1].dived = true
	var reach := MovementResolver.reachable(state, state.units[0])
	assert_false(reach.has(Vector2i(1, 0)), "the boat right beside it gives it away, so it walls")


## A dived sub the mover is not next to is hidden — and now free to plan through —
## even with fog off, because being under the water is not a question of sight.
func test_a_distant_dived_sub_is_planned_through() -> void:
	var state := _state("[terrain]\nSSSS\n[units]\n1 s 0 0\n2 s 2 0", false)
	state.units[1].dived = true
	var reach := MovementResolver.reachable(state, state.units[0])
	assert_true(reach.has(Vector2i(2, 0)), "two tiles off it is hidden, so its cell plans free")
	assert_true(reach.can_stop_at(Vector2i(2, 0)))
