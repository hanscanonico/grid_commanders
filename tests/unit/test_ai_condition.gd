extends GutTest
## AR6b · a unit is worth what is left of it.
##
## Every valuation in the planner read `type.cost` and nothing else, so a 10-HP
## md tank was priced as sixteen thousand funds — as a target worth killing and
## as an asset worth keeping alike. `condition_weight` interpolates that price
## toward what is left of the unit; at 0 it is the shipped planner exactly.
##
## Every test is one board reached twice, with the dial off and on. The off runs
## are the inertness pin the Judgement contract owes: they are what makes "0
## skips the code" a fact about the board rather than about a guard clause.

## Our artillery between two targets it can reach and neither can answer: a
## 16 000-funds md tank at the west end and a 1 000-funds infantry at the east.
## Indirect fire is never countered, so nothing but the two valuations is on the
## ballot.
const TWO_TARGETS := "[terrain]\n.....\n[units]\n1 g 2 0\n2 T 0 0\n2 i 4 0"

## The withdrawal plan's own board: our md tank beside an enemy infantry it can
## shoot, inside the ring of a bomber that would take everything it has left.
## Running costs the tank's price, and shooting is worth the infantry's.
const LETHAL := (
	"[terrain]\n"
	+ "................\n"
	+ "................\n"
	+ "[units]\n1 T 7 1\n2 i 7 0\n2 b 15 1"
)

## An enemy infantry in a pocket between two mountains, so the cell our md tank
## already stands on is the only cell it can fire from, and a bomber eight tiles
## east whose ring covers exactly that cell. What standing there risks is priced
## in what the tank is worth, and there is no second firing cell to dodge to.
const NOWHERE_ELSE_TO_SHOOT_FROM := (
	"[terrain]\n"
	+ "......M.M.......\n"
	+ "................\n"
	+ "[units]\n1 T 7 1\n2 i 7 0\n2 b 15 1"
)

## Our infantry at 20 HP beside an enemy mech, which would answer any shot with
## more than the infantry has left. The counter is the only cost on this board:
## nothing is threatened here but the shot itself.
const A_COUNTER_THAT_KILLS_US := "[terrain]\n...\n[units]\n1 i 0 0\n2 m 1 0"

## The wounded md tank with nothing else on the ballot, so what the planner does
## is decided entirely by what that one target is priced at. A price below zero
## turns the kill into something to avoid.
const ONE_WOUNDED_TARGET := "[terrain]\n.....\n[units]\n1 g 2 0\n2 T 0 0"

const OUR_INFANTRY := Vector2i(0, 0)
const WOUNDED_TANK := Vector2i(0, 0)
const HEALTHY_INFANTRY := Vector2i(4, 0)
const OUR_TANK := Vector2i(7, 1)

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()


## Normal's shipped numbers with one or two dials moved, built here rather than
## loaded: which value a tier ships is a balance fact and must never be a test
## failure.
func _profile(condition_weight: float, withdraw_weight := 0.0, threat_aversion := 0.0) -> AIProfile:
	var profile := AIProfile.new()
	profile.condition_weight = condition_weight
	profile.withdraw_weight = withdraw_weight
	profile.threat_aversion = threat_aversion
	return profile


## The command planned on `map_text`, with `wounds` (cell -> hp) applied first.
func _plan(map_text: String, profile: AIProfile, wounds: Dictionary = {}) -> Command:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	for unit in state.units:
		if wounds.has(unit.cell):
			unit.hp = wounds[unit.cell]
	return AIController.new(unit_db, profile).plan_next_command(state)


func _target(command: Command) -> Vector2i:
	if not (command is AttackCommand):
		fail_test("expected an attack, got %s" % command)
		return Vector2i(-1, -1)
	return (command as AttackCommand).target_cell


## The ticket's own case, from the target's side: a 10-HP md tank is a tenth of
## an md tank, and the planner shot at it as though it were all of one.
func test_a_nearly_dead_target_stops_outbidding_a_healthy_cheap_one() -> void:
	var wounds := {WOUNDED_TANK: 10}
	assert_eq(
		_target(_plan(TWO_TARGETS, _profile(0.0), wounds)),
		WOUNDED_TANK,
		"blind, sixteen thousand funds of md tank outbids the infantry whatever is left of it"
	)
	assert_eq(
		_target(_plan(TWO_TARGETS, _profile(1.0), wounds)),
		HEALTHY_INFANTRY,
		"priced by what is left, the kill is worth 1 600 and the whole infantry is worth more"
	)


