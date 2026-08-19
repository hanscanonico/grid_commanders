extends GutTest
## The board's muzzle flash, as geometry: how far the star reaches at a given
## point in its beat, and the whole-pixel rects that reach draws. Pure and
## static, like PathArrow.segments, so the shape is checked without a scene.
##
## Worth checking rather than eyeballing because the flash's whole job is to be
## legible for two frames on a 16-pixel tile: a reach that lands on half a pixel
## shimmers against art drawn on whole ones, and a star that never reaches zero
## is a flash that stays on the board after the shot.

const ORIGIN := Vector2(40, 24)


func test_a_full_spark_reaches_the_style_radius() -> void:
	assert_eq(MuzzleFlash.reach_for(2.0, 1.0), 2.0)


func test_a_spent_spark_draws_nothing() -> void:
	assert_eq(MuzzleFlash.reach_for(2.0, 0.0), 0.0)
	assert_eq(MuzzleFlash.arms(ORIGIN, MuzzleFlash.reach_for(2.0, 0.0)).size(), 0)


func test_a_styleless_weapon_never_draws() -> void:
	assert_eq(MuzzleFlash.reach_for(0.0, 1.0), 0.0)


## Every reach the tween passes through is a whole number of world pixels, so the
## star steps down a pixel at a time instead of sliding between them.
func test_the_reach_is_always_whole_pixels() -> void:
	for step in 21:
		var reach := MuzzleFlash.reach_for(1.875, step / 20.0)
		assert_eq(reach, floorf(reach), "reach at %d/20 is off the pixel grid" % step)


func test_the_star_is_two_bars_crossing_at_the_muzzle() -> void:
	var bars := MuzzleFlash.arms(ORIGIN, 3.0)
	var span := 3.0 * 2.0 + MuzzleFlash.ARM
	assert_eq(bars.size(), 2)
	assert_eq(bars[0].size, Vector2(span, MuzzleFlash.ARM))
	assert_eq(bars[1].size, Vector2(MuzzleFlash.ARM, span))
	assert_eq(bars[0].get_center(), ORIGIN)
	assert_eq(bars[1].get_center(), ORIGIN)


## The smallest star the board can draw is a single lit pixel with an outline
## around it, not an empty rect.
func test_a_one_pixel_reach_still_draws() -> void:
	assert_eq(MuzzleFlash.arms(ORIGIN, 1.0).size(), 2)
	assert_eq(MuzzleFlash.core_mark(ORIGIN, 1.0).size(), 0)


func test_the_core_arrives_once_the_arms_stand_out_past_it() -> void:
	var heart := MuzzleFlash.core_mark(ORIGIN, 2.0)
	assert_eq(heart.size(), 1)
	assert_eq(heart[0].size, Vector2(MuzzleFlash.CORE, MuzzleFlash.CORE))
	assert_eq(heart[0].get_center(), ORIGIN)
