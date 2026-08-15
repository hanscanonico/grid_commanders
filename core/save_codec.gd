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
## adds one flag per unit: whether a submarine is submerged. Version 4 adds the
## match roster — which armies the board seated — because a match stopped being a
## duel by definition. Version 5 adds the grouping: which armies stood together,
## because a roster stopped implying who was fighting whom. Version 6 adds the
## fallen, because an army leaving the board stopped being the end of the match.
## Version 7 adds each army's home HQ, which pins where every army began against a
## later edit of the map file it names: the board still derives the same answer, so
## carrying it is what lets a save whose board has since moved be *refused* rather
## than silently re-homed. Version 8 records whether an acted unit's last committed
## action was not an attack, so a refresh power is exact across a mid-turn save.
## Version 9 carries the name a board gave a unit, so a mission that is about one
## unit can still find it after a resume. Version 10 carries which seats a player
## has handed to the computer mid-match through the pause menu's Auto row, and at
## what tier, because that fact can now change after the match began instead of
## only at setup. Version 11 carries the tier each computer seat was launched at,
## because difficulty stopped being one match-wide setting. All ten are purely additive, so older
## saves are still read
## rather than rejected — a save with no commander block loads with both sides
## neutral, one with no dive flag loads with every boat on the surface, one with no
## roster loads as the duel it was, one with no grouping loads as the free-for-all
## it was, one with no casualty list loads with every army it names still standing,
## and one with no home HQs takes them from the map it names. An older save with no
## refresh flag treats every acted unit as ineligible, one with no tags loads
## with every unit unnamed, and one with no Auto tiers loads with no seat the
## computer plays on Auto's behalf, and one with no seat tiers resumes with every computer
## seat on the one tier it records. New saves are always written at the current version.
##
## Which is why the version number is load-bearing rather than decorative: it is what
## separates a save that is *old* from one that is *damaged*. Every additive field is
## optional only to the versions that predate it, and a save claiming a version that
## wrote a field has to carry it, in the shape that version wrote it — see SaveSchema.KEY_RULES.
##
## When a format arrives that *cannot* be read this way, it gets its own
## encode/decode pair here and SaveGame keeps choosing between them; the facade
## and its callers do not change.

const VERSION := 11
## Every version this codec can still read, oldest first.
const READABLE_VERSIONS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]

## The version-rule schema — `Shape`, `KEY_RULES` and its per-list siblings, and the
## generic readers over them (`is_shape`, `_entries_error` and friends) — moved to
## `SaveSchema` (COM-184), shared with `ReplayCodec` rather than copied. This file
## keeps only what is the *save envelope's* own: which version wrote what is
## `SaveSchema.KEY_RULES`'s question, but which version a save may claim at all
## (`VERSION`, `READABLE_VERSIONS` above) and what a claimed field then has to say
## about the board (`board_error`'s checks) are this codec's alone.

## The purse is a Dictionary keyed by side rather than a record of named fields, so its
## one rule lives here: every side's money is a number, checked in `_funds_error`.
const FUNDS_SHAPE := SaveSchema.Shape.NUMBER

## A unit standing on the board rather than riding in something.
const NO_CARRIER := -1

## What a save claims to be when it claims nothing this codec can read. No release ever
## wrote it, so no rule may be derived from it — see `_claimed_version`.
const NO_VERSION := 0

## What a live unit's internal HP may be. Zero is not a wounded unit, it is a dead
## one: every route that takes a unit to zero removes it in the same breath, so a
## save that records one is describing a board the rules cannot produce. Both
## bounds are Unit's own — see its header on the 0-100 scale the UI divides by ten.
const MIN_HP := Unit.MIN_HP
const MAX_HP := Unit.MAX_HP


class LoadedMatch:
	var state: GameState
	var ai_teams: Array[int] = []
	## The tier the match was being played at. Normal for any save written before
	## difficulty existed, which is the AI those saves actually recorded.
	var difficulty: StringName = Difficulty.DEFAULT_ID
	## Seats a player had handed to the computer mid-match, and the tier each was
	## on — a subset of `ai_teams`, never the whole of it. Empty for any save
	## written before Auto existed, which is the same match with no such seat.
	var auto_tiers: Dictionary[int, StringName] = {}
	## The tier each computer seat was launched at, where that is not the match's
	## own `difficulty` above — a subset of `ai_teams` like the Auto seats, and
	## kept apart from them because a seat the computer has always played is not a
	## seat a player handed over. Empty for any save written before a seat could
	## carry a tier of its own, which is the same match on one tier.
	var seat_tiers: Dictionary[int, StringName] = {}


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
	state: GameState,
	ai_teams: Array[int],
	difficulty: StringName = Difficulty.DEFAULT_ID,
	auto_tiers: Dictionary[int, StringName] = {},
	seat_tiers: Dictionary[int, StringName] = {}
) -> Dictionary:
	var carrier_indices := _unit_indices(state)
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
					"refreshable": unit.refreshable,
					"tag": String(unit.tag),
					"carrier": carrier_indices.get(unit.carrier, NO_CARRIER),  # -1 when on the board
				}
			)
		)
	var owners: Array = []
	for cell: Vector2i in state.property_owners:
		owners.append({"x": cell.x, "y": cell.y, "team": state.property_owners[cell]})
	var progress: Array = []
	for cell: Vector2i in state.capture_progress:
		progress.append({"x": cell.x, "y": cell.y, "points": state.capture_progress[cell]})
	# Left generic rather than typed: this feeds straight into the returned envelope,
	# and `validate`'s own tests deliberately corrupt a field's value here (a String
	# into "funds") to prove the shape check catches it — a typed container would
	# refuse the corruption before the check under test ever saw it.
	var commanders: Dictionary = {}
	var funds: Dictionary = {}
	for team in state.teams:
		var co_state := state.commander_state(team)
		commanders[str(team)] = {
			"id": String(co_state.type.id),
			"charge": co_state.charge,
			"active": co_state.power_active,
		}
		# Written from the same list every other per-side block here is written from, and
		# the same list `decode` reads it back with. Spelled out as two literal keys it was
		# the one place in this file that knew how many sides there are, so a third army's
		# treasury went through a save round-trip and came back empty (COM-55).
		funds[str(team)] = state.funds[team]
	return {
		"version": VERSION,
		"map_path": state.map_path,
		"teams": state.teams.duplicate(),
		"sides": _encode_sides(state.sides),
		"eliminated": _encode_eliminated(state),
		"home_hq": _encode_home_hq(state),
		"fog": state.fog_enabled,
		"day": state.day,
		"current_team": state.current_team,
		"winner": state.winner,
		"funds": funds,
		"rng_state": str(state.rng.state),  # int64 as string: JSON numbers are lossy
		"ai_teams": ai_teams,
		"difficulty": String(difficulty),
		"auto_tiers": _encode_tiers(auto_tiers),
		"seat_tiers": _encode_tiers(seat_tiers),
		"commanders": commanders,
		"owners": owners,
		"capture_progress": progress,
		"units": units,
	}


