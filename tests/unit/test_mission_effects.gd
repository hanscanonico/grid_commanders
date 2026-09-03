extends GutTest
## The four effects that move the board: what lands, what leaves, what changes
## hands and what changes sides.
##
## Two of these are rules rather than behaviour and are the reason the suite
## exists. A scripted removal **banks nothing to either meter** — charge is
## minted inside `ChargeLedger.bank_losses` and nowhere else, so paying a side
## for a beat written against it is the failure to catch. And a defection carries
## its cargo, its capture and its turn with it, each for a reason stated on
## `DefectEffect`.
##
## The four that touch no board — the two grants, the reveal and the ending —
## are `test_mission_grants.gd`'s.
##
## Every rejection asserts the exact reason string: a bare `assert_ne(error, "")`
## passes on any refusal, so a branch that started answering with its neighbour's
## message would have kept the suite green.

const FIELD := """
[terrain]
CCQ...
....BF
[owners]
1 0 0
2 1 0
2 2 0
1 4 1
[units]
1 i 3 0 courier
2 t 4 0 siege_gun
2 i 5 0 garrison
1 p 3 1 truck
"""

## The same board with a third army, so a rout can empty a seat without ending
## the match.
const THIRD_ARMY := """
[terrain]
CCQ...
....BF
[owners]
1 0 0
2 1 0
3 2 0
[units]
1 i 3 0 courier
2 t 4 0 siege_gun
3 i 5 0 garrison
"""


func _state(commanders: Dictionary = {}) -> GameState:
	return Fixture.state(FIELD, commanders)


func _map() -> MapData:
	return MapData.parse(FIELD, Fixture.terrain_db())


func _withdraw(state: GameState, tags: Array[StringName]) -> void:
	var effect := RemoveUnitsEffect.new()
	effect.tags = tags
	effect.apply(state, 1)


func _spawn(symbol: String, cell: Vector2i, tag: StringName = &"") -> MissionSpawn:
	var spawn := MissionSpawn.new()
	spawn.unit_type = Fixture.unit_db().by_symbol(symbol)
	spawn.cell = cell
	spawn.tag = tag
	return spawn


# --- reinforcements ---------------------------------------------------------


func test_spawn_lands_units_exhausted_named_and_damaged_as_authored() -> void:
	var state := _state()
	var effect := SpawnUnitsEffect.new()
	effect.team = 2
	var relief := _spawn("T", Vector2i(0, 1), &"relief")
	relief.hp = 60
	effect.units = [relief]
	effect.apply(state, 1)
	var landed := MissionObjective.tagged_unit(state, &"relief")
	assert_not_null(landed, "the column arrived")
	assert_eq(landed.team, 2)
	assert_eq(landed.hp, 60, "it has been fighting somewhere else")
	assert_true(landed.acted, "and it arrives exhausted, exactly as a built unit does")


func test_spawn_skips_a_cell_somebody_is_standing_on() -> void:
	var state := _state()
	var effect := SpawnUnitsEffect.new()
	effect.team = 2
	effect.units = [_spawn("t", Vector2i(3, 0), &"blocked"), _spawn("t", Vector2i(0, 1), &"clear")]
	effect.apply(state, 1)
	assert_null(MissionObjective.tagged_unit(state, &"blocked"), "the courier is standing there")
	assert_not_null(MissionObjective.tagged_unit(state, &"clear"), "the rest of the column lands")
	assert_eq(state.unit_at(Vector2i(3, 0)).tag, &"courier", "and nothing was cleared to make room")


func test_spawn_refuses_ground_nothing_could_land_on() -> void:
	var effect := SpawnUnitsEffect.new()
	effect.team = 2
	effect.units = [_spawn("t", Vector2i(3, 0))]
	assert_ne(
		effect.definition_error(_map(), 1, Fixture.unit_db()), "", "the board stands one there"
	)
	effect.units = [_spawn("t", Vector2i(99, 0))]
	assert_ne(effect.definition_error(_map(), 1, Fixture.unit_db()), "", "off the board")
	effect.units = [_spawn("t", Vector2i(0, 1)), _spawn("t", Vector2i(0, 1))]
	assert_ne(effect.definition_error(_map(), 1, Fixture.unit_db()), "", "two on one cell")
	effect.units = [_spawn("t", Vector2i(0, 1), &"courier")]
	assert_ne(effect.definition_error(_map(), 1, Fixture.unit_db()), "", "that name is taken")
	effect.units = [_spawn("t", Vector2i(0, 1), &"relief")]
	assert_eq(effect.definition_error(_map(), 1, Fixture.unit_db()), "")


func test_spawn_refuses_a_seat_this_match_is_not_playing() -> void:
	var state := _state()
	var effect := SpawnUnitsEffect.new()
	effect.team = 3
	effect.units = [_spawn("t", Vector2i(0, 1))]
	assert_ne(effect.board_error(state, 1), "", "army 3 is not at this table")
	effect.team = 2
	assert_eq(effect.board_error(state, 1), "")


