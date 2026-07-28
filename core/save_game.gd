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
##
## The slot is replaced *atomically*, and that is part of what this file promises:
## a save that fails leaves the previous one exactly as it was, so a full disk costs
## the player the save they just asked for and never the one they already had.

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
##
## The payload lands in a sibling `.tmp` and is only renamed over `path` once the
## write has answered for itself: `FileAccess.open(…, WRITE)` truncates its target
## before a single byte is stored, so writing straight into the slot destroyed the
## previous save the moment the new one began — a failure the player then read as
## "no saved match" on the next boot.
static func save(
	state: GameState,
	ai_teams: Array[int],
	path: String = SAVE_PATH,
	difficulty: StringName = Difficulty.DEFAULT_ID
) -> bool:
	# Derived from the caller's path, not from SAVE_PATH, so a test writing its own
	# slot stages its own temp beside it rather than beside the player's.
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error(
			"SaveGame: cannot write %s (error %d)" % [temp_path, FileAccess.get_open_error()]
		)
		return false
	var stored := file.store_string(
		JSON.stringify(SAVE_CODEC_SCRIPT.encode(state, ai_teams, difficulty), "\t")
	)
	# Three signals, because no one of them is sufficient. The store's own `false` is
	# what a short write raises on Unix — that path returns it rather than recording a
	# `last_error`, so a save that only asked `get_error()` still answered `true` over a
	# truncated file. The error is then asked twice, and the handle is closed here
	# rather than left to the local going out of scope, because a store whose buffer
	# spilled cleanly can still fail on the tail the flush pushes out.
	var write_error := file.get_error()
	file.close()
	if write_error == OK:
		write_error = file.get_error()
	if not stored or write_error != OK:
		push_error("SaveGame: failed writing %s (error %d)" % [temp_path, write_error])
		_discard(temp_path)
		return false
	# POSIX rename replaces the destination in one step, which is what makes the swap
	# atomic — there is no instant where the slot is neither the old save nor the new.
	var swap_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(path)
	)
	if swap_error != OK:
		push_error("SaveGame: cannot replace %s (error %d)" % [path, swap_error])
		_discard(temp_path)
		return false
	return true


## A half-written temp is worse than none: it would outlive the failure and the next
## save would rename it over a slot it never described.
static func _discard(temp_path: String) -> void:
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))


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
