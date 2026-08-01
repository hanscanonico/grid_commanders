class_name ReplayCodec
extends RefCounted
## Translation between a running match and the lines of a replay.
##
## Pure: no filesystem, no JSON text, no `user://`. ReplayFile owns storage and
## hands this a Dictionary that is already parsed — the same split SaveCodec and
## SaveGame keep, and for the same reason: a format rule can then be tested on a
## literal dictionary, and a disk error is never mistaken for a malformed line.
##
## A replay is an **opening board plus the commands that were applied to it**
## (plan D1). The opening is a `SaveCodec.encode` envelope, verbatim — it already
## carries the roster, the seating, the grouping, the fog flag, the commanders
## with their charge, and `rng_state` itself, and it already has a total
## validator — so this file owns only the command list. Nothing here describes a
## board, and nothing here re-derives one.
##
## ## Which unit a line names
##
## The cell it acted from, `path[0]`, and nothing else. That is unambiguous
## because a carried unit can never act — `MoveCommand.validate_path_steps`
## refuses one outright — so every unit that can appear in a line is alone on its
## cell. No ids to mint, nothing to keep in step across a Join or a Build, and a
## log a human can read. `DropCommand`'s named passenger is the one exception and
## rides as an index into the transport's cargo, which is deterministic because
## `GameState.cargo_of` walks `state.units` in order.
##
## That is also why `encode_command` takes the state **before** the command is
## applied: after a drop the passenger has left the cargo it was named in.

## The line format, not the save format. Bumped when a line's shape changes; a
## replay is disposable (plan D3), so there is no upgrade path to owe and older
## formats are refused rather than read.
const FORMAT := 1

## `DropCommand` with no passenger named — "the first loaded", which is what
## `DropCommand._rider` does with a null and what every single-slot transport
## drops.
const NO_PASSENGER := -1

## Every field of a header line, and the shape it must carry. Read off this table
## rather than checked by hand, the way `SaveCodec.KEY_RULES` is: two lists that
## have to agree by hand is the drift COM-54 was about.
const HEADER_KEY_RULES := {
	"replay": SaveCodec.Shape.NUMBER,
	"opening": SaveCodec.Shape.DICTIONARY,
}

## What each kind of line must name, beyond `c` itself. Presence is checked from
## here, so a line missing its path is refused out loud instead of decoding into a
## command about the cell at the origin.
##
## `power` and `end_turn` name nothing because they are nothing but themselves:
## which side fires and which side hands over is the board's answer, already in
## the state the line is applied to.
const REQUIRED_KEYS := {
	"move": ["path"],
	"attack": ["path", "target"],
	"capture": ["path"],
	"join": ["path"],
	"load": ["path"],
	"supply": ["path"],
	"dive": ["path", "submerge"],
	"drop": ["path", "drop"],
	"build": ["cell", "unit"],
	"power": [],
	"end_turn": [],
}

## Keeps the digest inside 48 bits, and that ceiling is load-bearing rather than
## arbitrary: JSON has one number type and a replay read back off disk hands every
## whole number over as a double, which holds integers exactly only up to 2^53. A
## wider digest would survive being written and come back with its tail rounded
## off, so every replay would fail its own self-check for a reason that has
## nothing to do with the board. 48 bits also keeps it positive, so no line ever
## carries a minus sign nobody can read.
const _DIGEST_MASK := 0xFFFF_FFFF_FFFF
const _DIGEST_SEED := 1469598103
## Under 2^15, so a 48-bit accumulator times it stays inside a signed 64-bit
## integer. A wider prime lands the product past that ceiling and only comes back
## in range by two's-complement wraparound — which is the same promise `hash()` is
## avoided for below, and a digest that moved would refuse every replay on disk.
const _DIGEST_PRIME := 16381
## Wider than any board this game will ever hold, so packing a cell into one
## integer for the sort below cannot make two different cells collide.
const _CELL_STRIDE := 4096


## One replay, read back: the header line and the commands under it.
class Replay:
	var format: int = 0
	## The `SaveCodec` envelope the match opened on.
	var opening: Dictionary = {}
	## What the menu names it with. Presentation only — nothing is derived from it.
	var label: String = ""
	var recorded: String = ""
	var entries: Array[Dictionary] = []


# --- header ------------------------------------------------------------------


## The line every replay opens with. `label` and `recorded` are the caller's to
## supply and may be empty: a clock belongs to whoever is writing, not to a codec,
## which is what keeps a Balance Lab replay diffable run to run.
static func header(opening: Dictionary, label: String = "", recorded: String = "") -> Dictionary:
	return {"replay": FORMAT, "recorded": recorded, "label": label, "opening": opening}


## "" when `line` is a header this codec can read, else the reason it is not.
static func header_error(line: Dictionary) -> String:
	for key: String in HEADER_KEY_RULES:
		if not line.has(key):
			return "the header names no %s" % key
		if not _is_shaped(line[key], HEADER_KEY_RULES[key]):
			return "the header's %s is not %s" % [key, _shape_name(HEADER_KEY_RULES[key])]
	var format := int(line["replay"])
	if format != FORMAT:
		return "replay format %d, and this build reads %d" % [format, FORMAT]
	return ""