## `unit -> index` in `state.units`, built once per `encode` call rather than
## re-scanned for every one of the n units it writes out — the same shape
## MovementResolver._occupants is waived for (CLAUDE.md). A unit with no
## carrier is simply absent as a key, so the lookup above falls back to
## `NO_CARRIER` exactly as `Array.find` did.
static func _unit_indices(state: GameState) -> Dictionary[Unit, int]:
	var indices: Dictionary[Unit, int] = {}
	for i in state.units.size():
		indices[state.units[i]] = i
	return indices


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
		# Still a log rather than a player, but no longer the only place it is said:
		# the menu gates Continue on `SaveGame.status`, which asks this same `validate`
		# and hands the reason back, so a save refused here is offered as damaged
		# rather than as no save at all (COM-121).
		push_error("SaveCodec: %s" % error)
		return null
	var map := MapData.load_from_file(String(data["map_path"]), terrain_db)
	if map == null:
		return null  # MapData already reported why
	# Only askable now: what counts as a legal cell is the board's to say, and the
	# board is what was just loaded. See `board_error`.
	error = board_error(data, map, unit_db)
	if error != "":
		push_error("SaveCodec: %s" % error)
		return null

	# Readable from here on, because `validate` refused anything else above. Every read
	# below that is not unconditional asks it first: a key a save's version never wrote
	# is not that field, and `validate` deliberately shapes no such key, so coercing one
	# would be the age rule turned into a crash. `difficulty` is the exception in both
	# directions — read at any version because an older save may carry a real tier, and
	# shaped at any version for exactly that reason. See `_difficulty_error`.
	#
	# Four phases, in the order a board can be trusted in: the tables the state is
	# otherwise built from, then the units standing on it, then the carrier links
	# between them — checked only once the unit count is known, and only once they
	# are wired up is a transport's capacity askable — and finally the match-setup
	# facts (COM-184) that ride alongside the state rather than inside it.
	var version := _claimed_version(data)
	var roster := _roster(data)
	var state := _decode_board_tables(data, map, damage_chart, commander_db, version, roster)

	var decoded_units := _decode_units(data, unit_db, version)
	if decoded_units.error != "":
		push_error("SaveCodec: %s" % decoded_units.error)
		return null
	state.units = decoded_units.units

	var link_error := _link_carriers(state, decoded_units.carrier_indices)
	if link_error != "":
		push_error("SaveCodec: %s" % link_error)
		return null

	return _decode_setup(data, state, version)


## The one phase of `decode` that carries no error of its own: everything on `GameState`
## that is a table keyed by cell or by side, plus the scalar facts (day, turn, winner,
## fog) that sit beside them. `board_error` has already refused every value read here,
## so nothing below is a coercion over something nothing checked — that is what makes
## this phase unconditional where `_decode_units` and `_link_carriers` are not.
static func _decode_board_tables(
	data: Dictionary,
	map: MapData,
	damage_chart: DamageChart,
	commander_db: CommanderDB,
	version: int,
	roster: Array[int]
) -> GameState:
	var state := GameState.new()
	state.map = map
	state.map_path = String(data["map_path"])
	state.teams = roster
	state.sides = _decode_sides(data)
	state.eliminated = _decode_eliminated(data)
	state.home_hq = _decode_home_hq(data, map, roster)
	state.damage_chart = damage_chart
	state.fog_enabled = bool(data.get("fog", false))
	state.day = int(data["day"])
	state.current_team = int(data["current_team"])
	state.winner = int(data.get("winner", 0))
	var funds: Dictionary = data["funds"]
	for team in roster:
		state.funds[team] = int(funds[str(team)])
	state.rng.state = int(String(data["rng_state"]))
	for entry in data["owners"]:
		state.property_owners[Vector2i(int(entry.x), int(entry.y))] = int(entry.team)
	for entry in data.get("capture_progress", []):
		state.capture_progress[Vector2i(int(entry.x), int(entry.y))] = int(entry.points)
	_decode_commanders(state, data, commander_db, version)
	return state


## What `_decode_units` hands back: the units it built, in save order, and the raw
## carrier index each was saved with — `_link_carriers` wires those once the whole
## list exists, since a unit may name a carrier that has not been built yet. `error`
## is "" on success; a caller checks it before trusting either array, the same
## discipline every `_x_error` check in this file already follows.
class _DecodedUnits:
	var units: Array[Unit] = []
	var carrier_indices: Array[int] = []
	var error: String = ""


## The second phase: the units themselves, off `data["units"]` — `board_error` has
## already checked every entry's shape, cell and HP, so what is left is building the
## `Unit` and reading the fields whose meaning depends on the save's version.
static func _decode_units(data: Dictionary, unit_db: UnitDB, version: int) -> _DecodedUnits:
	var result := _DecodedUnits.new()
	var dive_flags := version >= int(SaveSchema.UNIT_KEY_RULES["dived"]["since"])
	var refresh_flags := version >= int(SaveSchema.UNIT_KEY_RULES["refreshable"]["since"])
	var tags := version >= int(SaveSchema.UNIT_KEY_RULES["tag"]["since"])
	for entry in data["units"]:
		var type := unit_db.by_id(StringName(String(entry.type)))
		if type == null:
			result.error = "unknown unit type '%s'" % entry.type
			return result
		var unit := Unit.create(type, int(entry.team), Vector2i(int(entry.x), int(entry.y)))
		unit.hp = int(entry.hp)
		unit.fuel = int(entry.fuel)
		unit.ammo = int(entry.ammo)
		unit.acted = bool(entry.acted)
		unit.dived = dive_flags and bool(entry["dived"])
		unit.refreshable = refresh_flags and bool(entry["refreshable"])
		if tags:
			unit.tag = StringName(String(entry["tag"]))
		result.units.append(unit)
		result.carrier_indices.append(int(entry.get("carrier", NO_CARRIER)))
	return result


