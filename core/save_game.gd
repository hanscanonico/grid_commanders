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
## At every instant of a save, on every platform, one whole save is on disk — the
## previous one or the new one — and that is part of what this file promises: a save
## that fails leaves the previous one exactly as it was, so a full disk costs the
## player the save they just asked for and never the one they already had. The
## replacement keeps that true itself rather than borrowing it from `rename`, which
## is indivisible on Unix but a delete-then-move on Windows.
##
## That costs a second copy's worth of free space, and the trade is deliberate: a
## volume too full to hold the temp fails the save outright, where writing in place
## would have squeezed it in by first truncating — and so destroying — the only good
## copy. Losing the save the player just asked for is the cheaper of the two.

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
## The payload lands in a sibling `.tmp` and is only swapped into `path` once the
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
	# Both derived from the caller's path, not from SAVE_PATH, so a test writing its own
	# slot stages its own temp and backup beside it rather than beside the player's.
	var temp_path := path + ".tmp"
	var backup_path := path + ".bak"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error(
			"SaveGame: cannot write %s (error %d)" % [temp_path, FileAccess.get_open_error()]
		)
		return false
	var payload := JSON.stringify(SAVE_CODEC_SCRIPT.encode(state, ai_teams, difficulty), "\t")
	# Bytes, not characters: `store_string` writes UTF-8, so a single accented character
	# in a map name would make a truncated file look the right length to a `length()`.
	var expected_bytes := payload.to_utf8_buffer().size()
	file.store_string(payload)
	# Closed here rather than left to the local going out of scope, because the tail of
	# the payload only reaches the disk on the flush the close forces.
	file.close()
	# The one authority on whether the write landed is what the disk hands back, and it
	# has to be: on a full volume `store_string` returns true and `get_error()` reads OK
	# both before and after the close while zero bytes land, because the ENOSPC surfaces
	# inside that buffered flush and no FileAccess call carries it out. Asking the handle
	# is not a cheaper version of this question — it is a different one, and on the
	# failure the ticket was filed about it answers "saved".
	var landed_bytes := FileAccess.get_file_as_bytes(temp_path).size()
	if landed_bytes != expected_bytes:
		push_error(
			(
				"SaveGame: %s holds %d of %d bytes — the disk is full or the write was cut short"
				% [temp_path, landed_bytes, expected_bytes]
			)
		)
		_discard(temp_path)
		return false
	return _swap_into_place(temp_path, backup_path, path)


## The old save is set aside rather than overwritten, because one rename is only
## indivisible on Unix: Godot's Windows `rename` deletes the destination before it
## moves, so a slot replaced in a single call has an instant there where it holds
## neither save — the ticket's own harm, reappearing on the platform nobody tested on.
## Moving the previous save to a sibling first makes the guarantee the code's rather
## than the filesystem's: whichever rename fails, one whole save is still on disk and
## neither stray is left behind.
static func _swap_into_place(temp_path: String, backup_path: String, path: String) -> bool:
	var previous := FileAccess.file_exists(path)
	if previous:
		var aside := DirAccess.rename_absolute(_absolute(path), _absolute(backup_path))
		if aside != OK:
			push_error("SaveGame: cannot set %s aside (error %d)" % [path, aside])
			_discard(temp_path)
			return false
	var swap_error := DirAccess.rename_absolute(_absolute(temp_path), _absolute(path))
	if swap_error != OK:
		push_error("SaveGame: cannot replace %s (error %d)" % [path, swap_error])
		_discard(temp_path)
		if previous:
			DirAccess.rename_absolute(_absolute(backup_path), _absolute(path))
		return false
	# Unconditional: a backup that outlived a crashed save is stale the moment this one
	# lands, and the slot it described is the file just replaced.
	_discard(backup_path)
	return true


## A half-written temp — or a backup of a save that is no longer the current one — is
## worse than none: it would outlive the failure and the next save would rename it over
## a slot it never described.
static func _discard(stray_path: String) -> void:
	if FileAccess.file_exists(stray_path):
		DirAccess.remove_absolute(_absolute(stray_path))


static func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path)


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
