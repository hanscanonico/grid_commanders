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

## Two corridors and a repairing city of our own at the bottom of the trunk. The
## infantry at (0, 6) is closest to the middle property and the one at (0, 3) is
## next, so blind the second is pushed out to the far corridor — but wound the
## first and the repair clause takes it before it ever reaches a capture goal.
const WOUNDED_AND_HEALTHY := (
	"[terrain]\n"
	+ "...........C\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ "...........C\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ "CSSSSSSSSSSS\n"
	+ "[owners]\n1 0 8\n"
	+ "[units]\n1 i 0 3\n1 i 0 6\n"
)

## The cell the wounded infantry of `WOUNDED_AND_HEALTHY` stands on, and the HP
## that puts it under the shipped retreat line.
const WOUNDED_CELL := Vector2i(0, 6)
const WOUNDED_HP := 30

## The same two corridors, with the wounded infantry standing on the middle
## property rather than walking toward it: whatever its HP says, that unit is
## taking that tile, so the healthy one belongs in the far corridor.
const CAPTURING_AND_WOUNDED := (
	"[terrain]\n"
	+ "...........C\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ "...........C\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ "CSSSSSSSSSSS\n"
	+ "[owners]\n1 0 8\n"
	+ "[units]\n1 i 0 3\n1 i 11 5\n"
)

## The middle property of `CAPTURING_AND_WOUNDED`, wounded infantry and all.
const CAPTURING_CELL := Vector2i(11, 5)

## A city and a base at the far end of two corridors, exactly as far from the one
## infantry in the trunk. Row-major scan order puts the city first, so blind the
## tie goes to it — and pricing what the base builds is the only thing that can
## turn the unit round.
const CITY_AND_BASE_LEVEL := (
	"[terrain]\n"
	+ "...........C\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ "...........B\n"
	+ "[units]\n1 i 0 2\n"
)

## The same pair with the base one tile further out than the city, so nothing but
## the detour dial can reach it.
const BASE_ONE_TILE_FURTHER := (
	"[terrain]\n"
	+ "...........C\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ ".SSSSSSSSSSS\n"
	+ "...........B\n"
	+ "[units]\n1 i 0 2\n"
)

## A city one step away and a base three, both inside one infantry's move. This
## one is the *arrival*: the goal never enters it, because a property in reach is
## captured by `_consider_captures` rather than walked to.
const CITY_NEAR_BASE_FAR := "[terrain]\n.C.B\n[units]\n1 i 0 0\n"

## Enough of a multiplier to be legible in both readings, and enough tiles to buy
## two of them — one more than BASE_ONE_TILE_FURTHER needs, so the fixture proves
## the dial rather than a rounding edge.
const PRODUCTION_WORTH := 1.5
const DETOUR_TILES := 4.0

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()


func _profile(capture_units_per_property: float) -> AIProfile:
	var profile := AIProfile.new()  # every other capability at the shipped default
	profile.capture_units_per_property = capture_units_per_property
	return profile


func _claiming(depth: int) -> AIProfile:
	var profile := AIProfile.new()
	profile.capture_claim_depth = depth
	return profile


## One judgement, both its readings — the arrival multiplier and the tiles of
## detour it buys — so a fixture can never switch on half of it.
func _pricing(multiplier: float, detour_tiles: float) -> AIProfile:
	var profile := AIProfile.new()
	profile.production_capture_multiplier = multiplier
	profile.capture_goal_value_tiles = detour_tiles
	return profile


## The property the AI actually starts taking this turn, or Vector2i(-1, -1) when
## it takes none. The arrival reading, where the goal reading cannot reach.
func _captures(map_text: String, profile: AIProfile) -> Vector2i:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	var command := AIController.new(unit_db, profile).plan_next_command(state)
	if command is CaptureCommand:
		var path := (command as CaptureCommand).path
		return path[path.size() - 1]
	return Vector2i(-1, -1)


## Plays one whole turn for team 1 and returns the row each surviving unit ends
## it on, in scan order. On the corridor boards the row IS the goal: the trunk is
## the only passable column, so closing on a corridor's property means walking the
## trunk toward that corridor.
func _rows_after_a_day(
	map_text: String, profile: AIProfile, wounded: Vector2i = Vector2i(-1, -1)
) -> Array[int]:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	state.rng.seed = 1701  # COM-206: commands are applied for real below
	var hurt := state.unit_at(wounded)
	if hurt != null:
		hurt.hp = WOUNDED_HP
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


