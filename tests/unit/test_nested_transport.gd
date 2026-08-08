extends GutTest
## The sim carries cargo one level deep. A loaded transport that itself boards a
## larger one would freeze its own cargo at the boarding cell and, on sinking,
## erase capture progress at that stale cell — so a loaded carrier is refused, and
## remove_unit never lets a passenger's stale cell wipe a live capture.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()


func test_load_refuses_a_transport_that_is_itself_carrying_cargo() -> void:
	# An APC with infantry aboard tries to drive onto a lander at the shoal.
	var state := Fixture.state("[terrain]\n._\nSS\n[units]\n1 p 0 0\n1 l 1 0")
	var apc := state.units[0]
	var passenger := Unit.create(unit_db.by_id(&"infantry"), 1, apc.cell)
	passenger.carrier = apc
	state.units.append(passenger)
	var command := LoadCommand.new(apc, Fixture.path([Vector2i(0, 0), Vector2i(1, 0)]))
	assert_eq(command.validate(state), "unit is carrying cargo")


func test_sinking_a_transport_spares_a_stale_passengers_capture_cell() -> void:
	# A passenger's stored cell freezes at the port it boarded on. If a live enemy
	# capture later runs there, sinking the transport must not wipe it: a passenger
	# holds no capture of its own.
	var state := Fixture.state("[terrain]\n...\n[units]\n1 p 0 0\n2 i 2 0")
	var apc := state.units[0]
	var stale_cell := Vector2i(2, 0)
	var passenger := Unit.create(unit_db.by_id(&"infantry"), 1, stale_cell)
	passenger.carrier = apc
	state.units.append(passenger)
	state.capture_progress[stale_cell] = 7
	state.remove_unit(apc)
	assert_true(
		state.capture_progress.has(stale_cell),
		"a drowned passenger must not erase an unrelated capture at its stale cell"
	)
	assert_eq(state.capture_progress[stale_cell], 7)
