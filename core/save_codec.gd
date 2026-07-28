class_name SaveCodec
extends RefCounted
## Translation between a running match and the save dictionary.
##
## Pure: no filesystem, no JSON text, no `user://`. SaveGame owns storage and
## hands this a Dictionary that is already parsed. Keeping the two apart means
## a format change or a validation rule can be tested on a literal dictionary,
## without a file on disk — and a storage failure is never mistaken for a
## malformed save.
##
## Version 2 adds the commander block: which general each side is playing, how
## much charge their meter holds, and whether their Command Power is up. Version 3
## adds one flag per unit: whether a submarine is submerged. Both are purely
## additive, so older saves are still read rather than rejected — a save with no
## commander block loads with both sides neutral, and one with no dive flag loads
## with every boat on the surface, which is exactly the match each recorded. New
## saves are always written at the current version.
##
## Which is why the version number is load-bearing rather than decorative: it is what
## separates a save that is *old* from one that is *damaged*. Every additive field is
## optional only to the versions that predate it, and a save claiming a version that
## wrote a field has to carry it, in the shape that version wrote it — see
## OPTIONAL_KEY_RULES.
##
## When a format arrives that *cannot* be read this way, it gets its own
## encode/decode pair here and SaveGame keeps choosing between them; the facade
## and its callers do not change.

const VERSION := 3
## Every version this codec can still read, oldest first.
const READABLE_VERSIONS: Array[int] = [1, 2, 3]

## Keys every save envelope must carry, whatever version wrote it.
const REQUIRED_KEYS: Array = [
	"map_path",
	"day",
	"current_team",
	"funds",
	"rng_state",
	"owners",
	"units",
]
const REQUIRED_UNIT_KEYS: Array = ["type", "team", "x", "y", "hp", "fuel", "ammo", "acted"]
const REQUIRED_OWNER_KEYS: Array = ["x", "y", "team"]
const REQUIRED_PROGRESS_KEYS: Array = ["x", "y", "points"]
## What `encode` writes for each side's general — demanded of every save old enough
## to have a commander block at all. See `_commander_block_error`.
const REQUIRED_COMMANDER_KEYS: Array = ["id", "charge", "active"]

## What a saved value is allowed to be. `NUMBER` rather than an integer because JSON
## has a single number type: a save read back off disk hands every whole number over
## as a float, which is why `decode` coerces with `int()` at every read.
enum Shape { BOOL, NUMBER, STRING, ARRAY, DICTIONARY }

## The remaining keys: for each, the first version that always wrote it and the shape
## that version wrote. The two live in one entry on purpose — they answer the same
## question, what a save of a given version promised — because a declaration drifting
## away from the fallback it describes is the whole of COM-54.
##
## Every one of them has a fallback in `decode`, and the fallback is for *age*, not for
## damage: a save old enough not to know about a field is entitled to the default, and
## a save that claims to be new enough is telling the truth about what it contains or
## it is truncated. Without this the two were indistinguishable, so a field lost to a
## short write — or a typo leaving one holding the wrong kind of value, which `decode`
## coerces into a plausible default rather than a refusal — loaded a match that played
## differently: fog off, captures reset, both sides commander-less, a computer opponent
## resuming as a second human. And said nothing (COM-54).
##
## Shape only. Which sides `ai_teams` may name and which side may have won are
## questions about the board rather than the format, and `board_error` already owns
## those, so nothing declared here holds a second opinion on them.
##
## `difficulty` is the awkward one, and it is deliberately listed at 3 rather than 2:
## it was added between those two versions without a bump of its own, so a version 2
## save may or may not carry it and only a version 3 save is guaranteed to.
##
## The entries listed at 1 are demanded of every version this codec still reads, so
## their `decode` defaults cannot currently be taken. They stay all the same, for the
## reason `board_error` is total: a decoder that answers for any dictionary is one a
## later caller cannot reach through a hole in.
const OPTIONAL_KEY_RULES := {
	"fog": {"since": 1, "shape": Shape.BOOL},
	"winner": {"since": 1, "shape": Shape.NUMBER},
	"capture_progress": {"since": 1, "shape": Shape.ARRAY},
	"ai_teams": {"since": 1, "shape": Shape.ARRAY},
	"commanders": {"since": 2, "shape": Shape.DICTIONARY},
	"difficulty": {"since": 3, "shape": Shape.STRING},
}
## The same, per unit entry: `carrier` shipped with the format, `dived` is version 3's
## whole reason for existing. What a `carrier` number may *be* — a link in range, nobody
## carrying themselves, no rings — is `_validate_carriers`', which can only ask once the
## unit count is known; this says no more than that it is a number.
const OPTIONAL_UNIT_KEY_RULES := {
	"carrier": {"since": 1, "shape": Shape.NUMBER},
	"dived": {"since": 3, "shape": Shape.BOOL},
}

