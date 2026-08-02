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
## AE2 is the capture goal. Every capture unit walked to its own nearest
## property with nothing marking one as already somebody's, so units standing
## near each other picked the same tile and travelled it together — and on a
## board dense in properties there is always a nearer tile than the far corner,
## so the far corner was never anyone's goal at any point in the match.
##
## The AE1 tests isolate production the way test_ai_production.gd does — every
## unit has already acted, so the only command left to plan is the build. The AE2
## tests do the opposite and play whole turns, because a goal is only observable
## in where the unit walks.

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

## The rate every AE1 fixture probes with. High enough that the property-rich
## board clears the floor and the property-poor one cannot.
const RATE := 0.25

## Three infantry in a trunk, three properties at the far end of three corridors
## the trunk is the only way into. The sea is what makes the walk legible: on open
## ground a unit closing on a diagonal goal has several equally good cells and
## picks between them by scan order, so the row it ends the day on says nothing.
## Here reducing the distance to a corridor's property means walking the trunk
## toward that corridor, and the row it stops on IS the goal it chose.
##
## All three are nearest to the middle property, so blind they converge on it.
const THREE_CORRIDORS := (
	"[terrain]\n"
	+ "...........C\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ "...........C\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ "...........C\n"
	+ "[units]\n1 i 0 4\n1 i 0 5\n1 i 0 6\n"
)

## The same three corridors with two infantry placed at exactly equal distance
## from the middle property, so nothing but scan order can settle which of them
## claims it. `HIGH_ROAD` and `LOW_ROAD` are the pair, and reversing them proves
## the tiebreak is scan order rather than a position the sort happens to prefer.
const EQUIDISTANT_BOARD := (
	"[terrain]\n"
	+ "...........C\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ "...........C\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ "...........C\n"
	+ "[units]\n"
)
const HIGH_ROAD := "1 i 0 4\n"
const LOW_ROAD := "1 i 0 6\n"

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


func _claiming(depth: int) -> AIProfile:
	var profile := AIProfile.new()
	profile.capture_claim_depth = depth
	return profile


## Plays one whole turn for team 1 and returns the row each surviving unit ends
## it on, in scan order. On the corridor boards the row IS the goal: the trunk is
## the only passable column, so closing on a corridor's property means walking the
## trunk toward that corridor.
func _rows_after_a_day(map_text: String, profile: AIProfile) -> Array[int]:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	var ai := AIController.new(unit_db, profile)
	for _step in range(12):
		var command := ai.plan_next_command(state)
		if command is EndTurnCommand or command.validate(state) != "":
			break
		command.apply(state)
	var rows: Array[int] = []
	for unit in state.units:
		if unit.team == 1:
			rows.append(unit.cell.y)
	return rows


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


## The defect and the fix in one board. Three infantry stand a row apart with
## three properties out at the end of three corridors, and all three are nearest
## to the middle one — so blind they walk it together and the two outer corridors
## are never anybody's goal at any point in the match.
func test_capture_goals_spread_across_the_board_once_they_are_claimed() -> void:
	assert_eq(
		_rows_after_a_day(THREE_CORRIDORS, _claiming(0)),
		[5, 5, 5] as Array[int],
		"blind, all three infantry converge on the one middle property"
	)

	var spread := _rows_after_a_day(THREE_CORRIDORS, _claiming(1))
	assert_eq(spread.size(), 3, "all three infantry should survive an unopposed day")
	var rows := spread.duplicate()
	rows.sort()
	assert_eq(
		rows,
		[1, 5, 9] as Array[int],
		"claimed, each takes a different corridor: the nearest keeps the middle one"
	)


## Depth is a count of places, not a switch. At 2 a pair may travel to the same
## property, which is what keeps AE2 from being the thinnest possible line — the
## plan's R3, spreading is thinning.
func test_depth_two_lets_a_pair_travel_together() -> void:
	var paired := _rows_after_a_day(THREE_CORRIDORS, _claiming(2))
	var rows := paired.duplicate()
	rows.sort()
	assert_eq(
		rows,
		[5, 5, 9] as Array[int],
		"the two closest keep the middle property and only the third is pushed out"
	)


## R6, the determinism pin. Two infantry exactly equidistant from the middle
## property have to be separated by something, and it is scan order: the same
## board plans the same way every time, and listing the pair the other way round
## hands the middle property to the other unit.
func test_an_exact_tie_is_settled_by_scan_order_and_stays_settled() -> void:
	var high_first := EQUIDISTANT_BOARD + HIGH_ROAD + LOW_ROAD
	var first := _rows_after_a_day(high_first, _claiming(1))
	for _replan in range(4):
		assert_eq(
			_rows_after_a_day(high_first, _claiming(1)),
			first,
			"the same board must plan the same way every time it is asked"
		)
	assert_eq(first, [5, 9] as Array[int], "the unit listed first keeps the tied property")

	var low_first := EQUIDISTANT_BOARD + LOW_ROAD + HIGH_ROAD
	assert_eq(
		_rows_after_a_day(low_first, _claiming(1)),
		[5, 1] as Array[int],
		"listed the other way round, the other unit keeps it — the tiebreak is scan order"
	)


## D1's inert pin for AE2. At depth 0 the claim is not built and the capture
## clause is the shipped nearest-property walk, so a zeroed profile plans exactly
## what the shipped one does on the board a live depth demonstrably changes.
func test_claim_depth_at_zero_walks_exactly_like_the_shipped_profile() -> void:
	var shipped := AIProfile.load_default()
	assert_eq(shipped.capture_claim_depth, 0, "the dial ships inert")
	assert_eq(
		_rows_after_a_day(THREE_CORRIDORS, _claiming(0)),
		_rows_after_a_day(THREE_CORRIDORS, shipped),
		"zeroed and shipped should walk the same board the same way"
	)
