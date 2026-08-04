extends GutTest
## The pools: which boards and seeds a run is measured on, and who it is
## measured against.
##
## Two of these are the instrument's honesty rather than its convenience. A
## validation match must never be one the search could have selected on, on
## either axis; and the command that plays a pool must be the same statement of
## it that the report reads matches back against, or a leaderboard is scored
## against a split nothing played.


func test_the_anchors_are_the_three_shipped_tiers() -> void:
	assert_eq(ArenaPools.ANCHORS.size(), 3)
	for path: String in ArenaPools.ANCHORS:
		assert_true(ResourceLoader.exists("res://%s" % path), "%s is a profile on disk" % path)
		assert_true(load("res://%s" % path) is AIProfile, path)


func test_the_two_pools_share_no_board() -> void:
	for board: String in ArenaPools.TRAINING_BOARDS:
		assert_false(board in ArenaPools.VALIDATION_BOARDS, "%s is in both pools" % board)


func test_the_two_pools_share_no_seed() -> void:
	# The board split already separates them; the seed split is what keeps a
	# board added to both lists later from leaking the pool it was selected on.
	var training_last := (
		ArenaPools.seed_offset(ArenaPools.TRAINING) + ArenaPools.seeds(ArenaPools.TRAINING)
	)
	assert_lte(training_last, ArenaPools.seed_offset(ArenaPools.VALIDATION))


func test_every_pooled_board_is_a_land_duel_the_arena_can_seat() -> void:
	var terrain_db := TerrainDB.load_default()
	var boards: Array[String] = ArenaPools.TRAINING_BOARDS.duplicate()
	boards.append_array(ArenaPools.VALIDATION_BOARDS)
	boards.append_array(ArenaPools.RESERVE_BOARDS)
	for name: String in boards:
		var path := MapCatalog.resolve(name)
		assert_ne(path, "", "%s is a shipped board" % name)
		var map := MapData.load_from_file(path, terrain_db)
		assert_eq(map.teams().size(), 2, "%s seats two candidates" % name)
		assert_false(_builds_hulls(map), "%s is a land board (naval plan R1)" % name)


func test_a_seed_is_read_back_to_the_pool_it_was_played_in() -> void:
	var board: String = ArenaPools.TRAINING_BOARDS[0]
	var first := BalanceMatchSchedule.seed_at(board, 0)
	assert_eq(ArenaPools.pool_of(board, first), ArenaPools.TRAINING)
	assert_eq(
		ArenaPools.pool_of(board, BalanceMatchSchedule.seed_at(board, ArenaPools.TRAINING_SEEDS)),
		ArenaPools.OFF_POOL,
		"one seed past the training range is nobody's"
	)
	var held: String = ArenaPools.VALIDATION_BOARDS[0]
	assert_eq(
		ArenaPools.pool_of(held, BalanceMatchSchedule.seed_at(held, ArenaPools.VALIDATION_OFFSET)),
		ArenaPools.VALIDATION
	)
	assert_eq(
		ArenaPools.pool_of(held, BalanceMatchSchedule.seed_at(held, 0)),
		ArenaPools.OFF_POOL,
		"a validation board's training-range seeds are held out of both"
	)


func test_a_pairing_list_never_seats_a_candidate_against_itself() -> void:
	var pairs := ArenaPools.pairings(ArenaPools.ANCHORS)
	assert_eq(pairs.size(), 3, "three anchors make three unordered pairs")
	for pair: Array in pairs:
		assert_ne(pair[0], pair[1], "a self-pairing is the seat talking (D5)")
	assert_eq(ArenaPools.pairings(["only.tres"] as Array[String]).size(), 0)


func test_the_pool_plan_is_the_split_it_will_be_read_against() -> void:
	var plan := ArenaPools.pool_args(ArenaPools.VALIDATION)
	assert_string_contains(plan, "--maps=%s" % ",".join(ArenaPools.VALIDATION_BOARDS))
	assert_string_contains(plan, "--seeds=%d" % ArenaPools.VALIDATION_SEEDS)
	assert_string_contains(plan, "--seed-offset=%d" % ArenaPools.VALIDATION_OFFSET)
	assert_string_contains(plan, "--days=%d" % ArenaPools.DAYS)
	assert_string_contains(plan, "::", "the arena pairs on :: because a side is a path")
	assert_eq(ArenaPools.DAYS, ArenaFitness.HORIZON, "scored against the cap it was played at")


func _builds_hulls(map: MapData) -> bool:
	for y in map.height:
		for x in map.width:
			var builds := map.terrain_at(Vector2i(x, y)).builds
			if TerrainType.SHIP in builds or TerrainType.LANDER in builds:
				return true
	return false
