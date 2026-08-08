extends GutTest
## The carried army (campaign-depth D6): losses stop being erased between the
## missions of a chain, and force size never moves.
##
## The rule the whole milestone is: **a carry slot always ends up occupied by
## exactly one unit of the type the board authored.** Every test below is a way of
## asking that — with a roster, without one, with a roster of the wrong shape, and
## after three missions of accumulated damage — because the moment it stops being
## true, 108 boards nobody is going to re-balance are being played with armies
## nobody authored.
##
## The short-roster fallback is the common case rather than the edge: 106 of the
## 108 missions carry nothing, so the path where the map's own unit stands is the
## one almost every mission takes.

const PROBE := &"__probe_roster_campaign"
## The board's tank slot, which is the unit these tests follow through the war.
const TANK_SLOT := Vector2i(2, 1)

## Team 1 opens with two infantry slots, a tank slot and an infantry the board
## keeps for itself; team 1 already owns (0,0), so a mission whose objective is
## that cell is won on the first board it is asked about.
const LINE := """
[terrain]
C...Q
.....
[owners]
1 0 0
2 4 0
[units]
1 i 0 1 ^
1 i 1 1 ^
1 t 2 1 ^
1 i 3 1
2 i 4 1
"""

## The same board with the enemy's own row marked as well — a slip a mission is
## refused for, and one `deploy` ignores whatever the lint says.
const RIVAL_SLOT := """
[terrain]
C...Q
.....
[owners]
1 0 0
2 4 0
[units]
1 i 0 1 ^
2 i 4 1 ^
"""

## A named carry slot, and a name already spoken for on the same board.
const NAMED := """
[terrain]
C...Q
.....
[owners]
1 0 0
2 4 0
[units]
1 i 0 1 ^
1 t 2 1 relay ^
1 i 3 1 courier
2 i 4 1
"""


func before_each() -> void:
	CampaignSession.clear()
	CampaignProfile.erase(PROBE)


func after_each() -> void:
	CampaignSession.clear()
	CampaignProfile.erase(PROBE)


func _carried(unit_id: StringName, hp: int, tag: StringName = &"") -> CarriedUnit:
	return CarriedUnit.new(unit_id, hp, tag)


func _roster(entries: Array) -> Array[CarriedUnit]:
	var carried: Array[CarriedUnit] = []
	for entry: CarriedUnit in entries:
		carried.append(entry)
	return carried


## `cell -> "<type> <hp>"` for one team, which is what "the army the board fields"
## means here: the types and where they stand, and then their condition.
func _army(state: GameState, team: int) -> Dictionary:
	var army := {}
	for unit in state.units_of(team):
		army[unit.cell] = "%s %d" % [unit.type.id, unit.hp]
	return army


func _mission(id: StringName) -> MissionDefinition:
	var mission := MissionDefinition.new()
	mission.id = id
	mission.title = String(id)
	mission.map_path = "res://maps/first_steps.txt"
	mission.player_team = 1
	var objective := CaptureCellObjective.new()
	objective.cell = Vector2i(0, 0)
	mission.objectives.append(objective)
	return mission


func _campaign(ids: Array = [&"probe_one", &"probe_two", &"probe_three"]) -> CampaignDefinition:
	var campaign := CampaignDefinition.new()
	campaign.id = PROBE
	campaign.title = "Probe"
	for id: StringName in ids:
		campaign.missions.append(_mission(id))
	return campaign


## The board a mission opens on, opened the way the live scene opens it: the
## carried army stands in the board's carry slots, and the tally takes what
## results as its baseline.
func _deploy(
	campaign: CampaignDefinition, mission: MissionDefinition, progress: CampaignState
) -> GameState:
	CampaignSession.begin(campaign, mission, progress)
	var state := Fixture.state(LINE)
	CampaignSession.deploy_army(state)
	CampaignSession.open_board(state)
	return state


## That mission won, with the fight having left the army in whatever condition
## `wound` says — `cell -> hp`, which is what the next mission carries.
func _win(state: GameState, wound: Dictionary = {}) -> void:
	for cell: Vector2i in wound:
		state.unit_at(cell).hp = wound[cell]
	assert_true(CampaignSession.decide(state), "the fixture objective is met at the opening")
	CampaignSession.record(state)


# --- the slots -----------------------------------------------------------------


## The path 106 of the 108 shipped missions take, and the one that has to be
## cheapest to be right: nothing carried, so every slot keeps its own unit.
func test_a_board_with_no_army_to_carry_opens_exactly_as_authored() -> void:
	var state := Fixture.state(LINE)
	var authored := _army(state, 1)
	CampaignRoster.deploy(state, 1, [] as Array[CarriedUnit], 0)
	assert_eq(_army(state, 1), authored)