## A unit standing on the board rather than riding in something.
const NO_CARRIER := -1

## What a live unit's internal HP may be. Zero is not a wounded unit, it is a dead
## one: every route that takes a unit to zero removes it in the same breath, so a
## save that records one is describing a board the rules cannot produce. The ceiling
## is Unit's own full health — see its header on the 0-100 scale the UI divides by ten.
const MIN_HP := 1
const MAX_HP := 100


class LoadedMatch:
	var state: GameState
	var ai_teams: Array[int] = []
	## The tier the match was being played at. Normal for any save written before
	## difficulty existed, which is the AI those saves actually recorded.
	var difficulty: StringName = Difficulty.DEFAULT_ID


## Just enough of a save to name it on a menu: which board, and how far in.
##
## Deliberately not a `LoadedMatch` with the rest blanked out — a summary is
## readable without the databases, without loading the map, and without
## rebuilding a single unit, so the menu can label Continue before it has any of
## those. Nothing here is new in the format; both fields are already required
## keys, which is what makes labelling a save a pure read.
class Summary:
	var day: int = 0
	var map_path: String = ""

	## What a player is shown: "Day 4 · Scrimmage".
	func label() -> String:
		return SaveCodec.describe(day, map_path)


## The whole match as a plain Dictionary: sim state plus the match setup (AI
## sides and difficulty tier). The map itself is stored by path and reloaded from
## res:// on the way back in, so saves stay small and follow map edits.
##
## `difficulty` is an id rather than the tier's numbers on purpose: retuning a
## tier should reach saved matches too, exactly as retuning a commander does.
static func encode(
	state: GameState, ai_teams: Array[int], difficulty: StringName = Difficulty.DEFAULT_ID
) -> Dictionary:
	var units: Array = []
	for unit in state.units:
		(
			units
			. append(
				{
					"type": String(unit.type.id),
					"team": unit.team,
					"x": unit.cell.x,
					"y": unit.cell.y,
					"hp": unit.hp,
					"fuel": unit.fuel,
					"ammo": unit.ammo,
					"acted": unit.acted,
					"dived": unit.dived,
					"carrier": state.units.find(unit.carrier),  # -1 when on the board
				}
			)
		)
	var owners: Array = []
	for cell: Vector2i in state.property_owners:
		owners.append({"x": cell.x, "y": cell.y, "team": state.property_owners[cell]})
	var progress: Array = []
	for cell: Vector2i in state.capture_progress:
		progress.append({"x": cell.x, "y": cell.y, "points": state.capture_progress[cell]})
	var commanders: Dictionary = {}
	for team in GameState.TEAMS:
		var co_state := state.commander_state(team)
		commanders[str(team)] = {
			"id": String(co_state.type.id),
			"charge": co_state.charge,
			"active": co_state.power_active,
		}
	return {
		"version": VERSION,
		"map_path": state.map_path,
		"fog": state.fog_enabled,
		"day": state.day,
		"current_team": state.current_team,
		"winner": state.winner,
		"funds": {"1": state.funds[1], "2": state.funds[2]},
		"rng_state": str(state.rng.state),  # int64 as string: JSON numbers are lossy
		"ai_teams": ai_teams,
		"difficulty": String(difficulty),
		"commanders": commanders,
		"owners": owners,
		"capture_progress": progress,
		"units": units,
	}