## The third phase: wires each unit's `carrier` from the indices `_decode_units`
## collected, once `state.units` holds all of them. Checked only now that the unit
## count is known, and before anything is wired up, so a bad save never produces a
## half-linked board; and only once they are wired up is whether a transport is over
## capacity askable, which is a question about the whole board rather than one link.
## "" on success.
static func _link_carriers(state: GameState, carrier_indices: Array[int]) -> String:
	var carrier_error := _validate_carriers(carrier_indices)
	if carrier_error != "":
		return carrier_error
	for i in state.units.size():
		var index := carrier_indices[i]
		if index != NO_CARRIER:
			state.units[i].carrier = state.units[index]
	return _carriage_error(state)


## The fourth and last phase: the match-setup facts that ride beside the state
## rather than inside it (`encode`'s own "sim state plus the match setup") — which
## computer seats and what tier they play at.
static func _decode_setup(data: Dictionary, state: GameState, version: int) -> LoadedMatch:
	var result := LoadedMatch.new()
	result.state = state
	for team in data["ai_teams"]:
		result.ai_teams.append(int(team))
	# Missing on every save written before difficulty existed; those matches were
	# played against the shipped AI, which is exactly what Normal is.
	result.difficulty = StringName(String(data.get("difficulty", String(Difficulty.DEFAULT_ID))))
	# A version below the one that wrote the block has no such section to read: the
	# match recorded no seat a player had handed to the computer, so whatever sits
	# under that key is not one and `validate` shaped none of it.
	if version >= int(SaveSchema.KEY_RULES["auto_tiers"]["since"]):
		result.auto_tiers = _decode_tiers(data.get("auto_tiers", {}))
	if version >= int(SaveSchema.KEY_RULES["seat_tiers"]["since"]):
		result.seat_tiers = _decode_tiers(data.get("seat_tiers", {}))
	return result


