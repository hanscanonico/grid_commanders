extends GutTest
## AI armies playing out every grouping — on the fixture (COM-45, four-players
## plan FP2) and on the shipped boards that seat more than a duel (COM-49, FP6).
##
## The unit tests beside this one ask the authority a question at a time. This
## one asks the whole engine at once, because the rule it guards lives in two
## places at every routed site: `MovementResolver` decides where a unit may go and
## `MoveCommand.validate` decides whether it may — and an alliance that reached
## only one of them produces a planner proposing moves the rules turn down. That
## split is exactly what an AI-vs-AI soak catches and a unit test cannot: the same
## lesson `test_commander_match_soak.gd` was written for.
##
## The first case runs every grouping on `maps/fixtures/quartet.txt`, whose four
## armies are what makes a 2v2 and a 3v1 expressible at all; the second replays
## them on `maps/compass.txt`, `maps/foursquare.txt`, `maps/heartland.txt`,
## `maps/pinwheel.txt`, `maps/trident.txt`, `maps/marchlands.txt` and
## `maps/atoll.txt`, because a
## grouping that only ever ran on a fixture is a capability no player can pick.
## The menu's seat strip writes the same `sides`, but the groupings are set
## directly here so the soak never has to walk a menu to reach one.
##
## Pinwheel is also played with seats left open (COM-129): its whole claim is that
## the corners are one quarter turn apart, so the duel it promises is an
## opposite-seat pair — and a duel is a *seating*, not a grouping. The seat strip
## writes the same `seats`, and the closed corners' HQs sit there unowned, which is
## the shape the open-seats plan's R3 warns about.
##
## Marchlands is the one board that exists *for* a grouping: its ridge puts seats
## 1 and 2 north of it and 3 and 4 south, so `1+2v3+4` is a shared front rather
## than two armies that happen not to shoot each other. That makes it the one
## board where an alliance bug would show up as terrain — a pair advancing into
## the lane its ally holds — so it is soaked in its own pairing first.
##
## Each army is seated with a doctrine, and with a meter full enough to weigh
## firing it, on purpose. Without one every commander hook stays at its neutral
## default, so a grouping only ever reaches the commands — and the reads a
## doctrine makes about the other side of the board ("can anyone reach me", "is
## there ground I can take") are exactly where an alliance is easiest to get
## wrong. Each grouping asserts a power actually fired, so the hooks cannot go
## quietly unexercised again.

const FIXTURE := "res://maps/fixtures/quartet.txt"
## The shipped boards that seat more than a duel: four armies, then three.
const COMPASS := "res://maps/compass.txt"
const FOURSQUARE := "res://maps/foursquare.txt"
const HEARTLAND := "res://maps/heartland.txt"
const PINWHEEL := "res://maps/pinwheel.txt"
const TRIDENT := "res://maps/trident.txt"
## The grand tier's two water boards: the only shipped boards where four armies
## share one sea, so they are the only place an allied pair can put a fleet
## between a rival and its own coast.
const CAUSEWAY := "res://maps/causeway.txt"
const CONFLUENCE := "res://maps/confluence.txt"
## The 2v2 board — four armies, paired across the ridge rather than diagonally.
const MARCHLANDS := "res://maps/marchlands.txt"
const WINDROSE := "res://maps/windrose.txt"
## The four-army naval board, and the reason it is soaked rather than left to the
## map lints: every other board in this file is dry, so a grouping that reached
## the land planner and not the sea one would go unnoticed. Here the armies share
## sight across water, target across it, and buy from a dock as well as a base.
const ATOLL := "res://maps/atoll.txt"
## One doctrine per seat, in seat order, so a run is reproducible. Chosen for the
## hooks this milestone touched rather than for balance: Tomas Reed and Nia Rowan
## weigh their powers on takeable ground, Mara Voss and Orin Flux on whether a
## rival can reach them — and Orin's jamming reaches across the table.
const DOCTRINES: Array[StringName] = [&"tomas_reed", &"mara_voss", &"orin_flux", &"nia_rowan"]
## Long enough for four armies to bank income, build and meet, without making the
## suite pay for a full match per grouping.
const DAYS := 10
## A stall shows up as a planner that keeps proposing without the day ever
## ending, so this only has to sit above "a real match" — a deadlock detector.
const COMMAND_CAP := 900

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