## Rebuilds a match from a parsed save. Returns null (with a pushed error
## naming the problem) when the dictionary is not a save this codec can read.
##
## `commander_db` is optional so callers that have no commanders to resolve —
## most tests — need not mention one. Left out, only the neutral commander is
## known, which is also what every id that is not in the database resolves to.
static func decode(
	data: Dictionary,
	terrain_db: TerrainDB,
	unit_db: UnitDB,
	damage_chart: DamageChart,
	commander_db: CommanderDB = null
) -> LoadedMatch:
	var error := validate(data)
	if error != "":
		# Reaches a log, not a player: the menu gates Continue on `summarize`, which
		# asks this same `validate` through the deliberately silent `SaveGame.peek`,
		# so a save refused here reads as no save at all on the way in.
		push_error("SaveCodec: %s" % error)
		return null
	var map := MapData.load_from_file(String(data["map_path"]), terrain_db)
	if map == null:
		return null  # MapData already reported why
	# Only askable now: what counts as a legal cell is the board's to say, and the
	# board is what was just loaded. See `board_error`.
	error = board_error(data, map)
	if error != "":
		push_error("SaveCodec: %s" % error)
		return null

	var state := GameState.new()
	state.map = map
	state.map_path = String(data["map_path"])
	state.damage_chart = damage_chart
	state.fog_enabled = bool(data.get("fog", false))
	state.day = int(data["day"])
	state.current_team = int(data["current_team"])
	state.winner = int(data.get("winner", 0))
	var funds: Dictionary = data["funds"]
	for team in GameState.TEAMS:
		state.funds[team] = int(funds[str(team)])
	state.rng.state = int(String(data["rng_state"]))
	for entry in data["owners"]:
		state.property_owners[Vector2i(int(entry.x), int(entry.y))] = int(entry.team)
	for entry in data.get("capture_progress", []):
		state.capture_progress[Vector2i(int(entry.x), int(entry.y))] = int(entry.points)
	_decode_commanders(state, data, commander_db)

	var carrier_indices: Array[int] = []
	for entry in data["units"]:
		var type := unit_db.by_id(StringName(String(entry.type)))
		if type == null:
			push_error("SaveCodec: unknown unit type '%s'" % entry.type)
			return null
		var unit := Unit.create(type, int(entry.team), Vector2i(int(entry.x), int(entry.y)))
		unit.hp = int(entry.hp)
		unit.fuel = int(entry.fuel)
		unit.ammo = int(entry.ammo)
		unit.acted = bool(entry.acted)
		unit.dived = bool(entry.get("dived", false))
		state.units.append(unit)
		carrier_indices.append(int(entry.get("carrier", NO_CARRIER)))

	# Checked only now that the unit count is known, and before anything is
	# wired up, so a bad save never produces a half-linked board.
	var carrier_error := _validate_carriers(carrier_indices)
	if carrier_error != "":
		push_error("SaveCodec: %s" % carrier_error)
		return null
	for i in state.units.size():
		var index := carrier_indices[i]
		if index != NO_CARRIER:
			state.units[i].carrier = state.units[index]
	# And only now that they are: whether a transport is over capacity is a question
	# about the whole board, not about one link. See `_carriage_error`.
	var riding_error := _carriage_error(state)
	if riding_error != "":
		push_error("SaveCodec: %s" % riding_error)
		return null

	var result := LoadedMatch.new()
	result.state = state
	for team in data["ai_teams"]:
		result.ai_teams.append(int(team))
	# Missing on every save written before difficulty existed; those matches were
	# played against the shipped AI, which is exactly what Normal is.
	result.difficulty = StringName(String(data.get("difficulty", String(Difficulty.DEFAULT_ID))))
	return result


