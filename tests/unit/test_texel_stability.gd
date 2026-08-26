extends GutTest
## Texel stability: the board's art must land on whole screen pixels at every
## rung of the zoom ladder, or nearest-neighbour sampling drops and doubles rows
## — and which rows it drops moves as the camera pans, which reads as crawling
## edges the moment anything on the board is animated.
##
## `BattleZoom.floor_for` and `rungs_for` are pure and static, like
## `PathArrow.segments` and `SeatStrip.normalised_sides`, so the ladder is checked
## without a scene. What a windowed render would show is simulated exactly rather
## than photographed: a render is not CI-able, and the sampling is arithmetic
## anyway.
##
## TWO CLAIMS WERE WEAKENED BY PLAYTEST (2026-08-19), and the suite says so rather
## than quietly dropping them. The player's verdict on the shipped build was that
## it "looks more pixelized than before", and the captures agreed: forcing the
## window to a whole multiple of the canvas made every texel a perfectly square,
## perfectly aligned block and shrank a maximized 1512x945 Mac window's picture to
## 1280x720 inside hard bars. So `window/stretch/scale_mode` is back off, the
## window scale is fractional again on such a window, and `s` with it — the
## instability below is now a *recorded cost* rather than a thing the ladder
## defends against. The floor rung went with it: it frames the whole board and is
## allowed to be fractional, because at maximum zoom-out Bulwark's 49x32 was
## showing half of itself. Every rung above the floor is still whole — and on a
## board whose fit rung sits above the default (`boot_camp`, `quartet`) the floor
## is the rung the match opens on, so those play fractional again as they did
## before the snap.
##
## THE FORMULA. Under `canvas_items` stretch the game draws into a 640x360 canvas
## and the window scales it by `window_scale = window_height / 360`. A world
## pixel is therefore `s = zoom * window_scale` screen pixels, and screen row `p`
## shows source row `floori((p + 0.5) / s)`. The board's art is stable when every
## source row occupies the same number of screen rows — which is exactly when `s`
## is a whole number.
##
## The 4x terrain oversample is not part of `s` on purpose. The atlas cell is
## `TERRAIN_PX` for a `TILE` world cell and the layer is scaled by `TILE /
## TERRAIN_PX`; that ratio is an exact 1-in-4 decimation with a phase that never
## moves, so it contributes no crawl of its own and `s` is the whole of what the
## eye judges. `test_the_terrain_oversample_is_a_whole_ratio` is what holds it.

## Window heights a player actually gets, over the 360-line canvas: the 720p
## default, a 1080p screen, and the canvas at 1:1.
const INTEGER_WINDOW_SCALES: Array[float] = [1.0, 2.0, 3.0]

## A maximized window on a 1512x945 Mac. Not a multiple of the canvas, which is
## what `window/stretch/scale_mode = "integer"` exists to answer.
const FRACTIONAL_WINDOW_SCALE := 945.0 / 360.0

## Rows enough that a fractional scale's period cannot hide inside the sample.
const SOURCE_ROWS := 64


## One column of a 1px checkerboard, sampled nearest-neighbour at `s` screen
## pixels per source row: how many screen rows each source row won.
func _rows_per_source_row(s: float) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(SOURCE_ROWS)
	counts.fill(0)
	var screen_rows := int(SOURCE_ROWS * s)
	for p in screen_rows:
		var source := floori((p + 0.5) / s)
		if source < SOURCE_ROWS:
			counts[source] += 1
	return counts


## True when no source row was dropped (won nothing) or doubled (won more than
## its neighbours) — the checkerboard renders as even bands rather than as a
## pattern of fat and thin ones.
func _is_stable(s: float) -> bool:
	var counts := _rows_per_source_row(s)
	for count in counts:
		if count < 1 or count != counts[0]:
			return false
	return true


## The whole rungs a board offers above its floor. A board too big for 1x — the
## 49x32 asked for here — offers the whole ladder.
func _ladder() -> Array[float]:
	var rungs: Array[float] = []
	for rung in BattleZoom.rungs_for(
		BattleZoom.floor_for(_board_view(), _map_px(Vector2i(49, 32)))
	):
		if rung == floorf(rung):
			rungs.append(rung)
	return rungs


