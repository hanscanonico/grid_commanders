extends GutTest
## The campaign's 108 boards, read as a set rather than one mission at a time.
##
## The failure this catches is a board copied into a second mission: both
## missions load, both play, and the only symptom is a player recognising the
## ground. `CampaignBoards.SHARED_BOARDS` is where a share that is meant — or
## that is known debt — is written down.

## A share the test owns, so the behaviour under test does not ride on which
## boards the shipped allowlist happens to hold — or on it holding any.
const ONE_DECLARED_GROUP: Array[Array] = [["board_a", "board_b"]]

var terrain_db: TerrainDB


func before_all() -> void:
	terrain_db = Fixture.terrain_db()


func test_every_campaign_board_is_discovered() -> void:
	assert_gt(CampaignBoards.paths().size(), 0, "maps/campaign/ holds no board")


func test_no_two_missions_share_undeclared_ground() -> void:
	assert_eq(CampaignBoards.shared_board_error(terrain_db), "")


func test_the_digest_reads_terrain_and_not_ownership() -> void:
	var ground := "[terrain]\n.C.\n[owners]\n"
	var neutral := MapData.parse(ground, terrain_db)
	var owned := MapData.parse("%s1 1 0\n" % ground, terrain_db)
	assert_eq(CampaignBoards.terrain_digest(neutral), CampaignBoards.terrain_digest(owned))


func test_a_board_that_differs_by_one_cell_is_not_a_share() -> void:
	var plain := MapData.parse("[terrain]\n...\n", terrain_db)
	var wooded := MapData.parse("[terrain]\n.F.\n", terrain_db)
	assert_ne(CampaignBoards.terrain_digest(plain), CampaignBoards.terrain_digest(wooded))


func test_a_board_given_its_own_ground_must_leave_the_allowlist() -> void:
	var still_sharing: Dictionary[String, PackedStringArray] = {
		"shared ground": PackedStringArray(["board_a", "board_b"]),
	}
	assert_eq(
		CampaignBoards.stale_group_errors(still_sharing, ONE_DECLARED_GROUP),
		PackedStringArray(),
		"a group whose boards still share reads clean"
	)
	var separated: Dictionary[String, PackedStringArray] = {
		"shared ground": PackedStringArray(["board_b"]),
		"its own ground": PackedStringArray(["board_a"]),
	}
	var errors := CampaignBoards.stale_group_errors(separated, ONE_DECLARED_GROUP)
	assert_eq(errors.size(), 1, "one line, naming the group that stopped sharing")
	assert_string_contains(errors[0], "board_a")


func test_an_empty_allowlist_reports_nothing_stale() -> void:
	var by_digest: Dictionary[String, PackedStringArray] = {
		"shared ground": PackedStringArray(["board_a", "board_b"]),
	}
	var no_group_declared: Array[Array] = []
	assert_eq(CampaignBoards.stale_group_errors(by_digest, no_group_declared), PackedStringArray())