## Restores each side's general, meter and running power. Every step falls back
## to the neutral commander with an empty meter, which is what makes a version-1
## save — where the whole block is missing — load as the no-commander match it
## actually was. From version 2 on those fallbacks are unreachable: `validate` has
## already refused a block missing a side or a field, so a hollow one never gets
## this far.
static func _decode_commanders(
	state: GameState, data: Dictionary, commander_db: CommanderDB
) -> void:
	var db := commander_db if commander_db != null else CommanderDB.new()
	var saved: Variant = data.get("commanders", {})
	if not (saved is Dictionary):
		return
	for team in GameState.TEAMS:
		var entry: Variant = (saved as Dictionary).get(str(team), {})
		if not (entry is Dictionary):
			continue
		var record := entry as Dictionary
		state.set_commander(team, db.by_id(StringName(String(record.get("id", "")))))
		var co_state := state.commander_state(team)
		# Through add_charge so a hand-edited meter is still capped at the cost,
		# and so a commander who has since lost their power banks nothing. The
		# charge is restored *before* the power is raised: add_charge banks nothing
		# for a team whose power is already active, so a mid-power save must fill
		# the meter while it still reads down.
		state.add_charge(team, int(record.get("charge", 0)))
		co_state.power_active = bool(record.get("active", false)) and co_state.type.has_power()


## The board and day of a parsed save, or null when it is not a save this codec
## reads. Both facts come straight off the envelope's own keys, which is why
## naming a save needs no format change — and why nothing summarized here is a
## fact `decode` would read differently: it asks the same `validate`, so a save
## with no summary is one Continue could not have resumed either.
##
## The implication runs one way only. Naming a save deliberately loads no map, so
## a summary is not a promise `decode` will accept: it goes on to ask
## `board_error` of the loaded board, and a save that describes an impossible one
## is named on the menu and then refused — the same fallback a save whose map has
## since gone missing has always taken.
static func summarize(data: Dictionary) -> Summary:
	if validate(data) != "":
		return null
	var summary := Summary.new()
	summary.day = int(data["day"])
	summary.map_path = String(data["map_path"])
	return summary


## "Day 4 · Scrimmage" — how a match is named wherever one has to be named: the
## menu's Continue caption and the in-battle Saved banner both say it, so the two
## can never drift into two phrasings of the same fact. The board's name is
## MapCatalog's, the same words the map picker shows.
static func describe(day: int, map_path: String) -> String:
	return "Day %d · %s" % [day, MapCatalog.display_name(map_path)]


## "" when `data` is a well-formed save this codec can read, else the reason it
## is not.
## Structure only — it does not check that the map exists or that unit ids are
## known, because that needs the databases decode is given. Nor whether the values
## describe a board that could exist: that is its sibling `board_error`'s, which
## needs the map this one deliberately answers without.
static func validate(data: Dictionary) -> String:
	var version := int(data.get("version", -1))
	if not READABLE_VERSIONS.has(version):
		return "unsupported save version"
	var missing := _missing_key(data, REQUIRED_KEYS)
	if missing != "":
		return "save is missing '%s'" % missing
	# What a save of *this* version promised to write, it has to have written. See
	# OPTIONAL_KEY_RULES: below its version a key is old, at or above it is lost.
	var written := _keys_written_by(version, OPTIONAL_KEY_RULES)
	missing = _missing_key(data, written)
	if missing != "":
		return "a version %d save is missing '%s'" % [version, missing]
	# And having written it is not the same as still holding it: a key carrying the
	# wrong kind of value is the same field lost, wearing a typo.
	for key: String in written:
		if not _is_shape(data[key], int(OPTIONAL_KEY_RULES[key]["shape"])):
			return "'%s' is malformed" % key
	# Both checks above stop at the envelope, and neither a hollow commander block nor
	# a list holding something that is not a number is missing or the wrong kind of
	# value at that level.
	var error := _commander_block_error(data, version)
	if error != "":
		return error
	error = _ai_teams_error(data)
	if error != "":
		return error
	error = _entries_error(data["owners"], REQUIRED_OWNER_KEYS, "owner")
	if error != "":
		return error
	error = _entries_error(
		data.get("capture_progress", []), REQUIRED_PROGRESS_KEYS, "capture progress"
	)
	if error != "":
		return error
	var unit_keys := REQUIRED_UNIT_KEYS + _keys_written_by(version, OPTIONAL_UNIT_KEY_RULES)
	error = _entries_error(data["units"], unit_keys, "unit")
	if error != "":
		return error
	error = _unit_shapes_error(data["units"] as Array, version)
	if error != "":
		return error
	return _funds_error(data)