# --- one command -------------------------------------------------------------


## The line for a command about to be applied to `state`.
##
## Takes the state because of the drop passenger above, and takes it *before*
## `apply` for the same reason. Everything else here is read off the command
## itself.
static func encode_command(state: GameState, command: Command) -> Dictionary:
	var entry := {"c": name_of(command)}
	if command is BuildCommand:
		var build := command as BuildCommand
		entry["cell"] = encode_cell(build.cell)
		entry["unit"] = String(build.unit_type.id) if build.unit_type != null else ""
		return entry
	# Every command that is not a Build and not one of the two bare ones carries a
	# path, and each carries it under the same name. Asked for rather than named
	# class by class — the same reading `BalanceMatchRecorder._log_entry` takes — so
	# a twelfth movement command records correctly with no edit here.
	var path: Variant = command.get("path")
	if path is Array:
		entry["path"] = encode_path(path)
	if command is AttackCommand:
		entry["target"] = encode_cell((command as AttackCommand).target_cell)
	elif command is DiveCommand:
		entry["submerge"] = (command as DiveCommand).submerge
	elif command is DropCommand:
		var drop := command as DropCommand
		entry["drop"] = encode_cell(drop.drop_cell)
		entry["p"] = _cargo_index(state, drop)
	return entry


## The command a line describes, bound to the units standing on `state` right now.
## Null (with a pushed error naming the problem) when the line is not one this
## build can re-issue — a kind it does not know, a field it does not carry, a unit
## type that has since been renamed, or an empty cell where an actor should be.
##
## It rebuilds; it does not vet. Whether the command is *legal* is the sim's
## answer and the caller asks for it the ordinary way, through `validate`.
static func command_from(state: GameState, unit_db: UnitDB, entry: Dictionary) -> Command:
	var kind := String(entry.get("c", ""))
	if not REQUIRED_KEYS.has(kind):
		push_error("ReplayCodec: '%s' is not a command this build knows" % kind)
		return null
	for key: String in REQUIRED_KEYS[kind]:
		if not entry.has(key):
			push_error("ReplayCodec: a %s line names no %s" % [kind, key])
			return null
	if kind == "end_turn":
		return EndTurnCommand.new()
	if kind == "power":
		return PowerCommand.new()
	if kind == "build":
		var type := unit_db.by_id(StringName(String(entry["unit"])))
		if type == null:
			push_error("ReplayCodec: unknown unit type '%s'" % entry["unit"])
			return null
		# The team is the board's answer, never the line's: a build validates only
		# for the side holding the turn, so recording one would be a second opinion
		# about whose turn it was.
		return BuildCommand.new(state.current_team, type, decode_cell(entry["cell"]))
	return _movement_from(state, kind, entry)


## The eight commands that walk a unit somewhere and then do something.
static func _movement_from(state: GameState, kind: String, entry: Dictionary) -> Command:
	var path := decode_path(entry["path"])
	if path.is_empty():
		push_error("ReplayCodec: a %s line carries an empty path" % kind)
		return null
	var actor := state.unit_at(path[0])
	if actor == null:
		push_error("ReplayCodec: a %s line acts from %s, where nothing stands" % [kind, path[0]])
		return null
	match kind:
		"move":
			return MoveCommand.new(actor, path)
		"attack":
			return AttackCommand.new(actor, path, decode_cell(entry["target"]))
		"capture":
			return CaptureCommand.new(actor, path)
		"join":
			return JoinCommand.new(actor, path)
		"load":
			return LoadCommand.new(actor, path)
		"supply":
			return SupplyCommand.new(actor, path)
		"dive":
			return DiveCommand.new(actor, path, bool(entry["submerge"]))
		"drop":
			return DropCommand.new(
				actor, path, decode_cell(entry["drop"]), _passenger(state, actor, entry)
			)
	push_error("ReplayCodec: '%s' has no rebuild" % kind)
	return null


## `AttackCommand` -> `attack`. Spelled out rather than derived from the class,
## unlike the Balance Lab's log beside it: these names are a *format*, so a file
## renamed for tidiness must not quietly stop older replays loading.
static func name_of(command: Command) -> String:
	if command is AttackCommand:
		return "attack"
	if command is CaptureCommand:
		return "capture"
	if command is BuildCommand:
		return "build"
	if command is PowerCommand:
		return "power"
	if command is EndTurnCommand:
		return "end_turn"
	if command is DiveCommand:
		return "dive"
	if command is DropCommand:
		return "drop"
	if command is JoinCommand:
		return "join"
	if command is LoadCommand:
		return "load"
	if command is SupplyCommand:
		return "supply"
	if command is MoveCommand:
		return "move"
	return ""


static func _cargo_index(state: GameState, drop: DropCommand) -> int:
	if drop.passenger == null:
		return NO_PASSENGER
	return state.cargo_of(drop.unit).find(drop.passenger)


