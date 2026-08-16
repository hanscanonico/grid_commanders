extends GutTest
## The launch grammar: which match a set of command-line flags asks for, and what
## each of the three adapters puts in the request.
##
## Testable at all only since architecture finding A3 (COM-36). The same rules
## used to live inside `BattleSetup.build`, reading a mutable autoload and calling
## `OS.get_cmdline_user_args()` directly, so the only way to check that `--map=`
## refused an unknown board or that `--hotseat` cleared the AI side was to launch
## a process and photograph the result. `MatchRequest` takes the args as an
## argument, which is what lets these run headless with the rest of the suite.
##
## The flag *spellings* are a compatibility surface: `make smoke`, the Balance Lab
## and docs/ all pass them. A test here failing means a launch someone scripted
## has changed meaning.

const RED := 1
const BLUE := 2

# --- defaults -----------------------------------------------------------------


func test_a_request_nobody_configured_plays_the_default_match() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args([]))
	assert_eq(request.map_path, MatchRequest.DEFAULT_MAP_PATH, "default board")
	assert_eq(request.ai_teams, [BLUE] as Array[int], "the computer takes blue")
	assert_false(request.fog_enabled, "fog off")
	assert_false(request.resume, "a fresh match, not the save")
	assert_false(request.watching, "not a watched run")
	assert_eq(request.seed_value, -1, "negative means randomize")


# --- the flags ----------------------------------------------------------------


func test_hotseat_clears_the_computer_side() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--hotseat"]))
	assert_eq(request.ai_teams, [] as Array[int], "both seats are human")


func test_fog_turns_fog_on() -> void:
	var request := MatchRequest.new()
	request.fog_enabled = false
	request.apply_cmdline(Fixture.args(["--fog"]))
	assert_true(request.fog_enabled)


func test_watch_gives_both_seats_to_the_computer() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--watch"]))
	assert_true(request.watching, "watch mode announced")
	assert_eq(request.ai_teams, MapData.DEFAULT_TEAMS, "the duel the board has yet to widen")


func test_seed_pins_the_match_rng() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--seed=7"]))
	assert_eq(request.seed_value, 7)


## A watched row is diffed against the CSV line it came from, so seed 0 has to be
## a real seed rather than "unset" — which is why the sentinel is negative.
func test_seed_zero_is_a_seed_not_an_absence() -> void:
	var zero := MatchRequest.new()
	zero.apply_cmdline(Fixture.args(["--seed=0"]))
	assert_eq(zero.seed_value, 0, "an explicit zero pins the RNG")
	var negative := MatchRequest.new()
	negative.apply_cmdline(Fixture.args(["--seed=-5"]))
	assert_eq(negative.seed_value, 0, "and a negative one is clamped, not read as unset")


func test_days_caps_a_watched_match_and_never_goes_below_one() -> void:
	var capped := MatchRequest.new()
	capped.apply_cmdline(Fixture.args(["--days=12"]))
	assert_eq(capped.days_cap, 12)
	var zero := MatchRequest.new()
	zero.apply_cmdline(Fixture.args(["--days=0"]))
	assert_eq(zero.days_cap, 1)


## Which horizon an unset launch is scored on is the scene's, and it can only pick
## one if "no `--days=`" is distinguishable from a cap that happens to equal the
## default — so the sentinel has to be a value the flag can never produce.
func test_days_is_unset_until_a_flag_writes_one() -> void:
	var untouched := MatchRequest.new()
	assert_eq(untouched.days_cap, MatchRequest.DAYS_UNSET, "no flag, no horizon")
	var other := MatchRequest.new()
	other.apply_cmdline(Fixture.args(["--map=first_steps"]))
	assert_eq(other.days_cap, MatchRequest.DAYS_UNSET, "and other flags leave it alone")
	var sentinel := MatchRequest.new()
	sentinel.apply_cmdline(Fixture.args(["--days=%d" % MatchRequest.DAYS_UNSET]))
	assert_ne(sentinel.days_cap, MatchRequest.DAYS_UNSET, "the flag can never write the sentinel")


func test_difficulty_is_carried_as_an_id_for_the_database_to_resolve() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--difficulty=  hard  "]))
	assert_eq(request.difficulty, &"hard", "trimmed, not resolved")


func test_side_specs_are_kept_unparsed_for_the_labs_own_parser() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--red=alina_ward:hard", "--blue=viktor_draeg:easy"]))
	assert_eq(request.side_specs[RED], "alina_ward:hard")
	assert_eq(request.side_specs[BLUE], "viktor_draeg:easy")