func test_a_veteran_stands_in_a_slot_of_its_own_type_and_nothing_else_moves() -> void:
	var state := Fixture.state(LINE)
	CampaignRoster.deploy(state, 1, _roster([_carried(&"tank", 40)]), 0)
	assert_eq(
		_army(state, 1),
		{
			Vector2i(0, 1): "infantry 100",
			Vector2i(1, 1): "infantry 100",
			Vector2i(2, 1): "tank 40",
			Vector2i(3, 1): "infantry 100",
		}
	)


## The type is what identifies a veteran across the gap, so a board that authored
## no slot for one fields its own army and the veteran simply does not deploy.
func test_a_veteran_the_board_authored_no_slot_for_stands_nowhere() -> void:
	var state := Fixture.state(LINE)
	var authored := _army(state, 1)
	CampaignRoster.deploy(state, 1, _roster([_carried(&"mech", 30), _carried(&"recon", 30)]), 0)
	assert_eq(_army(state, 1), authored)


## Slots are filled in board order and each takes one veteran, so a roster shorter
## than the slots leaves the rest of the board at full strength — which is the
## whole of "losses hurt, and the army is never smaller".
func test_each_slot_takes_one_veteran_and_a_short_roster_leaves_the_rest_fresh() -> void:
	var state := Fixture.state(LINE)
	CampaignRoster.deploy(state, 1, _roster([_carried(&"infantry", 60)]), 0)
	assert_eq(state.unit_at(Vector2i(0, 1)).hp, 60, "the first slot in board order")
	assert_eq(state.unit_at(Vector2i(1, 1)).hp, 100, "and the second has nothing left to take")
	assert_eq(state.unit_at(Vector2i(3, 1)).hp, 100, "the board's own unit was never a slot")


func test_a_slot_on_another_army_is_never_the_players_to_fill() -> void:
	var state := Fixture.state(RIVAL_SLOT)
	CampaignRoster.deploy(state, 1, _roster([_carried(&"infantry", 25)]), 0)
	assert_eq(state.unit_at(Vector2i(0, 1)).hp, 25, "ours")
	assert_eq(state.unit_at(Vector2i(4, 1)).hp, 100, "and theirs is not part of our war")


# --- the floor (R1) ------------------------------------------------------------


## The author's answer to a death spiral, and it only ever mends: a mission
## declares the worst a veteran may land at, and a healthier one keeps its HP.
func test_the_floor_is_the_worst_a_veteran_lands_at() -> void:
	var state := Fixture.state(LINE)
	CampaignRoster.deploy(state, 1, _roster([_carried(&"tank", 20)]), 60)
	assert_eq(state.unit_at(TANK_SLOT).hp, 60, "refit to the floor")
	state = Fixture.state(LINE)
	CampaignRoster.deploy(state, 1, _roster([_carried(&"tank", 80)]), 60)
	assert_eq(state.unit_at(TANK_SLOT).hp, 80, "and never refit down to it")

	# `_carry_error` refuses a floor above full strength, but it is only ever asked
	# by `make campaigns`, so the board is what guarantees it: `Unit` is the one
	# authority on how healthy a unit can be and nothing authored may outbid it.
	state = Fixture.state(LINE)
	CampaignRoster.deploy(state, 1, _roster([_carried(&"tank", 20)]), Unit.MAX_HP + 40)
	assert_eq(state.unit_at(TANK_SLOT).hp, Unit.MAX_HP, "and never past full strength")


# --- the names -----------------------------------------------------------------


## A name carries with the unit that earned it, and the board's own names are the
## mission's — an objective can only name what the board authored — so a carried
## name fills what the board left unnamed, yields to a slot that is already named,
## and can never end up on two units at once.
func test_a_carried_name_fills_only_what_the_board_left_unnamed() -> void:
	var state := Fixture.state(NAMED)
	CampaignRoster.deploy(state, 1, _roster([_carried(&"infantry", 70, &"vanguard")]), 0)
	assert_eq(state.unit_at(Vector2i(0, 1)).tag, &"vanguard", "the slot the board left unnamed")

	state = Fixture.state(NAMED)
	var carried := _roster(
		[_carried(&"tank", 50, &"iron_lance"), _carried(&"infantry", 50, &"courier")]
	)
	CampaignRoster.deploy(state, 1, carried, 0)
	assert_eq(state.unit_at(TANK_SLOT).tag, &"relay", "a slot the board named keeps its name")
	assert_eq(state.unit_at(Vector2i(0, 1)).tag, &"", "and one already in use is not taken twice")
	assert_eq(state.unit_at(Vector2i(3, 1)).tag, &"courier", "by the unit that has it")


# --- banking -------------------------------------------------------------------


