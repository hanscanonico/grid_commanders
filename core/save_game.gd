class_name SaveGame
extends RefCounted
## Storage for a running match: reads and writes the single save slot under
## user:// — and the two siblings a replacement stages beside it — and nothing else.
##
## Everything about *what* a save contains — the field layout, the validation
## rules, rebuilding a GameState — belongs to SaveCodec. This file only knows
## about files and JSON text, so a disk error and a malformed save are separate
## failures with separate messages.
##
## The public surface is small and stays that way: `save`, `load_game`, `status`,
## `has_save`, `SAVE_PATH`, and `VERSION` are what callers use — plus `TEMP_SUFFIX`
## and `BACKUP_SUFFIX`, which are public only so a test can name the siblings a save
## stages beside a slot rather than spelling them a second time. Which on-disk
## versions exist and which still load is SaveCodec's to say — see its header.
##
## At every instant of a save, on every platform, one whole save is on disk *and this
## file can find it* — the previous one or the new one. That is part of what this file
## promises: a save that fails leaves the previous one exactly as it was, so a full disk
## costs the player the save they just asked for and never the one they already had. The
## replacement keeps that true itself rather than borrowing it from `rename`, which is
## indivisible on Unix but a delete-then-move on Windows. Its price is a moment where
## the previous save sits at the sibling backup rather than at the slot, which is why
## every reader here goes through `_slot_path` instead of opening `path`.
##
## That costs a second copy's worth of free space, and the trade is deliberate: a
## volume too full to hold the temp fails the save outright, where writing in place
## would have squeezed it in by first truncating — and so destroying — the only good
## copy. Losing the save the player just asked for is the cheaper of the two.

const SAVE_PATH := "user://save.json"
const SAVE_CODEC_SCRIPT := preload("res://core/save_codec.gd")
const VERSION := SAVE_CODEC_SCRIPT.VERSION
const TEMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"


## What a slot holds, as far as naming it goes: nothing, a save nothing here can
## read — with the words of whoever refused it — or the summary that names it.
##
## Three states rather than a summary that may be null, because "you have no saved
## match" and "your saved match is damaged" are opposite things to be told and a
## null says both. A save this file writes and the disk then truncates used to
## reach the player as the first of those.
class Slot:
	enum State { ABSENT, UNREADABLE, READABLE }

	var state := State.ABSENT
	## Why the save cannot be read: this file's words for a storage failure,
	## SaveCodec's for a malformed save. Empty unless UNREADABLE.
	var reason := ""
	## Null unless READABLE.
	var summary: SAVE_CODEC_SCRIPT.Summary = null

	static func absent() -> Slot:
		return Slot.new()

	static func unreadable(why: String) -> Slot:
		var slot := Slot.new()
		slot.state = State.UNREADABLE
		slot.reason = why
		return slot

	static func readable(named: SAVE_CODEC_SCRIPT.Summary) -> Slot:
		var slot := Slot.new()
		slot.state = State.READABLE
		slot.summary = named
		return slot


static func has_save(path: String = SAVE_PATH) -> bool:
	return not _slot_path(path).is_empty()


## Which file holds this slot's save right now: the slot, or — when a save was
## interrupted between the swap's two renames and the slot is therefore not there — the
## backup it was set aside to. Empty when neither exists.
##
## Every reader asks this rather than opening `path` itself, because a backup nothing
## looks at is not durability: without it a machine that lost power mid-swap would boot
## to "no saved match" while the whole previous match sat beside the slot, which is the
## harm this file exists to prevent. Answering anything but the slot means a genuine
## interruption — the next successful save takes the slot back and clears the backup.
##
## Reading is a pure query here as everywhere: recovery is the *writer's* to finish.
static func _slot_path(path: String) -> String:
	if FileAccess.file_exists(path):
		return path
	var backup_path := path + BACKUP_SUFFIX
	if FileAccess.file_exists(backup_path):
		return backup_path
	return ""


## Which board and day the save holds, without rebuilding the match — what the
## menu needs to name what Continue resumes — or why it cannot be named.
##
## Silent where `load_game` pushes errors: asking whether a slot is worth naming
## is a query the menu makes on every boot, and having nothing saved is the
## ordinary answer, not a failure. A damaged one is not a failure of the query
## either — it is news, so it is handed back as words rather than pushed at a log
## no player reads.
##
## READABLE is not a promise `load_game` will accept: naming a save loads no board,
## so a save describing one that has since moved is named here and refused there
## (see SaveCodec.summarize). Whoever offers the slot has to be ready for that.
static func status(path: String = SAVE_PATH) -> Slot:
	var slot := _slot_path(path)
	if slot.is_empty():
		return Slot.absent()
	var text := FileAccess.get_file_as_string(slot)
	if text.is_empty():
		return Slot.unreadable("%s is empty or cannot be read" % slot)
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return Slot.unreadable("%s is not a valid save" % slot)
	var reason := SAVE_CODEC_SCRIPT.validate(json.data)
	if reason != "":
		return Slot.unreadable(reason)
	return Slot.readable(SAVE_CODEC_SCRIPT.summarize(json.data))


## `difficulty` trails `path` so every existing caller keeps working; a save
## written without one records Normal, which is the tier those matches played at.
## `auto_tiers` trails it for the same reason, and defaults empty — no seat on
## Auto — for the same reason; `seat_tiers` is the same again, and empty is a match
## whose computer seats all play the one tier above.
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
	difficulty: StringName = Difficulty.DEFAULT_ID,
	auto_tiers: Dictionary[int, StringName] = {},
	seat_tiers: Dictionary[int, StringName] = {}
) -> bool:
	# Both derived from the caller's path, not from SAVE_PATH, so a test writing its own
	# slot stages its own temp and backup beside it rather than beside the player's.
	var temp_path := path + TEMP_SUFFIX
	var backup_path := path + BACKUP_SUFFIX
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error(
			"SaveGame: cannot write %s (error %d)" % [temp_path, FileAccess.get_open_error()]
		)
		return false
	var payload := JSON.stringify(
		SAVE_CODEC_SCRIPT.encode(state, ai_teams, difficulty, auto_tiers, seat_tiers), "\t"
	)
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
##
## What each failure leaves, stated as what the code does rather than as one promise:
## a refused set-aside never touches the slot; a refused swap puts the previous save
## back and reports only the replacement as failed; and a restore that is *itself*
## refused leaves that save at the backup, where `_slot_path` finds it — so it says so,
## rather than letting a caller tell the player a save it can no longer open is intact.
## Only that last path leaves a file standing, and it is the previous save, whole.
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
			var restore := DirAccess.rename_absolute(_absolute(backup_path), _absolute(path))
			if restore != OK:
				push_error(
					(
						"SaveGame: %s is empty — the previous save is at %s (error %d)"
						% [path, backup_path, restore]
					)
				)
		return false
	# Unconditional: a backup left standing by an interrupted save is stale the moment
	# this one lands, and clearing it here is what keeps `_slot_path` reaching for one
	# only after a genuine interruption rather than for the rest of the match.
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
	var slot := _slot_path(path)
	if slot.is_empty():
		push_error("SaveGame: cannot read %s" % path)
		return null
	var text := FileAccess.get_file_as_string(slot)
	if text.is_empty():
		push_error("SaveGame: cannot read %s" % slot)
		return null
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		push_error("SaveGame: %s is not a valid save" % slot)
		return null
	return SAVE_CODEC_SCRIPT.decode(json.data, terrain_db, unit_db, damage_chart, commander_db)