## Free-for-all, 2v2 each way round, and a 3v1 — the three groupings the plan
## ships, plus the one that has to stay identical to how the board played before
## groupings existed.
func test_the_ai_plays_every_grouping_without_the_rules_refusing_it() -> void:
	_soak("free-for-all", {}, 610)
	_soak("2v2 alternating", {1: 0, 3: 0, 2: 1, 4: 1}, 611)
	_soak("2v2 in blocks", {1: 0, 2: 0, 3: 1, 4: 1}, 612)
	_soak("3v1", {1: 0, 2: 0, 3: 0}, 613)


## The same proof on the boards a player actually reaches. A grouping that only
## ever ran on a fixture is a capability nobody can use (COM-49): these are the
## shipped four- and three-army boards, played in the groupings their seat strips
## offer.
func test_the_ai_plays_the_shipped_multi_army_boards_in_their_groupings() -> void:
	_soak("compass free-for-all", {}, 620, COMPASS)
	_soak("compass 2v2", {1: 0, 3: 0, 2: 1, 4: 1}, 621, COMPASS)
	_soak("compass 3v1", {1: 0, 2: 0, 3: 0, 4: 1}, 622, COMPASS)
	_soak("foursquare ffa", {}, 625, FOURSQUARE)
	_soak("foursquare 2v2", {1: 0, 3: 0, 2: 1, 4: 1}, 626, FOURSQUARE)
	_soak("foursquare 3v1", {1: 0, 2: 0, 3: 0, 4: 1}, 627, FOURSQUARE)
	_soak("heartland ffa", {}, 640, HEARTLAND)
	_soak("heartland 2v2", {1: 0, 3: 0, 2: 1, 4: 1}, 641, HEARTLAND)
	_soak("heartland 3v1", {1: 0, 2: 0, 3: 0, 4: 1}, 642, HEARTLAND)
	_soak("trident free-for-all", {}, 623, TRIDENT)
	_soak("trident 2v1", {1: 0, 2: 0, 3: 1}, 624, TRIDENT)
	# The pairing Marchlands is laid out for goes first: north of the ridge against
	# south, which is also the one grouping on any shipped board where allies start
	# side by side rather than opposite each other.
	_soak("marchlands 2v2", {1: 0, 2: 0, 3: 1, 4: 1}, 625, MARCHLANDS)
	_soak("marchlands free-for-all", {}, 626, MARCHLANDS)
	_soak("marchlands 3v1", {1: 0, 2: 0, 3: 0, 4: 1}, 627, MARCHLANDS)
	# Windrose is the first board where an alliance owns airfields, so it is the
	# first where a shared side can put something over the ridge that the ground
	# war is channelled by — and where an ally's airfield is a pad the other side
	# of a mountain wall.
	_soak("windrose free-for-all", {}, 625, WINDROSE)
	_soak("windrose 2v2", {1: 0, 3: 0, 2: 1, 4: 1}, 626, WINDROSE)
	_soak("windrose 3v1", {1: 0, 2: 0, 3: 0, 4: 1}, 627, WINDROSE)
	_soak("atoll free-for-all", {}, 636, ATOLL)
	_soak("atoll 2v2", {1: 0, 3: 0, 2: 1, 4: 1}, 637, ATOLL)
	_soak("atoll 3v1", {1: 0, 2: 0, 3: 0, 4: 1}, 638, ATOLL)
	# The grand tier's water boards. Both put four fleets on one sea, so an ally's
	# coast is reachable by a rival's hull without a ferry the planner cannot plan
	# — which is the arrangement naval R1 makes every four-army water board prove.
	_soak("causeway free-for-all", {}, 650, CAUSEWAY)
	_soak("causeway 2v2", {1: 0, 3: 0, 2: 1, 4: 1}, 651, CAUSEWAY)
	_soak("causeway 3v1", {1: 0, 2: 0, 3: 0, 4: 1}, 652, CAUSEWAY)
	_soak("confluence free-for-all", {}, 655, CONFLUENCE)
	_soak("confluence 2v2", {1: 0, 3: 0, 2: 1, 4: 1}, 656, CONFLUENCE)
	_soak("confluence 3v1", {1: 0, 2: 0, 3: 0, 4: 1}, 657, CONFLUENCE)


