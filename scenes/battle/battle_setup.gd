class_name BattleSetup
extends RefCounted
## Builds the match the battle scene is about to play, from the MatchRequest that
## asked for it: which map, which commanders, which sides the computer takes, and
## whether this is a fresh start or a resumed save.
##
## Split out of Battle because none of it is *flow*. Battle runs a match; this
## decides which match — and since architecture finding A3, it decides it from
## one explicit argument. It no longer reads `MatchConfig`, no longer scans the
## command line, and no longer writes anything back: staging the request is the
## menu's job, layering the flags is `MatchRequest.apply_cmdline`'s, and what
## comes out is a value the caller owns.
##
## Node-free, like the rest of the logic the scene leans on: it takes a request
## and the databases, and hands back plain simulation objects.


class BuiltMatch:
	var map: MapData
	var game: GameState
	## Teams played by the computer. Blue by default; `--hotseat` clears it.
	var ai_teams: Array[int] = []
	## The tier the computer plays at. Never null — DifficultyDB always answers —
	## and the source of both the AI's profile and the id the save records.
	var difficulty: Difficulty
	## team -> Difficulty, when the sides play at *different* tiers. The seat
	## strip's per-seat picks fill it, so does watch mode, and so does a resumed
	## save for whatever it lists in `seat_difficulty` and `auto_tiers` below; a
	## match that tuned no seat of its own plays every computer seat at
	## `difficulty` above, which is the tier the save records.
	var per_team_difficulty: Dictionary[int, Difficulty] = {}
	## team -> tier id, for the computer seats the *launch* gave a tier of their
	## own (COM-225) — the ids behind `per_team_difficulty`, kept because they are
	## what a save records and what a rematch is derived from. Narrowed to the
	## seats the computer actually took, so nothing in it is inert.
	var seat_difficulty: Dictionary[int, StringName] = {}
	## team -> tier id, for seats a player had handed to the computer mid-match
	## through the pause menu's Auto row — a subset of `ai_teams`, carried by a
	## resumed save so Battle's own live copy (`Battle.auto_tiers`) starts where
	## the save left it. Empty for a fresh match or a rematch: Auto always
	## starts off, same as before Auto existed.
	var auto_tiers: Dictionary[int, StringName] = {}
	## team -> the planner that plays it, one AIController per seat at that seat's
	## own tier. Built here rather than by the scene because a tier is only an
	## AIProfile (difficulty plan D2/D3), so choosing the profile is the last step
	## of choosing the match — and every team gets its own controller even when the
	## tiers match, since a controller caches a threat map for the turn it is
	## planning and two teams sharing one would be reading each other's.
	var planners: Dictionary[int, AIController] = {}
	## Set only for `--replay=`: the recording this match is a playback of. Null for
	## every match that is actually being played, which is what everything
	## downstream asks it.
	var replay: ReplayPlayer = null
	## The file it was read from, so restarting a playback can open the same
	## recording again. A replay has no live board to derive a rematch from.
	var replay_path := ""


## Why there is no match, in the sentence the player is shown. `build` fills it
## on every refusal, beside the `push_error` that has always gone to the log —
## an export build has no log a player reads, so a launch that failed with
## nothing on screen was a frozen board with no way out of it.
class Failure:
	var message := ""


