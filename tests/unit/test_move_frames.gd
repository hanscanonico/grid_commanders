extends GutTest
## The board's move clip: the gait sheets a unit plays while it walks a path,
## their cadence, and which way a step turns it.
##
## In scope for the same reason test_ambient_frames.gd is: the sheet paths,
## `BoardBeat.frame` and `UnitSprite.facing_for` are static and pure, and nothing
## here builds a sprite. What is under test is the art contract — a clip
## regenerated as the idle, or a sheet cut on a different grid, changes no code
## and no other test unless one reads the pixels.

const SPRITE_W := UnitSprite.SPRITE_W
const SPRITE_H := UnitSprite.SPRITE_H

var units: UnitDB
var ambient_a: Image
var ambient_b: Image
var move_a: Image
var move_b: Image
var opened_at: GameSpeed


func before_each() -> void:
	units = Fixture.unit_db()
	ambient_a = _sheet(UnitSprite.UNITS_ATLAS_PATH)
	ambient_b = _sheet(UnitSprite.UNITS_ATLAS_B_PATH)
	move_a = _sheet(UnitSprite.UNITS_ATLAS_MOVE_PATH)
	move_b = _sheet(UnitSprite.UNITS_ATLAS_MOVE_B_PATH)
	opened_at = Settings.speed


func after_each() -> void:
	Settings.speed = opened_at
	BoardBeat.frozen = false


## Swapping the clip swaps which texture the AtlasTexture points at and nothing
## else, so a move sheet cut on a different grid would put every unit in its
## neighbour's cell.
func test_the_move_sheets_are_the_ambient_grid() -> void:
	assert_not_null(move_a, "the move sheet did not load")
	assert_not_null(move_b, "move frame B did not load")
	assert_eq(move_a.get_size(), ambient_a.get_size(), "the move sheet is a different size")
	assert_eq(move_b.get_size(), ambient_a.get_size(), "move frame B is a different size")


## The gait is opt-in per unit family in the generator, so an unauthored column
## carries its ambient cell in both move sheets — which is what lets the game
## play the clip for the whole roster with no per-unit branch. What may not
## happen is one of the pair moving without the other: that is a half-authored
## family, and it reads as a unit snapping between parked and striding.
func test_every_column_is_authored_in_both_move_frames_or_in_neither() -> void:
	assert_gt(units.size(), 0, "no units loaded, so this would pass vacuously")
	for type in units.all():
		var walks_a := _column_differs(ambient_a, move_a, type.atlas_col)
		var walks_b := _column_differs(ambient_b, move_b, type.atlas_col)
		assert_eq(
			walks_a,
			walks_b,
			"%s: one move frame is its ambient cell and the other is not" % type.id
		)


## Otherwise the clip is the idle and nothing shipped.
func test_at_least_one_column_walks() -> void:
	var walkers: Array[String] = []
	for type in units.all():
		if _column_differs(ambient_a, move_a, type.atlas_col):
			walkers.append(String(type.id))
	assert_gt(walkers.size(), 0, "no column differs from its ambient cell, so the clip is the idle")


## The tier is named rather than inherited: this machine's stored preference may
## be Instant, which is a still board and would pass this vacuously.
func test_the_move_beat_alternates_every_cadence() -> void:
	Settings.speed = GameSpeed.by_id(GameSpeed.DEFAULT_ID)
	assert_eq(BoardBeat.frame(BoardBeat.MOVE_MS, 0), 0, "the gait did not open on frame A")
	assert_eq(
		BoardBeat.frame(BoardBeat.MOVE_MS, BoardBeat.MOVE_MS), 1, "the gait did not turn over"
	)
	assert_eq(
		BoardBeat.frame(BoardBeat.MOVE_MS, 2 * BoardBeat.MOVE_MS), 0, "the gait did not come back"
	)


## The gait belongs to the move tween, which the tier scales, so its cadence has
## to scale with it: `cutscene_rate` is 1.0 at the default tier and 1.5 at Quick.
func test_the_gait_beats_on_the_tier_being_played() -> void:
	Settings.speed = GameSpeed.by_id(GameSpeed.DEFAULT_ID)
	assert_eq(BoardBeat.move_ms(), BoardBeat.MOVE_MS, "the default tier retimed the gait")
	Settings.speed = GameSpeed.by_id(&"quick")
	assert_eq(BoardBeat.move_ms(), 107, "Quick did not hurry the gait")
	assert_eq(BoardBeat.frame(BoardBeat.move_ms(), 0), 0, "the gait did not open on frame A")
	assert_eq(
		BoardBeat.frame(BoardBeat.move_ms(), BoardBeat.move_ms()),
		1,
		"the gait did not turn over on Quick's period"
	)
	assert_eq(
		BoardBeat.frame(BoardBeat.move_ms(), BoardBeat.MOVE_MS - 1),
		1,
		"Quick's gait was still walking the authored period"
	)


## A tier hurries the legs; it may not put them back on a cadence that shares a
## tick with the scenery, which is the anti-stutter rule below at every tier.
func test_every_tier_keeps_the_gait_off_the_other_cadences() -> void:
	for id: StringName in [GameSpeed.DEFAULT_ID, &"quick", &"instant"]:
		Settings.speed = GameSpeed.by_id(id)
		var gait := BoardBeat.move_ms()
		for other in [BoardBeat.AMBIENT_MS, BoardBeat.SEA_MS]:
			assert_ne(other % gait, 0, "%s: the gait divides %d" % [id, other])
			assert_ne(gait % other, 0, "%s: the gait is a multiple of %d" % [id, other])