## Pinwheel, over the seatings its own layout promises: the four-army groupings,
## both opposite-seat duels — the pair the quarter turn makes fair — and a
## three-way with one corner left open.
func test_the_ai_plays_pinwheel_at_every_seating_its_corners_offer() -> void:
	_soak("pinwheel free-for-all", {}, 630, PINWHEEL)
	_soak("pinwheel 2v2", {1: 0, 3: 0, 2: 1, 4: 1}, 631, PINWHEEL)
	_soak("pinwheel 3v1", {1: 0, 2: 0, 3: 0, 4: 1}, 632, PINWHEEL)
	_soak("pinwheel duel 1v3", {}, 633, PINWHEEL, [1, 3] as Array[int])
	_soak("pinwheel duel 2v4", {}, 634, PINWHEEL, [2, 4] as Array[int])
	_soak("pinwheel three-way", {}, 635, PINWHEEL, [1, 2, 3] as Array[int])


## Plays the board out with `sides` applied and a planner per army. Fails on the
## first command the rules turn down — which is the whole point — and on a run
## that never ends.
func _soak(
	label: String, sides: Dictionary, rng_seed: int, board: String = FIXTURE, seats: Array[int] = []
) -> void:
	var map := MapData.load_from_file(board, terrain_db)
	assert_not_null(map, "%s should parse" % board)
	if map == null:
		return
	var state := GameState.create(map, unit_db, chart, {}, seats)
	assert_not_null(state, "%s should seat %s" % [board, seats])
	if state == null:
		return
	state.sides = sides
	state.rng.seed = rng_seed
	# Seated with a full meter, so the doctrine reads are asked from day one under
	# every grouping instead of waiting on charge a short fixture match may never
	# bank. Firing is still the doctrine's own call, which is what is being tested.
	for i in state.teams.size():
		var team: int = state.teams[i]
		state.set_commander(team, commander_db.by_id(DOCTRINES[i % DOCTRINES.size()]))
		var co_state := state.commander_state(team)
		co_state.charge = co_state.type.power_cost
	state.fog_enabled = rng_seed % 2 == 1  # so the shared-sight path is walked too
	# One controller per army: a controller caches a threat map for the turn it is
	# planning, and two armies sharing one would read each other's.
	var planners: Dictionary = {}
	for team in state.teams:
		planners[team] = AIController.new(unit_db)
	var commands := 0
	var powers := 0
	while state.winner == 0 and state.day <= DAYS and commands < COMMAND_CAP:
		var ai: AIController = planners[state.current_team]
		var command := ai.plan_next_command(state)
		var error := command.validate(state)
		if error != "":
			fail_test(
				(
					"%s (day %d, team %d): the planner proposed a command the rules reject: %s."
					% [label, state.day, state.current_team, error]
				)
			)
			return
		command.apply(state)
		commands += 1
		if command is PowerCommand:
			powers += 1
	gut.p("%-16s %4d commands, %d powers, day %d" % [label, commands, powers, state.day])
	assert_lt(commands, COMMAND_CAP, "%s: the match never progressed" % label)
	assert_gt(powers, 0, "%s: no power fired, so no doctrine read the board" % label)
	_assert_no_friendly_fire(label, state, sides)


## Nobody on a side ever took ground off it. Asked of the board rather than of the
## command stream, because a capture the rules allowed but should not have leaves
## its evidence in the ownership map and nowhere else.
func _assert_no_friendly_fire(label: String, state: GameState, sides: Dictionary) -> void:
	for cell: Vector2i in state.property_owners:
		var owner_team: int = state.property_owners[cell]
		if owner_team == MapData.NEUTRAL:
			continue
		var started_as := int(state.map.initial_owners().get(cell, MapData.NEUTRAL))
		if started_as == MapData.NEUTRAL or started_as == owner_team:
			continue
		assert_false(
			state.allied(started_as, owner_team),
			(
				"%s: %s passed from team %d to team %d, which stands with it — sides %s"
				% [label, cell, started_as, owner_team, sides]
			)
		)