# --- withdrawals ------------------------------------------------------------


func test_removal_takes_the_named_units_off() -> void:
	var state := _state()
	var effect := RemoveUnitsEffect.new()
	effect.tags = [&"siege_gun", &"garrison"]
	effect.apply(state, 1)
	assert_null(MissionObjective.tagged_unit(state, &"siege_gun"))
	assert_null(MissionObjective.tagged_unit(state, &"garrison"))
	assert_eq(state.units.size(), 2, "and nobody else left with them")


func test_removal_banks_nothing_to_either_meter() -> void:
	var state := _state({1: &"alina_ward", 2: &"alina_ward"})
	var purse_before: int = state.funds[2]
	var effect := RemoveUnitsEffect.new()
	effect.tags = [&"siege_gun"]
	effect.apply(state, 1)
	assert_eq(state.commander_state(1).charge, 0, "the beat is not a kill")
	assert_eq(state.commander_state(2).charge, 0, "and it is not a loss to bank either")
	assert_eq(state.funds[2] as int, purse_before, "and no bounty was taken out of the purse")


## COM-179 reached the campaign through a scripted beat: rout judged one unit at
## a time crowned whichever army the tag list emptied first and left the other
## standing on an empty board, never flagged. The batch seam judges the whole
## withdrawal at once, so reversing the tags may not move the outcome. Both
## armies on this board go into it, so nobody is left to win — the case
## `_check_victory` flags out loud rather than modelling a draw.
func test_removal_falls_every_army_it_empties_whatever_order_the_tags_read() -> void:
	var courier_first := _state()
	var garrison_first := _state()
	var tags: Array[StringName] = [&"courier", &"truck", &"siege_gun", &"garrison"]
	_withdraw(courier_first, tags.duplicate())
	assert_push_error("every remaining army fell at once")
	tags.reverse()
	_withdraw(garrison_first, tags)
	assert_push_error("every remaining army fell at once")
	for state in [courier_first, garrison_first]:
		assert_true(state.is_eliminated(1), "army 1 lost its last unit to the beat")
		assert_true(state.is_eliminated(2), "and so did army 2, in the same withdrawal")
		assert_eq(state.winner, 0, "with nobody left standing there is no side to crown")


## A rider named beside the hull it is inside is reached twice — once as the
## transport's cargo, once as its own tag — and both passes are harmless. The
## second `units.erase` finds nothing left to erase, and a passenger's stored
## cell is stale from wherever it last boarded, so `carrier != null` keeps it
## from clearing the capture somebody else is standing on there.
func test_removal_of_a_hull_and_its_own_rider_clears_no_bystander_capture() -> void:
	var state := Fixture.state(
		"[terrain]\nC..\n[units]\n1 p 1 0 truck\n1 i 2 0 courier\n2 i 0 0 sapper"
	)
	var courier := MissionObjective.tagged_unit(state, &"courier")
	courier.carrier = MissionObjective.tagged_unit(state, &"truck")
	courier.cell = Vector2i(0, 0)
	state.capture_progress[Vector2i(0, 0)] = 8
	_withdraw(state, [&"truck", &"courier"])
	assert_eq(state.units_of(1).size(), 0, "the hull and the rider both left")
	assert_eq(state.capture_progress.get(Vector2i(0, 0), 0), 8, "the rider owned no cell to lose")


func test_removal_refuses_a_name_the_board_never_gave() -> void:
	var effect := RemoveUnitsEffect.new()
	assert_eq(effect.definition_error(_map(), 1, Fixture.unit_db()), "removal names no units")
	effect.tags = [&"nobody"]
	assert_eq(
		effect.definition_error(_map(), 1, Fixture.unit_db()),
		"removal names 'nobody', which no unit on this board carries"
	)
	effect.tags = [&"garrison"]
	assert_eq(effect.definition_error(_map(), 1, Fixture.unit_db()), "")


# --- ground changing hands --------------------------------------------------


func test_set_owner_flips_the_ground_and_drops_the_capture_on_it() -> void:
	var state := _state()
	state.capture_progress[Vector2i(1, 0)] = 8
	var effect := SetOwnerEffect.new()
	effect.team = 1
	effect.cells = [Vector2i(1, 0)]
	effect.apply(state, 1)
	assert_eq(state.owner_at(Vector2i(1, 0)), 1)
	assert_false(
		state.capture_progress.has(Vector2i(1, 0)), "the points were spent against the old owner"
	)


func test_set_owner_refuses_ground_that_belongs_to_nobody() -> void:
	var effect := SetOwnerEffect.new()
	effect.team = 1
	effect.cells = [Vector2i(3, 0)]
	assert_ne(effect.definition_error(_map(), 1, Fixture.unit_db()), "", "plains has no owner")
	effect.cells = [Vector2i(0, 0)]
	assert_eq(effect.definition_error(_map(), 1, Fixture.unit_db()), "")
	effect.team = 3
	assert_ne(effect.board_error(_state(), 1), "", "army 3 is not at this table")


