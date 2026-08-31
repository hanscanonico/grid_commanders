extends GutTest
## The campaign's 108 boards, read as a set rather than one mission at a time.
##
## The failure this catches is a board copied into a second mission: both
## missions load, both play, and the only symptom is a player recognising the
## ground. `CampaignBoards.SHARED_BOARDS` is where a share that is meant — or
## that is known debt — is written down.

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
