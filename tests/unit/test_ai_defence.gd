extends GutTest
## AJ1 · the planner can see what an enemy is *achieving*, not only what it is.
##
## Every test is the same board reached twice — once with `defend_weight` at 0
## and once with it live — because the claim is a change of mind, not a score.
## The zero runs double as the inertness pin the plan's D1 owes: at 0 the code
## added here never runs and the command is the one the pre-AJ1 planner picked.
##
## Profiles are built here rather than loaded from data/ai/, because what these
## pin is the behaviour of the capability at a chosen weight. What a shipped tier
## sets it to is a balance decision, and retuning one must never break this suite.

## Our HQ at (0,0) with an enemy infantry standing on it, our tank one tile away,
## and a fatter target — an enemy tank — the same distance in the other
## direction. Blind, the tank takes the fatter target every time.
const HQ_BOARD := "[terrain]\nQ....\n.....\n[owners]\n1 0 0\n[units]\n1 t 1 1\n2 i 0 0\n2 t 2 1"

## Our besieged HQ 15 tiles west, a closer enemy 10 tiles east, and our tank in
## between with neither in reach — so the turn is an advance and the only
## question is which way it faces.
const FAR_SIEGE_BOARD := (
	"[terrain]\n"
	+ "Q.............................\n"
	+ "..............................\n"
	+ "[owners]\n1 0 0\n"
	+ "[units]\n1 t 15 1\n2 i 0 0\n2 i 25 1"
)

var unit_db: UnitDB


func before_each() -> void:
	unit_db = Fixture.unit_db()


func _state(map_text: String, hq_points_left: int = GameState.CAPTURE_POINTS) -> GameState:
	var state := Fixture.state(map_text)
	if hq_points_left < GameState.CAPTURE_POINTS:
		state.capture_progress[Vector2i(0, 0)] = hq_points_left
	return state


func _profile(defend_weight: float) -> AIProfile:
	var profile := AIProfile.new()  # Normal's shipped numbers; only defend_weight varies
	profile.defend_weight = defend_weight
	return profile


func _plan(map_text: String, defend_weight: float, hq_points_left: int) -> Command:
	var state := _state(map_text, hq_points_left)
	return AIController.new(unit_db, _profile(defend_weight)).plan_next_command(state)


func _destination(command: Command) -> Vector2i:
	var path: Array[Vector2i] = []
	if command is MoveCommand:
		path = (command as MoveCommand).path
	elif command is AttackCommand:
		path = (command as AttackCommand).path
	assert_false(path.is_empty(), "expected a command carrying a path, got %s" % command)
	return path[path.size() - 1]


# --- The attack path ----------------------------------------------------------


## The flagship case, and the one the bug report described: an infantry two
## thirds of the way through taking our headquarters, while the planner shoots
## at something more expensive somewhere else.
func test_defend_weight_turns_the_guns_on_the_unit_taking_our_hq() -> void:
	var blind := _plan(HQ_BOARD, 0.0, 5)
	assert_true(blind is AttackCommand, "expected an attack, got %s" % blind)
	assert_eq(
		(blind as AttackCommand).target_cell,
		Vector2i(2, 1),
		"blind, the planner prices the enemy tank higher and lets the HQ go"
	)

	var wary := _plan(HQ_BOARD, 1.0, 5)
	assert_true(wary is AttackCommand, "expected an attack, got %s" % wary)
	assert_eq(
		(wary as AttackCommand).target_cell,
		Vector2i(0, 0),
		"with the capture priced from our side, the capturer outbids the fatter target"
	)


## The bonus is worth more the closer the capture is to finishing, which is the
## capture list's own progress term read backwards. An enemy that has only just
## stepped on must be worth less than one about to finish.
##
## 0.6 is a measured value, not a taste: on this board the enemy tank is worth
## enough that an untouched HQ needs ~0.7 to outbid it and an almost-taken one
## needs ~0.5, so 0.6 sits between the two crossovers and nothing else does.
func test_the_defence_bonus_grows_as_the_capture_finishes() -> void:
	var untouched := _plan(HQ_BOARD, 0.6, GameState.CAPTURE_POINTS)
	assert_true(untouched is AttackCommand, "expected an attack, got %s" % untouched)
	assert_eq(
		(untouched as AttackCommand).target_cell,
		Vector2i(2, 1),
		"a capture that has not started yet does not outbid the fatter target at this weight"
	)

	var nearly_done := _plan(HQ_BOARD, 0.6, 1)
	assert_true(nearly_done is AttackCommand, "expected an attack, got %s" % nearly_done)
	assert_eq(
		(nearly_done as AttackCommand).target_cell,
		Vector2i(0, 0),
		"the same weight, with the HQ nearly gone, does"
	)


## A tank parked on our HQ takes nothing from us — it cannot capture. The danger
## it poses is the threat map's job, and paying for it here as well would be the
## double count R3 exists to prevent.
func test_a_unit_that_cannot_capture_earns_no_defence_bonus() -> void:
	var board := "[terrain]\nQ....\n.....\n[owners]\n1 0 0\n[units]\n1 t 1 1\n2 t 0 0\n2 i 2 1"
	var blind := _plan(board, 0.0, GameState.CAPTURE_POINTS)
	var wary := _plan(board, 1.0, GameState.CAPTURE_POINTS)
	assert_true(blind is AttackCommand and wary is AttackCommand, "expected two attacks")
	assert_eq(
		(wary as AttackCommand).target_cell,
		(blind as AttackCommand).target_cell,
		"an occupier that cannot capture must not move the planner's mind"
	)