## Null, with a pushed error, when the board or the state cannot be built — the
## same contract `GameState.create` and `MapData.load_from_file` already have,
## and the reason these two failures stopped being `assert()`s: asserts are
## stripped from an exported release build, so a bad `--map=` used to leave a
## null map for the scene to dereference on its first touch instead of saying so.
##
## `save_path` is the slot a resume reads, defaulted like every reader in
## `SaveGame` so a test names its own rather than the player's. `failure` is the
## caller's copy of the sentence behind that null, defaulted so the instruments
## and the tests that only ask whether a match built need not carry one.
static func build(
	request: MatchRequest,
	terrain_db: TerrainDB,
	unit_db: UnitDB,
	commander_db: CommanderDB,
	save_path: String = SaveGame.SAVE_PATH,
	failure: Failure = null
) -> BuiltMatch:
	var result := BuiltMatch.new()
	var chart: DamageChart = load(DamageChart.DEFAULT_PATH)
	var difficulty_db := DifficultyDB.load_default()
	result.ai_teams = request.ai_teams.duplicate()
	result.difficulty = difficulty_db.by_id(request.difficulty)
	if request.replay_requested:
		return _build_replay(
			request, terrain_db, unit_db, chart, commander_db, difficulty_db, failure
		)
	# A campaign resume reads the battle embedded in the campaign's profile — the
	# same `SaveCodec` envelope as the skirmish slot, in a different place on
	# purpose. Refused out loud rather than dropped to a fresh mission start, for
	# COM-121's reason: day one of the mission would look exactly like the resume
	# working, with the player's half-played attempt quietly gone.
	if request.campaign_resume != &"":
		return _build_campaign_resume(
			request, terrain_db, unit_db, chart, commander_db, difficulty_db, failure
		)
	# A slot that holds nothing is not a resume that failed: the request states a
	# board too, and playing it is what a launch that found an empty slot has always
	# done. A save that is *there* and will not load is the other case, and falling
	# through to that same fresh match is how the player who asked for Day 12 got day
	# one on whatever board the menu was showing, with nothing said (COM-121).
	if request.resume and SaveGame.has_save(save_path):
		var loaded := SaveGame.load_game(terrain_db, unit_db, chart, save_path, commander_db)
		if loaded == null:
			return _refuse(failure, "The saved match cannot be read; there is no match to play.")
		# A resumed save brings its own map, sides, commanders and tier;
		# nothing the menu last chose applies to it.
		result.game = loaded.state
		result.ai_teams = loaded.ai_teams
		result.difficulty = difficulty_db.by_id(loaded.difficulty)
		result.map = result.game.map
		_apply_seat_tiers(result, loaded.seat_tiers, difficulty_db)
		_apply_auto_tiers(result, loaded, difficulty_db)
		_seat_planners(result, unit_db)
		return result
	var map_path := request.map_path
	result.map = MapData.load_from_file(map_path, terrain_db)
	# Playing the default board instead is a skirmish's answer — the launch asked
	# for a match and any board is one. A mission's board carries its objectives
	# and its scripted beats, so the substitution would open a mission whose script
	# resolves against nothing; see MatchRequest.campaign_mission.
	if (
		result.map == null
		and not request.campaign_mission
		and map_path != MatchRequest.DEFAULT_MAP_PATH
	):
		push_error(
			"failed to load %s; falling back to %s" % [map_path, MatchRequest.DEFAULT_MAP_PATH]
		)
		map_path = MatchRequest.DEFAULT_MAP_PATH
		result.map = MapData.load_from_file(map_path, terrain_db)
	if result.map == null:
		return _refuse(failure, "The board %s cannot be loaded." % map_path)
	# The launch's per-seat tiers go on before the side specs do, so a Lab
	# `--red=<co>:<tier>` still wins for the seat it names: that grammar states one
	# seat outright, where these are the match's own tier for each of them.
	_apply_seat_tiers(result, _typed_tiers(request.seat_difficulty), difficulty_db)
	# Commanders resolved *before* the state is built, so the opening side's day-1
	# begin_turn runs against its real doctrine (a supply radius, a repair discount)
	# rather than the neutral one it would see if commanders were set afterward.
	var commanders := _resolve_commanders(result, commander_db, difficulty_db, request)
	# The seating rides in with everything else and is vetted where it can be: only
	# the board knows which seats it deals, so `create` refuses a seating naming one
	# it does not, or leaving fewer than two armies, and says which (open-seats D2).
	# There is no guessing and no silent filling — a `--seats=` nobody could play
	# leaves no match, and `Battle` disables itself rather than inventing one.
	result.game = GameState.create(result.map, unit_db, chart, commanders, request.seats)
	if result.game == null:
		return _refuse(failure, "No match can be seated on %s." % map_path)
	result.game.map_path = map_path
	result.game.fog_enabled = request.fog_enabled
	# How the armies group is the match's choice, not the board's (plan D1). Empty
	# is a free-for-all, which is what an ungrouped seat strip and an absent
	# `--sides=` both hand in.
	#
	# Whether a grouping leaves anybody to fight is the *board's* answer, so it is
	# checked here rather than where the grouping was written: `--sides=1+2` is a
	# pair against two loners on a four-army board and an alliance of everybody on
	# a duel, and only a loaded roster tells the two apart. An alliance of everybody
	# is a match no command can advance — every attack and capture is refused, so no
	# army can ever fall — and the free-for-all is the honest thing to play instead.
	#
	# A grouping may only name a seat this match fills (open-seats D2) — meaning one
	# the board deals and the seating then closed. Those two statements arrive in the
	# same launch and contradict each other, so the grouping described a different
	# match and honouring the rest of it would half-apply something nobody asked for.
	# Refused the same way an unreadable one is: out loud, and dropped to the
	# free-for-all rather than half-applied (four-players D6).
	#
	# A seat the board never deals at all is the *other* case and stays tolerated:
	# `--sides=1+3v2+4` on a two-army board is one grouping written for any roster,
	# which degenerates to the duel that board seats. Nothing there contradicts
	# anything — the flag simply reached further than the file.
	result.game.sides = _typed_sides(request.sides)
	var vacant := _sides_off_the_roster(result.game, request.sides)
	if not vacant.is_empty():
		push_error(
			(
				"battle: the grouping allies %s, which %s does not seat; playing the free-for-all"
				% [vacant, map_path]
			)
		)
		result.game.sides = {}
	if not result.game.sides.is_empty() and not _anyone_is_hostile(result.game):
		push_error(
			"battle: the grouping allies every army on %s; playing the free-for-all" % map_path
		)
		result.game.sides = {}
	# The computer's seats are narrowed to the table for a related reason: a planner
	# on a seat nobody is in plays nobody. Silently, unlike the grouping above, and
	# the difference is whose statement is being dropped — nothing a player types can
	# reach this list. It is the request's own default (seat 2, the opponent every
	# launch has had) or `--watch`'s roster, and narrowing a default to a fact stated
	# later is not the same as discarding something somebody asked for.
	result.ai_teams = _seated_ai_teams(result.game, result.ai_teams)
	# Watch mode seats every army with a planner, and which armies those are is the
	# board's answer (four-players plan D1) — not knowable when the flag was parsed,
	# which is why the request could only carry the duel it assumed.
	if request.watching:
		result.ai_teams = result.game.teams.duplicate()
	# A pinned seed is what makes a watched match *the* match rather than another
	# one like it: the AI is lookahead-free and RNG-free, so the seed is the only
	# thing left that could make two runs of one spec diverge.
	if request.seed_value >= 0:
		result.game.rng.seed = request.seed_value
	else:
		result.game.rng.randomize()
	# Narrowed to the computer's seats for the reason `ai_teams` was: a tier is what
	# a planner weighs its moves with, so a tier for a seat nobody plans tunes
	# nobody — and this list is what the save records and what a rematch replays.
	result.seat_difficulty = _computer_tiers(result)
	_seat_planners(result, unit_db)
	return result