## "" when every value in `data` describes something that can exist on `map`, else
## the reason it cannot. `validate`'s sibling, split from it for one reason: these
## questions need the board, and `validate` deliberately answers without one so a
## save can be named on a menu that has loaded no map.
##
## The rules layer trusts what it is handed — `MovementResolver`, `AttackRange` and
## `CombatResolver` all read terrain at a unit's cell without asking whether the unit
## is standing anywhere real — because every other route onto the board goes through
## a command that already checked. A save does not, so a hand-edited or truncated one
## used to load clean and take the game down much later and far away:
## `CombatResolver` null-derefs `terrain_at(...).defense_stars` for a unit off the
## map, an `hp` of zero puts a corpse on the board that no attack can finish, and a
## `team` outside `GameState.TEAMS` produces a unit no turn ever readies. Refusing
## here is what keeps the delayed crash from ever being the player's first symptom.
##
## Every cell the save carries is asked the same question, not only the units' — a
## board is a board, and a rule applied to one list and not the others is the sort of
## half-rule that reads as deliberate until it isn't. Every *team* it carries is asked
## too, for the same reason: refusing a unit on team 9 while accepting a whole turn or
## a victory belonging to team 9 would be the rule half-applied.
##
## Safe to call on a dictionary `validate` has not seen. It leans on `validate`'s own
## entry check for that rather than restating the structure, so a save missing a list
## comes back as a reason — which is what the signature promises — instead of a
## runtime error off a key that was never there.
static func board_error(data: Dictionary, map: MapData) -> String:
	var error := _entries_error(data.get("units"), REQUIRED_UNIT_KEYS, "unit")
	if error != "":
		return error
	error = _entries_error(data.get("owners"), REQUIRED_OWNER_KEYS, "owner")
	if error != "":
		return error
	error = _entries_error(
		data.get("capture_progress", []), REQUIRED_PROGRESS_KEYS, "capture progress"
	)
	if error != "":
		return error
	# The turn indexes `funds`, which decode fills for GameState.TEAMS and nothing
	# else, so a turn belonging to a side that does not play is an invalid-key read
	# the first time the HUD draws it.
	var turn := int(data.get("current_team", 0))
	if not GameState.TEAMS.has(turn):
		return "the save's turn belongs to team %d, which does not play" % turn
	# Zero is the running match; anything else is the side that won, and every
	# command refuses while one stands. A winner no side ever was resumes into a
	# board locked against every move, announcing a victory nobody could have won.
	var winner := int(data.get("winner", 0))
	if winner != 0 and not GameState.TEAMS.has(winner):
		return "the save was won by team %d, which does not play" % winner
	# The computer's sides are teams like any other, and the last one this had never
	# asked: a save handing the AI a side that does not play resumes with a side nobody
	# plays at all — `Battle` takes the list as written.
	error = _ai_teams_error(data)
	if error != "":
		return error
	for team: Variant in data.get("ai_teams", []) as Array:
		if not GameState.TEAMS.has(int(team)):
			return "the save gives team %d to the computer, which does not play" % int(team)
	for entry: Dictionary in data["units"] as Array:
		var cell := Vector2i(int(entry["x"]), int(entry["y"]))
		if not map.in_bounds(cell):
			return (
				"unit '%s' stands at %s, off a %dx%d board"
				% [entry["type"], cell, map.width, map.height]
			)
		var hp := int(entry["hp"])
		if hp < MIN_HP or hp > MAX_HP:
			return "unit '%s' has %d HP, outside %d-%d" % [entry["type"], hp, MIN_HP, MAX_HP]
		var team := int(entry["team"])
		if not GameState.TEAMS.has(team):
			return "unit '%s' belongs to team %d, which does not play" % [entry["type"], team]
	var cells_error := _cells_on_board(data["owners"], map, "owned property")
	if cells_error != "":
		return cells_error
	return _cells_on_board(data.get("capture_progress", []), map, "capture in progress")