## Restores each side's general, meter and running power. Both sides stay neutral with an
## empty meter for a save written before the block existed, which is the no-commander
## match such a save recorded.
##
## That is a question about the *version*, not about what the file happens to hold: a
## version 1 save has no commander block, so whatever sits under that key is not one, and
## none of the three coercions below is spent on it. `validate` shapes those fields from
## version 2 up and does not touch them below — reading them anyway is where the age rule
## would have become a crash, since `bool()` will not take a String.
static func _decode_commanders(
	state: GameState, data: Dictionary, commander_db: CommanderDB, version: int
) -> void:
	if version < int(SaveSchema.KEY_RULES["commanders"]["since"]):
		return
	var db := commander_db if commander_db != null else CommanderDB.new()
	var saved: Variant = data.get("commanders", {})
	if not (saved is Dictionary):
		return
	for team in _roster(data):
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
## — or names a board that has since gone missing — is named on the menu and then
## refused. Both callers of that refusal are refusals rather than fallbacks: the
## menu opens the save on the press and stages nothing when it will not open, and
## `BattleSetup` returns no match at all (COM-121).
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
	# Answered first, and refused rather than floored: every rule below is derived from
	# this number, so nothing may be asked of a save until it is one this codec reads.
	var version := _claimed_version(data)
	if version == NO_VERSION:
		return "unsupported save version"
	# What a save of *this* version promised to write, it has to have written, holding
	# what it promised to hold. See SaveSchema.KEY_RULES: below its version a field is old, at or
	# above it a missing one is lost and a wrong-typed one is a typo.
	var written := SaveSchema._keys_written_by(version, SaveSchema.KEY_RULES)
	var missing := SaveSchema._missing_key(data, written)
	if missing != "":
		return SaveSchema._missing_message(
			missing, SaveSchema.KEY_RULES, version, READABLE_VERSIONS[0]
		)
	for key: String in written:
		if not SaveSchema.is_shape(data[key], int(SaveSchema.KEY_RULES[key]["shape"])):
			return "'%s' is malformed" % key
	# The envelope pass stops at the keys this version promised, and every rule below
	# is asked of the value each key holds — in this exact order, which is a promise
	# rather than an accident: `difficulty` is the one a version below its own may
	# still be carrying for real, so it is asked before anything else reads a version
	# number; and `_teams_error` runs before every per-side rule that follows it,
	# because each of them asks the roster whose side is whose — refusing a roster no
	# board could have dealt only after reporting a purse or a commander missing *for*
	# it would report the damage instead of the cause. `_rng_state_error` onward is
	# where the pass stops at each key's own value: a Dictionary that is hollow, a list
	# of things that are not numbers and a number spelled as a word are all perfectly
	# good values one level up.
	var checks: Array[Callable] = [
		func() -> String: return _difficulty_error(data),
		func() -> String: return _teams_error(data),
		func() -> String: return _sides_error(data),
		func() -> String: return _eliminated_error(data),
		func() -> String: return _home_hq_error(data),
		func() -> String: return _rng_state_error(data),
		func() -> String: return _commander_block_error(data, version),
		func() -> String: return _ai_teams_error(data),
		func() -> String: return _auto_tiers_error(data),
		func() -> String: return _seat_tiers_error(data),
		func() -> String:
			return SaveSchema._entries_error(
				data["owners"], SaveSchema.OWNER_KEY_RULES, version, "owner"
			),
		func() -> String:
			return SaveSchema._entries_error(
				data.get("capture_progress", []),
				SaveSchema.PROGRESS_KEY_RULES,
				version,
				"capture progress"
			),
		func() -> String:
			return SaveSchema._entries_error(
				data["units"], SaveSchema.UNIT_KEY_RULES, version, "unit"
			),
		func() -> String: return _unit_tags_error(data, version),
		func() -> String: return _funds_error(data),
	]
	for check: Callable in checks:
		var error: String = check.call()
		if error != "":
			return error
	return ""


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
## `team` outside the save's roster produces a unit no turn ever readies. Refusing
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
## runtime error off a key that was never there. Which version's fields to ask for is
## floored rather than trusted for exactly that reason; see the note where it is read.
##
## `unit_db` is what the two checks below need to answer for a unit that has not been
## built yet — `GameState.create`'s own two refusals, held to here for the arrangement
## a save can reach that a starting roster cannot: two units sharing a cell, where
## `unit_at` returns the first and leaves the second a ghost that never draws, never
## targets and never blocks in `_occupants`, yet still counts for `_check_rout`; and a
## unit standing on terrain its move class cannot enter, the same class of board
## `CombatResolver`'s terrain read cannot reason about (COM-174).
static func board_error(data: Dictionary, map: MapData, unit_db: UnitDB) -> String:
	# The asymmetry that makes this necessary: `validate` refuses a version it cannot read
	# before deriving one rule from it, and this function is documented to answer for a
	# dictionary `validate` has never seen — so it cannot refuse, and floors instead. The
	# oldest readable version asks of every entry exactly the fields the reads below need
	# and nothing a later format added; trusting an unreadable one would ask for nothing
	# at all and leave those reads falling off records nobody had checked.
	var claimed := _claimed_version(data)
	var version := claimed if claimed != NO_VERSION else READABLE_VERSIONS[0]
	# The format pass, in order: every list's own entries first, then the two scalar
	# facts about the board a version can still get wrong. Each is independent of the
	# ones after it, so the order here is only "cheapest and most specific first" —
	# unlike `validate`'s walk, nothing below is derived from an earlier rule's answer.
	var format_checks: Array[Callable] = [
		func() -> String:
			return SaveSchema._entries_error(
				data.get("units"), SaveSchema.UNIT_KEY_RULES, version, "unit"
			),
		func() -> String:
			return SaveSchema._entries_error(
				data.get("owners"), SaveSchema.OWNER_KEY_RULES, version, "owner"
			),
		func() -> String:
			return SaveSchema._entries_error(
				data.get("capture_progress", []),
				SaveSchema.PROGRESS_KEY_RULES,
				version,
				"capture progress"
			),
		func() -> String: return _turn_and_winner_error(data),
		func() -> String: return _ai_teams_error(data),
	]
	for check: Callable in format_checks:
		var error: String = check.call()
		if error != "":
			return error
	# The computer's sides are teams like any other, and the last one this had never
	# asked: a save handing the AI a side that does not play resumes with a side nobody
	# plays at all — `Battle` takes the list as written.
	var roster := _roster(data)
	for team: Variant in data.get("ai_teams", []) as Array:
		if not roster.has(int(team)):
			return "the save gives team %d to the computer, which does not play" % int(team)
	# Every cell a unit that is actually standing on the board occupies, so the
	# second check below can ask whether it is the only one there. A rider shares
	# no cell of its own — `advance_unit` mirrors it onto the carrier's the moment
	# it boards, and `encode` writes that mirrored cell straight back out — so
	# both checks below skip any entry still linked to a carrier.
	var occupied: Dictionary[Vector2i, bool] = {}
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
		if not roster.has(team):
			return "unit '%s' belongs to team %d, which does not play" % [entry["type"], team]
		if int(entry["carrier"]) != NO_CARRIER:
			continue
		if occupied.has(cell):
			return "two units stand on cell %s" % cell
		occupied[cell] = true
		var type := unit_db.by_id(StringName(String(entry["type"])))
		if type != null and not map.terrain_at(cell).is_passable(type.move_class):
			return (
				"unit '%s' cannot stand on %s at %s"
				% [entry["type"], map.terrain_at(cell).id, cell]
			)
	var cell_checks: Array[Callable] = [
		func() -> String: return _cells_on_board(data["owners"], map, "owned property"),
		func() -> String:
			return _cells_on_board(data.get("capture_progress", []), map, "capture in progress"),
	]
	for check: Callable in cell_checks:
		var cells_error: String = check.call()
		if cells_error != "":
			return cells_error
	return _home_hq_board_error(data, map, version)


## "" when the save's home HQs are the ones its board deals, else why they are not.
## `_home_hq_error`'s half of the same field, split for the reason the whole file is
## split: which cells exist, what stands on them, and which armies a board homes at
## all are the board's answers.
##
## The expected answer is `Seating.home_hqs` — the one derivation, asked of this
## save's map and roster — and the save is held to it whole: same armies, same cells.
## Which is the pin the field is carried for, finally enforced rather than merely
## claimed: a save whose board has since moved is refused here instead of resuming
## silently re-homed.
##
## Every way it can be wrong is the same harm — an army beheaded through a cell that
## is not its head, or through none at all, in a match that loads clean and plays a
## rule short. A cell that is not an HQ says so first, because it is the most
## specific thing that can be said about it.
##
## Which keeps the allowance it has to keep: a board is free to deal a seat no HQ,
## and `home_hqs` names no such seat, so no entry is demanded for it — nor allowed
## for it, since a home the board never dealt is one nothing on the board answers to.
##
## Gated on the version that writes the field, like its sibling, and for a second
## reason here: `board_error` floors an unreadable version to the oldest one, which
## asks a home-HQ entry for none of its fields — so the reads below would be
## coercions over records nothing checked.
static func _home_hq_board_error(data: Dictionary, map: MapData, version: int) -> String:
	if version < int(SaveSchema.KEY_RULES["home_hq"]["since"]):
		return ""
	var error := SaveSchema._entries_error(
		data.get("home_hq"), SaveSchema.HOME_HQ_KEY_RULES, version, "home HQ"
	)
	if error != "":
		return error
	error = _cells_on_board(data["home_hq"], map, "home HQ")
	if error != "":
		return error
	var expected := Seating.home_hqs(map, _roster(data))
	var homed: Dictionary[int, bool] = {}
	for entry: Dictionary in data["home_hq"] as Array:
		var team := int(entry["team"])
		var cell := Vector2i(int(entry["x"]), int(entry["y"]))
		if not map.terrain_at(cell).is_headquarters:
			return "team %d's home HQ at %s is not an HQ" % [team, cell]
		if not expected.has(team):
			return "the save homes team %d at %s, but its board homes it nowhere" % [team, cell]
		if expected[team] != cell:
			return (
				"the save homes team %d at %s, but its board starts it at %s"
				% [team, cell, expected[team]]
			)
		homed[team] = true
	for team: int in expected:
		if not homed.has(team):
			return "the save gives team %d no home HQ, but its board starts it on one" % team
	return ""


