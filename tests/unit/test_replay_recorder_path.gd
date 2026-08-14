extends GutTest
## Which file a recorder is writing, which is what the victory screen asks before
## it offers to watch the match back.
##
## The slot is claimed by the first command rather than by the boot (see
## ReplayRecorder), so "has a file" and "was handed an opener" are different
## questions and only the first of them means there is something to watch.

const DIR := "user://test_replay_recorder_path"

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	_clear()


func after_all() -> void:
	_clear()


func _clear() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIR)):
		return
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [DIR, name]))


func _state() -> GameState:
	var map := MapData.load_from_file("res://maps/first_steps.txt", terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.map_path = "res://maps/first_steps.txt"
	return state


func _recorder() -> ReplayRecorder:
	return ReplayRecorder.new(func() -> ReplayFile: return ReplayFile.open_slot("1", DIR))


func test_a_match_with_no_commands_names_no_file() -> void:
	var recorder := _recorder()
	recorder.begin(_state(), [2] as Array[int])
	assert_eq(recorder.path(), "", "the slot is the first command's to claim")
	recorder.close()


func test_the_first_command_gives_the_recorder_its_path() -> void:
	var state := _state()
	var recorder := _recorder()
	recorder.begin(state, [2] as Array[int])
	recorder.before_apply(state, EndTurnCommand.new())
	recorder.after_apply(state)

	assert_eq(recorder.path(), "%s/1%s" % [DIR, ReplayFile.EXTENSION])
	recorder.close()


## A recorder with no sink is a test's or the Balance Lab's, reading its lines
## back out of memory: there is no file to name.
func test_a_recorder_without_a_sink_names_no_file() -> void:
	var state := _state()
	var recorder := ReplayRecorder.new()
	recorder.begin(state, [2] as Array[int])
	recorder.before_apply(state, EndTurnCommand.new())
	recorder.after_apply(state)

	assert_eq(recorder.path(), "")
	assert_eq(recorder.lines().size(), 2, "header and command, held in memory")
