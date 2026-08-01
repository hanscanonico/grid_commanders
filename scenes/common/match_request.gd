class_name MatchRequest
extends RefCounted
## Which match to play, stated once and in full: the board, the sides, the
## commanders, the tier, and whether this is a fresh start or the saved match
## resumed.
##
## The match a battle produces was always typed — `BattleSetup.BuiltMatch` — but
## the *request* that produced it was not (architecture finding A3). Menu launch,
## CLI override, resume, rematch and watch mode were one procedural merge inside
## `BattleSetup.build`, which read a mutable autoload, scanned `OS` and wrote
## back to that autoload as it went. There is now one object to point at, made by
## one of three adapters:
##
## * `from_menu` — the player's choices on the main menu.
## * `from_match` — the match actually running, for a rematch. Derived from the
##   `GameState`, so a resumed save's board and commanders replay correctly even
##   though the menu never saw them.
## * `apply_cmdline` — the flags, layered *over* either of the above. Applied on
##   every boot, so a headless capture and a menu launch arrive at the same board
##   by the same route, exactly as they did when `build` scanned the args itself.
##
## Node-free on purpose, like the rest of the logic the scene leans on, and
## unlike the autoload it replaces: the flag grammar that decides which match a
## `make smoke` scenario plays is now something tests can read directly.
##
## `Settings` and `GameSpeed` are deliberately absent (refactor guardrail R4).
## The speed and the retired tutorial hints are device preferences, not match
## state — a resumed match plays at today's preference, not the one it was saved
## under — so they travel in `user://settings.cfg` and never through here.

## The board a battle scene booted directly comes up on — `make screenshot` and
## every smoke scenario that names no `--map=`. Deliberately *not*
## `MapCatalog.TUTORIAL_MAP_PATH`: that one is which board the *menu* leads with,
## and moving this too would reshoot the whole sweep, whose merge bar is
## byte-identical captures (COM-122).
const DEFAULT_MAP_PATH := "res://maps/first_steps.txt"

## The board. A path, already resolved: `--map=` accepts a catalog *name*, and
## resolving it is the CLI adapter's job so everything downstream sees a path.
var map_path := DEFAULT_MAP_PATH
## Teams played by the computer. Blue by default; `--hotseat` clears it and
## `--watch` fills it with both.
var ai_teams: Array[int] = [2]
var fog_enabled := false
## A tier id in `data/difficulty/`, resolved against `DifficultyDB` by
## `BattleSetup` — this object stays free of the databases so it can be built
## before they are loaded.
var difficulty: StringName = Difficulty.DEFAULT_ID
## team -> commander id. A team with no entry plays without a commander, which is
## the default and reproduces the pre-commander game exactly.
var commanders: Dictionary = {}
## Resume `SaveGame.SAVE_PATH` instead of starting fresh. The saved match brings
## its own board, sides, commanders and tier, so everything above is ignored when
## this is true and the file is actually there.
var resume := false
## `--seed=`. Negative means randomize, which is every match but a watched one.
var seed_value := -1
## `--replay=<path>`: watch a recorded match instead of playing one. The recording
## brings its own board, seating, grouping, commanders and fog — it opens on a
## `SaveCodec` envelope, exactly as `resume` does — so everything above is ignored
## when this is set and the file is actually readable.
##
## Deliberately not `--watch` with a file attached: that flag re-plans a Balance Lab
## row from its seed and must keep diverging when the AI changes, which is the whole
## of its job (replay plan D7). This one cannot diverge, because the decisions are in
## the file.
var replay_path := ""
## `--watch`: both seats are the computer's and the match came from a Balance Lab
## spec. The scene prints its result and exits when the match ends, so a watched
## run can be diffed against the CSV row it was launched from.
var watching := false
## Watch mode only: the day after which a match nobody has won is scored on the
## harness's own tiebreak. `--days=`, matching the Lab's flag. Normal play ignores
## it entirely — a hot-seat or player-vs-AI match has no day limit.
var days_cap := BalanceMatchEngine.DEFAULT_DAYS
## team -> the raw `--red=<co>:<tier>` / `--blue=` spec, kept unparsed because the
## Lab's own parser needs the commander and difficulty databases. `BattleSetup`
## resolves them, so a spec means the same thing in the window as in the report.
var side_specs: Dictionary = {}
## team -> side id: how the armies are grouped into sides. Empty is a free-for-all
## — every army its own side — which is what the menu's seat strip and `--sides=`
## both produce for an ungrouped table (four-players plan D1: the grouping is the
## *match's* choice, never the board's, so the same map hosts a free-for-all, a
## 2v2 and a 3v1).
var sides: Dictionary = {}
## Which of the board's seats this match fills, in seat order — **empty is every
## one of them**, which is what every launch said before a seat could close.
##
## The match's fourth setup fact (open-seats plan D2), beside the board, the sides
## and the commanders. The board still owns how many seats exist and where they
## sit; this only says which are taken, so a four-seat map plays a duel without
## being copied into a second, smaller file. `GameState.create` is what refuses a
## seating that names a seat no board deals or leaves fewer than two armies — this
## object states the request, it does not vet it against a map it has not loaded.
var seats: Array[int] = []