## "" when a save of `version` carries the commander block that version wrote, else
## the reason it does not. The envelope's own check cannot see this: a block that is
## present but empty, or one whose second side was lost to a hand-edit, satisfies
## `has("commanders")` while `_decode_commanders` falls back per team — so the match
## resumes with both sides commander-less and their meters at zero, which is the very
## harm the version gate was added to end (COM-54).
##
## The per-entry fields go with it rather than staying optional. All three have been
## written for as long as the block has existed, so an entry without a charge is a
## meter lost, not one that predates the key — the same reasoning, one level down.
##
## A version 1 save is not asked, because it knew of no such block: it keeps loading
## both sides neutral with an empty meter, which is the match it recorded. That the
## block is a Dictionary at all is the shape pass's answer, not restated here.
static func _commander_block_error(data: Dictionary, version: int) -> String:
	if version < int(OPTIONAL_KEY_RULES["commanders"]["since"]):
		return ""
	var saved: Dictionary = data["commanders"]
	for team in GameState.TEAMS:
		var entry: Variant = saved.get(str(team))
		if not (entry is Dictionary):
			return "a version %d save is missing the commander for team %d" % [version, team]
		var missing := _missing_key(entry as Dictionary, REQUIRED_COMMANDER_KEYS)
		if missing != "":
			return (
				"a version %d save is missing '%s' for team %d's commander"
				% [version, missing, team]
			)
	return ""


## "" when the save's computer sides are a list of numbers, else why they are not.
## *Which* sides those numbers may name is `board_error`'s question, beside the turn
## and the winner; this one is answered without a board and says no more than that the
## list is a list of numbers.
##
## It is asked at all because `decode` used to skip a malformed one in silence: a save
## whose `ai_teams` read `2` rather than `[2]` resumed as a two-human hot seat with the
## computer opponent quietly gone — a match that loads clean and plays differently,
## which is exactly the harm the version gate was added to end (COM-54).
static func _ai_teams_error(data: Dictionary) -> String:
	var teams: Variant = data.get("ai_teams", [])
	if not (teams is Array):
		return "'ai_teams' is malformed"
	for team: Variant in teams as Array:
		if not _is_shape(team, Shape.NUMBER):
			return "'ai_teams' is malformed"
	return ""


## "" when every unit entry holds the flags its version wrote in the shape it wrote
## them. Asked after `_entries_error` has established that the entries are dictionaries
## carrying the keys at all, which is what lets this read them straight.
static func _unit_shapes_error(entries: Array, version: int) -> String:
	for key: String in _keys_written_by(version, OPTIONAL_UNIT_KEY_RULES):
		var shape := int(OPTIONAL_UNIT_KEY_RULES[key]["shape"])
		for entry: Dictionary in entries:
			if not _is_shape(entry[key], shape):
				return "unit entry's '%s' is malformed" % key
	return ""


## "" when the save carries a purse for every side that plays.
static func _funds_error(data: Dictionary) -> String:
	var funds: Variant = data["funds"]
	if not (funds is Dictionary):
		return "'funds' is malformed"
	for team in GameState.TEAMS:
		if not (funds as Dictionary).has(str(team)):
			return "save has no funds for team %d" % team
	return ""


