class_name SaveGame
extends RefCounted
## Storage for a running match: reads and writes the single save slot under
## user://, and nothing else.
##
## Everything about *what* a save contains — the field layout, the validation
## rules, rebuilding a GameState — belongs to SaveCodec. This file only knows
## about files and JSON text, so a disk error and a malformed save are separate
## failures with separate messages.
##
## The public surface is small and stays that way: `save`, `load_game`, `peek`,
## `has_save`, `SAVE_PATH`, and `VERSION` are what callers use. Which on-disk
## versions exist and which still load is SaveCodec's to say — see its header.

const SAVE_PATH := "user://save.json"
const SAVE_CODEC_SCRIPT := preload("res://core/save_codec.gd")
const VERSION := SAVE_CODEC_SCRIPT.VERSION


static func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


## Which board and day the save holds, without rebuilding the match — what the
## menu needs to name what Continue resumes. Null when there is no save, or it is
## not one the codec reads.
##
## Silent where `load_game` pushes errors: asking whether a slot is worth naming
## is a query the menu makes on every boot, and having nothing saved is the
## ordinary answer, not a failure.
static func peek(path: String = SAVE_PATH) -> SAVE_CODEC_SCRIPT.Summary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return null
	return SAVE_CODEC_SCRIPT.summarize(json.data)


## `difficulty` trails `path` so every existing caller keeps working; a save
## written without one records Normal, which is the tier those matches played at.
static func save(
	state: GameState,
	ai_teams: Array[int],
	path: String = SAVE_PATH,
	difficulty: StringName = Difficulty.DEFAULT_ID
) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(SAVE_CODEC_SCRIPT.encode(state, ai_teams, difficulty), "\t"))
	# Asked twice, and the handle is closed here rather than left to the local going
	# out of scope, which is what makes the second question askable at all. A write
	# that runs out of disk is reported by the store once its buffer spills, and the
	# tail of it only when the handle is flushed shut — so a save that answered
	# `true` off the store alone was a save the player could lose.
	var write_error := file.get_error()
	file.close()
	if write_error == OK:
		write_error = file.get_error()
	if write_error != OK:
		push_error("SaveGame: failed writing %s (error %d)" % [path, write_error])
		return false
	return true


## Returns null (with a pushed error) when the file is missing or invalid.
static func load_game(
	terrain_db: TerrainDB,
	unit_db: UnitDB,
	damage_chart: DamageChart,
	path: String = SAVE_PATH,
	commander_db: CommanderDB = null
) -> SAVE_CODEC_SCRIPT.LoadedMatch:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("SaveGame: cannot read %s" % path)
		return null
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		push_error("SaveGame: %s is not a valid save" % path)
		return null
	return SAVE_CODEC_SCRIPT.decode(json.data, terrain_db, unit_db, damage_chart, commander_db)
