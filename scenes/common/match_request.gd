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


## The main menu's choices. `resume` is the Continue button: the saved match
## applies its own board, commanders, AI sides and tier, so the rest is ignored.
static func from_menu(
	map_path_in: String,
	ai_teams_in: Array[int],
	fog_enabled_in: bool,
	difficulty_in: StringName,
	commanders_in: Dictionary,
	resume_in: bool
) -> MatchRequest:
	var request := MatchRequest.new()
	request.map_path = map_path_in
	request.ai_teams = ai_teams_in.duplicate()
	request.fog_enabled = fog_enabled_in
	request.difficulty = difficulty_in
	request.commanders = commanders_in.duplicate()
	request.resume = resume_in
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
	for team in GameState.TEAMS:
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
	if CmdArgs.has(args, "--co"):
		commanders = parse_co_flag(CmdArgs.value(args, "--co"))
	if CmdArgs.has(args, "--difficulty"):
		difficulty = StringName(CmdArgs.value(args, "--difficulty").strip_edges())
	if CmdArgs.has(args, "--red"):
		side_specs[GameState.TEAMS[0]] = CmdArgs.value(args, "--red")
	if CmdArgs.has(args, "--blue"):
		side_specs[GameState.TEAMS[1]] = CmdArgs.value(args, "--blue")
	if CmdArgs.has(args, "--seed"):
		seed_value = maxi(0, int(CmdArgs.value(args, "--seed")))
	if CmdArgs.flag(args, "--hotseat"):
		ai_teams = []
	if CmdArgs.flag(args, "--fog"):
		fog_enabled = true
	if CmdArgs.flag(args, "--watch"):
		# Watch mode (balance plan BS3): both seats are the computer's, each with
		# its own commander and its own tier, and the match RNG is pinned. That is
		# the whole difference from a normal launch — the sim, the planners and the
		# animations are the shipped ones, which is what makes the watched match
		# the same match as its headless row (plan D7).
		ai_teams = GameState.TEAMS.duplicate()
		watching = true


## `--co=alina_ward,viktor_draeg`: red first, blue second, either side blank for
## no commander. Keeps headless demos and captures able to pick a matchup without
## the menu, exactly as `--map` and `--fog` do.
static func parse_co_flag(value: String) -> Dictionary:
	var picked: Dictionary = {}
	var ids := value.split(",")
	for i in mini(ids.size(), GameState.TEAMS.size()):
		var id := ids[i].strip_edges()
		if id != "":
			picked[GameState.TEAMS[i]] = StringName(id)
	return picked
