extends GutTest
## The board's beat, on the animated water families: the sea's swell, the
## river's flow and the shoal's foam edge (S9). Split from
## test_terrain_autotiles_water.gd so neither file sits over the
## public-method ceiling — that file keeps the pure family/mask/phase logic,
## this one the frame-B sheets and `BoardBeat`'s cadences over them, all
## through `TerrainAutotiles`.
##
## The sea's own suite is the template every family below repeats: frame B
## holds the same variants at the same cut with only the moving tone changed,
## the beat alternates, a pinned capture and Instant both hold frame A.
## Cadence disjointness across all five of the board's clips is
## `test_board_beat.gd`'s, not restated per family here.

## How much of each water sheet a beat is allowed to move. Frame B is the
## same water (or shore) a beat later with its glints or foam shifted, not a
## second tile: a regeneration that redrew the surface would be a legibility
## question rather than a beat, and the ruler reads frame A only. Rivers and
## shoals (S9) get their own shares — measured off the shipped sheets, the
## same way the sea's own 0.05 was — because a connection-keyed cell's water
## covers a different fraction of the 64px tile than the open sea's does.
const GLINT_SHARE := 0.05
const RIVER_GLINT_SHARE := 0.03
const SHOAL_FOAM_SHARE := 0.10

var _opened_at: GameSpeed


func before_each() -> void:
	_opened_at = Settings.speed


func after_each() -> void:
	Settings.speed = _opened_at
	BoardBeat.frozen = false


func _family_sheet(family: int, frame: int) -> Image:
	var path := TerrainAutotiles.sheet_path(family, frame)
	var texture := load(path) as Texture2D
	return texture.get_image() if texture != null else null


## Frame 0 of every animated family is the sheet every static surface has
## always read, whatever family is asked and whether or not it animates.
func test_the_frame_a_readers_cannot_drift() -> void:
	# The miniature and the legibility ruler ask for a sheet with no frame, and
	# what they get has to stay the file every other surface has always read.
	for family: int in TerrainAutotiles.FRAME_B_PATHS:
		assert_eq(
			TerrainAutotiles.sheet_path(family),
			TerrainAutotiles.SHEET_PATHS[family],
			"family %d's frame 0 drifted off its own sheet" % family
		)
		assert_eq(
			TerrainAutotiles.sheet_path(family, 1),
			TerrainAutotiles.FRAME_B_PATHS[family],
			"family %d's frame B is not FRAME_B_PATHS'" % family
		)
	# Only the families in FRAME_B_PATHS have a second frame; every other
	# family answers its one sheet whatever it is asked, so no caller has to
	# know which families animate.
	for family: int in TerrainAutotiles.SHEET_PATHS:
		if TerrainAutotiles.FRAME_B_PATHS.has(family):
			continue
		assert_eq(
			TerrainAutotiles.sheet_path(family, 1),
			TerrainAutotiles.SHEET_PATHS[family],
			"family %d grew a frame B" % family
		)


# --- the sea's beat ----------------------------------------------------------


func test_the_two_sea_frames_are_cut_the_same() -> void:
	var frame_a := _family_sheet(TerrainAutotiles.Family.SEA, 0)
	var frame_b := _family_sheet(TerrainAutotiles.Family.SEA, 1)
	assert_not_null(frame_a, "the sea sheet did not load")
	assert_not_null(frame_b, "the sea sheet's frame B did not load")
	assert_eq(frame_b.get_size(), frame_a.get_size(), "the two frames are different sizes")
	# The beat re-points one texture on a source whose tiles are already
	# registered, so the cut has to survive the swap: the same phases, at the
	# same margin and separation, in the same sheet.
	var phases := TerrainAutotiles.sheet_cells(TerrainAutotiles.Family.SEA).size()
	assert_eq(phases, TerrainAutotiles.SEA_PHASES)
	var margin := TerrainAutotiles.SHEET_MARGIN
	var separation := TerrainAutotiles.SHEET_SEPARATION
	var span := phases * (BattleView.TERRAIN_PX + separation) - separation
	assert_eq(frame_b.get_width(), 2 * margin + span, "frame B holds other than three phases")
	assert_eq(frame_b.get_height(), 2 * margin + BattleView.TERRAIN_PX, "frame B is another row")


