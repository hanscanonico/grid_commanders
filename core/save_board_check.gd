class_name SaveBoardCheck
extends RefCounted
## The half of save validation that needs the board.
##
## `SaveCodec.validate` deliberately answers without a map, so a save can be named on
## a menu that has loaded none; every question that can only be asked once the board
## is in hand lives here instead — which cells exist, what may stand on them, which
## armies a board homes, and which riders could have boarded their carriers. The codec
## already argued the seam on `board_error`; this file is that argument taken the rest
## of the way, so a version bump has room to grow the envelope's own rules.
##
## `SaveCodec.board_error` stays as the one-line call site every caller already uses.
##
## What is *not* here: the roster and the claimed version. Both are read by a dozen
## board-less rules in the codec as well as by these, so the codec keeps them and this
## file asks — one derivation, not two (`SaveCodec.roster`, `SaveCodec.claimed_version`).

## The fewest capture points a part-captured property can still be holding. Zero is
## not a property on the brink, it is one already flipped: `CaptureCommand.apply`
## erases the entry the moment the meter empties, so a save that records one is
## describing a board the rules cannot produce. The ceiling is the match's own
## `capture_points`, asked of the config a decoded save actually plays under rather
## than pinned to a constant beside it.
const MIN_CAPTURE_POINTS := 1


## "" when every value in `data` describes something that can exist on `map`, else
## the reason it cannot. `SaveCodec.validate`'s sibling, split from it for one reason:
## these questions need the board, and `validate` deliberately answers without one so a
## save can be named on a menu that has loaded no map. `SaveCodec.board_error` forwards
## here, so every caller keeps the call site it already holds.
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
	var claimed := SaveCodec.claimed_version(data)
	var version := claimed if claimed != SaveCodec.NO_VERSION else SaveCodec.READABLE_VERSIONS[0]
	# The format pass, in order: every list's own entries first, then the two scalar
	# facts about the board a version can still get wrong. Each is independent of the
	# ones after it, so the order here is only "cheapest and most specific first" —
	# unlike `validate`'s walk, nothing below is derived from an earlier rule's answer.
	var format_checks: Array[Callable] = [
		func() -> String:
			return SaveSchema.entries_error(
				data.get("units"), SaveSchema.UNIT_KEY_RULES, version, "unit"
			),
		func() -> String:
			return SaveSchema.entries_error(
				data.get("owners"), SaveSchema.OWNER_KEY_RULES, version, "owner"
			),
		func() -> String:
			return SaveSchema.entries_error(
				data.get("capture_progress", []),
				SaveSchema.PROGRESS_KEY_RULES,
				version,
				"capture progress"
			),
		func() -> String: return _turn_and_winner_error(data),
		func() -> String: return SaveCodec.ai_teams_error(data),
	]
	for check: Callable in format_checks:
		var error: String = check.call()
		if error != "":
			return error
	# The computer's sides are teams like any other, and the last one this had never
	# asked: a save handing the AI a side that does not play resumes with a side nobody
	# plays at all — `Battle` takes the list as written.
	var roster := SaveCodec.roster(data)
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
		if hp < SaveCodec.MIN_HP or hp > SaveCodec.MAX_HP:
			return (
				"unit '%s' has %d HP, outside %d-%d"
				% [entry["type"], hp, SaveCodec.MIN_HP, SaveCodec.MAX_HP]
			)
		var team := int(entry["team"])
		if not roster.has(team):
			return "unit '%s' belongs to team %d, which does not play" % [entry["type"], team]
		if int(entry["carrier"]) != SaveCodec.NO_CARRIER:
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
		func() -> String: return _capture_progress_error(data, map),
	]
	for check: Callable in cell_checks:
		var cells_error: String = check.call()
		if cells_error != "":
			return cells_error
	return _home_hq_board_error(data, map, version)


## "" when the save's home HQs are the ones its board deals, else why they are not.
## `SaveCodec`'s own home-HQ shape check is the other half of the same field, split
## for the reason this file is: which cells exist, what stands on them, and which
## armies a board homes at all are the board's answers.
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
	var error := SaveSchema.entries_error(
		data.get("home_hq"), SaveSchema.HOME_HQ_KEY_RULES, version, "home HQ"
	)
	if error != "":
		return error
	error = _cells_on_board(data["home_hq"], map, "home HQ")
	if error != "":
		return error
	var expected := Seating.home_hqs(map, SaveCodec.roster(data))
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
	var roster := SaveCodec.roster(data)
	var turn := int(data.get("current_team", 0))
	if not roster.has(turn):
		return "the save's turn belongs to team %d, which does not play" % turn
	var winner := int(data.get("winner", 0))
	if winner != 0 and not roster.has(winner):
		return "the save was won by team %d, which does not play" % winner
	return ""


## "" when every capture underway is one this board could be holding, else why it
## is not. The list's cell check plus the two questions nothing was asking.
##
## The points bound is what the harm turns on. `CaptureCommand.apply` defaults an
## unrecorded property to full and subtracts from what it reads, so an entry at zero
## or below leaves a negative remainder — the property flips on a single action,
## which for a home HQ is an army beheaded in one move, and the cut-in replays a
## meter draining from 0 to 0. Above the cap the same property is merely slow, or
## slower than any unit can finish.
##
## The cell being a property at all is the other half, and it is the loader's to ask
## for the reason every other rule here is: `CaptureCommand.validate` refuses a
## non-property destination, so no command puts a pip on grass, and a save is the one
## route onto the board that never went through a command.
static func _capture_progress_error(data: Dictionary, map: MapData) -> String:
	var entries: Variant = data.get("capture_progress", [])
	var off_board := _cells_on_board(entries, map, "capture in progress")
	if off_board != "":
		return off_board
	var cap := RulesConfig.load_default().capture_points
	for entry: Dictionary in entries as Array:
		var cell := Vector2i(int(entry["x"]), int(entry["y"]))
		var points := int(entry["points"])
		if points < MIN_CAPTURE_POINTS or points > cap:
			return (
				"capture in progress at %s has %d points, outside %d-%d"
				% [cell, points, MIN_CAPTURE_POINTS, cap]
			)
		if not map.terrain_at(cell).is_property:
			return "capture in progress at %s, which is not a property" % cell
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
static func carriage_error(state: GameState) -> String:
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