## Neutral ground is nobody's to lose. Asked through GameState.allied, so a
## property we have not taken yet earns nothing however far along the enemy is.
func test_neutral_ground_earns_no_defence_bonus() -> void:
	var board := "[terrain]\nC....\n.....\n[owners]\n[units]\n1 t 1 1\n2 i 0 0\n2 t 2 1"
	var blind := _plan(board, 0.0, GameState.CAPTURE_POINTS)
	var wary := _plan(board, 1.0, GameState.CAPTURE_POINTS)
	assert_true(blind is AttackCommand and wary is AttackCommand, "expected two attacks")
	assert_eq(
		(wary as AttackCommand).target_cell,
		(blind as AttackCommand).target_cell,
		"a neutral city is not ours to defend"
	)


## An HQ is worth a multiple of a city, so the same capture on a city must not
## buy the same swing. Same board, same progress, HQ terrain swapped for a city:
## at 1.0 the HQ turns the guns and the city, needing ~1.5 here, does not.
func test_a_city_is_defended_less_hard_than_the_home_hq() -> void:
	var city := "[terrain]\nC....\n.....\n[owners]\n1 0 0\n[units]\n1 t 1 1\n2 i 0 0\n2 t 2 1"
	var on_a_city := _plan(city, 1.0, 1)
	assert_true(on_a_city is AttackCommand, "expected an attack, got %s" % on_a_city)
	assert_eq(
		(on_a_city as AttackCommand).target_cell,
		Vector2i(2, 1),
		"at a weight the HQ swings, a city must not"
	)

	var on_the_hq := _plan(HQ_BOARD, 1.0, 1)
	assert_eq(
		(on_the_hq as AttackCommand).target_cell,
		Vector2i(0, 0),
		"the same weight and the same progress, on the seat of the army"
	)


## A factory is defended at a city's price on purpose: the production multiplier
## is the capture list's alone, and `_property_score` is told so. Same board,
## weight and progress as the city case above, with that multiplier live — were
## the denial bonus to take it, the doubled price would swing the guns the way
## the HQ's own multiplier does at a far lower weight.
func test_a_factory_is_defended_at_a_citys_price() -> void:
	var board := "[terrain]\nB....\n.....\n[owners]\n1 0 0\n[units]\n1 t 1 1\n2 i 0 0\n2 t 2 1"
	var profile := _profile(1.0)
	profile.production_capture_multiplier = 2.0
	var command := AIController.new(unit_db, profile).plan_next_command(_state(board, 1))
	assert_true(command is AttackCommand, "expected an attack, got %s" % command)
	assert_eq(
		(command as AttackCommand).target_cell,
		Vector2i(2, 1),
		"what the enemy takes is the ground, so a factory is worth a city here"
	)


# --- The advance path ---------------------------------------------------------


## When nobody can reach the siege this turn, somebody starts walking. Only the
## home HQ does this (R2): a city is a setback, an HQ is the match.
func test_a_besieged_home_hq_turns_the_advance_around() -> void:
	var blind := _plan(FAR_SIEGE_BOARD, 0.0, 5)
	assert_true(blind is MoveCommand, "expected an advance, got %s" % blind)
	assert_eq(_destination(blind).x, 21, "blind, the tank walks east at the nearer enemy")

	# West of the start, not an exact cell: the HQ is a corner, so two cells a
	# tank's move away tie on distance to it and the tie breaks by scan order.
	# The claim is the turn, not the tile.
	var wary := _plan(FAR_SIEGE_BOARD, 1.0, 5)
	assert_true(wary is MoveCommand, "expected an advance, got %s" % wary)
	assert_lt(_destination(wary).x, 15, "with the HQ under siege it turns around and heads home")


## An indirect unit answering the siege has to stop where it can shoot. The HQ
## cell is a goal to bring under fire, never one to reach: walked onto or up
## against, an artillery (min_range 2) sits in its own dead zone and can never
## fire from there, so the diversion would strand it beside the capturer.
func test_a_besieged_home_hq_is_a_standoff_goal_for_an_indirect_unit() -> void:
	var board := (
		"[terrain]\n"
		+ "Q...........\n"
		+ "............\n"
		+ "[owners]\n1 0 0\n"
		+ "[units]\n1 g 5 1\n2 i 0 0\n2 i 9 1"
	)
	var blind := _plan(board, 0.0, 5)
	assert_true(blind is MoveCommand, "expected an advance, got %s" % blind)
	assert_gt(_destination(blind).x, 5, "blind, the artillery closes on the nearer enemy east")

	var wary := _plan(board, 1.0, 5)
	assert_true(wary is MoveCommand, "expected an advance, got %s" % wary)
	var dest := _destination(wary)
	var dist := absi(dest.x) + absi(dest.y)
	assert_between(
		dist, 2, 3, "the artillery has to stop inside its firing ring, not on the HQ it defends"
	)


## The same board with the siege on a city instead. The advance must not turn:
## an ordinary property is defended by whoever already had a shot, never by
## emptying the front.
func test_a_besieged_city_does_not_turn_the_advance_around() -> void:
	var city_board := FAR_SIEGE_BOARD.replace("[terrain]\nQ", "[terrain]\nC")
	var blind := _plan(city_board, 0.0, 5)
	var wary := _plan(city_board, 1.0, 5)
	assert_true(blind is MoveCommand and wary is MoveCommand, "expected two advances")
	assert_eq(
		_destination(wary),
		_destination(blind),
		"a city under capture must not pull the army off the front"
	)
