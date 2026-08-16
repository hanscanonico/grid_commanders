extends GutTest
## `capture_threat_aversion` · the capture walk is priced against the fire it
## invites.
##
## `_consider_captures` prices the ground, the progress and the walk and nothing
## else, on every tier — which is why infantry is the first subject of the replay
## analyser's `walk_into_fire` in every recording surveyed so far. The term is
## `_threat_penalty`'s exact arithmetic, so it competes in the one AIUnitPlan
## score every sibling candidate is in.
##
## Every test is one board reached twice, with the dial off and on. It ships at 0
## on every tier, so a tier value is never what these read.

## Two neutral cities our infantry can reach: the near one at (2,0), two steps
## away and inside an enemy tank's reach, and the far one at (7,0), three steps
## away and outside it.
const A_SAFE_CITY_AND_A_WATCHED_ONE := (
	"[terrain]\n"
	+ "..C....C..\n"
	+ "..........\n"
	+ "..........\n"
	+ "..........\n"
	+ "[units]\n1 i 4 0\n2 t 1 3"
)

## The same board with both cities already ours, so the infantry has nothing to
## capture and the capture path never asks a question.
const NOTHING_TO_TAKE := (
	"[terrain]\n"
	+ "..C....C..\n"
	+ "..........\n"
	+ "..........\n"
	+ "..........\n"
	+ "[owners]\n1 2 0\n1 7 0\n"
	+ "[units]\n1 i 4 0\n2 t 1 3"
)

const WATCHED_CITY := Vector2i(2, 0)
const SAFE_CITY := Vector2i(7, 0)


func _capture_cell(map_text: String, aversion: float) -> Vector2i:
	var profile := AIProfile.new()  # Normal's shipped numbers; only the one dial varies
	profile.capture_threat_aversion = aversion
	var state := Fixture.state(map_text)
	assert_not_null(state, "the fixture board must build")
	var command := AIController.new(Fixture.unit_db(), profile).plan_next_command(state)
	assert_true(command is CaptureCommand, "expected a capture, got %s" % command)
	var path: Array[Vector2i] = (command as CaptureCommand).path
	return path[path.size() - 1]


## The defect: nothing on the capture path knows the near city is being watched,
## so the shorter walk wins and the infantry is shot for it next turn.
func test_a_capturer_walks_around_a_watched_property() -> void:
	assert_eq(
		_capture_cell(A_SAFE_CITY_AND_A_WATCHED_ONE, 0.0),
		WATCHED_CITY,
		"blind, the only thing separating the two cities is one step of walking"
	)
	assert_eq(
		_capture_cell(A_SAFE_CITY_AND_A_WATCHED_ONE, 1.0),
		SAFE_CITY,
		"priced, the tank's reading of the near city outweighs the step it saves"
	)


## The threat map is a flood fill per visible enemy, so it is resolved on the
## first capturable cell rather than up front: a unit with nothing to take builds
## nothing, and the dial at 0 never reaches the question at all.
func test_no_threat_map_is_built_for_a_unit_with_nothing_to_capture() -> void:
	for aversion in [0.0, 1.0]:
		var state := Fixture.state(NOTHING_TO_TAKE)
		assert_not_null(state, "the fixture board must build")
		var profile := AIProfile.new()
		profile.capture_threat_aversion = aversion
		var context := AIPlanningContext.new(Fixture.unit_db())
		context.begin(state)
		AIUnitActionPlanner.new(profile).plan_next(context)
		assert_false(
			context.threat_map_built(),
			"at aversion %s a board with nothing to capture must build no threat map" % aversion
		)