func test_banking_records_what_survived_in_board_order() -> void:
	var state := Fixture.state(LINE)
	state.unit_at(Vector2i(1, 1)).hp = 30
	state.remove_unit(state.unit_at(Vector2i(0, 1)))
	var carried := CampaignRoster.bank(state, 1)
	assert_eq(carried.size(), 3, "the dead are simply not in it")
	assert_eq(carried[0].unit_id, &"infantry")
	assert_eq(carried[0].hp, 30)
	assert_eq(carried[1].unit_id, &"tank")
	assert_eq(carried[2].unit_id, &"infantry")


## What a transport was carrying is a fact about a board that is over: the rider
## banks as itself and rides nothing into the next mission.
func test_cargo_banks_as_itself() -> void:
	var state := Fixture.state(LINE)
	var rider := state.unit_at(Vector2i(3, 1))
	rider.carrier = state.unit_at(TANK_SLOT)
	var carried := CampaignRoster.bank(state, 1)
	assert_eq(carried.size(), 4, "a rider is one of the army")
	assert_eq(carried[3].unit_id, &"infantry")


# --- the profile ---------------------------------------------------------------


func test_the_carried_army_survives_a_round_trip() -> void:
	var state := CampaignState.begin(_campaign())
	state.roster = _roster([_carried(&"tank", 40, &"iron_lance"), _carried(&"infantry", 100)])
	var decoded := CampaignSaveCodec.decode(CampaignSaveCodec.encode(state))
	assert_not_null(decoded)
	assert_eq(decoded.roster.size(), 2)
	assert_eq(decoded.roster[0].unit_id, &"tank")
	assert_eq(decoded.roster[0].hp, 40)
	assert_eq(decoded.roster[0].tag, &"iron_lance")
	assert_eq(decoded.roster[1].tag, &"", "and a unit nobody named carries forward unnamed")


func test_a_profile_from_before_the_carried_army_opens_with_none() -> void:
	var older := CampaignSaveCodec.encode(CampaignState.begin(_campaign()))
	older["version"] = 3
	older.erase("roster")
	assert_eq(CampaignSaveCodec.validate(older), "", "a version 3 profile is still a profile")
	var decoded := CampaignSaveCodec.decode(older)
	assert_not_null(decoded)
	assert_eq(decoded.roster.size(), 0, "which is what it was playing with")


## The compatibility promise reads one way only, exactly as the ledger's does: a
## profile older than the section may carry no army at all.
func test_a_profile_older_than_the_carried_army_may_not_hold_one() -> void:
	var older := CampaignSaveCodec.encode(CampaignState.begin(_campaign()))
	older["version"] = 3
	older["roster"] = [{"unit": "tank", "hp": 40, "tag": ""}]
	assert_string_contains(CampaignSaveCodec.validate(older), "the carried army arrived in")
	older["roster"] = []
	assert_eq(CampaignSaveCodec.validate(older), "", "and an empty section carries no army at all")


func test_a_carried_army_no_writer_could_have_produced_is_refused() -> void:
	var data := CampaignSaveCodec.encode(CampaignState.begin(_campaign()))
	data["roster"] = [{"unit": "tank", "hp": 0, "tag": ""}]
	assert_ne(CampaignSaveCodec.validate(data), "", "a dead unit did not survive anything")
	data["roster"] = [{"unit": "tank", "hp": 140, "tag": ""}]
	assert_ne(CampaignSaveCodec.validate(data), "", "and none of them came back stronger")
	data["roster"] = [{"unit": "tank", "hp": 40, "tag": "iron lance"}]
	assert_ne(CampaignSaveCodec.validate(data), "", "a name is an identifier")
	data["roster"] = [{"hp": 40}]
	assert_ne(CampaignSaveCodec.validate(data), "", "and a veteran is always something")
	data["roster"] = [{"unit": {}, "hp": 40, "tag": ""}]
	assert_ne(CampaignSaveCodec.validate(data), "", "a type is a name rather than a shape")
	data["roster"] = [{"unit": "tank", "hp": {}, "tag": ""}]
	assert_ne(CampaignSaveCodec.validate(data), "", "a condition is a number")
	data["roster"] = [{"unit": "tank", "hp": "40", "tag": ""}]
	assert_ne(CampaignSaveCodec.validate(data), "", "and one written as text was never one")
	data["roster"] = [{"unit": "tank", "hp": 40, "tag": []}]
	assert_ne(CampaignSaveCodec.validate(data), "", "a name is text or it is nothing")
	data["roster"] = [{"unit": "siege_walker", "hp": 40, "tag": ""}]
	assert_eq(
		CampaignSaveCodec.validate(data),
		"",
		"but a retired unit type costs itself a slot, not the war"
	)


# --- the chain -----------------------------------------------------------------