## No match, said once: to the log, where a developer reads it, and onto the
## caller's `Failure`, which is what the scene puts in front of the player.
static func _refuse(failure: Failure, message: String) -> BuiltMatch:
	push_error("battle: %s" % message)
	return _record(failure, message)


## `_refuse` for the refusals whose detail the reader that found it has already
## pushed — ReplayFile, SaveCodec. The player still needs a sentence; the log
## does not need the same failure named twice.
static func _record(failure: Failure, message: String) -> BuiltMatch:
	if failure != null:
		failure.message = message
	return null


## The mission a campaign profile was midway through, rebuilt from the envelope
## embedded in it. `SaveCodec.decode` is the one rebuilder, exactly as the
## skirmish resume above and the replay opening below — so the mission's units,
## RNG, commanders and tier come back through every validation a save already
## has. Null, with a pushed error, when the profile holds no battle or one the
## codec refuses.
static func _build_campaign_resume(
	request: MatchRequest,
	terrain_db: TerrainDB,
	unit_db: UnitDB,
	chart: DamageChart,
	commander_db: CommanderDB,
	difficulty_db: DifficultyDB,
	failure: Failure
) -> BuiltMatch:
	var battle := CampaignProfile.load_battle(request.campaign_resume)
	if battle.is_empty():
		return _refuse(
			failure,
			"Campaign '%s' holds no mission in progress." % request.campaign_resume,
		)
	var loaded := SaveCodec.decode(battle, terrain_db, unit_db, chart, commander_db)
	if loaded == null:
		return _refuse(failure, "The saved mission cannot be read; there is no match to play.")
	var result := BuiltMatch.new()
	result.game = loaded.state
	result.ai_teams = loaded.ai_teams
	result.difficulty = difficulty_db.by_id(loaded.difficulty)
	result.map = result.game.map
	_apply_seat_tiers(result, loaded.seat_tiers, difficulty_db)
	_apply_auto_tiers(result, loaded, difficulty_db)
	_seat_planners(result, unit_db)
	return result


