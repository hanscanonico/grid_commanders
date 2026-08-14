class_name SaveSchema
extends RefCounted
## The version-rule schema engine SaveCodec and ReplayCodec both read through
## (COM-184): which shape a value must have, and which keys a given format
## version has already promised to write.
##
## Pure data plus the generic readers over it — nothing here knows what a save
## or a replay *is*. `SaveCodec` owns the save envelope's own rules
## (`VERSION`, `READABLE_VERSIONS`, the per-field `_x_error` checks); this is
## only the table shape both codecs' version gates are built from, so a shape
## rule has exactly one authority rather than two readers that have to agree
## by hand (COM-54, COM-175).

## What a saved value is allowed to be. `NUMBER` rather than an integer because JSON
## has a single number type: a save read back off disk hands every whole number over
## as a float, which is why `decode` coerces with `int()` at every read.
enum Shape { BOOL, NUMBER, STRING, ARRAY, DICTIONARY }

## Every field of a save envelope: the first version that always wrote it, and the shape
## that version wrote. One entry per field, and nothing beside it — the presence rules and
## the shape rules are read off this same table, because two lists that have to agree by
## hand is the drift this whole ticket is about (COM-54).
##
## `since: 1` is what "required" used to be a separate list for: a field written by every
## version this codec still reads. The distinction that remains is real but narrow — such
## a field is simply missing, while a later arrival is missing *for the version the save
## claims* — and `_missing_message` derives even that from the table rather than from a
## second list.
##
## Both halves of a rule answer the same question: what a save of a given version
## promised. A field it promised and did not deliver was lost to a short write; one it
## delivered in the wrong kind of value was lost to a typo, and `decode` coerces that
## into a plausible default rather than a refusal — `int()` on a word is zero, and a
## String is truthy while `bool()` will not take one at all. Either way the match loaded
## clean and played differently — fog off, captures reset, both sides commander-less, a
## computer opponent resuming as a second human — and said nothing.
##
## Shape only. Which sides `ai_teams` may name, which side may have won, and where on the
## board a cell is are questions about the board rather than the format, and `board_error`
## already owns those, so nothing declared here holds a second opinion on them.
##
## `teams` is the exception that proves it, and deliberately so: the roster is not a fact
## *about* the board, it is the list every other per-side rule here is derived from — whose
## purse must be present, whose commander, which side may be taking the turn. A roster that
## is not one the rules could seat has to be refused before any of those are asked, or each
## of them is asked about a side that never existed. See `SaveCodec._teams_error`.
##
## `difficulty` is the awkward one, and it is deliberately listed at 3 rather than 2:
## it was added between those two versions without a bump of its own, so a version 2
## save may or may not carry it and only a version 3 save is guaranteed to. Its `since`
## therefore means *guaranteed from*, where every other entry's means *introduced at* —
## which is why it is the one field `decode` reads below its own version, and the one
## whose shape is asked wherever the key appears. See `SaveCodec._difficulty_error`.
##
## The entries listed at 1 are demanded of every version this codec still reads, so
## their `decode` defaults cannot currently be taken. They stay all the same, for the
## reason `board_error` is total: a decoder that answers for any dictionary is one a
## later caller cannot reach through a hole in.
const KEY_RULES := {
	"map_path": {"since": 1, "shape": Shape.STRING},
	"day": {"since": 1, "shape": Shape.NUMBER},
	"current_team": {"since": 1, "shape": Shape.NUMBER},
	"funds": {"since": 1, "shape": Shape.DICTIONARY},
	"rng_state": {"since": 1, "shape": Shape.STRING},
	"owners": {"since": 1, "shape": Shape.ARRAY},
	"units": {"since": 1, "shape": Shape.ARRAY},
	"fog": {"since": 1, "shape": Shape.BOOL},
	"winner": {"since": 1, "shape": Shape.NUMBER},
	"capture_progress": {"since": 1, "shape": Shape.ARRAY},
	"ai_teams": {"since": 1, "shape": Shape.ARRAY},
	"commanders": {"since": 2, "shape": Shape.DICTIONARY},
	"difficulty": {"since": 3, "shape": Shape.STRING},
	"teams": {"since": 4, "shape": Shape.ARRAY},
	"sides": {"since": 5, "shape": Shape.DICTIONARY},
	"eliminated": {"since": 6, "shape": Shape.ARRAY},
	"home_hq": {"since": 7, "shape": Shape.ARRAY},
	"auto_tiers": {"since": 10, "shape": Shape.DICTIONARY},
}
## The same, per unit entry: everything but the dive flag shipped with the format, and
## `dived` is version 3's whole reason for existing. What a `carrier` number may *be* —
## a link in range, nobody carrying themselves, no rings — is `SaveCodec._validate_carriers`',
## which can only ask once the unit count is known; this says no more than that it is a
## number. `acted` earns its place here as much as any of them: it is a flag the sim
## plays the resumed turn under, so a quoted one is a unit that cannot move.
## `refreshable` arrived in version 8 and qualifies that action for Second Wind,
## and `tag` in version 9 is the name its board gave it — empty for most units, and
## the only way a mission that is about one unit finds it again after a resume. What
## that text may *say* is `UnitTag`'s, asked in `SaveCodec._unit_tags_error`; this
## says no more than that it is text.
const UNIT_KEY_RULES := {
	"type": {"since": 1, "shape": Shape.STRING},
	"team": {"since": 1, "shape": Shape.NUMBER},
	"x": {"since": 1, "shape": Shape.NUMBER},
	"y": {"since": 1, "shape": Shape.NUMBER},
	"hp": {"since": 1, "shape": Shape.NUMBER},
	"fuel": {"since": 1, "shape": Shape.NUMBER},
	"ammo": {"since": 1, "shape": Shape.NUMBER},
	"acted": {"since": 1, "shape": Shape.BOOL},
	"carrier": {"since": 1, "shape": Shape.NUMBER},
	"dived": {"since": 3, "shape": Shape.BOOL},
	"refreshable": {"since": 8, "shape": Shape.BOOL},
	"tag": {"since": 9, "shape": Shape.STRING},
}
## And per entry in the two cell lists, which are the same shape of thing: a cell and
## one number about it.
const OWNER_KEY_RULES := {
	"x": {"since": 1, "shape": Shape.NUMBER},
	"y": {"since": 1, "shape": Shape.NUMBER},
	"team": {"since": 1, "shape": Shape.NUMBER},
}
const PROGRESS_KEY_RULES := {
	"x": {"since": 1, "shape": Shape.NUMBER},
	"y": {"since": 1, "shape": Shape.NUMBER},
	"points": {"since": 1, "shape": Shape.NUMBER},
}
## And per army in the home-HQ list, which is a third list of that same shape: a
## cell and one number about it. Listed at 7 rather than 1 because that is the
## version that started writing it, which is what keeps an older save from being
## asked for fields it never promised.
const HOME_HQ_KEY_RULES := {
	"x": {"since": 7, "shape": Shape.NUMBER},
	"y": {"since": 7, "shape": Shape.NUMBER},
	"team": {"since": 7, "shape": Shape.NUMBER},
}
## And per side inside the commander block: all three arrived with the block itself at
## version 2, which is why they share its version and why a version 1 save is asked for
## none of them.
const COMMANDER_KEY_RULES := {
	"id": {"since": 2, "shape": Shape.STRING},
	"charge": {"since": 2, "shape": Shape.NUMBER},
	"active": {"since": 2, "shape": Shape.BOOL},
}


