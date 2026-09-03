extends GutTest
## The scene layer's one fog adapter, checked without a scene. `BattlePerspective`
## is a `RefCounted` that composes `Vision`, `AttackRange` and `MovementResolver`
## into viewer policy, and nothing had ever asked it a question — every rule below
## was held only by playing the board and looking.
##
## Two of them are the ones a captured frame cannot show. Omniscience is a *viewer*
## policy, so a replay must leave `fog_enabled` exactly as the match was played or
## the sim resolves the recorded moves differently. And `drop_options` deliberately
## KEEPS a cell whose only occupant the viewer cannot see: leaving it out would
## disclose the hidden unit by the shape of the offer, so `DropCommand` discovers
## it on apply instead.

## Ten plains on two rows, so a hostile fill is partly inside the viewer's sight
## and partly outside it.
const TWO_ROWS := "[terrain]\n..........\n..........\n[units]\n1 i 0 0\n2 t 6 1"

## An APC with a squad to put down, an enemy beside it and another six cells
## away — one occupant the viewer sees and one it does not.
const TRANSPORT_BOARD := "[terrain]\n.......\n.......\n[units]\n1 p 0 0\n1 i 0 1\n2 i 1 0\n2 i 6 1"

## Open water, with team 1's cruiser far enough off to leave a dive unbroken.
const SUB_AT_RANGE := "[terrain]\nSSSS\n[units]\n1 c 0 0\n2 s 3 0"

## The same water with the cruiser alongside, which is how a submarine is found.
const SUB_ALONGSIDE := "[terrain]\nSSSS\n[units]\n1 c 2 0\n2 s 3 0"


func _seen(game: GameState, team: int, blacked_out: bool = false) -> BattlePerspective:
	var perspective := BattlePerspective.new(game)
	perspective.refresh(team, blacked_out)
	return perspective


func _sorted(cells: Array[Vector2i]) -> Array[Vector2i]:
	var copy := cells.duplicate()
	copy.sort()
	return copy


# --- the Fire row's four answers ----------------------------------------------


func test_a_target_in_reach_is_offered() -> void:
	var game := Fixture.state(Fixture.TANK_VS_INFANTRY)
	var fire := _seen(game, 1).fire_targets(game.unit_at(Vector2i(0, 0)), Vector2i(0, 0), false)
	assert_eq(fire.block, BattlePerspective.FireBlock.NONE)
	assert_eq(fire.cells, [Vector2i(1, 0)] as Array[Vector2i])


## The classic new-player confusion: the artillery walked one cell and its Fire
## row disappeared. It is the indirect rule, and it now says so.
func test_an_indirect_unit_that_moved_says_moved() -> void:
	var game := Fixture.state(Fixture.ARTILLERY_VS_TANK)
	var gun := game.unit_at(Vector2i(0, 0))
	var perspective := _seen(game, 1)
	assert_eq(
		perspective.fire_targets(gun, Vector2i(1, 0), true).block, BattlePerspective.FireBlock.MOVED
	)
	assert_eq(
		perspective.fire_targets(gun, Vector2i(0, 0), false).block, BattlePerspective.FireBlock.NONE
	)


func test_a_dry_gun_says_no_ammo() -> void:
	var game := Fixture.state(Fixture.ARTILLERY_VS_TANK)
	var gun := game.unit_at(Vector2i(0, 0))
	gun.ammo = 0
	var fire := _seen(game, 1).fire_targets(gun, Vector2i(0, 0), false)
	assert_eq(fire.block, BattlePerspective.FireBlock.NO_AMMO)
	assert_true(fire.cells.is_empty())


## Ammo is `AttackRange`'s answer and not a count of shells: a Tank at zero still
## carries an infinite machine gun, so it is offered the shot rather than refused.
func test_an_empty_main_gun_with_a_secondary_still_fires() -> void:
	var game := Fixture.state(Fixture.TANK_VS_INFANTRY)
	var tank := game.unit_at(Vector2i(0, 0))
	tank.ammo = 0
	var fire := _seen(game, 1).fire_targets(tank, Vector2i(0, 0), false)
	assert_eq(fire.block, BattlePerspective.FireBlock.NONE)
	assert_eq(fire.cells, [Vector2i(1, 0)] as Array[Vector2i])


func test_an_empty_ring_says_no_target() -> void:
	var game := Fixture.state(Fixture.LONE_TANK)
	var fire := _seen(game, 1).fire_targets(game.unit_at(Vector2i(0, 0)), Vector2i(0, 0), false)
	assert_eq(fire.block, BattlePerspective.FireBlock.NO_TARGET)


## A transport has no shot to explain, which is what keeps the menu from offering
## every APC on the board a greyed row about a gun it never had.
func test_an_unarmed_hull_reads_as_unarmed() -> void:
	var game := Fixture.state("[terrain]\n..\n[units]\n1 p 0 0\n2 i 1 0")
	var fire := _seen(game, 1).fire_targets(game.unit_at(Vector2i(0, 0)), Vector2i(0, 0), false)
	assert_eq(fire.block, BattlePerspective.FireBlock.UNARMED)


# --- what the viewer may see ---------------------------------------------------