# --- changing sides ---------------------------------------------------------


func test_defection_moves_the_unit_exhausts_it_and_drops_its_capture() -> void:
	var state := _state()
	var garrison := MissionObjective.tagged_unit(state, &"garrison")
	garrison.cell = Vector2i(1, 0)
	garrison.acted = false
	state.capture_progress[Vector2i(1, 0)] = 8
	var effect := DefectEffect.new()
	effect.from_team = 2
	effect.to_team = 1
	effect.tags = [&"garrison"]
	effect.apply(state, 1)
	assert_eq(garrison.team, 1)
	assert_true(garrison.acted, "a beat hands nobody a free action")
	assert_false(state.capture_progress.has(Vector2i(1, 0)), "the capture was the old army's")


func test_defection_takes_the_cargo_with_the_transport() -> void:
	# `LoadCommand.carriage_error` refuses a rider of another army, and `SaveCodec`
	# asks it per carrier link — so a transport that changed sides alone would be a
	# board no save could carry.
	var state := _state()
	var truck := MissionObjective.tagged_unit(state, &"truck")
	var courier := MissionObjective.tagged_unit(state, &"courier")
	courier.carrier = truck
	courier.cell = truck.cell
	var effect := DefectEffect.new()
	effect.from_team = 1
	effect.to_team = 2
	effect.tags = [&"truck"]
	effect.apply(state, 1)
	assert_eq(truck.team, 2)
	assert_eq(courier.team, 2, "the rider went with the hull it is inside")
	assert_eq(
		LoadCommand.carriage_error(state, truck, courier), "", "and the carriage is still legal"
	)


func test_defection_leaves_a_rider_whose_carrier_stays_put() -> void:
	var state := _state()
	var courier := MissionObjective.tagged_unit(state, &"courier")
	courier.carrier = MissionObjective.tagged_unit(state, &"truck")
	var effect := DefectEffect.new()
	effect.from_team = 1
	effect.to_team = 2
	effect.tags = [&"courier"]
	effect.apply(state, 1)
	assert_eq(courier.team, 1, "it cannot change army while it is aboard")


func test_defection_does_not_rout_the_army_it_empties() -> void:
	var state := _state()
	var effect := DefectEffect.new()
	effect.from_team = 2
	effect.to_team = 1
	effect.tags = [&"siege_gun", &"garrison"]
	effect.apply(state, 1)
	assert_eq(state.units_of(2).size(), 0, "army 2 fields nothing")
	assert_false(state.is_eliminated(2), "and has still not fallen — a defection is not a rout")
	assert_eq(state.winner, 0, "so the match is not over either")


func test_defection_refuses_an_army_that_could_not_receive() -> void:
	var state := _state()
	var effect := DefectEffect.new()
	effect.from_team = 2
	effect.to_team = 2
	effect.tags = [&"garrison"]
	assert_ne(effect.definition_error(_map(), 1, Fixture.unit_db()), "", "from itself, to itself")
	effect.to_team = 1
	assert_eq(effect.definition_error(_map(), 1, Fixture.unit_db()), "")
	state.eliminate(1)
	assert_ne(effect.board_error(state, 1), "", "army 1 has already fallen")


# --- the seats an effect names ----------------------------------------------


## `named_teams` is the seat half of `board_error` asked on its own, because it
## is the half a rout can newly make true — and the campaign layer drops a beat
## on it rather than offering one that would be refused for the rest of the
## mission. The two grants are here for that question alone; what they do to the
## board is still `test_mission_grants.gd`'s.
##
## A third army, because a rout on a duel board is also a verdict, and neutral
## ground, which is no army's seat.
func test_an_effect_names_the_seats_a_rout_can_empty() -> void:
	var state := Fixture.state(THIRD_ARMY)
	var spawn := SpawnUnitsEffect.new()
	spawn.team = 3
	var ground := SetOwnerEffect.new()
	ground.team = 3
	var purse := GrantFundsEffect.new()
	purse.team = 3
	var charge := GrantChargeEffect.new()
	charge.team = 3
	var defection := DefectEffect.new()
	defection.from_team = 3
	defection.to_team = 1
	var event := MissionEvent.new()
	for effect: MissionEffect in [spawn, ground, purse, charge, defection]:
		assert_true(effect.named_teams().has(3), "army 3 is named")
		event.effects = [effect]
		assert_false(event.names_fallen_army(state), "and is still fighting")
	state.eliminate(3)
	assert_eq(state.winner, 0, "two armies are left, so the match runs on")
	for effect: MissionEffect in [spawn, ground, purse, charge, defection]:
		event.effects = [effect]
		assert_true(event.names_fallen_army(state), "and the beat is now aimed at a fallen one")
	ground.team = MapData.NEUTRAL
	event.effects = [ground, RemoveUnitsEffect.new(), null]
	assert_false(event.names_fallen_army(state), "neutral ground and a removal name no seat")