## Whether `value` is the kind of thing `shape` describes — the one reader of the
## shapes declared in the two rule tables, so every field is asked the same way.
static func _is_shape(value: Variant, shape: int) -> bool:
	var kind := typeof(value)
	match shape:
		Shape.BOOL:
			return kind == TYPE_BOOL
		Shape.NUMBER:
			return kind == TYPE_INT or kind == TYPE_FLOAT
		Shape.STRING:
			return kind == TYPE_STRING or kind == TYPE_STRING_NAME
		Shape.ARRAY:
			return kind == TYPE_ARRAY
		Shape.DICTIONARY:
			return kind == TYPE_DICTIONARY
	return false


## "" when every entry in `entries` names a cell `map` actually has.
static func _cells_on_board(entries: Variant, map: MapData, what: String) -> String:
	for entry: Dictionary in entries as Array:
		var cell := Vector2i(int(entry["x"]), int(entry["y"]))
		if not map.in_bounds(cell):
			return "%s at %s is off a %dx%d board" % [what, cell, map.width, map.height]
	return ""


## "" when every unit riding in another is one that could have boarded it, else the
## reason it could not. Asked of the wired-up board rather than of the raw indices,
## because capacity and nesting are questions about the whole arrangement.
##
## The rules themselves are `LoadCommand`'s, asked rather than copied. Boarding is
## simply not the only way a rider ends up inside a transport, and while the codec
## kept its own opinion — indices in range, nobody carrying themselves, no cycles —
## a save could seat a battleship inside an infantry and every rule the command
## enforces at runtime was bypassed by editing a file (COM-53).
static func _carriage_error(state: GameState) -> String:
	for i in state.units.size():
		var rider := state.units[i]
		if rider.carrier == null:
			continue
		var reason := LoadCommand.carriage_error(state, rider.carrier, rider)
		if reason != "":
			return (
				"unit %d (%s) cannot ride in %s: %s"
				% [i, rider.type.id, rider.carrier.type.id, reason]
			)
	return ""


## Carrier links are indices into the unit list, so a corrupt save can point
## anywhere. Rejecting the three ways that goes wrong — off the end of the
## list, a unit carrying itself, and a ring of units carrying each other —
## keeps the loader from building a board the rules cannot reason about, or
## looping forever walking a cargo chain.
static func _validate_carriers(indices: Array[int]) -> String:
	var count := indices.size()
	for i in count:
		var index := indices[i]
		if index == NO_CARRIER:
			continue
		if index < 0 or index >= count:
			return "unit %d has carrier index %d, outside the %d unit(s) saved" % [i, index, count]
		if index == i:
			return "unit %d is its own carrier" % i
	# Every chain must reach the board. More hops than there are units means it
	# never will, which is exactly a cycle.
	for i in count:
		var at := i
		var hops := 0
		while indices[at] != NO_CARRIER:
			at = indices[at]
			hops += 1
			if hops > count:
				return "unit %d is in a loop of units carrying each other" % i
	return ""


## Every key in `rules` that a save of this `version` was already writing — which is
## exactly the set it is neither allowed to be missing nor allowed to hold the wrong
## kind of value. Below its version a key is old and none of those rules reach it.
static func _keys_written_by(version: int, rules: Dictionary) -> Array:
	var keys: Array = []
	for key: String in rules:
		if version >= int(rules[key]["since"]):
			keys.append(key)
	return keys


## The first key `data` lacks, or "" when it carries them all.
static func _missing_key(data: Dictionary, keys: Array) -> String:
	for key in keys:
		if not data.has(key):
			return String(key)
	return ""


## "" when `value` is an array of dictionaries that all carry `keys`.
static func _entries_error(value: Variant, keys: Array, what: String) -> String:
	if not (value is Array):
		return "'%s' list is malformed" % what
	for entry: Variant in value as Array:
		if not (entry is Dictionary):
			return "%s entry is malformed" % what
		var missing := _missing_key(entry as Dictionary, keys)
		if missing != "":
			return "%s entry is missing '%s'" % [what, missing]
	return ""
