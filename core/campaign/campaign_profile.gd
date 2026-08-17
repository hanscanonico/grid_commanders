class_name CampaignProfile
extends RefCounted
## Storage for campaign progress: reads and writes one file per campaign under
## `user://campaigns/`, and nothing else.
##
## `SaveGame`'s sibling, and deliberately the same shape — what a profile
## *contains* is `CampaignSaveCodec`'s, and this file knows only about paths and
## JSON text, so a full disk and a malformed profile are separate failures with
## separate messages.
##
## **One file per campaign** rather than one profile holding six. Six campaigns
## progress independently, so a single file would make finishing one able to
## corrupt the record of another, and a player who deletes one campaign's
## progress should not lose the rest.
##
## It writes through a temp and a backup for the same reason `SaveGame` does: at
## every instant one whole profile is on disk and this file can find it. Progress
## is cheap to lose in theory and infuriating to lose in practice — eighteen
## missions of it.

const DIR := "user://campaigns"
const TEMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"


## The mission a profile is midway through: the board and the tally it was being
## kept with. The two are written together and a resume wants both, so they are
## read together — the profile embeds a whole `SaveCodec` envelope, and asking
## for one part at a time parses the largest file this class writes twice.
class InProgress:
	extends RefCounted

	var battle: Dictionary
	var tally: MissionProgress

	func _init(p_battle: Dictionary, p_tally: MissionProgress) -> void:
		battle = p_battle
		tally = p_tally


## Where a campaign's progress lives. Public so a test can name the file rather
## than spelling the convention a second time.
static func path_for(campaign_id: StringName) -> String:
	return "%s/%s.json" % [DIR, campaign_id]


static func has_profile(campaign_id: StringName) -> bool:
	return FileAccess.file_exists(_slot_path(path_for(campaign_id)))


## Whichever copy is the live one. A replacement parks the previous profile at
## the backup for a moment, so a reader that opened `path` blindly would see
## nothing exactly then.
static func _slot_path(path: String) -> String:
	if FileAccess.file_exists(path):
		return path
	var backup := path + BACKUP_SUFFIX
	return backup if FileAccess.file_exists(backup) else path


## The progress recorded for this campaign, or null when there is none to read.
## A profile the codec refuses is reported and answered as absent: a player whose
## file was damaged is offered a fresh start rather than a dead menu row.
static func load_progress(campaign_id: StringName) -> CampaignState:
	var path := _slot_path(path_for(campaign_id))
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("CampaignProfile: could not read %s" % path)
		return null
	# A JSON instance rather than `parse_string`, for `SaveGame.load_game`'s
	# reason: the static call logs an engine error of its own on malformed text,
	# and a damaged profile is an expected condition this file reports in its own
	# words rather than a fault the engine should be shouting about.
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		push_error("CampaignProfile: %s is not a profile" % path)
		return null
	return CampaignSaveCodec.decode(json.data)


## The battle a profile was midway through, or an empty dictionary. Handed
## straight to `SaveCodec.decode`; nothing here reads inside it.
static func load_battle(campaign_id: StringName) -> Dictionary:
	return CampaignSaveCodec.battle_of(_read(campaign_id))


## That battle and the tally it was being kept with, off one read. What a deploy
## asks: it needs to know there is a board to pick up *and* what that board was
## being counted with, and a resumed mission has to open owing the losses it had
## already taken.
static func load_in_progress(campaign_id: StringName) -> InProgress:
	var data := _read(campaign_id)
	return InProgress.new(CampaignSaveCodec.battle_of(data), CampaignSaveCodec.tally_of(data))


## The profile as it sits on disk *once the codec has accepted it*, or an empty
## dictionary. A file `load_progress` would refuse holds no mission anybody may
## resume either, so every reader here answers about the same profile that one
## does. Silent throughout, unlike `load_progress`: a caller asking for one part
## of a profile is asking about a mission in progress, "there is none" is the
## ordinary answer, and a damaged file is said once by the reader that reports.
static func _read(campaign_id: StringName) -> Dictionary:
	var path := _slot_path(path_for(campaign_id))
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	var data: Dictionary = json.data
	return {} if CampaignSaveCodec.validate(data) != "" else data


## Writes progress, leaving the previous profile untouched if anything fails.
## Returns false and says why; the caller decides whether that is worth telling
## the player about.
##
## A run with the developer override open writes nothing at all, and the refusal
## is here rather than at either caller because this is the one door onto the
## disk: a mission played out of order would otherwise be recorded as cleared,
## which walks the route past every mission behind it and reads the war back as
## finished. So `--unlock-missions` is an inspection — the profile it opens is
## exactly the profile it leaves.
static func save_progress(
	state: CampaignState, battle: Dictionary = {}, tally: MissionProgress = null
) -> bool:
	if state.unlock_all:
		return false
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIR)):
		var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
		if error != OK:
			push_error("CampaignProfile: cannot create %s (%d)" % [DIR, error])
			return false
	var path := path_for(state.campaign_id)
	var temp := path + TEMP_SUFFIX
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_error("CampaignProfile: cannot write %s (%d)" % [temp, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(CampaignSaveCodec.encode(state, battle, tally), "\t"))
	file.close()
	return _swap_into_place(temp, path + BACKUP_SUFFIX, path)


## The new profile becomes the live one without either copy being absent: the
## previous one steps aside to the backup first, so a crash between the two moves
## leaves the backup, which `_slot_path` reads.
static func _swap_into_place(temp_path: String, backup_path: String, path: String) -> bool:
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("CampaignProfile: cannot open user:// to place the profile")
		return false
	if FileAccess.file_exists(path) and dir.rename(path, backup_path) != OK:
		push_error("CampaignProfile: cannot set the previous profile aside")
		return false
	if dir.rename(temp_path, path) != OK:
		push_error("CampaignProfile: cannot move the new profile into place")
		if FileAccess.file_exists(backup_path):
			dir.rename(backup_path, path)
		return false
	if FileAccess.file_exists(backup_path):
		dir.remove(backup_path)
	return true


## Forgets a campaign's progress. No shipped screen calls it yet — it exists for
## the restart a hub will someday offer, and for the tests — so it removes the
## siblings too: a backup left behind would be read back as the progress the
## player just discarded.
static func erase(campaign_id: StringName) -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	var path := path_for(campaign_id)
	for candidate in [path, path + BACKUP_SUFFIX, path + TEMP_SUFFIX]:
		if FileAccess.file_exists(candidate):
			dir.remove(candidate)