func test_a_frozen_clock_and_instant_hold_frame_a() -> void:
	Settings.speed = GameSpeed.by_id(GameSpeed.DEFAULT_ID)
	BoardBeat.frozen = true
	assert_eq(BoardBeat.frame(BoardBeat.MOVE_MS, BoardBeat.MOVE_MS), 0, "a pinned capture strode")
	BoardBeat.frozen = false
	Settings.speed = GameSpeed.by_id(&"instant")
	assert_eq(BoardBeat.frame(BoardBeat.move_ms(), BoardBeat.MOVE_MS), 0, "Instant played the gait")


## The tier shows a turn rather than playing it out, so the pad before the
## computer's first command is the last thing that may hold the board still.
func test_instant_opens_a_turn_with_no_delay() -> void:
	assert_eq(GameSpeed.by_id(&"instant").start_delay_seconds(), 0.0, "Instant padded its opening")
	assert_gt(
		GameSpeed.by_id(GameSpeed.DEFAULT_ID).start_delay_seconds(),
		0.0,
		"the default tier lost its opening pad"
	)


## A walking unit, a parked one and the water must never turn over on the same
## tick, or the whole board blinks at once instead of moving.
func test_the_cadences_share_no_tick() -> void:
	for other in [BoardBeat.AMBIENT_MS, BoardBeat.SEA_MS]:
		assert_ne(other % BoardBeat.MOVE_MS, 0, "the gait divides %d" % other)
		assert_ne(BoardBeat.MOVE_MS % other, 0, "the gait is a multiple of %d" % other)


## The sheets are drawn facing screen-left; a vertical leg turns nothing, which
## is what keeps a unit walking up a column facing the way it entered it.
func test_a_step_turns_the_sprite_only_when_it_has_a_side() -> void:
	assert_true(UnitSprite.facing_for(Vector2i(1, 0), false), "a rightward step did not mirror")
	assert_false(UnitSprite.facing_for(Vector2i(-1, 0), true), "a leftward step stayed mirrored")
	assert_true(UnitSprite.facing_for(Vector2i(0, 1), true), "a downward step turned the sprite")
	assert_false(UnitSprite.facing_for(Vector2i(0, -1), false), "an upward step turned the sprite")


## Why the mirror ends with the clip. The ambient pair is drawn over a cast
## shadow the generator does not centre in the cell, so a sprite left mirrored
## after a walk drops that shadow on the other side of the unit from an
## unmirrored neighbour of the same type — two suns on one board. `UnitSprite`'s
## `moving` setter faces a parked sprite forward again, and this is the
## measurement that says it has to.
func test_a_mirrored_park_would_move_the_ambient_shadow() -> void:
	var centre := float(SPRITE_W - 1) / 2.0
	for type in units.all():
		for sheet: Image in [ambient_a, ambient_b]:
			var shadow := _shadow_centre(sheet, type.atlas_col)
			assert_gt(shadow, 0.0, "%s: no cast shadow under the parked cell" % type.id)
			assert_ne(
				shadow,
				centre,
				(
					(
						"%s parks over a cell-centred shadow — the ambient art has moved,"
						+ " so UnitSprite's rest-facing rule can be revisited"
					)
					% type.id
				)
			)


## The horizontal middle of what a column draws below the ground line, which on
## these sheets is the cast shadow and nothing else.
func _shadow_centre(sheet: Image, column: int) -> float:
	var left := SPRITE_W
	var right := -1
	for row in int(sheet.get_height() / SPRITE_H):
		for y in range(SPRITE_H - UnitSprite.CELL_GROUND_PX, SPRITE_H):
			for x in SPRITE_W:
				if sheet.get_pixel(column * SPRITE_W + x, row * SPRITE_H + y).a == 0.0:
					continue
				left = mini(left, x)
				right = maxi(right, x)
	return -1.0 if right < 0 else float(left + right) / 2.0


## True when any faction row of `column` is *drawn* differently between two
## sheets. Bytes alone are not the reading, for test_ambient_frames.gd's reason:
## the atlases import with `fix_alpha_border`, which bleeds each figure's colours
## into the transparent pixels around it.
func _column_differs(left: Image, right: Image, column: int) -> bool:
	var rows := int(left.get_height() / SPRITE_H)
	for row in rows:
		var region := Rect2i(column * SPRITE_W, row * SPRITE_H, SPRITE_W, SPRITE_H)
		var cell_left := left.get_region(region)
		var cell_right := right.get_region(region)
		if (
			cell_left.get_data() != cell_right.get_data()
			and _visibly_differs(cell_left, cell_right)
		):
			return true
	return false


func _visibly_differs(cell_a: Image, cell_b: Image) -> bool:
	for y in cell_a.get_height():
		for x in cell_a.get_width():
			var pixel_a := cell_a.get_pixel(x, y)
			var pixel_b := cell_b.get_pixel(x, y)
			if pixel_a.a == 0.0 and pixel_b.a == 0.0:
				continue
			if pixel_a != pixel_b:
				return true
	return false


func _sheet(path: String) -> Image:
	var texture := load(path) as Texture2D
	return texture.get_image() if texture != null else null
