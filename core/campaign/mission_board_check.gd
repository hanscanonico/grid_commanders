class_name MissionBoardCheck
extends RefCounted
## The refusals every authored objective, trigger and effect shares, stated once.
##
## A cell off the board, ground that carries no property, an army the board never
## dealt and a name no unit on it answers to are facts about the board rather than
## about the condition asking, so dozens of call sites were assembling the same
## few sentences by hand — and the fire-time sibling of the seat check, an army
## that is not at this table, six more. CD8 puts the check in `core/` for the
## tool and the suite to share; this is that rule read one step further, so the
## sentence cannot drift either.
##
## Each caller passes only its own noun phrase, because what a mission was doing
## when it named the ground is the half a shared authority cannot know.


## "" when `cell` is on `map`, else why it is not.
static func off_board(map: MapData, cell: Vector2i, prefix: String) -> String:
	if map.in_bounds(cell):
		return ""
	return "%s %s, off a %dx%d board" % [prefix, cell, map.width, map.height]


## "" when `cell` carries a property, else why it does not. Bounds are the
## caller's to check first: ground that is not there is a different refusal.
static func property_cell(map: MapData, cell: Vector2i, prefix: String) -> String:
	if map.terrain_at(cell).is_property:
		return ""
	return "%s %s, which is %s and not a property" % [prefix, cell, map.terrain_at(cell).id]


## "" when `tag` names a unit this board deals, else why it does not — an unnamed
## unit and a name nothing carries being the same refusal from two directions.
static func named_unit(map: MapData, tag: StringName, prefix: String) -> String:
	if tag == &"":
		return "%s no unit" % prefix
	if not MissionObjective.board_names(map, tag):
		return "%s '%s', which no unit on this board carries" % [prefix, tag]
	return ""


## "" when `map` deals `team` a seat, else why it does not.
static func unseated_team(map: MapData, team: int, prefix: String) -> String:
	if map.teams().has(team):
		return ""
	return "%s army %d, which this board does not seat" % [prefix, team]


## "" when `team` is playing this match, else why it is not. The board's own
## question, asked of the seating a mission actually filled.
static func absent_team(state: GameState, team: int, prefix: String) -> String:
	if state.teams.has(team):
		return ""
	return "%s army %d, which is not at this table" % [prefix, team]