## An interpolation and not a switch: half weight is half the correction, and on
## this board that still leaves the wounded md tank the better target.
func test_the_dial_interpolates_rather_than_switching() -> void:
	assert_eq(
		_target(_plan(TWO_TARGETS, _profile(0.5), {WOUNDED_TANK: 10})),
		WOUNDED_TANK,
		"at half weight the md tank is priced at 8 800 and still outbids the infantry"
	)


## It prices condition and never cost: a unit nobody has shot is worth its price
## at every setting, so the dial can never quietly re-rank a healthy roster.
func test_a_healthy_board_is_priced_identically_at_every_weight() -> void:
	var blind := _target(_plan(TWO_TARGETS, _profile(0.0)))
	assert_eq(blind, WOUNDED_TANK, "unhurt, the md tank is the target worth shooting")
	for weight in [0.5, 1.0]:
		assert_eq(
			_target(_plan(TWO_TARGETS, _profile(weight))),
			blind,
			"at weight %s an undamaged board must plan exactly as the blind planner does" % weight
		)


## The same dial from the asset side, on the board AJ2 pinned withdrawal with: a
## 30-HP md tank buys 30% of an md tank by running, not all of one, so the shot
## it was refusing is worth taking. One dial moves both readings on purpose —
## they are the same valuation seen from either end.
func test_a_wounded_unit_stops_overpaying_to_save_itself() -> void:
	var wounds := {OUR_TANK: 30}
	assert_true(
		_plan(LETHAL, _profile(0.0, 0.1), wounds) is MoveCommand,
		"blind, saving sixteen thousand funds outbids a shot worth a few hundred"
	)
	assert_eq(
		_target(_plan(LETHAL, _profile(1.0, 0.1), wounds)),
		Vector2i(7, 0),
		"priced by what is left, the escape is worth less than the shot and it takes the shot"
	)


## The third reading of our own price, and the one two shipped tiers carry: what
## a destination risks is the threat map's damage times what the unit standing
## there is worth. Blind, a 30-HP md tank prices the bomber's ring at the full
## sixteen thousand and refuses the only shot it has; priced by what is left, the
## same ring costs 4 800 and the shot is worth taking.
func test_a_wounded_unit_prices_the_ring_it_stands_in_by_what_is_left_of_it() -> void:
	var wounds := {OUR_TANK: 30}
	assert_true(
		_plan(NOWHERE_ELSE_TO_SHOOT_FROM, _profile(0.0, 0.0, 0.1), wounds) is MoveCommand,
		"blind, the ring is priced at a whole md tank and outweighs the shot"
	)
	assert_eq(
		_target(_plan(NOWHERE_ELSE_TO_SHOOT_FROM, _profile(1.0, 0.0, 0.1), wounds)),
		Vector2i(7, 0),
		"priced by what is left, the same ring costs less than the shot is worth"
	)


## The fourth reading, and the one inside the shot itself: what the counter costs
## is our own price times the HP it takes. A 20-HP infantry priced at a whole
## thousand refuses a trade worth 240 funds; priced at 200 it takes it. The
## doubling for a lethal counter is what makes this the sharpest of the four —
## it is exactly where the old valuation was most wrong.
func test_a_wounded_unit_prices_the_counter_by_what_is_left_of_it() -> void:
	var wounds := {OUR_INFANTRY: 20}
	assert_true(
		_plan(A_COUNTER_THAT_KILLS_US, _profile(0.0), wounds) is MoveCommand,
		"blind, dying costs a whole infantry and the shot is not worth it"
	)
	assert_eq(
		_target(_plan(A_COUNTER_THAT_KILLS_US, _profile(1.0), wounds)),
		Vector2i(1, 0),
		"priced by what is left, the trade is worth taking"
	)


## The dial is defined on 0 to 1 and the arena searches exactly these exports, so
## a candidate sampled wider must get a strong planner rather than an inverted
## one: past 1.0 the interpolation extrapolates and prices a wounded unit below
## nothing, and every reader of that price — the shot, the counter, the ring, the
## withdrawal — changes sign with it, leaving a planner that pays to leave a
## target alive and to stand in fire. Out of range reads as the strongest defined
## setting instead.
func test_a_weight_past_the_range_never_prices_a_unit_below_nothing() -> void:
	var wounds := {WOUNDED_TANK: 10}
	assert_eq(
		_target(_plan(ONE_WOUNDED_TARGET, _profile(1.0), wounds)),
		WOUNDED_TANK,
		"a tenth of an md tank is worth 1 600 and is still the shot worth taking"
	)
	for weight in [1.5, 2.0, 10.0]:
		assert_eq(
			_target(_plan(ONE_WOUNDED_TARGET, _profile(weight), wounds)),
			WOUNDED_TANK,
			"at weight %s the kill must still be worth something, not owed something" % weight
		)