## The defect, on the board it costs the most: sixteen neutral properties sitting
## there and the planner opens down its priority list, because the roster it was
## dealt already met the flat target.
func test_a_property_rich_board_makes_the_capture_roster_short_on_day_one() -> void:
	assert_eq(
		_build_id(_board(PROPERTY_RICH, 5000), _profile(0.0)),
		&"apc",
		"blind, the AI opens on its list with sixteen neutral cities on the board"
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
## small board the same non-zero rate never clears the floor, so the AI plans its
## ordinary list and still fields its Md Tank.
func test_a_property_poor_board_still_fields_its_md_tank() -> void:
	assert_eq(
		_build_id(_board(PROPERTY_POOR, 5000), _profile(RATE)),
		&"apc",
		"two neutral cities are not a race; no capturer is urgent here"
	)
	assert_eq(
		_build_id(_board(PROPERTY_POOR, 16000), _profile(RATE)),
		&"md_tank",
		"and it spends the bank on the unit it was saving for"
	)


## The seated rate, read on this board. It ships live since
## docs/causeway_measure.md's V4, but 0.15 over sixteen unowned cities rounds to
## three — exactly the floor — so the shipped profile still plans the blind plan
## here, and the rate only reaches the roster on a board with more left to take
## (Causeway deals thirty-six).
func test_the_seated_rate_is_still_the_floor_on_this_board() -> void:
	var shipped := AIProfile.load_default()
	assert_eq(shipped.capture_units_per_property, 0.15, "the rate seated on Normal")
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


## A claim is only worth making by a unit that will walk it. The infantry closest
## to the middle property is wounded and has a repairing city of its own to go to,
## so the repair clause answers for it long before any capture goal does — and if
## it claimed the middle property anyway, the healthy infantry behind it would be
## pushed out to the far corridor and the nearest property would go unvisited by
## anybody, which is the very defect claiming exists to end.
func test_a_unit_an_errand_has_taken_claims_no_property() -> void:
	assert_eq(
		_rows_after_a_day(WOUNDED_AND_HEALTHY, _claiming(0), WOUNDED_CELL),
		[5, 8] as Array[int],
		"blind, the healthy infantry walks the middle property and the wounded one repairs"
	)
	assert_eq(
		_rows_after_a_day(WOUNDED_AND_HEALTHY, _claiming(1), WOUNDED_CELL),
		[5, 8] as Array[int],
		"claimed, the property nearest the wounded unit is still the healthy one's goal"
	)
	assert_eq(
		_rows_after_a_day(WOUNDED_AND_HEALTHY, _claiming(1)),
		[0, 5] as Array[int],
		"and unwounded that same unit does claim it, pushing the other to the far corridor"
	)


## The errand exclusion stops at the tile itself. The wounded infantry is standing
## on the middle property and spends its turn capturing it, so the repair clause
## never answers for it and its claim has to hold — otherwise the healthy
## infantry is sent at ground that is about to change hands.
func test_a_wounded_capturer_on_its_property_keeps_the_claim() -> void:
	assert_eq(
		_rows_after_a_day(CAPTURING_AND_WOUNDED, _claiming(0), CAPTURING_CELL),
		[5, 5] as Array[int],
		"blind, the healthy infantry walks the property the wounded one is already taking"
	)
	assert_eq(
		_rows_after_a_day(CAPTURING_AND_WOUNDED, _claiming(1), CAPTURING_CELL),
		[0, 5] as Array[int],
		"claimed, the tile being captured is held and the healthy infantry takes the far corridor"
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


## The arrival reading. A base and a city both inside one infantry's move, the
## base two steps further out: blind it takes the city, because nothing in the
## planner knows one of them builds tanks and the other only pays.
func test_a_property_that_builds_is_worth_more_to_take() -> void:
	assert_eq(
		_captures(CITY_NEAR_BASE_FAR, _pricing(1.0, 0.0)),
		Vector2i(1, 0),
		"blind, a base is priced as a plains city and the nearer tile wins"
	)
	assert_eq(
		_captures(CITY_NEAR_BASE_FAR, _pricing(PRODUCTION_WORTH, 0.0)),
		Vector2i(3, 0),
		"priced, the production line is worth the two extra steps"
	)


## The goal reading, on a tie. The city and the base are exactly as far away and
## the city wins the scan-order tie, so this fixture reverses on the dial alone.
func test_a_property_that_builds_is_worth_walking_to() -> void:
	assert_eq(
		_rows_after_a_day(CITY_AND_BASE_LEVEL, _pricing(1.0, 0.0)),
		[0] as Array[int],
		"blind, the tie goes to the city because it is scanned first"
	)
	assert_eq(
		_rows_after_a_day(CITY_AND_BASE_LEVEL, _pricing(PRODUCTION_WORTH, DETOUR_TILES)),
		[4] as Array[int],
		"priced, the same walk is worth making toward the base instead"
	)


## D4's "one judgement, two readings", checked from the side that could break it:
## the detour has to be the dial that moves a *further* property, and the unit
## that walks there has to still want it when it arrives — or it turns around on
## the doorstep and the two readings are two opinions.
func test_the_detour_dial_is_what_reaches_a_further_property() -> void:
	assert_eq(
		_rows_after_a_day(BASE_ONE_TILE_FURTHER, _pricing(1.0, 0.0)),
		[0] as Array[int],
		"blind, the nearer city wins"
	)
	assert_eq(
		_rows_after_a_day(BASE_ONE_TILE_FURTHER, _pricing(PRODUCTION_WORTH, 0.0)),
		[0] as Array[int],
		"pricing the arrival alone does not move a goal — that is the detour's job"
	)
	assert_eq(
		_rows_after_a_day(BASE_ONE_TILE_FURTHER, _pricing(PRODUCTION_WORTH, DETOUR_TILES)),
		[5] as Array[int],
		"with the detour bought, the base one tile further is the goal"
	)
	assert_eq(
		_captures(CITY_NEAR_BASE_FAR, _pricing(PRODUCTION_WORTH, DETOUR_TILES)),
		Vector2i(3, 0),
		"and the unit that walked there still wants it when it arrives"
	)


## The detour composes with AE2's claim rather than replacing it: the assignment
## prices a property the same way the plain walk does, so a claimed goal cannot
## disagree with an unclaimed one about which ground is worth more.
func test_the_detour_prices_a_claimed_goal_the_same_way() -> void:
	var priced := _pricing(PRODUCTION_WORTH, DETOUR_TILES)
	priced.capture_claim_depth = 1
	assert_eq(
		_rows_after_a_day(BASE_ONE_TILE_FURTHER, priced),
		[5] as Array[int],
		"one capturer, claiming on: it still walks to the property worth more"
	)


## D1's inert pin for AE3. At 1.0 and 0.0 neither reading is built and both are
## the shipped arithmetic, so a zeroed profile plans exactly what the shipped one
## does on the two boards a live pair demonstrably changes.
func test_the_production_dials_at_their_inert_values_plan_like_the_shipped_profile() -> void:
	var shipped := AIProfile.load_default()
	assert_eq(shipped.production_capture_multiplier, 1.0, "the multiplier ships inert")
	assert_eq(shipped.capture_goal_value_tiles, 0.0, "the detour ships inert")
	assert_eq(
		_captures(CITY_NEAR_BASE_FAR, _pricing(1.0, 0.0)),
		_captures(CITY_NEAR_BASE_FAR, shipped),
		"zeroed and shipped should take the same property"
	)
	for board in [CITY_AND_BASE_LEVEL, BASE_ONE_TILE_FURTHER]:
		assert_eq(
			_rows_after_a_day(board, _pricing(1.0, 0.0)),
			_rows_after_a_day(board, shipped),
			"zeroed and shipped should walk the same board the same way"
		)


## Which of the three banking dials each tier seats. Only the spend ceiling has
## been measured (docs/causeway_measure.md's V4, on Causeway's 2v2), so only it is
## live, and only on the three tiers that carry V4 — Easy keeps the whole block
## inert. What the ceiling does to the cadence is
## tests/unit/test_ai_production_cadence.gd's.
func test_only_the_measured_banking_dial_is_seated() -> void:
	for tier in ["default", "easy", "hard", "brutal"]:
		var profile: AIProfile = load("res://data/ai/%s.tres" % tier)
		var ceiling: float = 0.0 if tier == "easy" else 3.0
		assert_eq(profile.spend_ceiling_turns, ceiling, "%s: the spend ceiling" % tier)
		assert_eq(
			profile.bank_scope, AIProfile.BANK_SCOPE_BOARD, "%s: one answer for the board" % tier
		)
		assert_eq(profile.bank_rank_margin, 0, "%s: one place is still worth banking for" % tier)