func test_frame_b_moves_the_glints_and_does_not_redraw_the_sea() -> void:
	var frame_a := _family_sheet(TerrainAutotiles.Family.SEA, 0)
	var frame_b := _family_sheet(TerrainAutotiles.Family.SEA, 1)
	var moved := 0
	for y in frame_a.get_height():
		for x in frame_a.get_width():
			if frame_a.get_pixel(x, y) != frame_b.get_pixel(x, y):
				moved += 1
	assert_gt(moved, 0, "the two frames are the same water, so there is no beat")
	var pixels := frame_a.get_width() * frame_a.get_height()
	assert_lt(
		float(moved) / float(pixels),
		GLINT_SHARE,
		"%d of %d pixels moved: that is a redrawn sea rather than a swell" % [moved, pixels]
	)


## The tier is named rather than inherited: this machine's stored preference may
## be Instant, which is a still board and would pass this vacuously.
func test_the_swell_alternates_on_its_own_cadence() -> void:
	Settings.speed = GameSpeed.by_id(GameSpeed.DEFAULT_ID)
	assert_eq(BoardBeat.frame(BoardBeat.SEA_MS, 0), 0, "the swell did not open on frame A")
	assert_eq(BoardBeat.frame(BoardBeat.SEA_MS, BoardBeat.SEA_MS), 1, "the swell did not turn over")
	assert_eq(
		BoardBeat.frame(BoardBeat.SEA_MS, 2 * BoardBeat.SEA_MS), 0, "the swell did not come back"
	)


func test_a_pinned_capture_holds_frame_a() -> void:
	Settings.speed = GameSpeed.by_id(GameSpeed.DEFAULT_ID)
	BoardBeat.frozen = true
	assert_eq(
		BoardBeat.frame(BoardBeat.SEA_MS, BoardBeat.SEA_MS), 0, "a pinned capture read a beat"
	)


func test_instant_holds_frame_a() -> void:
	Settings.speed = GameSpeed.by_id(&"instant")
	assert_eq(BoardBeat.frame(BoardBeat.SEA_MS, BoardBeat.SEA_MS), 0, "Instant played the swell")


# --- the river's beat (S9) ----------------------------------------------------
##
## Connection-keyed rather than phase-keyed, so the sheet is 16 cells over 4
## columns rather than 3 over one row — `sheet_cells` is asked rather than
## restated, so a generator change to the sheet's own layout cannot leave
## this file behind.


func test_the_two_river_frames_are_cut_the_same() -> void:
	var frame_a := _family_sheet(TerrainAutotiles.Family.RIVERS, 0)
	var frame_b := _family_sheet(TerrainAutotiles.Family.RIVERS, 1)
	assert_not_null(frame_a, "the rivers sheet did not load")
	assert_not_null(frame_b, "the rivers sheet's frame B did not load")
	assert_eq(frame_b.get_size(), frame_a.get_size(), "the two frames are different sizes")
	var variants := TerrainAutotiles.sheet_cells(TerrainAutotiles.Family.RIVERS).size()
	assert_eq(variants, TerrainAutotiles.CONNECTION_VARIANTS)


func test_frame_b_moves_the_flow_and_does_not_redraw_the_channel() -> void:
	var frame_a := _family_sheet(TerrainAutotiles.Family.RIVERS, 0)
	var frame_b := _family_sheet(TerrainAutotiles.Family.RIVERS, 1)
	var moved := 0
	for y in frame_a.get_height():
		for x in frame_a.get_width():
			if frame_a.get_pixel(x, y) != frame_b.get_pixel(x, y):
				moved += 1
	assert_gt(moved, 0, "the two frames are the same channel, so there is no beat")
	var pixels := frame_a.get_width() * frame_a.get_height()
	assert_lt(
		float(moved) / float(pixels),
		RIVER_GLINT_SHARE,
		"%d of %d pixels moved: that is a redrawn river rather than a flow" % [moved, pixels]
	)


