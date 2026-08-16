extends GutTest
## `standoff_band_tolerance` · an indirect unit inside its band is content there.
##
## `_position_rank` makes an indirect unit want exactly maximum stand-off from a
## goal that is recomputed every turn, which is a potential that repels up close
## and attracts from afar: a battleship in one analysed recording cycled between
## two cells for eight days (docs/causeway_measure.md). Flat inside the band lets
## `_advance_command`'s own cost tie-break hold the unit where it stands.
##
## Every test is one board reached twice, with the dial off and on. It ships at 0
## on every tier, so a tier value is never what these read.
##
## The gun is out of ammo on every board here, which is the whole of the setup:
## `AttackRange.can_fire` then offers no shot, so the turn falls through to the
## advance these tests are about. Being indirect and its band are its type's, so
## neither moves with the magazine.

## Our artillery at (5,0) with the enemy two tiles east: inside its 2-3 band, one
## short of maximum stand-off.
const INSIDE_THE_BAND := "[terrain]\n............\n[units]\n1 g 5 0\n2 t 7 0"

## The same board with the enemy one tile further off, so the gun already stands
## at maximum stand-off.
const AT_MAXIMUM_STANDOFF := "[terrain]\n............\n[units]\n1 g 5 0\n2 t 8 0"

const OUR_GUN := Vector2i(5, 0)


func _destination(map_text: String, tolerance: int, at := OUR_GUN) -> Vector2i:
	var state := Fixture.state(map_text)
	assert_not_null(state, "the fixture board must build")
	var gun := state.unit_at(at)
	assert_not_null(gun, "the fixture must stand a gun at %s" % at)
	gun.ammo = 0
	var profile := AIProfile.new()  # Normal's shipped numbers; only the one dial varies
	profile.standoff_band_tolerance = tolerance
	var command := AIController.new(Fixture.unit_db(), profile).plan_next_command(state)
	assert_true(command is MoveCommand, "expected an advance, got %s" % command)
	var path: Array[Vector2i] = (command as MoveCommand).path
	if path.is_empty():
		return at
	return path[path.size() - 1]


## The cycle's own step: the enemy closed a tile, so the blind gun backs off a
## tile — and next turn the enemy closes again and it backs off again.
func test_a_gun_inside_its_band_stays_put() -> void:
	assert_eq(
		_destination(INSIDE_THE_BAND, 0),
		Vector2i(4, 0),
		"blind, one tile short of maximum stand-off is worth a tile of walking"
	)
	assert_eq(
		_destination(INSIDE_THE_BAND, 1),
		OUR_GUN,
		"inside the band every cell ranks alike, so the cheapest one is the one it is on"
	)


## The band is flattened and nothing else is: a gun outside its ring still walks
## into it, at either setting, because that half of the rank is untouched.
func test_a_gun_outside_its_band_still_closes_on_the_ring() -> void:
	var far := "[terrain]\n............\n[units]\n1 g 0 0\n2 t 11 0"
	for tolerance in [0, 1]:
		assert_gt(
			_destination(far, tolerance, Vector2i(0, 0)).x,
			0,
			"at tolerance %s a gun out of range must still march toward the enemy" % tolerance
		)


## The gun already at maximum stand-off is where the two settings agree, which is
## what says the dial buys stillness rather than a different preference.
func test_a_gun_at_maximum_standoff_is_unmoved_by_the_dial() -> void:
	assert_eq(
		_destination(AT_MAXIMUM_STANDOFF, 0),
		OUR_GUN,
		"blind, the gun is already exactly where it wants to be"
	)
	assert_eq(_destination(AT_MAXIMUM_STANDOFF, 1), OUR_GUN, "and the band changes nothing there")
