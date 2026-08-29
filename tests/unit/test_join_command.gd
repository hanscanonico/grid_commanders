extends GutTest
## JoinCommand on its own: what it refuses, and what a merge actually does to
## the twin that stays.
##
## Every rejection asserts the exact reason string. A join has five of them and
## four had never been reached — a bare `assert_ne(validate(), "")` passes on any
## of the five, so a branch that started answering with its neighbour's message
## would have kept the suite green.
##
## The one reason not staged here is the team half of "can only join an identical
## friendly unit": two armies' units do not merge even when allied, which is the
## four-players D2 rule and is pinned where the rest of that rule lives, in
## tests/unit/test_alliances.gd.


func _state(map_text: String, fog: bool = false) -> GameState:
	var state := Fixture.state(map_text)
	state.fog_enabled = fog
	return state


# --- the merge ----------------------------------------------------------------


func test_join_merges_and_removes_the_mover() -> void:
	var state := _state("[terrain]\n...\n[units]\n1 t 0 0\n1 t 2 0")
	var mover := state.units[0]
	var target := state.units[1]
	mover.hp = 40
	mover.ammo = 5
	target.hp = 50
	target.ammo = 6
	var command := JoinCommand.new(
		mover, Fixture.path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	)
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_false(state.units.has(mover))
	assert_eq(target.hp, 90)
	assert_eq(target.ammo, 9, "ammo caps at the type maximum")
	assert_true(target.acted)
	assert_eq(state.winner, 0, "a merge is not a death")


## Fuel adds up like HP and ammo do, and the mover brings only what it has left
## when it arrives — the walk is charged first, on the way in.
func test_a_merge_carries_the_fuel_the_mover_arrives_with() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n1 t 1 0")
	var mover := state.units[0]
	var target := state.units[1]
	mover.hp = 40
	mover.fuel = 10
	mover.ammo = 2
	target.hp = 50
	target.fuel = 20
	target.ammo = 3
	JoinCommand.new(mover, Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])).apply(state)
	assert_eq(target.fuel, 29, "one plains step off the mover's ten, then 20 + 9")
	assert_eq(target.ammo, 5)


## Everything past a type maximum evaporates: the sim tops the twin out and
## refunds nothing, which is what makes a nearly-whole pair worth keeping apart.
func test_a_merge_spills_everything_over_the_caps() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n1 t 1 0")
	var mover := state.units[0]
	var target := state.units[1]
	mover.hp = 60
	target.hp = 60
	target.fuel = 65
	target.ammo = 6
	JoinCommand.new(mover, Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])).apply(state)
	assert_eq(target.hp, 100, "120 points of HP land as 100")
	assert_eq(target.fuel, target.type.max_fuel)
	assert_eq(target.ammo, target.type.max_ammo)


## The twin is spent by the merge, and it is spent for good: a refresh power may
## not hand back the action the two of them just shared.
func test_the_twin_is_exhausted_and_cannot_be_refreshed() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n1 t 1 0")
	var target := state.units[1]
	target.hp = 50
	target.refreshable = true
	JoinCommand.new(state.units[0], Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])).apply(state)
	assert_true(target.acted)
	assert_false(target.refreshable)


## Only the mover has to be unspent: a twin that already took its turn is still
## a place to put a wounded unit, and it stays spent afterwards.
func test_a_spent_twin_can_still_be_merged_into() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n1 t 1 0")
	var mover := state.units[0]
	var target := state.units[1]
	mover.hp = 40
	target.hp = 50
	target.acted = true
	var command := JoinCommand.new(mover, Fixture.path([Vector2i(0, 0), Vector2i(1, 0)]))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(target.hp, 90, "the mover's points land on the twin")
	assert_true(target.acted, "which is still done for the turn")
	assert_false(state.units.has(mover), "and the mover is gone")


# --- the five refusals ---------------------------------------------------------


func test_join_answers_the_move_rules_first() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n1 t 1 0")
	state.units[0].acted = true
	assert_eq(
		JoinCommand.new(state.units[0], Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])).validate(
			state
		),
		"unit has already acted"
	)


func test_join_rejects_an_empty_destination() -> void:
	var state := _state(Fixture.LONE_TANK)
	assert_eq(
		JoinCommand.new(state.units[0], Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])).validate(
			state
		),
		"no unit to join at the destination"
	)


## Standing still is the Wait action, never a merge with yourself.
func test_join_rejects_a_unit_joining_itself() -> void:
	var state := _state(Fixture.LONE_TANK)
	assert_eq(
		JoinCommand.new(state.units[0], Fixture.path([Vector2i(0, 0)])).validate(state),
		"no unit to join at the destination"
	)


func test_join_rejects_a_different_unit_type() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n1 r 1 0")
	state.units[1].hp = 50
	assert_eq(
		JoinCommand.new(state.units[0], Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])).validate(
			state
		),
		"can only join an identical friendly unit"
	)


func test_join_rejects_a_target_at_full_strength() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n1 t 1 0")
	assert_eq(
		JoinCommand.new(state.units[0], Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])).validate(
			state
		),
		"target is at full strength"
	)


## Cargo has nowhere to go when its hull disappears, so a loaded transport is
## refused from either end of the merge.
func test_join_rejects_transports_carrying_cargo() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 p 0 0\n1 p 2 0\n1 i 3 0")
	var mover := state.units[0]
	var target := state.units[1]
	var rider := state.units[2]
	mover.hp = 50
	target.hp = 50
	var walk := Fixture.path([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	LoadCommand.new(rider, Fixture.path([Vector2i(3, 0), Vector2i(2, 0)])).apply(state)
	assert_eq(
		JoinCommand.new(mover, walk).validate(state),
		"cannot join transports with cargo",
		"the twin standing still is carrying somebody"
	)
	rider.carrier = mover
	rider.cell = mover.cell
	assert_eq(
		JoinCommand.new(mover, walk).validate(state),
		"cannot join transports with cargo",
		"and so is the one walking"
	)


# --- the ambush ---------------------------------------------------------------


## The trap springs on commit like it does for an attack or a capture: the walk
## is cut short before the twin, so there is no merge and both units survive.
func test_an_ambushed_join_never_merges() -> void:
	var state := _state("[terrain]\n.....\n[units]\n1 p 0 0\n2 i 2 0\n1 p 4 0", true)
	var mover := state.units[0]
	var target := state.units[2]
	target.hp = 50
	var command := JoinCommand.new(
		mover,
		Fixture.path(
			[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
		)
	)
	assert_eq(
		command.validate(state), "", "the hidden enemy must not be refused — that is the probe"
	)
	command.apply(state)
	assert_true(command.ambushed)
	assert_true(state.units.has(mover), "the mover is still on the board")
	assert_eq(mover.cell, Vector2i(1, 0), "stopped on the last free cell before the hidden enemy")
	assert_eq(target.hp, 50, "and the twin it never reached is untouched")
	assert_false(target.acted)