func test_the_river_flows_on_its_own_cadence() -> void:
	Settings.speed = GameSpeed.by_id(GameSpeed.DEFAULT_ID)
	assert_eq(BoardBeat.frame(BoardBeat.RIVER_MS, 0), 0, "the flow did not open on frame A")
	assert_eq(
		BoardBeat.frame(BoardBeat.RIVER_MS, BoardBeat.RIVER_MS), 1, "the flow did not turn over"
	)
	assert_eq(
		BoardBeat.frame(BoardBeat.RIVER_MS, 2 * BoardBeat.RIVER_MS), 0, "the flow did not come back"
	)


func test_a_pinned_capture_holds_the_river_at_frame_a() -> void:
	Settings.speed = GameSpeed.by_id(GameSpeed.DEFAULT_ID)
	BoardBeat.frozen = true
	assert_eq(
		BoardBeat.frame(BoardBeat.RIVER_MS, BoardBeat.RIVER_MS), 0, "a pinned capture read a beat"
	)


func test_instant_holds_the_river_at_frame_a() -> void:
	Settings.speed = GameSpeed.by_id(&"instant")
	assert_eq(BoardBeat.frame(BoardBeat.RIVER_MS, BoardBeat.RIVER_MS), 0, "Instant played the flow")


# --- the shoal's beat (S9) -----------------------------------------------------


func test_the_two_shoal_frames_are_cut_the_same() -> void:
	var frame_a := _family_sheet(TerrainAutotiles.Family.SHOALS, 0)
	var frame_b := _family_sheet(TerrainAutotiles.Family.SHOALS, 1)
	assert_not_null(frame_a, "the shoals sheet did not load")
	assert_not_null(frame_b, "the shoals sheet's frame B did not load")
	assert_eq(frame_b.get_size(), frame_a.get_size(), "the two frames are different sizes")
	var variants := TerrainAutotiles.sheet_cells(TerrainAutotiles.Family.SHOALS).size()
	assert_eq(variants, TerrainAutotiles.CONNECTION_VARIANTS)


func test_frame_b_moves_the_foam_and_does_not_redraw_the_shore() -> void:
	var frame_a := _family_sheet(TerrainAutotiles.Family.SHOALS, 0)
	var frame_b := _family_sheet(TerrainAutotiles.Family.SHOALS, 1)
	var moved := 0
	for y in frame_a.get_height():
		for x in frame_a.get_width():
			if frame_a.get_pixel(x, y) != frame_b.get_pixel(x, y):
				moved += 1
	assert_gt(moved, 0, "the two frames are the same shore, so there is no beat")
	var pixels := frame_a.get_width() * frame_a.get_height()
	assert_lt(
		float(moved) / float(pixels),
		SHOAL_FOAM_SHARE,
		"%d of %d pixels moved: that is a redrawn shore rather than a shimmer" % [moved, pixels]
	)


func test_the_shoal_shimmers_on_its_own_cadence() -> void:
	Settings.speed = GameSpeed.by_id(GameSpeed.DEFAULT_ID)
	assert_eq(BoardBeat.frame(BoardBeat.SHOAL_MS, 0), 0, "the shimmer did not open on frame A")
	assert_eq(
		BoardBeat.frame(BoardBeat.SHOAL_MS, BoardBeat.SHOAL_MS), 1, "the shimmer did not turn over"
	)
	assert_eq(
		BoardBeat.frame(BoardBeat.SHOAL_MS, 2 * BoardBeat.SHOAL_MS),
		0,
		"the shimmer did not come back"
	)


func test_a_pinned_capture_holds_the_shoal_at_frame_a() -> void:
	Settings.speed = GameSpeed.by_id(GameSpeed.DEFAULT_ID)
	BoardBeat.frozen = true
	assert_eq(
		BoardBeat.frame(BoardBeat.SHOAL_MS, BoardBeat.SHOAL_MS), 0, "a pinned capture read a beat"
	)


func test_instant_holds_the_shoal_at_frame_a() -> void:
	Settings.speed = GameSpeed.by_id(&"instant")
	assert_eq(
		BoardBeat.frame(BoardBeat.SHOAL_MS, BoardBeat.SHOAL_MS), 0, "Instant played the shimmer"
	)
