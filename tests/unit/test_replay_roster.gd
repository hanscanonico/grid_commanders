extends GutTest
## Every command class on disk is one `ReplayCodec` knows.
##
## The codec keeps four tables that have to agree — `name_of` (class -> name),
## `REQUIRED_KEYS` (name -> fields), `encode_command` (class -> fields) and
## `command_from` / `_movement_from` (name -> rebuild) — and `name_of` answers ""
## for anything it does not recognise. So a thirteenth command class records as
## `{"c": ""}` and every recording holding one dies on playback complaining about
## an unknown kind, while the sibling suite, which covers the twelve by hand,
## stays green. The load-bearing assertion here is the listing itself: the files
## under `core/commands/` are exactly the names the codec knows.

const COMMAND_DIR := "res://core/commands/"

## Command file basename -> the name it records as. Hand-maintained on purpose:
## these names are a *format* (`ReplayCodec.name_of` says so), so deriving them
## from the filenames would let a file renamed for tidiness silently retire every
## replay on disk.
const KNOWN := {
	"attack_command": "attack",
	"build_command": "build",
	"capture_command": "capture",
	"dive_command": "dive",
	"drop_command": "drop",
	"end_turn_command": "end_turn",
	"join_command": "join",
	"load_command": "load",
	"mission_event_command": "event",
	"move_command": "move",
	"power_command": "power",
	"supply_command": "supply",
}

## The base class every entry above extends. It records as nothing because it is
## never issued.
const BASE_FILE := "command"

var unit_db: UnitDB


func before_each() -> void:
	unit_db = Fixture.unit_db()


func test_every_command_on_disk_is_one_the_codec_knows() -> void:
	var found: Array[String] = []
	for file_name: String in DirAccess.get_files_at(COMMAND_DIR):
		if not file_name.ends_with(".gd"):
			continue
		var base := file_name.get_basename()
		if base == BASE_FILE:
			continue
		found.append(base)
	found.sort()

	var expected: Array[String] = []
	for base: String in KNOWN:
		expected.append(base)
	expected.sort()

	assert_eq(
		found, expected, 'a command class the replay format does not name records as {"c": ""}'
	)


func test_every_known_name_is_a_kind_the_codec_requires_fields_for() -> void:
	for base: String in KNOWN:
		assert_true(
			ReplayCodec.REQUIRED_KEYS.has(KNOWN[base]),
			"ReplayCodec.REQUIRED_KEYS names no '%s'" % KNOWN[base]
		)
	assert_eq(
		ReplayCodec.REQUIRED_KEYS.size(),
		KNOWN.size(),
		"REQUIRED_KEYS holds a kind no command class under core/commands/ produces"
	)


func test_every_known_name_rebuilds_from_a_line_carrying_only_its_required_keys() -> void:
	var state := Fixture.state("[terrain]\n....\n....\n[units]\n1 i 0 0")
	for base: String in KNOWN:
		var kind: String = KNOWN[base]
		var line := _minimal_line(state, kind)
		for key: String in ReplayCodec.REQUIRED_KEYS[kind]:
			assert_true(line.has(key), "the %s probe line names no %s" % [kind, key])
		assert_not_null(
			ReplayCodec.command_from(state, unit_db, line, _mission()),
			"ReplayCodec cannot rebuild a %s line" % kind
		)


## The smallest line of `kind` this build accepts: `c` plus exactly the fields
## `REQUIRED_KEYS` asks for, on the board above — one infantry at the origin, so
## every movement kind has an actor to name.
func _minimal_line(state: GameState, kind: String) -> Dictionary:
	var line := {"c": kind}
	for key: String in ReplayCodec.REQUIRED_KEYS[kind]:
		match key:
			"path":
				line["path"] = [[0, 0], [1, 0]]
			"cell", "target", "drop":
				line[key] = [1, 0]
			"submerge":
				line["submerge"] = true
			"unit":
				line["unit"] = String(state.units[0].type.id)
			"event":
				line["event"] = "the_gate_opens"
	return line


## A one-beat mission for the event line to be resolved against, the same shape
## `test_replay_codec.gd` builds — this file stays the codec's roster and loads no
## shipped campaign.
func _mission() -> MissionDefinition:
	var effect := SetOwnerEffect.new()
	effect.team = 1
	effect.cells = [Vector2i(0, 0)]
	var event := MissionEvent.new()
	event.id = &"the_gate_opens"
	event.effects = [effect]
	var mission := MissionDefinition.new()
	mission.id = &"probe_one"
	mission.player_team = 1
	mission.events = [event]
	return mission
