extends GutTest
## Texel stability: the board's art must land on whole screen pixels at every
## rung of the zoom ladder, or nearest-neighbour sampling drops and doubles rows
## — and which rows it drops moves as the camera pans, which reads as crawling
## edges the moment anything on the board is animated.
##
## `BattleZoom.floor_for` is pure and static, like `PathArrow.segments` and
## `SeatStrip.normalised_sides`, so the ladder is checked without a scene. What a
## windowed render would show is simulated exactly rather than photographed: a
## render is not CI-able, and the sampling is arithmetic anyway.
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


func _ladder() -> Array[float]:
	var rungs: Array[float] = []
	var rung := BattleZoom.MIN_ZOOM
	while rung <= BattleZoom.MAX_ZOOM:
		rungs.append(rung)
		rung += BattleZoom.STEP
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
## whole multiple of the canvas puts every rung back on fractional sampling,
## which is the evidence for `window/stretch/scale_mode = "integer"`.
func test_a_fractional_window_scale_is_unstable() -> void:
	for rung in _ladder():
		assert_false(
			_is_stable(rung * FRACTIONAL_WINDOW_SCALE),
			"rung %.2f should sample fractionally on a non-multiple window" % rung
		)


func test_the_terrain_oversample_is_a_whole_ratio() -> void:
	assert_eq(BattleView.TERRAIN_PX % BattleView.TILE, 0)


## The board viewport of the 640x360 canvas: everything the two docked HUD bars
## leave over.
func _board_view() -> Vector2:
	return Vector2(640, 360 - UiTheme.HUD_BARS_H)


func _map_px(cells: Vector2i) -> Vector2:
	return Vector2(cells * BattleView.TILE)


func test_the_floor_is_always_a_whole_rung() -> void:
	for width in range(4, 60):
		for height in range(4, 40):
			var floor_zoom := BattleZoom.floor_for(_board_view(), _map_px(Vector2i(width, height)))
			assert_eq(floor_zoom, floorf(floor_zoom), "%dx%d floors fractionally" % [width, height])
			assert_between(floor_zoom, BattleZoom.MIN_ZOOM, BattleZoom.MAX_ZOOM)


## A board small enough to be shown whole is: the floor is the largest rung that
## still holds all of it, never one that crops it.
func test_a_small_board_is_shown_whole_at_its_floor() -> void:
	var cells := Vector2i(12, 8)
	var map_px := _map_px(cells)
	var view := _board_view()
	var floor_zoom := BattleZoom.floor_for(view, map_px)
	assert_gt(floor_zoom, BattleZoom.MIN_ZOOM, "a 12x8 board fits several times over")
	assert_true(map_px.x * floor_zoom <= view.x and map_px.y * floor_zoom <= view.y)
	assert_false(
		map_px.x * (floor_zoom + 1.0) <= view.x and map_px.y * (floor_zoom + 1.0) <= view.y,
		"the floor should be the furthest-out rung that fits, not one further in"
	)


## Bulwark's 49x32 does not fit the canvas at any whole rung. It scrolls at 1x
## rather than buying itself a fractional one — the honest floor.
func test_a_board_too_big_for_one_rung_floors_at_one() -> void:
	assert_eq(BattleZoom.floor_for(_board_view(), _map_px(Vector2i(49, 32))), BattleZoom.MIN_ZOOM)
