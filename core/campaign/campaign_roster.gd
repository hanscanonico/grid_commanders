class_name CampaignRoster
extends RefCounted
## The army a campaign carries from one mission to the next: what survived one,
## and how it stands on the next one's board.
##
## Campaign-depth D6 in two functions, and the whole of the decision is in
## `deploy`: **a carry slot always ends up occupied by exactly one unit of the
## type the board authored.** The roster changes that unit's condition and its
## name — never its type, never where it stands, and never how many units the
## board fields. So every board still plays the army it was balanced for, which
## is what makes carry-over shippable across boards nobody is going to
## re-balance; and the alternative, survivors appended to the map's army, is the
## one version of it that snowballs a player who lost nothing and death-spirals
## one who lost badly.
##
## Pure and integer: no RNG, no board geometry and no rule of its own, so a
## carried board opens the same way every time it is deployed and replays
## identically.


## What `team` still has standing, in the order the board and the war produced it
## — the map's own rows first, since `GameState.create` builds them in file order
## and a build only ever lands after them. A slot therefore takes the veteran that
## has been in the army longest, which is the one the slot was authored for.
##
## Cargo is banked as itself: what was riding in a transport is a fact about a
## board that is over, and a transport carries forward as a transport.
static func bank(state: GameState, team: int) -> Array[CarriedUnit]:
	var carried: Array[CarriedUnit] = []
	for unit in state.units_of(team):
		carried.append(CarriedUnit.of(unit))
	return carried


## Stand the carried army in `team`'s carry slots on a board `GameState.create`
## has just built, refitting each veteran to `floor_hp` at worst and to `MAX_HP`
## at best — `Unit` is the one authority on how healthy a unit can be, and a
## mission's authored floor is held to it here as well as at the content gate.
##
## Slots are filled in board order and each takes the first unclaimed veteran of
## its own type, so **a slot the roster has nothing for keeps the full-strength
## unit the map authored** — a short roster, the first mission of a chain, a
## commander change, a board whose army is shaped differently. That is the common
## case rather than the edge, and it is why leaving carry slots off a board costs
## nothing.
##
## Called once, on a board nobody has played yet: the deployed HP is then part of
## the board a save, a recording and the mission's own tally all open on.
static func deploy(state: GameState, team: int, carried: Array[CarriedUnit], floor_hp: int) -> void:
	var claimed: Dictionary[int, bool] = {}
	var named := _names_on(state)
	for entry: Dictionary in state.map.starting_units:
		if not entry.carry or entry.team != team:
			continue
		var unit := state.unit_at(entry.cell)
		if unit == null:
			continue  # a seat this match closed fields nothing to stand in
		var index := _veteran_of(carried, unit.type.id, claimed)
		if index < 0:
			continue
		claimed[index] = true
		var veteran := carried[index]
		unit.hp = mini(maxi(veteran.hp, floor_hp), Unit.MAX_HP)
		# The board's own names are the mission's — an objective can only name what
		# the board authored — so a carried name fills a slot the board left unnamed
		# and never takes one that is already spoken for.
		if unit.tag == &"" and veteran.tag != &"" and not named.has(veteran.tag):
			unit.tag = veteran.tag
			named[veteran.tag] = true


## The first veteran of this type nobody has claimed, or -1.
static func _veteran_of(
	carried: Array[CarriedUnit], unit_id: StringName, claimed: Dictionary[int, bool]
) -> int:
	for index in carried.size():
		if not claimed.has(index) and carried[index].unit_id == unit_id:
			return index
	return -1


## Every name in use on the board, so no two units can end up answering to one.
static func _names_on(state: GameState) -> Dictionary[StringName, bool]:
	var named: Dictionary[StringName, bool] = {}
	for unit in state.units:
		if unit.tag != &"":
			named[unit.tag] = true
	return named