## The main menu's choices. `resume` is the Continue button: the saved match
## applies its own board, commanders, AI sides and tier, so the rest is ignored.
static func from_menu(
	map_path_in: String,
	ai_teams_in: Array[int],
	fog_enabled_in: bool,
	difficulty_in: StringName,
	commanders_in: Dictionary,
	resume_in: bool,
	sides_in: Dictionary = {},
	seats_in: Array[int] = []
) -> MatchRequest:
	var request := MatchRequest.new()
	request.map_path = map_path_in
	request.ai_teams = ai_teams_in.duplicate()
	request.fog_enabled = fog_enabled_in
	request.difficulty = difficulty_in
	request.commanders = commanders_in.duplicate()
	request.resume = resume_in
	request.sides = sides_in.duplicate()
	request.seats = seats_in.duplicate()
	return request


## The match actually running, so a rematch replays *it* — including one resumed
## from a save, whose map, sides and commanders the menu never saw — rather than
## whatever the menu last chose. Never a resume: the point is to play this board
## again from day one, not to reload the disk.
static func from_match(
	game: GameState, ai_teams_in: Array[int], difficulty_in: StringName
) -> MatchRequest:
	var request := MatchRequest.new()
	request.map_path = game.map_path
	request.ai_teams = ai_teams_in.duplicate()
	request.fog_enabled = game.fog_enabled
	request.difficulty = difficulty_in
	request.sides = game.sides.duplicate()  # a rematch keeps the grouping it was played under
	# And the seating, off the live roster: a rematch of a reduced match is *that*
	# match again, not the full board it was played on a corner of.
	request.seats = game.teams.duplicate()
	for team in game.teams:
		request.commanders[team] = game.commander_of(team).id
	return request


## Layers the command line over whatever this request already says. Every flag
## here is an override, so a menu launch with no flags is unchanged and a
## headless capture gets the board it named.
func apply_cmdline(args: PackedStringArray) -> void:
	if CmdArgs.has(args, "--map"):
		var wanted_map := CmdArgs.value(args, "--map")
		# Through MapCatalog so a balance fixture resolves by the same name the
		# headless Lab knows it by — a watched match must be the same board its
		# CSV row was played on. A name nothing answers to is said out loud rather
		# than quietly played on the default board: a watched match on the wrong
		# map still prints a result line, and that line is what the
		# replay-fidelity check diffs.
		var resolved := MapCatalog.resolve(wanted_map)
		if resolved == "":
			push_error(
				(
					"battle: unknown map '%s'; playing %s instead. Known: %s"
					% [wanted_map, map_path, ", ".join(MapCatalog.resolvable_names())]
				)
			)
		else:
			map_path = resolved
	if CmdArgs.has(args, "--days"):
		days_cap = maxi(1, int(CmdArgs.value(args, "--days")))
	if CmdArgs.has(args, "--replay"):
		replay_path = CmdArgs.value(args, "--replay").strip_edges()
	# Read before `--co`, and that order is the whole reason it sits here: a
	# commander list is positional over the seats that *play*, so the seating has to
	# be known before the list is dealt out over it.
	if CmdArgs.has(args, "--seats"):
		seats = parse_seats_flag(CmdArgs.value(args, "--seats"))
	if CmdArgs.has(args, "--co"):
		commanders = parse_co_flag(CmdArgs.value(args, "--co"), filled_roster())
	if CmdArgs.has(args, "--difficulty"):
		difficulty = StringName(CmdArgs.value(args, "--difficulty").strip_edges())
	if CmdArgs.has(args, "--red"):
		side_specs[GameState.TEAMS[0]] = CmdArgs.value(args, "--red")
	if CmdArgs.has(args, "--blue"):
		side_specs[GameState.TEAMS[1]] = CmdArgs.value(args, "--blue")
	if CmdArgs.has(args, "--sides"):
		sides = parse_sides_flag(CmdArgs.value(args, "--sides"))
	if CmdArgs.has(args, "--seed"):
		seed_value = maxi(0, int(CmdArgs.value(args, "--seed")))
	if CmdArgs.flag(args, "--hotseat"):
		ai_teams = []
	if CmdArgs.flag(args, "--fog"):
		fog_enabled = true
	if CmdArgs.flag(args, "--watch"):
		# Watch mode (balance plan BS3): every seat is the computer's, each with
		# its own commander and its own tier, and the match RNG is pinned. That is
		# the whole difference from a normal launch — the sim, the planners and the
		# animations are the shipped ones, which is what makes the watched match
		# the same match as its headless row (plan D7).
		#
		# *Which* seats those are is the board's answer and no board is loaded yet, so
		# `BattleSetup` seats the match roster once one is. This is the duel every
		# board was until a map could seat more (four-players plan D1).
		ai_teams = MapData.DEFAULT_TEAMS.duplicate()
		watching = true


