extends GutTest
## The AI Economy plan's capabilities: what the planner buys and walks to once it
## can read the map as an economy rather than as a fight.
##
## AE1 is the capture roster. `capture_unit_target` used to be the whole answer
## and it happens to equal the roster every shipped board deals, so the urgent
## tier was empty before the first command of every match and the planner banked
## its opening turns away on a board covered in neutral ground. The target now
## scales with what is left to take, floored at that same number.
##
## Every test here isolates production the way test_ai_production.gd does — every
## unit has already acted, so the only command left to plan is the build.

## Seventeen properties: one owned base and sixteen neutral cities. At rate 0.25
## that is a target of four against the three capture units the board deals.
const PROPERTY_RICH := (
	"[terrain]\n"
	+ "B.......\n"
	+ "CCCCCCCC\n"
	+ "CCCCCCCC\n"
	+ "........\n"
	+ "[owners]\n1 0 0\n"
	+ "[units]\n1 i 1 3\n1 i 2 3\n1 m 3 3\n"
)

## Three properties: the owned base and two neutral cities. At the same rate the
## target never clears the floor, so this is the board the plan says must keep
## banking and keep reaching the expensive half of the roster.
const PROPERTY_POOR := (
	"[terrain]\n"
	+ "B..C\n"
	+ "...C\n"
	+ "[owners]\n1 0 0\n"
	+ "[units]\n1 i 1 1\n1 i 2 1\n1 m 3 1\n"
)

## The rate every fixture here probes with. High enough that the property-rich
## board clears the floor and the property-poor one cannot.
const RATE := 0.25

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _profile(capture_units_per_property: float) -> AIProfile:
	var profile := AIProfile.new()  # every other capability at the shipped default
	profile.capture_units_per_property = capture_units_per_property
	return profile


## The board with every unit already spent, so production is the only decision
## left and `plan_next_command` answers with the build or with the end of turn.
func _board(map_text: String, funds: int, owned: Array[Vector2i] = []) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	for cell in owned:
		state.set_owner(cell, 1)
	for unit in state.units:
		unit.acted = true
	state.funds[1] = funds
	return state


func _build_id(state: GameState, profile: AIProfile) -> StringName:
	var command := AIController.new(unit_db, profile).plan_next_command(state)
	if command is BuildCommand:
		return (command as BuildCommand).unit_type.id
	return &""


## The defect, on the board it costs the most: twenty neutral properties sitting
## there and the planner opens by banking, because the roster it was dealt already
## met the flat target.
func test_a_property_rich_board_makes_the_capture_roster_short_on_day_one() -> void:
	assert_eq(
		_build_id(_board(PROPERTY_RICH, 5000), _profile(0.0)),
		&"",
		"blind, the AI banks its opening turn with sixteen neutral cities on the board"
	)
	assert_eq(
		_build_id(_board(PROPERTY_RICH, 5000), _profile(RATE)),
		&"infantry",
		"with the map priced, a fourth capturer is urgent and the bank waits"
	)


## D5's self-damping, played on a board: the target counts what is left to take,
## so an army that has taken most of it stops wanting infantry on its own and the
## priority list resumes with no second dial to turn off.
func test_the_target_falls_as_the_map_is_taken() -> void:
	var taken: Array[Vector2i] = []
	for x in range(8):
		taken.append(Vector2i(x, 1))
		taken.append(Vector2i(x, 2))
	assert_eq(
		_build_id(_board(PROPERTY_RICH, 5000, taken.slice(0, 3)), _profile(RATE)),
		&"infantry",
		"thirteen cities still out there wants a fourth capturer"
	)
	assert_eq(
		_build_id(_board(PROPERTY_RICH, 5000, taken.slice(0, 4)), _profile(RATE)),
		&"",
		"one city later the target is back at the floor and the priority list resumes"
	)
	assert_eq(
		_build_id(_board(PROPERTY_RICH, 5000, taken), _profile(RATE)),
		&"",
		"and an army that has taken the whole map wants no more infantry at all"
	)


## R2, guarded directly. The rate that wins the property race must not delete the
## expensive half of the roster from boards with nothing much to race for: on a
## small board the same non-zero rate never clears the floor, so the AI banks and
## still fields its Md Tank.
func test_a_property_poor_board_still_banks_and_still_fields_its_md_tank() -> void:
	assert_eq(
		_build_id(_board(PROPERTY_POOR, 5000), _profile(RATE)),
		&"",
		"two neutral cities are not a race; the AI banks toward the better unit"
	)
	assert_eq(
		_build_id(_board(PROPERTY_POOR, 16000), _profile(RATE)),
		&"md_tank",
		"and it spends the bank on the unit it was saving for"
	)


## D1's inert pin. At rate 0 the board is never scanned and the floor is the whole
## answer, so a zeroed profile plans the same build as the shipped one on a board
## where a live rate demonstrably changes it.
func test_the_dial_at_zero_plans_exactly_like_the_shipped_profile() -> void:
	var shipped := AIProfile.load_default()
	assert_eq(shipped.capture_units_per_property, 0.0, "the dial ships inert")
	for funds in [1000, 5000, 16000]:
		assert_eq(
			_build_id(_board(PROPERTY_RICH, funds), _profile(0.0)),
			_build_id(_board(PROPERTY_RICH, funds), shipped),
			"zeroed and shipped should agree at %d funds" % funds
		)