func test_every_rung_is_stable_at_every_window_scale() -> void:
	for rung in _ladder():
		for window_scale in INTEGER_WINDOW_SCALES:
			assert_true(
				_is_stable(rung * window_scale),
				"rung %.2f at window scale %.0fx drops or doubles rows" % [rung, window_scale]
			)


## The ladder this replaced was anchored on the per-map fit ratio, so a board
## whose ratio was 1.37 was played on 1.37 / 2.37 / … — fractional at every rung
## but the last. This is the check failing on that ladder.
func test_the_old_map_ratio_ladder_is_unstable() -> void:
	var anchor := 1.37
	for step in 4:
		assert_false(
			_is_stable((anchor + step) * 2.0),
			"fit-anchored rung %.2f should sample fractionally" % [anchor + step]
		)


## The zoom half of the answer is not the whole of it: a window that is not a
## whole multiple of the canvas puts every rung back on fractional sampling. This
## is what the shipped game now does on a maximized Mac window, knowingly — see
## the header. The arithmetic is unchanged; only which side of it we ship is.
func test_a_fractional_window_scale_is_unstable() -> void:
	for rung in _ladder():
		assert_false(
			_is_stable(rung * FRACTIONAL_WINDOW_SCALE),
			"rung %.2f should sample fractionally on a non-multiple window" % rung
		)


func test_the_terrain_oversample_is_a_whole_ratio() -> void:
	assert_eq(BattleView.TERRAIN_PX % BattleView.TILE, 0)


## The other half of `s`, and the half no rung can defend — and the half the
## player overruled. `integer` fills the window's remainder with bars instead of
## picture and makes the texel lattice perfectly regular, which is what the
## playtest read as "more pixelized"; the setting is pinned to its absence here so
## re-forcing it is a decision rather than a drift.
func test_the_window_scale_is_not_forced_to_whole_multiples() -> void:
	assert_ne(ProjectSettings.get_setting("display/window/stretch/scale_mode"), "integer")


## The board viewport of the 640x360 canvas: everything the docked HUD chrome
## leaves over.
func _board_view() -> Vector2:
	return Vector2(640, 360 - MobileDock.chrome_h())


func _map_px(cells: Vector2i) -> Vector2:
	return Vector2(cells * BattleView.TILE)


## Every rung a match is played at is whole. The floor is the one exception and
## the next test is what it is for.
func test_every_rung_above_the_floor_is_whole() -> void:
	for width in range(1, 60):
		for height in range(1, 40):
			var floor_zoom := BattleZoom.floor_for(_board_view(), _map_px(Vector2i(width, height)))
			var rungs := BattleZoom.rungs_for(floor_zoom)
			assert_eq(rungs[0], floor_zoom, "the floor is the furthest-out rung")
			for i in range(1, rungs.size()):
				assert_eq(
					rungs[i], floorf(rungs[i]), "%dx%d offers a fractional rung" % [width, height]
				)
				assert_gt(rungs[i], floor_zoom, "a rung above the floor is above the floor")


## Whatever the board, its floor frames all of it — that is the whole job of the
## furthest-out rung, and why it is allowed to be fractional.
func test_the_floor_frames_the_whole_board() -> void:
	var view := _board_view()
	for width in range(1, 60):
		for height in range(1, 40):
			var map_px := _map_px(Vector2i(width, height))
			var floor_zoom := BattleZoom.floor_for(view, map_px)
			assert_true(
				map_px.x * floor_zoom <= view.x + 0.01 and map_px.y * floor_zoom <= view.y + 0.01,
				"%dx%d is cropped at its own floor" % [width, height]
			)


## A board small enough to be shown several times over pins at MAX_ZOOM instead,
## so the zoom keys cannot oscillate between a floor above the ceiling and it.
func test_a_tiny_board_pins_at_the_ceiling() -> void:
	var rungs := BattleZoom.rungs_for(BattleZoom.floor_for(_board_view(), _map_px(Vector2i(4, 3))))
	assert_eq(rungs.size(), 1)
	assert_eq(rungs[0], BattleZoom.MAX_ZOOM)