## `--sides=1+3v2+4`: armies joined by `+` stand together, groups separated by `v`
## fight each other. `--sides=1v2v3v4` and an absent flag are both free-for-alls,
## and both produce an empty dictionary — the value `GameState.allied` reads as
## "every army its own side", so a free-for-all launched this way is the match
## every board played before groupings existed.
##
## A seat the flag never names keeps its own side, so `--sides=1+2` on a four-army
## board is a pair against two loners — which is what `GameState.allied` reads a
## partial grouping as, so honouring it is the flag agreeing with the hostility
## authority rather than second-guessing it.
##
## This parses and nothing else: it refuses only what it cannot read, out loud,
## because a grouping nobody meant is a match nobody meant. Whether a grouping
## leaves anybody hostile depends on the seats the *board* deals, which no flag
## can see — `BattleSetup.build` answers that once a board is loaded, the same
## layering `--watch`'s seat list already uses.
static func parse_sides_flag(value: String) -> Dictionary:
	var grouped: Dictionary = {}
	var groups := value.strip_edges().split("v", false)
	for side in groups.size():
		for army: String in groups[side].split("+", false):
			var seat := army.strip_edges()
			if not seat.is_valid_int():
				push_error("battle: --sides=%s is not a grouping; ignoring it" % value)
				return {}
			grouped[int(seat)] = side
	# A group per army is the free-for-all the empty dictionary already says, and
	# spelling one out is not a mistake to report.
	if grouped.size() == groups.size():
		return {}
	return grouped


## The seats a commander list is dealt out over: the ones this request fills, or
## every seat the rules recognise when it fills them all. Not the board's roster —
## no board is loaded when the flags are read — which costs nothing, because
## `parse_co_flag` drops anything past the last seat either way.
func filled_roster() -> Array[int]:
	return seats if not seats.is_empty() else GameState.TEAMS


## `--seats=1,3,4`: which of the board's seats play, in the order written. An empty
## list is every seat, which is what the flag's absence already means — so
## `--seats=` clears a seating a rematch or the menu had put there, the same way
## `--co=` clears the commanders it picked.
##
## Parses and nothing else, like `parse_sides_flag` beside it: whether these are
## seats the *board* deals, and whether enough of them are left to make a match, are
## questions about a map no flag can see. `GameState.create` is the one authority on
## both and refuses out loud, so a `--seats=` naming one army fails the build rather
## than quietly playing something else.
##
## What it does refuse is a list it cannot read — a seating nobody meant is a match
## nobody meant, and silently playing the whole board instead would look exactly
## like a run that named no seats at all.
static func parse_seats_flag(value: String) -> Array[int]:
	var filled: Array[int] = []
	for entry: String in value.split(",", false):
		var seat := entry.strip_edges()
		if not seat.is_valid_int():
			push_error("battle: --seats=%s is not a seating; playing every seat" % value)
			return []
		filled.append(int(seat))
	return filled


## `--co=alina_ward,viktor_draeg`: one id per seat in seat order, any of them blank
## for no commander, and anything past the last seat a board could have dropped.
## Keeps headless demos and captures able to pick a matchup without the menu,
## exactly as `--map` and `--fog` do.
##
## Positional over `roster`, which is the seats that actually play: commanders
## belong to armies, so on `--seats=1,3` the second id is seat 3's general and not a
## pick for a chair nobody is in.
static func parse_co_flag(value: String, roster: Array[int] = GameState.TEAMS) -> Dictionary:
	var picked: Dictionary = {}
	var ids := value.split(",")
	for i in mini(ids.size(), roster.size()):
		var id := ids[i].strip_edges()
		if id != "":
			picked[roster[i]] = StringName(id)
	return picked