## Carries a resumed save's Auto seats onto the match being built: `Battle`'s
## own live copy (`Battle.auto_tiers`), and each team's planner tier folded
## into `per_team_difficulty` so `Battle._build_planners` needs no change of
## its own to honour it — it already reads
## `per_team_difficulty.get(team, difficulty)`.
static func _apply_auto_tiers(
	result: BuiltMatch, loaded: SaveCodec.LoadedMatch, difficulty_db: DifficultyDB
) -> void:
	result.auto_tiers = loaded.auto_tiers
	for team: int in loaded.auto_tiers:
		result.per_team_difficulty[team] = difficulty_db.by_id(loaded.auto_tiers[team])


## The per-seat tiers this match was launched (or saved) with, resolved into
## `per_team_difficulty` the same way the Auto seats above are. Assigned rather
## than merged, so a resumed save's seats replace whatever the request said: a
## save brings its own tiers exactly as it brings its own board.
static func _apply_seat_tiers(
	result: BuiltMatch, tiers: Dictionary[int, StringName], difficulty_db: DifficultyDB
) -> void:
	result.seat_difficulty = tiers.duplicate()
	for team: int in tiers:
		result.per_team_difficulty[team] = difficulty_db.by_id(tiers[team])


## `result.seat_difficulty` kept to the seats the computer actually took.
static func _computer_tiers(result: BuiltMatch) -> Dictionary[int, StringName]:
	var played: Dictionary[int, StringName] = {}
	for team: int in result.seat_difficulty:
		if result.ai_teams.has(team):
			played[team] = result.seat_difficulty[team]
	return played


## One planner per army, each at its own seat's tier — `per_team_difficulty` where
## the match named one and the match's own tier everywhere else.
static func _seat_planners(result: BuiltMatch, unit_db: UnitDB) -> void:
	for team in result.game.teams:
		var tier: Difficulty = result.per_team_difficulty.get(team, result.difficulty)
		result.planners[team] = AIController.new(unit_db, tier.profile())


## A recorded match, opened on the board it was recorded from. Null when the file
## is not a replay this build reads — or when the launch named no file at all,
## which `make replay` with no `REPLAY=` does. Both are a refusal rather than a
## fallback: a `--replay=` that quietly played a fresh match on the default board
## would look exactly like the replay working.
##
## The opening rebuilds through `SaveCodec.decode`, the same route `resume` takes
## above, so the recording brings its own board, roster, grouping, commanders and
## fog. Nobody plans: `ai_teams` is empty because every command is already written
## down, and the tier is carried only because a save envelope records one.
static func _build_replay(
	request: MatchRequest,
	terrain_db: TerrainDB,
	unit_db: UnitDB,
	chart: DamageChart,
	commander_db: CommanderDB,
	difficulty_db: DifficultyDB,
	failure: Failure
) -> BuiltMatch:
	if request.replay_path == "":
		return _refuse(failure, "No recording was named; there is no match to play.")
	var recording := ReplayFile.read(request.replay_path)
	if recording == null:
		# ReplayFile has already said what is wrong with the file.
		return _record(failure, "%s is not a recording this build can play." % request.replay_path)
	var player := ReplayPlayer.new(recording, unit_db)
	# A recording of a mission is refused whole rather than at its first scripted
	# beat: without the mission there is no script to resolve one against, and a
	# playback that opened anyway would run correctly right up to the moment the
	# story happens and then stop with a message about the board.
	if player.mission_error() != "":
		return _refuse(failure, "%s; there is no recording to play." % player.mission_error())
	var loaded := player.opening(terrain_db, chart, commander_db)
	if loaded == null:
		# SaveCodec has already said what is wrong with the opening.
		return _record(failure, "The recording's opening board cannot be read.")
	var result := BuiltMatch.new()
	result.replay = player
	result.replay_path = request.replay_path
	result.game = loaded.state
	result.map = loaded.state.map
	result.difficulty = difficulty_db.by_id(loaded.difficulty)
	_seat_planners(result, unit_db)
	return result


