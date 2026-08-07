extends GutTest
## The arena's flag grammar and its shard file — checked on the same terms the
## launch layer is (MatchRequest, CmdArgs): argument-taking and Node-free, so a
## spelling is pinned without a process to launch.
##
## The grammar is the whole of what AR3 adds, so its refusals are the point. A
## flag it accepted and then ignored would score a candidate that never played.

const SHARD := """
{
	"map": "ironworks",
	"seeds": 6,
	"days": 40,
	"pairings": [
		{"red": "data/ai/default.tres", "blue": "reports/arena/c7.tres"},
		{
			"map": "clash",
			"red": "data/ai/hard.tres",
			"blue": "reports/arena/c7.tres",
			"seeds": 2,
			"seed_offset": 6
		}
	]
}
"""


func _args(list: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for item: String in list:
		out.append(item)
	return out


func _parse(list: Array) -> ArenaRequest:
	return ArenaRequest.parse(_args(list))


func _pairings(list: Array, text: String = "") -> Array:
	return _parse(list).pairings(text)


# --- the flags -----------------------------------------------------------------


func test_a_side_is_a_profile_path() -> void:
	var request := _parse(["--red-profile=data/ai/easy.tres", "--blue-profile=reports/c1.tres"])
	assert_eq(request.error, "")
	var pairings: Array = request.pairings("")
	assert_eq(pairings.size(), 1)
	var pairing: ArenaRequest.Pairing = pairings[0]
	assert_eq(pairing.red_path, "data/ai/easy.tres")
	assert_eq(pairing.blue_path, "reports/c1.tres")
	assert_eq(pairing.map_name, ArenaRequest.DEFAULT_MAP)
	assert_eq(pairing.seeds, ArenaRequest.DEFAULT_SEEDS)
	assert_eq(pairing.days, ArenaRequest.DEFAULT_DAYS, "the horizon that resolves (plan D6)")


func test_the_flags_move_the_board_and_the_range() -> void:
	var pairings := _pairings(
		[
			"--map=clash",
			"--red-profile=a.tres",
			"--blue-profile=b.tres",
			"--seeds=9",
			"--seed-offset=3",
			"--days=25",
		]
	)
	var pairing: ArenaRequest.Pairing = pairings[0]
	assert_eq(pairing.map_name, "clash")
	assert_eq(pairing.seeds, 9)
	assert_eq(pairing.seed_offset, 3)
	assert_eq(pairing.days, 25)


func test_a_match_needs_a_candidate_a_side() -> void:
	# There is no default candidate on purpose: a run that quietly seated the
	# shipped profile would measure the tier the arena is trying to beat.
	assert_ne(_parse(["--red-profile=a.tres"]).error, "", "no blue")
	assert_ne(_parse(["--blue-profile=b.tres"]).error, "", "no red")
	assert_ne(_parse([]).error, "", "neither")


func test_a_side_may_seat_a_commander() -> void:
	var pairings := _pairings(
		[
			"--red-profile=a.tres",
			"--blue-profile=b.tres",
			"--red-co=gideon_holt",
			"--blue-co=none",
		]
	)
	var pairing: ArenaRequest.Pairing = pairings[0]
	assert_eq(pairing.red_co, "gideon_holt")
	assert_eq(pairing.blue_co, "", "'none' is the neutral default, said out loud")


func test_two_generals_on_one_profile_are_not_a_mirror() -> void:
	# Swapping the seats of a true mirror replays the identical match; with the
	# generals differing it does not, so both seats must be played.
	var seated := _pairings(
		["--red-profile=a.tres", "--blue-profile=a.tres", "--red-co=gideon_holt"]
	)
	assert_false((seated[0] as ArenaRequest.Pairing).mirror())
	var bare := _pairings(["--red-profile=a.tres", "--blue-profile=a.tres"])
	assert_true((bare[0] as ArenaRequest.Pairing).mirror())


func test_a_commander_beside_a_shard_file_is_refused() -> void:
	var request := _parse(["--pairings=shard.json", "--red-co=gideon_holt"])
	assert_string_contains(request.error, "--pairings")


func test_a_seated_commander_names_the_run_apart() -> void:
	var bare := _parse(["--map=clash", "--red-profile=a.tres", "--blue-profile=b.tres"])
	var seated := _parse(
		[
			"--map=clash",
			"--red-profile=a.tres",
			"--blue-profile=b.tres",
			"--red-co=gideon_holt",
		]
	)
	assert_string_contains(seated.run_name(), "a+gideon_holt")
	assert_ne(bare.run_name(), seated.run_name(), "two measurements, two directories")


func test_a_seated_commander_moves_the_digest() -> void:
	# The run name already differs through its readable label; the hashed spec
	# must carry the general too, or two labels trimmed to one slug would land
	# a seated measurement in the commander-free run's directory.
	var bare := _parse(["--red-profile=a.tres", "--blue-profile=b.tres"])
	var seated := _parse(["--red-profile=a.tres", "--blue-profile=b.tres", "--blue-co=radek_morn"])
	assert_ne(bare.digest(), seated.digest())
	assert_ne(bare.artifact_dir(), seated.artifact_dir(), "two measurements, two directories")


func test_a_pairing_may_seat_its_own_generals() -> void:
	var text := '{"pairings": [{"red": "a.tres", "blue": "b.tres", "red_co": "cass_orlov"}]}'
	var pairings := _pairings(["--pairings=shard.json"], text)
	var pairing: ArenaRequest.Pairing = pairings[0]
	assert_eq(pairing.red_co, "cass_orlov")
	assert_eq(pairing.blue_co, "")


func test_an_unknown_flag_is_refused() -> void:
	var request := _parse(["--red-profile=a.tres", "--blue-profile=b.tres", "--tier=hard"])
	assert_string_contains(request.error, "--tier=hard")


func test_a_shard_file_names_its_own_profiles() -> void:
	# Two ways of saying who plays, and the file wins every time — so a leftover
	# --red-profile beside it is refused rather than silently dropped.
	var request := _parse(["--pairings=shard.json", "--red-profile=a.tres"])
	assert_string_contains(request.error, "--pairings")


func test_a_run_is_named_for_its_spec() -> void:
	var flags := [
		"--map=clash", "--red-profile=data/ai/default.tres", "--blue-profile=reports/c7.tres"
	]
	var request := _parse(flags)
	assert_eq(request.run_name(), "clash_default_vs_c7_s4_d100_%s" % request.digest())
	assert_eq(request.artifact_dir(), "reports/ai_arena/%s" % request.run_name())
	assert_eq(
		request.run_name(),
		_parse(flags).run_name(),
		"the same question rerun overwrites its own directory"
	)
	var sharded := _parse(["--pairings=reports/arena/gen1/shard4.json"])
	assert_string_contains(sharded.run_name(), "shard4")


func test_two_candidates_sharing_a_filename_are_named_apart() -> void:
	# A candidate is a path and its slug is only the filename, so the generation
	# layout a search writes collides on every readable part of the name — and a
	# second run without --out= would overwrite the first run's records.
	var first := _parse(["--red-profile=a.tres", "--blue-profile=reports/g1/c1.tres"])
	var second := _parse(["--red-profile=a.tres", "--blue-profile=reports/g2/c1.tres"])
	assert_ne(first.run_name(), second.run_name(), "different candidates, different directory")
	assert_ne(first.artifact_dir(), second.artifact_dir())
	assert_ne(
		_parse(["--pairings=reports/arena/g1/shard4.json"]).run_name(),
		_parse(["--pairings=reports/arena/g2/shard4.json"]).run_name(),
		"and a shard file is named the same way"
	)


func test_out_overrides_the_derived_directory() -> void:
	var request := _parse(["--red-profile=a.tres", "--blue-profile=b.tres", "--out=reports/mine"])
	assert_eq(request.artifact_dir(), "reports/mine")


func test_a_path_is_read_inside_the_project() -> void:
	assert_eq(ArenaRequest.project_path("data/ai/hard.tres"), "res://data/ai/hard.tres")
	assert_eq(ArenaRequest.project_path("res://data/ai/hard.tres"), "res://data/ai/hard.tres")
	assert_eq(ArenaRequest.project_path("/tmp/hard.tres"), "", "load() cannot reach out there")


# --- the shard file -------------------------------------------------------------


func test_a_shard_file_is_a_list_of_pairings() -> void:
	var pairings := _pairings(["--pairings=shard.json"], SHARD)
	assert_eq(pairings.size(), 2)
	var first: ArenaRequest.Pairing = pairings[0]
	assert_eq(first.map_name, "ironworks")
	assert_eq(first.red_path, "data/ai/default.tres")
	assert_eq(first.blue_path, "reports/arena/c7.tres")
	assert_eq(first.seeds, 6, "the file's own default")
	assert_eq(first.days, 40)


func test_the_nearest_setting_wins() -> void:
	var pairings := _pairings(["--pairings=shard.json", "--seeds=99"], SHARD)
	var second: ArenaRequest.Pairing = pairings[1]
	assert_eq(second.map_name, "clash", "the pairing's own board")
	assert_eq(second.seeds, 2, "over the file's, which is over the flag's")
	assert_eq(second.seed_offset, 6)
	assert_eq(second.days, 40, "and what it does not say, the file does")


func test_a_misspelt_key_is_refused() -> void:
	# `offset` for `seed_offset` would play the first seeds of the range twice
	# and the shard would look perfectly healthy.
	for text: String in [
		'{"pairings": [{"red": "a.tres", "blue": "b.tres", "offset": 4}]}',
		'{"seed": 4, "pairings": [{"red": "a.tres", "blue": "b.tres"}]}',
	]:
		var request := _parse(["--pairings=shard.json"])
		assert_eq(request.pairings(text), [], "refused, not played")
		assert_string_contains(request.error, "unknown key")


func test_a_pairing_needs_both_sides() -> void:
	var request := _parse(["--pairings=shard.json"])
	assert_eq(request.pairings('{"pairings": [{"red": "a.tres"}]}'), [])
	assert_string_contains(request.error, "'red' and 'blue'")


func test_an_unreadable_shard_is_refused_out_loud() -> void:
	for text: String in ["", "not json", "[]", '{"pairings": {}}', '{"pairings": []}']:
		var request := _parse(["--pairings=shard.json"])
		assert_eq(request.pairings(text), [], "'%s' plays nothing" % text)
		assert_ne(request.error, "", "'%s' says why" % text)