## A hot-seat handoff hides the incoming team's own pieces too, which is the whole
## point of it: the board is blank until they are the ones looking at it.
func test_a_blackout_hides_the_viewers_own_board() -> void:
	var game := Fixture.state(Fixture.TANK_VS_INFANTRY)
	var tank := game.unit_at(Vector2i(0, 0))
	var perspective := _seen(game, 1, true)
	assert_false(perspective.can_see_cell(Vector2i(0, 0)))
	assert_false(perspective.can_see_unit(tank))
	assert_null(perspective.visible_unit_at(Vector2i(0, 0)))
	perspective.refresh(1, false)
	assert_true(perspective.can_see_cell(Vector2i(0, 0)))
	assert_same(perspective.visible_unit_at(Vector2i(0, 0)), tank)


## An omniscient replay overrules the blackout and the fog for the *viewer* only.
## `fog_enabled` staying set is the load-bearing half: the sim has to resolve the
## recorded moves the way it did, ambushes and all.
func test_omniscience_leaves_the_state_fogged() -> void:
	var game := Fixture.state(Fixture.TANK_VS_INFANTRY)
	game.fog_enabled = true
	var perspective := BattlePerspective.new(game, true)
	perspective.refresh(2, true)
	assert_true(perspective.can_see_cell(Vector2i(0, 0)))
	assert_true(perspective.can_see_unit(game.unit_at(Vector2i(0, 0))))
	assert_true(game.fog_enabled, "the viewer's policy may never re-write the match")


## A dived submarine reads as empty water, so a click cannot turn a hidden unit
## into a fog probe — and closing with it is what finds it.
func test_a_dived_sub_reads_as_empty_water() -> void:
	var game := Fixture.state(SUB_AT_RANGE)
	game.unit_at(Vector2i(3, 0)).dived = true
	assert_null(_seen(game, 1).visible_unit_at(Vector2i(3, 0)))
	var alongside := Fixture.state(SUB_ALONGSIDE)
	var sub := alongside.unit_at(Vector2i(3, 0))
	sub.dived = true
	assert_same(_seen(alongside, 1).visible_unit_at(Vector2i(3, 0)), sub)


# --- the two overlays ----------------------------------------------------------


## Own side: the whole fill, fog or no fog, because the overlay has to agree cell
## for cell with what `MoveCommand` will accept.
func test_an_own_units_overlays_are_shown_whole() -> void:
	var game := Fixture.state(TWO_ROWS)
	game.fog_enabled = true
	var infantry := game.unit_at(Vector2i(0, 0))
	var perspective := _seen(game, 1)
	var reach := perspective.move_overlay_cells(infantry)
	assert_eq(_sorted(reach), _sorted(MovementResolver.reachable(game, infantry, 0, 1).cells()))
	assert_true(Vector2i(3, 0) in reach, "the fill runs past what the squad can see")
	assert_false(perspective.can_see_cell(Vector2i(3, 0)))
	assert_eq(
		_sorted(perspective.threat_overlay_cells(infantry)),
		_sorted(AttackRange.threat_cells(game, infantry, 1))
	)


## Another side's: masked to scouted ground, because the outline of a fill drawn
## over ground the viewer never walked is a report on ground it never walked.
func test_a_hostile_units_overlays_stop_at_scouted_ground() -> void:
	var game := Fixture.state(TWO_ROWS)
	game.fog_enabled = true
	var tank := game.unit_at(Vector2i(6, 1))
	var perspective := _seen(game, 1)
	var shown := perspective.move_overlay_cells(tank)
	assert_false(shown.is_empty(), "the two do overlap on this board")
	assert_lt(shown.size(), MovementResolver.reachable(game, tank, 0, 1).cells().size())
	for cell in shown:
		assert_true(perspective.can_see_cell(cell))
	for cell in perspective.threat_overlay_cells(tank):
		assert_true(perspective.can_see_cell(cell))


# --- unloading -----------------------------------------------------------------


func test_a_visible_occupant_takes_its_drop_cell_away() -> void:
	var game := _loaded_transport()
	var options := _seen(game, 1).drop_options(game.unit_at(Vector2i(0, 0)), Vector2i(0, 0))
	assert_eq(options.size(), 1)
	assert_eq(options[0].cells, [Vector2i(0, 1)] as Array[Vector2i])


## The one this suite exists for as much as the Fire row: a cell whose only
## occupant is hidden is still offered, because withholding it would announce the
## ambush. `DropCommand` refuses it on apply, where the discovery belongs.
func test_a_hidden_occupant_keeps_its_drop_cell() -> void:
	var game := _loaded_transport()
	var options := _seen(game, 1).drop_options(game.unit_at(Vector2i(0, 0)), Vector2i(6, 0))
	assert_eq(options.size(), 1)
	assert_true(Vector2i(6, 1) in options[0].cells)


## An APC at (0, 0) with the squad from (0, 1) aboard, on a fogged board — boarded
## through LoadCommand rather than by hand, so the cargo is the one the rules made.
func _loaded_transport() -> GameState:
	var game := Fixture.state(TRANSPORT_BOARD)
	var command := LoadCommand.new(
		game.unit_at(Vector2i(0, 1)), Fixture.path([Vector2i(0, 1), Vector2i(0, 0)])
	)
	assert_eq(command.validate(game), "")
	command.apply(game)
	game.fog_enabled = true
	return game