## Bulwark's 49x32 fits no whole rung, so its floor is the fractional one that
## frames it — the survey view a 49x32 board exists to be read from.
func test_a_board_too_big_for_one_rung_still_gets_a_survey_rung() -> void:
	var floor_zoom := BattleZoom.floor_for(_board_view(), _map_px(Vector2i(49, 32)))
	assert_lt(floor_zoom, 1.0, "no whole rung frames Bulwark")
	assert_eq(BattleZoom.rungs_for(floor_zoom).size(), 6, "the floor plus 1x through 5x")


# --- where the board rests ----------------------------------------------------
#
# A whole rung is only half of a stable frame: the board also has to be *parked*
# on whole screen pixels. `BattleView._apply_board_offset` docks it by
# `MobileDock.board_lift_px() / zoom` **world** units, which the camera turns back into exactly
# that many screen pixels — the rung cancels. So no rung can rescue a
# fractional lift, and the lift itself is the whole of what has to be whole.
# That is why these hold it to an integer rather than walking the ladder.


func test_the_board_docks_on_a_whole_screen_pixel() -> void:
	var lift := float(MobileDock.board_lift_px())
	assert_eq(lift, floorf(lift), "the board docks %.2f screen pixels up" % lift)


## The bars differ by an odd number of pixels, so the exact half-difference the
## dock was derived from can only ever be half a pixel — which is why the lift is
## a rounded constant. It still has to be the *nearest* whole pixel to it, or the
## board would be docking somewhere other than the band's middle.
func test_the_lift_is_the_nearest_whole_pixel_to_the_bands_middle() -> void:
	var exact := float(UiTheme.HUD_BOTTOM_H + MobileDock.height() - UiTheme.HUD_TOP_H) / 2.0
	assert_ne(exact, floorf(exact), "the bars should differ by an odd number of pixels")
	assert_almost_eq(float(MobileDock.board_lift_px()), exact, 0.5, "the lift is the nearest pixel")


## The board rides up rather than down: the bottom bar is the taller one, so the
## band's middle is above the window's.
func test_the_board_rides_up_toward_the_shorter_bar() -> void:
	assert_gt(MobileDock.board_lift_px(), 0)


## The entry flinch is a scale on a still of the board, and it has to be scaled
## about the point a camera zoom would have scaled it about — the camera's own
## anchor, which is the window's middle lifted by the dock.
func test_the_punch_scales_about_the_cameras_own_anchor() -> void:
	var view := Vector2(640, 360)
	var anchor := BoardPunch.band_center(view)
	assert_eq(anchor.x, view.x / 2.0)
	assert_eq(anchor.y, view.y / 2.0 - float(MobileDock.board_lift_px()))
	assert_eq(anchor.y, floorf(anchor.y), "a fractional anchor would resample the still")


## The capture cut-in's squad is board art at 1:1, so its draw origin has to be a
## whole pixel however the march, the bob and the stagger place it.
func test_the_capture_squad_is_drawn_at_one_to_one() -> void:
	assert_eq(CaptureStage.FIGURE_PX, UnitSprite.SPRITE_W)
	assert_eq(CaptureStage.FIGURE_H, UnitSprite.SPRITE_H)


## Same rule for the combat cut-in's figures: both stages blow the board's own
## cell up at 1:1, so a box shaped anything but the cell's would rescale it.
func test_the_combat_figures_are_drawn_at_one_to_one() -> void:
	assert_eq(CutsceneSide.FIGURE_PX, UnitSprite.SPRITE_W)
	assert_eq(CutsceneSide.FIGURE_H, UnitSprite.SPRITE_H)


## A unit's art hangs off its footprint, so a cell taller than it is wide lifts the
## texture by half the surplus. Half of an odd surplus is half a texel, which the
## board samples with nearest filtering — the same defect a fractional rung has.
func test_the_unit_art_is_offset_by_whole_texels() -> void:
	assert_eq(UnitSprite.SPRITE_OVERFLOW % 2, 0, "an odd overflow draws the art on half a texel")
	assert_eq(UnitSprite.ART_OFFSET.x, 0.0)
	assert_eq(UnitSprite.ART_OFFSET.y, roundf(UnitSprite.ART_OFFSET.y))
	assert_eq(UnitSprite.ART_OFFSET.y, -float(UnitSprite.SPRITE_OVERFLOW) / 2.0)