## Whether `value` is the kind of thing `shape` describes — the one reader of every
## shape the rule tables declare, so no field is asked in its own way. Public
## because `ReplayCodec` reads a header through this same table (COM-54): two
## readers that had to agree by hand is the drift this rule exists to end.
static func is_shape(value: Variant, shape: int) -> bool:
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


## How a save of `version` is told it lacks `key`: a field every readable version wrote
## is simply missing, while a later arrival is missing *for the version the save claims*,
## which is the distinction the whole gate turns on. Derived from the rule rather than
## from a second list of which fields are which.
##
## `oldest_readable` is the caller's own floor (`SaveCodec.READABLE_VERSIONS[0]`) — this
## engine carries no opinion of its own about which versions a codec still reads.
static func _missing_message(
	key: String, rules: Dictionary, version: int, oldest_readable: int
) -> String:
	if int(rules[key]["since"]) <= oldest_readable:
		return "save is missing '%s'" % key
	return "a version %d save is missing '%s'" % [version, key]


## "" when `value` is an array of dictionaries that each carry the fields a save of
## `version` wrote, in the shapes it wrote them.
static func _entries_error(value: Variant, rules: Dictionary, version: int, what: String) -> String:
	if not (value is Array):
		return "'%s' list is malformed" % what
	var keys := _keys_written_by(version, rules)
	for entry: Variant in value as Array:
		if not (entry is Dictionary):
			return "%s entry is malformed" % what
		var record := entry as Dictionary
		var missing := _missing_key(record, keys)
		if missing != "":
			return "%s entry is missing '%s'" % [what, missing]
		for key: String in keys:
			if not is_shape(record[key], int(rules[key]["shape"])):
				return "%s entry's '%s' is malformed" % [what, key]
	return ""
