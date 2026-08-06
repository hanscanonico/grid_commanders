extends GutTest
## The `# grouping` tag (asymmetric-board plan D2/D3/R5): counter-tests for the
## grouped half of the property-parity lint in test_maps.gd.
##
## Kept apart from test_maps.gd because that file sits at the gdlintrc
## max-public-methods ceiling — the same reason test_sides_flag.gd split from
## test_match_request.gd. Both suites drive the same check,
## tests/helpers/map_parity.gd, so there is one authority for what "level"
## means whether or not a board is tagged.
##
## The grouped path is live on one shipped map — `maps/bulwark.txt` declares
## `1+2+3v4` — while every other shipped board still gets the untagged check.
## Its pass is only reassuring if the grouped path can fail at all — these
## fixtures check the mechanism against boards built to break it, the way
## test_maps.gd's own test_the_shared_water_lint_can_tell_two_seas_apart does.

const MapParity := preload("res://tests/helpers/map_parity.gd")

var terrain_db: TerrainDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()


func test_the_grouped_parity_lint_can_tell_an_uneven_ally_apart() -> void:
	var short_ally := _fixture({1: 2, 2: 1, 3: 2, 4: 6}, "1+2+3v4")
	assert_ne(
		MapParity.error(short_ally),
		"",
		"seat 2 opens on one city fewer than its allies, and the lint has to notice"
	)
	var level_ally := _fixture({1: 2, 2: 2, 3: 2, 4: 6}, "1+2+3v4")
	assert_eq(
		MapParity.error(level_ally), "", "the same board with seat 2 brought level opens fair"
	)


func test_the_grouped_parity_lint_can_tell_a_lopsided_side_apart() -> void:
	var lopsided := _fixture({1: 2, 2: 2, 3: 2, 4: 7}, "1+2+3v4")
	assert_ne(
		MapParity.error(lopsided),
		"",
		"the lone side opens on more property than its three rivals combined"
	)
	var at_ceiling := _fixture({1: 2, 2: 2, 3: 2, 4: 6}, "1+2+3v4")
	assert_eq(
		MapParity.error(at_ceiling),
		"",
		"tied with the rest combined is under the ceiling, not over it"
	)


## The ceiling is one-directional: it holds a side only while that side fields
## no more armies than the rest of the board does. Bulwark's own tally is the
## case — three allies on 36 properties against one army's 30 — and it passes
## because three armies holding more ground than one is what a 3v1 board is,
## while the same board with the lone army over its three rivals still fails.
func test_a_side_with_more_armies_may_out_own_the_lone_one() -> void:
	var bulwark := _fixture({1: 12, 2: 12, 3: 12, 4: 30}, "1+2+3v4")
	assert_eq(
		MapParity.error(bulwark),
		"",
		"the alliance's 36 against the bulwark's 30 is three armies out-owning one, not the defect"
	)
	var over_the_ceiling := _fixture({1: 12, 2: 12, 3: 12, 4: 37}, "1+2+3v4")
	assert_ne(
		MapParity.error(over_the_ceiling),
		"",
		"the bulwark holding more than its three rivals between them is the defect"
	)


## A grouping that allies every seat the board deals sets nobody against
## anybody, so it claims as little as a free-for-all does and fails for its own
## stated reason rather than through the across-side ceiling.
func test_a_grouping_that_opposes_nobody_fails() -> void:
	var all_allied := _fixture({1: 2, 2: 2, 3: 2, 4: 6}, "1+2+3+4")
	var reported := MapParity.error(all_allied)
	assert_ne(reported, "", "a grouping that sets nobody against anybody claims nothing")
	assert_string_contains(reported, "opposes nobody")


## R5's guard: the tag is not a general opt-out from the parity lint. A board
## whose seats were already going to open level bought nothing by declaring a
## grouping, so it fails here rather than pass for the wrong reason.
func test_a_grouping_tag_fails_when_it_was_never_needed() -> void:
	var already_level := _fixture({1: 2, 2: 2, 3: 2, 4: 2}, "1+2+3v4")
	assert_ne(
		MapParity.error(already_level),
		"",
		"every seat already opens identical kind for kind — the tag is unearned"
	)


## `MatchRequest.parse_sides_flag` reads a spelled-out free-for-all as the empty
## grouping — the same thing an absent tag already means — so a board that
## carries `# grouping` and says nothing with it is a claim that means nothing.
## The fixture is deliberately uneven: with every seat on its own side nothing
## else in the lint fails it, so the error can only come from the branch this
## test names.
func test_a_grouping_that_reads_as_a_free_for_all_fails() -> void:
	var spelled_out := _fixture({1: 2, 2: 2, 3: 2, 4: 6}, "1v2v3v4")
	var reported := MapParity.error(spelled_out)
	assert_ne(reported, "", "the tag names no real grouping, and claiming one is a defect")
	assert_string_contains(reported, "names no sides")


## One row of cities, as many per team as `counts` says, each owned by that
## team. No HQ, no base — the parity check reads nothing but ownership. Every
## seat the grouping names needs at least one, or MapData never seats it.
func _fixture(counts: Dictionary, grouping: String) -> MapData:
	var cells: Array[int] = []
	for team in MapData.PLAYER_TEAMS:
		for _i in int(counts.get(team, 0)):
			cells.append(team)
	var text := "# grouping %s\n[terrain]\n%s\n[owners]\n" % [grouping, "C".repeat(cells.size())]
	for x in cells.size():
		text += "%d %d 0\n" % [cells[x], x]
	return MapData.parse(text, terrain_db)