## "" when a save of `version` carries the commander block that version wrote, else
## the reason it does not. The envelope's own check cannot see this: a block that is
## present but empty, or one whose second side was lost to a hand-edit, satisfies
## `has("commanders")` while `_decode_commanders` falls back per team — so the match
## resumes with both sides commander-less and their meters at zero, which is the very
## harm the version gate was added to end (COM-54).
##
## The per-entry fields go with it rather than staying optional, and they are asked for
## their shape as well as their presence. All three have been written for as long as the
## block has existed, so an entry without a charge is a meter lost, not one that predates
## the key — and an entry whose charge is not a number is a meter lost the same way, by
## the same reasoning one level down.
##
## `active` is the one that bites hardest, and it is not obvious. A String is truthy in
## GDScript — `if "false":` runs — while `bool()` will not take one at all, so a quoted
## flag (a plausible hand-edit, or what a tool that stringifies everything would write)
## either reads as a power that is up or takes the rebuild down with an engine call
## error half way through, depending only on which spelling reads it. A power's state is
## what the sim plays the *next turn* under, so this field's damage is not merely how
## the board looks.
##
## A version 1 save is not asked, because it knew of no such block: it keeps loading
## both sides neutral with an empty meter, which is the match it recorded. That the
## block is a Dictionary at all is the shape pass's answer, not restated here.
static func _commander_block_error(data: Dictionary, version: int) -> String:
	if version < int(SaveSchema.KEY_RULES["commanders"]["since"]):
		return ""
	var saved: Dictionary = data["commanders"]
	var keys := SaveSchema._keys_written_by(version, SaveSchema.COMMANDER_KEY_RULES)
	for team in _roster(data):
		var entry: Variant = saved.get(str(team))
		if not (entry is Dictionary):
			return "a version %d save is missing the commander for team %d" % [version, team]
		var record := entry as Dictionary
		var missing := SaveSchema._missing_key(record, keys)
		if missing != "":
			return (
				"a version %d save is missing '%s' for team %d's commander"
				% [version, missing, team]
			)
		for key: String in keys:
			if not SaveSchema.is_shape(
				record[key], int(SaveSchema.COMMANDER_KEY_RULES[key]["shape"])
			):
				return (
					"a version %d save has a malformed '%s' for team %d's commander"
					% [version, key, team]
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
		if not SaveSchema.is_shape(team, SaveSchema.Shape.NUMBER):
			return "'ai_teams' is malformed"
	return ""


## "" when the save's Auto tiers name only teams the save itself hands to the
## computer, each with a tier as text, else why they do not. A team not in the
## save's own `ai_teams` cannot be on Auto — an Auto entry *is* a seat a
## player toggled into `ai_teams` mid-match, so one naming anyone else
## describes a match this save could not have recorded.
##
## Only the shape of the tier id, like `_difficulty_error`: an id nobody
## recognises falls back to Normal by `DifficultyDB`'s own deliberate rule,
## and a save must not be refused because a tier it once carried has since
## been retired.
##
## Asked only of the version that writes it. Below that there is nothing to
## be wrong: the save recorded no seat a human had handed to the computer
## mid-match.
static func _auto_tiers_error(data: Dictionary) -> String:
	return _tier_block_error(
		data,
		"auto_tiers",
		"the save puts team %s on Auto, but does not hand it to the computer",
		"the save's Auto tier for team %s is malformed"
	)


## The same question of version 11's per-seat tiers, and the same answer: a tier
## for a seat the save does not hand to the computer tunes a planner that never
## plans, so it describes a match this save could not have recorded.
static func _seat_tiers_error(data: Dictionary) -> String:
	return _tier_block_error(
		data,
		"seat_tiers",
		"the save gives team %s a tier of its own, but does not hand it to the computer",
		"the save's seat tier for team %s is malformed"
	)


## The shared reading of a team -> tier id block: every key an army the save
## itself hands to the computer, every value text. `misplaced` and `malformed`
## are the two things that can be wrong with one, in the words of the block being
## read.
##
## The roster is compared as integers rather than asked of the parsed array,
## because JSON has one number type: a save that has been through a file carries
## `[2.0, 3.0]`, and `Array.has(3)` on those is false — which refused every save
## written while a seat was on Auto (COM-225 found it; a dictionary in memory
## never showed it).
static func _tier_block_error(
	data: Dictionary, key: String, misplaced: String, malformed: String
) -> String:
	if _claimed_version(data) < int(SaveSchema.KEY_RULES[key]["since"]):
		return ""
	var saved: Dictionary = data[key]
	var computers: Dictionary = {}
	for team: Variant in data.get("ai_teams", []):
		computers[int(team)] = true
	for entry: Variant in saved:
		var name := String(entry)
		if not name.is_valid_int() or not computers.has(int(name)):
			return misplaced % name
		if not SaveSchema.is_shape(saved[entry], SaveSchema.Shape.STRING):
			return malformed % name
	return ""


## "" when the two sides the envelope names could hold what it gives them, else why they
## could not.
##
## Asked as a shape before it is asked as a side, for the reason the version is: `int()`
## will not take a Dictionary or an Array, so a save that is about to be told what is
## wrong with it must not be coerced on the way. `validate` guarantees both are numbers
## for the decode path and refuses in the same words; this is `board_error`'s standalone
## half of that, since either is public and either may be handed a raw parsed save. An
## absent one reads as zero exactly as it always has — which is no winner at all, and a
## turn belonging to nobody.
##
## The turn indexes `funds`, which decode fills for the save's roster and nothing else, so
## a turn belonging to a side that does not play is an invalid-key read the first time the
## HUD draws it. Zero is the running match; anything else is the side that won, and every
## command refuses while one stands, so a winner no side ever was resumes into a board
## locked against every move, announcing a victory nobody could have won.
static func _turn_and_winner_error(data: Dictionary) -> String:
	for key: String in ["current_team", "winner"]:
		if not SaveSchema.is_shape(data.get(key, 0), int(SaveSchema.KEY_RULES[key]["shape"])):
			return "'%s' is malformed" % key
	var roster := _roster(data)
	var turn := int(data.get("current_team", 0))
	if not roster.has(turn):
		return "the save's turn belongs to team %d, which does not play" % turn
	var winner := int(data.get("winner", 0))
	if winner != 0 and not roster.has(winner):
		return "the save was won by team %d, which does not play" % winner
	return ""


## The version `data` claims, or `NO_VERSION` when it claims none this codec can read —
## whether it says nothing, says a number no release ever wrote, or says something that
## is not a number at all. The last is why this is a shape question and not an `int()`:
## that constructor will not take a Dictionary or an Array, so reading the version the
## obvious way is a crash on the one field every other rule here hangs off.
##
## Not a reason string, because its two callers want different things from the answer:
## `validate` refuses, `board_error` floors. What each does with it is stated where it
## asks.
static func _claimed_version(data: Dictionary) -> int:
	var claimed: Variant = data.get("version")
	if not SaveSchema.is_shape(claimed, SaveSchema.Shape.NUMBER):
		return NO_VERSION
	var version := int(claimed)
	return version if READABLE_VERSIONS.has(version) else NO_VERSION


## "" when the save's difficulty is text at all, else why it is not. Asked wherever the
## key turns up rather than only from the version that demands it, which makes it the one
## field shaped outside its own `since`.
##
## That is the awkward entry earning its keep. `since: 3` says only that a version 3 save
## is *guaranteed* to carry a tier — the key arrived between 2 and 3 without a bump of its
## own, so a version 2 save may well hold a real one, and `decode` honours it rather than
## resuming that match at a tier it never played. A field `decode` reads at every version
## has to be shaped at every version, or the read is back to being a coercion over
## something nothing checked.
##
## Only the shape. A tier id nobody recognises is Normal by `DifficultyDB`'s deliberate
## fallback — retiring a tier must not strand the saves that played at it — but a tier
## that is not text is not an id at all.
static func _difficulty_error(data: Dictionary) -> String:
	if not data.has("difficulty"):
		return ""
	if not SaveSchema.is_shape(
		data["difficulty"], int(SaveSchema.KEY_RULES["difficulty"]["shape"])
	):
		return "'difficulty' is malformed"
	return ""


## The armies the save's match seated, which every per-side rule in this file is asked
## about. A save written before the roster existed played a duel — that is what a match
## was — so one is what it decodes as, and a two-army save round-trips through version 4
## naming the same pair it always did.
##
## Read only from the version that writes it, which is the gate `_teams_error` is under.
## Below it the field is not a roster this codec vetted — a hand-edited or merged one
## would drive every per-side rule off a list nothing refused — so the duel the save
## recorded by construction is the answer, and `teams` is not read at all.
##
## Total, like `board_error` is total and for the same reason: it is asked from
## `board_error`, which answers for dictionaries `validate` has never seen. A roster that
## is not one the rules could seat floors to the duel here and is *reported* by
## `_teams_error`, so nothing downstream is ever handed a side that could not exist.
static func _roster(data: Dictionary) -> Array[int]:
	if _claimed_version(data) < int(SaveSchema.KEY_RULES["teams"]["since"]):
		return MapData.DEFAULT_TEAMS.duplicate()
	var declared: Variant = data.get("teams")
	if not (declared is Array):
		return MapData.DEFAULT_TEAMS.duplicate()
	var roster: Array[int] = []
	for team: Variant in declared as Array:
		if not SaveSchema.is_shape(team, SaveSchema.Shape.NUMBER):
			return MapData.DEFAULT_TEAMS.duplicate()
		roster.append(int(team))
	if not _is_seatable(roster):
		return MapData.DEFAULT_TEAMS.duplicate()
	return roster


## The grouping as JSON writes it: side ids keyed by the army's number as text,
## like `funds` and `commanders` beside it. An empty grouping stays an empty
## dictionary, so a free-for-all — what an ungrouped table hands in — records as
## one rather than as a list of one-army sides.
static func _encode_sides(sides: Dictionary[int, int]) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	for team: int in sides:
		out[str(team)] = sides[team]
	return out


## A team -> tier block as JSON writes it: tier ids keyed by army number as text,
## the same shape `sides` and `funds` are. A match with no such seat writes an
## empty dictionary, same as a save written before the block existed.
static func _encode_tiers(tiers: Dictionary[int, StringName]) -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for team: int in tiers:
		out[str(team)] = String(tiers[team])
	return out


## One back, keyed to army numbers. A key that is not a number is dropped rather
## than read as team 0, which is what `int()` on a word would make of it.
static func _decode_tiers(saved: Variant) -> Dictionary[int, StringName]:
	var tiers: Dictionary[int, StringName] = {}
	if not saved is Dictionary:
		return tiers
	for key: Variant in saved as Dictionary:
		var name := String(key)
		if name.is_valid_int():
			tiers[int(name)] = StringName(String((saved as Dictionary)[key]))
	return tiers


## The grouping a save recorded, keyed back to army numbers. Empty for a save
## written before the grouping existed, which is the free-for-all every match was.
##
## Gated on its own version for the plain reason that a save below it recorded no
## grouping — the free-for-all every match was. Total, like `_roster`: a key that is
## not an army number, or a side that is not one, reads as no grouping at all rather
## than as a coercion nobody asked for, since `int("abc")` is 0 and 0 is the neutral
## owner. A malformed grouping is *reported* by `_sides_error`.
static func _decode_sides(data: Dictionary) -> Dictionary[int, int]:
	var out: Dictionary[int, int] = {}
	if _claimed_version(data) < int(SaveSchema.KEY_RULES["sides"]["since"]):
		return out
	var saved: Variant = data.get("sides")
	if not (saved is Dictionary):
		return out
	for key: Variant in saved as Dictionary:
		var side: Variant = (saved as Dictionary)[key]
		var name := String(key)
		if not name.is_valid_int() or not SaveSchema.is_shape(side, SaveSchema.Shape.NUMBER):
			return {}
		out[int(name)] = int(side)
	return out


## The armies that had fallen, in seat order — a plain list, because unlike the
## grouping there is nothing to say about one beyond that it is out.
static func _encode_eliminated(state: GameState) -> Array:
	var fallen: Array = []
	for team in state.teams:
		if state.is_eliminated(team):
			fallen.append(team)
	return fallen


## The casualty list a save recorded, or empty for one written before an army
## could fall without ending the match — which is the state every such save was
## in, since the first elimination was the victory.
##
## Floors on anything it cannot read, like its siblings; `_eliminated_error`
## reports a list that is wrong rather than leaving it to be inferred here.
static func _decode_eliminated(data: Dictionary) -> Dictionary[int, bool]:
	var fallen: Dictionary[int, bool] = {}
	if _claimed_version(data) < int(SaveSchema.KEY_RULES["eliminated"]["since"]):
		return fallen
	var saved: Variant = data.get("eliminated")
	if not (saved is Array):
		return fallen
	for team: Variant in saved as Array:
		if not SaveSchema.is_shape(team, SaveSchema.Shape.NUMBER):
			return {}
		fallen[int(team)] = true
	return fallen


## Where each army began: `{team, x, y}` per seat that has a home HQ, in seat
## order. A list rather than a dictionary keyed by team because it is the same
## shape of thing as `owners` and `capture_progress` beside it — a cell and one
## number about it — and shares their per-entry checks.
static func _encode_home_hq(state: GameState) -> Array:
	var homes: Array = []
	for team in state.teams:
		if state.home_hq.has(team):
			var cell: Vector2i = state.home_hq[team]
			homes.append({"team": team, "x": cell.x, "y": cell.y})
	return homes


## Where each army began, for the match being resumed.
##
## The map plus the roster derive the same answer — `Seating.home_hqs` is that one
## derivation — so what carrying the field buys is the map file no longer being able
## to move a home under a save that is already on disk: the pair of validators above
## refuse a save whose board has changed instead of re-homing an army in silence.
##
## Below the version that writes it there is nothing to read and the map answers,
## which is exact rather than a guess: such a save always seated the board's full
## roster, so every army it names began on the HQ its map file gave it. Never
## inferred from the save's own ownership either way — mid-match a conqueror owns
## the HQ it took as well as its own, and "the HQ this team owns" has two answers
## exactly when the distinction matters.
##
## Floors on anything it cannot read, like its siblings, and to the same map-derived
## answer; `_home_hq_error` reports a list that is wrong rather than leaving it to
## be papered over here.
static func _decode_home_hq(
	data: Dictionary, map: MapData, roster: Array[int]
) -> Dictionary[int, Vector2i]:
	if _claimed_version(data) < int(SaveSchema.KEY_RULES["home_hq"]["since"]):
		return Seating.home_hqs(map, roster)
	var saved: Variant = data.get("home_hq")
	if not (saved is Array):
		return Seating.home_hqs(map, roster)
	var homes: Dictionary[int, Vector2i] = {}
	for entry: Variant in saved as Array:
		if not (entry is Dictionary):
			return Seating.home_hqs(map, roster)
		var record := entry as Dictionary
		for key: String in SaveSchema.HOME_HQ_KEY_RULES:
			if not SaveSchema.is_shape(
				record.get(key), int(SaveSchema.HOME_HQ_KEY_RULES[key]["shape"])
			):
				return Seating.home_hqs(map, roster)
		homes[int(record["team"])] = Vector2i(int(record["x"]), int(record["y"]))
	return homes


## "" when the save's home HQs name armies that play, at most one each, else why
## they do not.
##
## A home HQ is what an army is beheaded through, so a stray entry is a seat that
## can be taken out of a match it was never in, and a second entry for one army is
## an ambiguity the last line silently wins — either way the match loads clean and
## the rule that ends it fires on the wrong cell. Whether the cell is a real HQ on a
## real board is `board_error`'s, which has the map this one deliberately does not.
##
## An army with *no* entry is `board_error`'s too, and for the same reason: whether
## one was owed depends on whether the board homes that seat at all, which is a
## question only the map answers.
##
## Asked only of the version that writes it. Below that there is no list to be
## wrong — `_decode_home_hq` takes the map's answer, which no save can damage.
static func _home_hq_error(data: Dictionary) -> String:
	var version := _claimed_version(data)
	if version < int(SaveSchema.KEY_RULES["home_hq"]["since"]):
		return ""
	var error := SaveSchema._entries_error(
		data["home_hq"], SaveSchema.HOME_HQ_KEY_RULES, version, "home HQ"
	)
	if error != "":
		return error
	var roster := _roster(data)
	var seen: Dictionary[int, bool] = {}
	for entry: Dictionary in data["home_hq"] as Array:
		var team := int(entry["team"])
		if not roster.has(team):
			return "the save gives a home HQ to team %d, which does not play" % team
		if seen.has(team):
			return "the save gives team %d two home HQs" % team
		seen[team] = true
	return ""


## "" when the save's casualty list describes a match that could still be resumed,
## else why it does not.
##
## Three rules, and each of them refuses a save that would otherwise load clean and
## break later — the delayed-crash class `board_error` exists to keep out:
##
##   - every name is a seat the board dealt. An army that does not play cannot
##     have fallen, so a stray entry quietly takes a side out of a match it was
##     never in.
##   - somebody is left standing. A list naming everyone decodes with `winner`
##     still zero — victory is not re-derived on load — and the first `EndTurn`
##     then indexes an empty roster, after the power expiry has already run: the
##     turn is stuck for good and the save gave no warning.
##   - the winner, when there is one, is still in the match. A match cannot have
##     been won by an army that was taken off the board.
##
## A fallen army *holding the turn* is deliberately admitted, and that is the line
## this function draws. It is a state the sim genuinely reaches — with three or more
## armies, the side taking its turn loses its last unit to a counter-attack or to an
## empty tank, `_check_rout` fells it there and then, and no winner follows because
## others are still fighting, so the hand has not moved when the player saves. It
## also resumes cleanly: `next_team()` skips the fallen seat and the day wrap reads
## the *roster*, so the very next `EndTurn` hands play on correctly. Refusing it
## would not protect anybody; it would condemn the only save slot a player has.
##
## The list is allowed to be empty (nobody has fallen) and allowed to be everyone
## but one (the match is over and `winner` says so).
##
## Asked only of the version that writes it. Below that a match ended at the first
## elimination, so there was no list to be wrong.
static func _eliminated_error(data: Dictionary) -> String:
	if _claimed_version(data) < int(SaveSchema.KEY_RULES["eliminated"]["since"]):
		return ""
	var saved: Array = data["eliminated"]
	var roster := _roster(data)
	var fallen: Dictionary[int, bool] = {}
	for team: Variant in saved:
		if not SaveSchema.is_shape(team, SaveSchema.Shape.NUMBER):
			return "'eliminated' is malformed"
		if not roster.has(int(team)):
			return "the save eliminates team %d, which does not play" % int(team)
		fallen[int(team)] = true
	if fallen.size() >= roster.size():
		return "the save eliminates every army, leaving nobody to take the turn"
	var winner := int(data.get("winner", 0))
	if winner != 0 and fallen.has(winner):
		return "the save was won by team %d, which it has eliminated" % winner
	return ""


## "" when the save's grouping names armies that play and gives each a side, else
## why it does not.
##
## Its own check rather than a clause of `_teams_error`, because the two answer
## different questions: the roster says who is at the table, the grouping says who
## stands with whom. A grouping is allowed to be partial — naming two armies as a
## pair leaves the rest each their own side, which is exactly a 3v1 — so the only
## rules are that every army it names is one that plays and every side id is a
## number. A grouping naming an army the roster does not is a save describing a
## match no board could produce, and it would silently allow or forbid a shot.
##
## A grouping putting every army on one side is deliberately not refused: FP3 makes
## "every surviving army shares one side" the victory condition, so that state is
## about to be a match that ends rather than a match no board could produce.
##
## Asked only of the version that writes it. Below that there is no grouping to be
## wrong: the save recorded a free-for-all by construction.
static func _sides_error(data: Dictionary) -> String:
	if _claimed_version(data) < int(SaveSchema.KEY_RULES["sides"]["since"]):
		return ""
	var saved: Dictionary = data["sides"]
	var roster := _roster(data)
	for key: Variant in saved:
		var name := String(key)
		if not name.is_valid_int() or not roster.has(int(name)):
			return "the save allies team %s, which does not play" % name
		if not SaveSchema.is_shape(saved[key], SaveSchema.Shape.NUMBER):
			return "the save's side for team %s is malformed" % name
	return ""


## "" when the save's roster is one a board could have seated, else why it could not.
##
## The one format rule that is about a side rather than a field, and it is here rather
## than in `board_error` because every other per-side rule is derived from its answer: a
## roster of `[1, 9]` would have this file demanding a purse and a commander for team 9,
## and reporting their absence as the damage instead of the cause. `MapData` refuses the
## same roster at parse, so a save claiming one describes a match no board could produce.
##
## Asked only of the version that writes it. Below that there is no roster to be wrong —
## the save recorded a duel by construction.
static func _teams_error(data: Dictionary) -> String:
	if _claimed_version(data) < int(SaveSchema.KEY_RULES["teams"]["since"]):
		return ""
	var declared: Array = data["teams"]
	var roster: Array[int] = []
	for team: Variant in declared:
		if not SaveSchema.is_shape(team, SaveSchema.Shape.NUMBER):
			return "'teams' is malformed"
		roster.append(int(team))
	if not _is_seatable(roster):
		return "the save seats teams %s, which no board could have dealt" % [roster]
	return ""


## Whether `roster` is a roster a match may have seated: at least a duel, at most the
## seats the rules recognise, each of them a real seat, each named once, in seat order.
##
## A *gap* is legal and was not always: a board is still authored full and
## `MapData._build_roster` still deals its seats from 1 with none missing, but a match
## fills any two or more of them (open-seats plan D1), so `[1, 3, 4]` is the perfectly
## ordinary state of a four-seat board played by three. What stays refused is a roster no
## seating could have produced — a seat outside the rules, a seat twice, seats out of
## order, or too few armies to have a match at all — because every per-side rule in this
## file is derived from this list, and one that is wrong reports the damage rather than
## the cause.
static func _is_seatable(roster: Array[int]) -> bool:
	if roster.size() < GameState.MIN_SEATS or roster.size() > MapData.PLAYER_TEAMS.size():
		return false
	var previous := 0
	for team in roster:
		if not MapData.PLAYER_TEAMS.has(team) or team <= previous:
			return false
		previous = team
	return true


## "" when the save's RNG state is a whole number spelled out in full, else why it is
## not. The one field a shape cannot finish: a 64-bit state does not survive JSON's
## single number type, so it is stored as text and `SaveSchema.Shape.STRING` is satisfied by any
## text at all — while `int()` turns whatever is left of a damaged one into 0, a seed
## nobody rolled, and every shot for the rest of the match lands differently than the
## match this save recorded.
static func _rng_state_error(data: Dictionary) -> String:
	if not String(data["rng_state"]).is_valid_int():
		return "'rng_state' is malformed"
	return ""


## "" when the save's unit names are ones a board could have given, else why they
## are not. `UnitTag`'s rule asked at the codec's own door: a save is the second way
## a unit reaches the board, and one naming two units the same names neither — the
## objective asking whether it still stands would have two answers, which is exactly
## what the parser refuses before a mission can pick one.
##
## The entry pass above has already shaped every `tag` as text, so this only asks
## what those strings say. Gated on the version that writes the field, like every
## other read of it: below it no unit carries a name at all.
static func _unit_tags_error(data: Dictionary, version: int) -> String:
	if version < int(SaveSchema.UNIT_KEY_RULES["tag"]["since"]):
		return ""
	var tags: Array[StringName] = []
	for entry: Dictionary in data["units"] as Array:
		var tag := StringName(String(entry["tag"]))
		var error := UnitTag.name_error(tag)
		if error != "":
			return error
		tags.append(tag)
	return UnitTag.duplicate_error(tags)


## "" when the save carries a purse for every side that plays, and every purse is money.
static func _funds_error(data: Dictionary) -> String:
	var funds: Dictionary = data["funds"]
	for team in _roster(data):
		if not funds.has(str(team)):
			return "save has no funds for team %d" % team
		if not SaveSchema.is_shape(funds[str(team)], FUNDS_SHAPE):
			return "the save's funds for team %d are malformed" % team
	return ""


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