## `request.sides` (untyped: it is `MatchRequest`'s own grammar, shared with
## `--sides=`) carried into `GameState.sides`'s typed shape. GDScript will not
## coerce a plain `Dictionary`, however int-keyed, into a `Dictionary[int, int]`
## variable or property in one step — only a fresh typed dictionary built key by
## key does.
## `request.seat_difficulty` (untyped: it is `MatchRequest`'s own grammar, shared
## with `--difficulty=2:hard`) in the typed shape a save and a `BuiltMatch` carry,
## for the reason `_typed_sides` below exists.
static func _typed_tiers(picked: Dictionary) -> Dictionary[int, StringName]:
	var tiers: Dictionary[int, StringName] = {}
	for team: int in picked:
		tiers[team] = StringName(picked[team])
	return tiers


static func _typed_sides(grouped: Dictionary) -> Dictionary[int, int]:
	var sides: Dictionary[int, int] = {}
	for team: int in grouped:
		sides[team] = int(grouped[team])
	return sides


## The armies a grouping names that this match **closed** — seats the board deals
## and the seating left out. Empty for every grouping that describes the table in
## play, including a partial one (a pair against loners, and always was) and one
## reaching past the board's own roster (a grouping written for a wider map).
static func _sides_off_the_roster(game: GameState, grouped: Dictionary) -> Array[int]:
	var dealt := game.map.teams()
	var vacant: Array[int] = []
	for team: int in grouped:
		if dealt.has(team) and not game.teams.has(team):
			vacant.append(team)
	return vacant


## `wanted` narrowed to the seats this match actually fills. So closing the seat the
## computer had leaves a table of people — which is what closing it said.
static func _seated_ai_teams(game: GameState, wanted: Array[int]) -> Array[int]:
	var seated: Array[int] = []
	for team in wanted:
		if game.teams.has(team):
			seated.append(team)
	return seated


## Whether any army on the board has an enemy at all, asked of the one hostility
## authority (plan D2) rather than by comparing the grouping's own values.
static func _anyone_is_hostile(game: GameState) -> bool:
	for team in game.teams:
		if not game.enemies_of(team).is_empty():
			return true
	return false


## The request's commander ids together with the Balance Lab's
## `--red=<co>:<tier>` / `--blue=<co>:<tier>` grammar, resolved to
## `team -> CommanderType` before the state is built so the opening side's day-1
## begin_turn sees its real doctrine. Side specs — read through the Lab's own
## parser so a spec means the same thing in the window as in the report — win over
## the plain commander ids for the same team, as they did when both called
## set_commander in turn; each records its tier so the scene can hand that team a
## planner of its own.
static func _resolve_commanders(
	result: BuiltMatch,
	commander_db: CommanderDB,
	difficulty_db: DifficultyDB,
	request: MatchRequest
) -> Dictionary:
	var commanders: Dictionary = {}
	for team: int in request.commanders:
		commanders[team] = commander_db.by_id(request.commanders[team])
	for team: int in request.side_specs:
		var spec := BalanceSideSpec.parse(request.side_specs[team], commander_db, difficulty_db)
		if spec.error != "":
			push_error("battle: %s" % spec.error)
			continue
		commanders[team] = commander_db.by_id(spec.commander)
		result.per_team_difficulty[team] = difficulty_db.by_id(spec.tier)
	return commanders