func test_a_mission_that_carries_nothing_in_opens_as_authored() -> void:
	var campaign := _campaign()
	var progress := CampaignState.begin(campaign)
	progress.roster = _roster([_carried(&"tank", 10)])
	CampaignSession.begin(campaign, campaign.missions[0], progress)
	var state := Fixture.state(LINE)
	CampaignSession.deploy_army(state)
	assert_eq(state.unit_at(TANK_SLOT).hp, 100, "a commander change is a different army")


func test_a_mission_that_carries_nothing_out_ends_the_chain() -> void:
	var campaign := _campaign()
	campaign.missions[0].carry_out = false
	var progress := CampaignState.begin(campaign)
	progress.roster = _roster([_carried(&"tank", 40)])
	_win(_deploy(campaign, campaign.missions[0], progress), {TANK_SLOT: 30})
	assert_eq(progress.roster.size(), 0, "the war forgets the army it handed on")


## A mission that was lost is retried from the army it began with, exactly as its
## staged facts are: the attempt that went wrong is not the war.
func test_a_lost_mission_leaves_the_carried_army_where_it_was() -> void:
	var campaign := _campaign()
	var mission := campaign.missions[0]
	mission.carry_in = true
	mission.carry_out = true
	var progress := CampaignState.begin(campaign)
	progress.roster = _roster([_carried(&"tank", 70)])

	CampaignSession.begin(campaign, mission, progress)
	var lost := Fixture.state(LINE)
	CampaignSession.deploy_army(lost)
	CampaignSession.open_board(lost)
	lost.unit_at(TANK_SLOT).hp = 10
	lost.eliminate(1)
	assert_true(CampaignSession.decide(lost))
	assert_eq(CampaignSession.outcome.status, MissionRuntime.Status.FAILURE)
	CampaignSession.record(lost)

	assert_eq(progress.roster.size(), 1, "nothing the attempt did reached the war")
	assert_eq(progress.roster[0].hp, 70)


## The ledger's rule, at the width an army has: the war takes what the first clear
## left standing and a replay re-banks nothing. Later missions have already been
## opened off that army — the roster *is* their board — so a second run for stars
## must not re-deal one the player may already have played past.
func test_a_replay_of_a_cleared_mission_leaves_the_carried_army_where_it_was() -> void:
	var campaign := _campaign()
	var mission := campaign.missions[0]
	mission.carry_out = true
	var progress := CampaignState.begin(campaign)

	_win(_deploy(campaign, mission, progress), {TANK_SLOT: 70})
	assert_eq(progress.roster.size(), 4, "the run that stood is the army the war remembers")
	assert_eq(progress.roster[2].hp, 70)

	_win(_deploy(campaign, mission, progress), {TANK_SLOT: 15})
	assert_eq(progress.roster.size(), 4)
	assert_eq(progress.roster[2].hp, 70, "and a replay is for stars: the war already happened")


# --- the milestone's gate ------------------------------------------------------


## Three missions of one chain, each fought harder than the last: the wounds carry,
## the board never fields a unit more or fewer than it was authored with, and the
## floor is what stops the third mission opening with an army that cannot win it.
func test_three_missions_of_accumulated_damage_and_the_floor_holding() -> void:
	var campaign := _campaign()
	for mission: MissionDefinition in campaign.missions:
		mission.carry_in = true
		mission.carry_out = true
		mission.carry_floor_hp = 30
	campaign.missions[0].carry_in = false  # the first of a chain carries nothing in
	var progress := CampaignState.begin(campaign)
	var authored := _army(Fixture.state(LINE), 1)

	var first := _deploy(campaign, campaign.missions[0], progress)
	assert_eq(_army(first, 1), authored, "the first of a chain opens exactly as authored")
	_win(first, {TANK_SLOT: 70})

	var second := _deploy(campaign, campaign.missions[1], progress)
	assert_eq(second.unit_at(TANK_SLOT).hp, 70, "and the second on the first's wounds")
	assert_eq(_army(second, 1).size(), authored.size(), "three slots and a fourth unit, again")
	_win(second, {TANK_SLOT: 45})

	var third := _deploy(campaign, campaign.missions[2], progress)
	assert_eq(third.unit_at(TANK_SLOT).hp, 45, "and the third on the second's")
	assert_eq(_army(third, 1).size(), authored.size())
	_win(third, {TANK_SLOT: 12})
	assert_eq(progress.roster[2].hp, 12, "the war remembers what the third cost")

	# A fourth would open on 12 HP without the floor, which is the death spiral R1
	# exists for: the mission's own number is what refuses it.
	var fourth := Fixture.state(LINE)
	CampaignRoster.deploy(fourth, 1, progress.roster, campaign.missions[2].carry_floor_hp)
	assert_eq(fourth.unit_at(TANK_SLOT).hp, 30, "refit to the floor the author set")
	assert_eq(_army(fourth, 1).size(), authored.size(), "at full strength in numbers, always")
