extends GutTest
## `goal_engageability` · a unit is only aimed at what it could shoot.
##
## The advance takes the nearest visible enemy of any kind, so a cruiser is
## routinely handed a land unit and walks the coast at something the damage chart
## says it can never hit. Half of the oscillation findings in the two analysed
## four-army recordings are that shape (docs/causeway_measure.md).
##
## Every test is one board reached twice, with the dial off and on; the off runs
## are the inertness pin the Judgement D1 contract owes. The dial ships at 0 on
## every tier, so a tier value is never what these read.

## Our cruiser on a channel, an enemy infantry ashore three tiles west and an
## enemy submarine twelve tiles east. The chart lets a cruiser fire on the boat
## and on nothing on the beach, so the two goals pull in opposite directions.
const A_BEACH_AND_A_BOAT := (
	"[terrain]\n"
	+ "................\n"
	+ "SSSSSSSSSSSSSSSS\n"
	+ "[units]\n1 c 2 1\n2 i 0 0\n2 s 14 1"
)

## The same channel with the submarine gone: nothing on the board is anything
## this cruiser could engage.
const A_BEACH_AND_NOTHING_ELSE := (
	"[terrain]\n" + "................\n" + "SSSSSSSSSSSSSSSS\n" + "[units]\n1 c 2 1\n2 i 0 0"
)

const OUR_CRUISER := Vector2i(2, 1)


func _destination(map_text: String, engageability: float) -> Vector2i:
	var state := Fixture.state(map_text)
	assert_not_null(state, "the fixture board must build")
	var profile := AIProfile.new()  # Normal's shipped numbers; only the one dial varies
	profile.goal_engageability = engageability
	var command := AIController.new(Fixture.unit_db(), profile).plan_next_command(state)
	assert_true(command is MoveCommand, "expected an advance, got %s" % command)
	var path: Array[Vector2i] = (command as MoveCommand).path
	assert_false(path.is_empty(), "an advance must carry a path")
	return path[path.size() - 1]


## The defect itself: with the dial off the boat walks west at an infantry it
## cannot shoot, and it would keep doing it every turn of the match.
func test_a_cruiser_walks_at_the_hull_it_can_engage_and_not_the_beach() -> void:
	assert_lt(
		_destination(A_BEACH_AND_A_BOAT, 0.0).x,
		OUR_CRUISER.x,
		"blind, the nearest enemy is the infantry ashore and the cruiser goes west at it"
	)
	assert_gt(
		_destination(A_BEACH_AND_A_BOAT, 1.0).x,
		OUR_CRUISER.x,
		"filtered, the only enemy it could ever fire on is the submarine, and it goes east"
	)


## The fallback, and the reason it is a fallback: an empty filter means "nothing
## on this board is yours to shoot", which is an argument for going somewhere
## rather than for standing still. A frozen fleet reads worse than a milling one.
func test_a_unit_with_nothing_to_engage_still_advances() -> void:
	var blind := _destination(A_BEACH_AND_NOTHING_ELSE, 0.0)
	assert_lt(blind.x, OUR_CRUISER.x, "blind, the cruiser closes on the only enemy there is")
	assert_eq(
		_destination(A_BEACH_AND_NOTHING_ELSE, 1.0),
		blind,
		"with nothing engageable anywhere the filtered turn must be the blind one"
	)