## The rider a drop line names, or null for "the first loaded" — which is both what
## an unnamed passenger means and what a line pointing past the end of the cargo
## has to fall back to, since the alternative is refusing to rebuild a command the
## sim will refuse anyway with a message about the board.
static func _passenger(state: GameState, transport: Unit, entry: Dictionary) -> Unit:
	var index := int(entry.get("p", NO_PASSENGER))
	var cargo := state.cargo_of(transport)
	if index < 0 or index >= cargo.size():
		return null
	return cargo[index]


# --- the self-check (plan D3) ------------------------------------------------


## A digest of the whole board, in one integer. Written beside every line as it is
## recorded and recomputed after every line as it is replayed.
##
## The point is not to catch a bug in the sim — it is the one thing a command log
## cannot survive on its own: the *game* moving underneath it. Retune a `.tres`,
## fix a rule, add a doctrine hook, and yesterday's replay describes a match this
## build would not play. Without this it would quietly play a different one and
## look fine; with it, playback halts on the exact command whose meaning moved,
## which is a genuinely useful thing to hand a bisect.
##
## Cell-keyed tables are read in sorted order rather than in the dictionary's own,
## so a board that was reached by two different routes — created, or decoded from
## an envelope — can never digest differently for a reason that is not a
## difference.
static func checkpoint(state: GameState) -> int:
	var digest := _DIGEST_SEED
	digest = _mix(digest, state.day)
	digest = _mix(digest, state.current_team)
	digest = _mix(digest, state.winner)
	for team in state.teams:
		digest = _mix(digest, team)
		digest = _mix(digest, int(state.funds.get(team, 0)))
		digest = _mix(digest, 1 if state.is_eliminated(team) else 0)
		var co_state := state.commander_state(team)
		digest = _mix(digest, co_state.charge)
		digest = _mix(digest, 1 if co_state.power_active else 0)
	for unit in state.units:
		digest = _mix_text(digest, String(unit.type.id))
		for value: int in [
			unit.team,
			unit.cell.x,
			unit.cell.y,
			unit.hp,
			unit.fuel,
			unit.ammo,
			1 if unit.acted else 0,
			1 if unit.dived else 0,
			state.units.find(unit.carrier),
		]:
			digest = _mix(digest, value)
	for key in _sorted_cells(state.property_owners):
		digest = _mix(digest, key)
		digest = _mix(digest, int(state.property_owners[_uncell(key)]))
	for key in _sorted_cells(state.capture_progress):
		digest = _mix(digest, key)
		digest = _mix(digest, int(state.capture_progress[_uncell(key)]))
	return digest


## Cell keys of a table as sortable integers, ascending. Packed rather than sorted
## with a comparator so the ordering is a plain integer sort with nothing to get
## wrong, and unpacked again by `_uncell`.
static func _sorted_cells(table: Dictionary) -> Array[int]:
	var packed: Array[int] = []
	for cell: Vector2i in table:
		packed.append(cell.y * _CELL_STRIDE + cell.x)
	packed.sort()
	return packed


static func _uncell(packed: int) -> Vector2i:
	return Vector2i(packed % _CELL_STRIDE, packed / _CELL_STRIDE)


static func _mix(accumulator: int, value: int) -> int:
	return ((accumulator * _DIGEST_PRIME) ^ value) & _DIGEST_MASK


## Character by character rather than through `hash()`, which promises nothing
## across engine versions — and a digest that changes when the engine is upgraded
## would refuse every replay on disk for no reason at all.
static func _mix_text(accumulator: int, text: String) -> int:
	var digest := accumulator
	for i in text.length():
		digest = _mix(digest, text.unicode_at(i))
	return digest


# --- small shared conversions ------------------------------------------------


static func encode_cell(cell: Vector2i) -> Array:
	return [cell.x, cell.y]


static func decode_cell(value: Variant) -> Vector2i:
	if not (value is Array) or (value as Array).size() < 2:
		return Vector2i.ZERO
	var pair: Array = value
	return Vector2i(int(pair[0]), int(pair[1]))


static func encode_path(path: Array) -> Array:
	var steps: Array = []
	for cell: Vector2i in path:
		steps.append(encode_cell(cell))
	return steps


static func decode_path(value: Variant) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not (value is Array):
		return path
	for step: Variant in value as Array:
		path.append(decode_cell(step))
	return path


static func _is_shaped(value: Variant, shape: SaveCodec.Shape) -> bool:
	match shape:
		SaveCodec.Shape.NUMBER:
			return value is float or value is int
		SaveCodec.Shape.STRING:
			return value is String
		SaveCodec.Shape.DICTIONARY:
			return value is Dictionary
		SaveCodec.Shape.ARRAY:
			return value is Array
	return value is bool


static func _shape_name(shape: SaveCodec.Shape) -> String:
	match shape:
		SaveCodec.Shape.NUMBER:
			return "a number"
		SaveCodec.Shape.STRING:
			return "a string"
		SaveCodec.Shape.DICTIONARY:
			return "a dictionary"
		SaveCodec.Shape.ARRAY:
			return "an array"
	return "a boolean"