func test_an_unknown_map_name_is_refused_rather_than_silently_swapped() -> void:
	var request := MatchRequest.new()
	request.map_path = MatchRequest.DEFAULT_MAP_PATH
	# A watched match on the wrong board would still print a result line, and that
	# line is what the replay-fidelity check diffs — so the board must not change
	# quietly. The pushed error is the point; the board staying put is the check.
	request.apply_cmdline(Fixture.args(["--map=no_such_map_anywhere"]))
	assert_push_error("unknown map 'no_such_map_anywhere'")
	assert_eq(request.map_path, MatchRequest.DEFAULT_MAP_PATH, "board unchanged")


# --- --co ---------------------------------------------------------------------


func test_co_assigns_red_first_then_blue() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--co=alina_ward,viktor_draeg"]))
	assert_eq(request.commanders[RED], &"alina_ward")
	assert_eq(request.commanders[BLUE], &"viktor_draeg")


func test_a_blank_side_in_co_plays_without_a_commander() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--co=,viktor_draeg"]))
	assert_false(request.commanders.has(RED), "red has no commander")
	assert_eq(request.commanders[BLUE], &"viktor_draeg")
	var over := ",".join(["a", "b", "c", "d", "e"])
	assert_eq(
		MatchRequest.parse_co_flag(over).size(),
		GameState.TEAMS.size(),
		"ids past the last seat a board could deal are dropped"
	)


## `--co=` with nothing after it clears the menu's picks, which is how a capture
## photographs the pre-commander game. Distinct from omitting the flag entirely.
func test_an_empty_co_clears_the_commanders_the_menu_chose() -> void:
	var request := MatchRequest.new()
	request.commanders = {RED: &"alina_ward", BLUE: &"viktor_draeg"}
	request.apply_cmdline(Fixture.args(["--co="]))
	assert_eq(request.commanders, {}, "cleared")


func test_omitting_co_leaves_the_menus_commanders_alone() -> void:
	var request := MatchRequest.new()
	request.commanders = {RED: &"alina_ward"}
	request.apply_cmdline(Fixture.args(["--fog"]))
	assert_eq(request.commanders[RED], &"alina_ward", "untouched")


# --- the adapters -------------------------------------------------------------


func test_the_menu_adapter_copies_rather_than_shares_its_collections() -> void:
	var teams: Array[int] = [BLUE]
	var commanders := {RED: &"alina_ward"}
	var request := MatchRequest.from_menu(
		"res://maps/x.txt", teams, true, &"hard", commanders, false
	)
	teams.append(RED)
	commanders[BLUE] = &"viktor_draeg"
	assert_eq(request.ai_teams, [BLUE] as Array[int], "the menu's later edit does not leak in")
	assert_false(request.commanders.has(BLUE), "nor into the commanders")


func test_the_menu_adapter_carries_every_choice() -> void:
	var request := MatchRequest.from_menu(
		"res://maps/x.txt", [] as Array[int], true, &"hard", {}, true
	)
	assert_eq(request.map_path, "res://maps/x.txt")
	assert_eq(request.ai_teams, [] as Array[int])
	assert_true(request.fog_enabled)
	assert_eq(request.difficulty, &"hard")
	assert_true(request.resume, "Continue asked to resume")
	assert_eq(request.seats, [] as Array[int], "a table nobody closed a seat at")


func test_the_flags_do_not_cancel_a_resume() -> void:
	var request := MatchRequest.from_menu(
		MatchRequest.DEFAULT_MAP_PATH, [BLUE] as Array[int], false, &"normal", {}, true
	)
	request.apply_cmdline(Fixture.args(["--fog", "--hotseat"]))
	assert_true(request.resume)


func test_a_device_preference_never_enters_the_request() -> void:
	# Guardrail R4: the speed and the retired hints are device preferences, so a
	# resumed match plays at today's preference rather than the one it was saved
	# under. Settings owns --speed=; nothing here may quietly start carrying it.
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--speed=fast", "--reset-hints"]))
	assert_false(&"speed" in request, "no speed field on the request")


func test_the_rematch_adapter_replays_the_running_match_not_the_menus() -> void:
	var terrain_db := TerrainDB.load_default()
	var unit_db := UnitDB.load_default()
	var chart: DamageChart = load("res://data/damage_chart.tres")
	var map := MapData.load_from_file(MatchRequest.DEFAULT_MAP_PATH, terrain_db)
	var game := GameState.create(map, unit_db, chart, {})
	game.map_path = "res://maps/fixtures/whatever.txt"
	game.fog_enabled = true

	var request := MatchRequest.from_match(game, [RED] as Array[int], &"hard")

	assert_eq(request.map_path, "res://maps/fixtures/whatever.txt", "the board being played")
	assert_true(request.fog_enabled, "and its fog")
	assert_eq(request.ai_teams, [RED] as Array[int])
	assert_eq(request.difficulty, &"hard")
	# The whole point of rematch: play this board again from day one, rather than
	# reloading the disk the resumed match originally came from.
	assert_false(request.resume, "a rematch never resumes")
