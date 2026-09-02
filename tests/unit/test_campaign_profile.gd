extends GutTest
## Campaign progress on disk.
##
## `SaveGame`'s tests' sibling and for the same reason: the promise is that a
## profile that fails to write leaves the previous one exactly as it was, and
## that a damaged file costs a campaign's record rather than the menu.
##
## Every case writes under a campaign id no shipped campaign uses, so a run of
## the suite can never touch a real profile.

const PROBE := &"__probe_campaign"
## The profile version the mission tally arrived in; the codec names the two
## later sections' versions and not this one, which a profile of version 1 lacks.
const TALLY_VERSION := 2

var campaign: CampaignDefinition


func before_each() -> void:
	CampaignProfile.erase(PROBE)
	campaign = CampaignDefinition.new()
	campaign.id = PROBE
	campaign.title = "Probe"
	for id: StringName in [&"one", &"two", &"three"]:
		var mission := MissionDefinition.new()
		mission.id = id
		mission.map_path = "res://maps/first_steps.txt"
		campaign.missions.append(mission)


func after_each() -> void:
	CampaignProfile.erase(PROBE)


func test_nothing_is_on_disk_until_something_is_written() -> void:
	assert_null(CampaignProfile.load_progress(PROBE))
	assert_eq(CampaignProfile.load_battle(PROBE), {})


func test_progress_survives_the_disk() -> void:
	var state := CampaignState.begin(campaign)
	state.complete(campaign, &"one", 3, 4)
	assert_true(CampaignProfile.save_progress(state))
	var back := CampaignProfile.load_progress(PROBE)
	assert_not_null(back)
	assert_eq(back.campaign_id, PROBE)
	assert_eq(back.stars_for(&"one"), 3)
	assert_eq(back.records[&"one"].best_day, 4)
	assert_true(back.is_unlocked(&"two"), "clearing one opened the next")


func test_a_second_write_replaces_the_first_and_leaves_no_siblings() -> void:
	var state := CampaignState.begin(campaign)
	state.complete(campaign, &"one", 1, 9)
	assert_true(CampaignProfile.save_progress(state))
	state.complete(campaign, &"two", 2, 5)
	assert_true(CampaignProfile.save_progress(state))
	var back := CampaignProfile.load_progress(PROBE)
	assert_eq(back.records.size(), 2)
	# The backup and temp are staging posts, not leftovers: one read back later
	# would be progress the player has already moved past.
	var path := CampaignProfile.path_for(PROBE)
	assert_false(FileAccess.file_exists(path + CampaignProfile.BACKUP_SUFFIX), "no backup left")
	assert_false(FileAccess.file_exists(path + CampaignProfile.TEMP_SUFFIX), "no temp left")


## The snapshot comes back key for key, but JSON has one number type, so what
## went in as 8 comes back as 8.0. That is the same round trip `SaveGame` has
## always made — `SaveCodec` reads every number through an `int()` cast for this
## reason — and it is asserted rather than papered over so the next reader knows
## the floats are the format's and not a bug here.
func test_the_battle_in_progress_rides_along_untouched() -> void:
	var state := CampaignState.begin(campaign)
	state.active_mission = &"one"
	var battle := {"version": 8, "day": 3, "anything": "the skirmish codec's business"}
	assert_true(CampaignProfile.save_progress(state, battle))
	var back := CampaignProfile.load_battle(PROBE)
	assert_eq(back.keys().size(), 3)
	assert_eq(int(back["version"]), 8)
	assert_eq(int(back["day"]), 3)
	assert_eq(back["anything"], "the skirmish codec's business")


func test_a_damaged_profile_reads_as_absent_rather_than_crashing() -> void:
	var file := FileAccess.open(CampaignProfile.path_for(PROBE), FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()
	# The codec's refusal is the log's business; the menu's is that the row still
	# works and offers a fresh start.
	assert_null(CampaignProfile.load_progress(PROBE))
	assert_push_error_count(1, "the damaged file is named once, in the log")


## The three readers answer off one file, so they have to agree about a damaged
## one: a profile the codec refuses holds no mission anybody may resume either,
## and the hub offers Resume off the battle rather than off the progress.
func test_a_profile_the_codec_refuses_is_absent_to_every_reader() -> void:
	var state := CampaignState.begin(campaign)
	state.active_mission = &"one"
	assert_true(CampaignProfile.save_progress(state, {"version": 8, "day": 3}))
	var path := CampaignProfile.path_for(PROBE)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	data["records"] = "not a set of records"
	_write(data)
	assert_null(CampaignProfile.load_progress(PROBE))
	assert_push_error_count(1, "said once, by the reader that reports")
	assert_eq(CampaignProfile.load_battle(PROBE), {}, "and there is no board to pick up")
	var in_progress := CampaignProfile.load_in_progress(PROBE)
	assert_eq(in_progress.battle, {})
	assert_true(in_progress.tally.is_empty())


## A profile every older format wrote still resumes: the sections it never had
## load empty, and the board it embeds is the board it embeds. Each older profile
## is the current one with its later sections stripped, since that is what its
## own writer produced and what `validate` holds it to.
func test_a_profile_from_every_older_version_still_resumes() -> void:
	var battle := {"version": 8, "day": 3}
	for version: int in range(1, CampaignSaveCodec.VERSION):
		CampaignProfile.erase(PROBE)
		var state := CampaignState.begin(campaign)
		state.active_mission = &"one"
		var data := CampaignSaveCodec.encode(
			state, battle, MissionProgress.from_dict({"losses": 1})
		)
		data["version"] = version
		if version < TALLY_VERSION:
			data.erase("mission_progress")
		if version < CampaignSaveCodec.LEDGER_VERSION:
			data.erase("flags")
		if version < CampaignSaveCodec.ROSTER_VERSION:
			data.erase("roster")
		_write(data)
		var back := CampaignProfile.load_progress(PROBE)
		assert_not_null(back, "a version %d profile still loads" % version)
		assert_eq(back.active_mission, &"one", "version %d names its mission" % version)
		var in_progress := CampaignProfile.load_in_progress(PROBE)
		assert_eq(int(in_progress.battle.get("version", 0)), 8, "version %d's board" % version)
		assert_eq(int(in_progress.battle.get("day", 0)), 3, "version %d's board" % version)
		assert_eq(
			in_progress.tally.losses(),
			1 if version >= TALLY_VERSION else 0,
			"version %d owes exactly the losses it could have written" % version
		)


## The profile as `data`, written straight to the slot the readers open.
func _write(data: Dictionary) -> void:
	var file := FileAccess.open(CampaignProfile.path_for(PROBE), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


# --- the developer override (`--unlock-missions`) ----------------------------


## A run that opened every mission writes nothing at all: it never creates a
## profile, and it never touches the one the player already had. Winning a
## mission out of order otherwise walks the route past everything behind it, and
## the war reads back as finished.
func test_a_run_with_the_override_open_writes_no_profile() -> void:
	var state := CampaignState.begin(campaign)
	state.unlock_all = true
	state.complete(campaign, &"three", 3, 4)
	assert_false(CampaignProfile.save_progress(state), "the write is refused")
	assert_false(FileAccess.file_exists(CampaignProfile.path_for(PROBE)), "and nothing is on disk")


func test_the_override_leaves_the_profile_the_player_earned_exactly_as_it_was() -> void:
	var earned := CampaignState.begin(campaign)
	earned.complete(campaign, &"one", 1, 9)
	assert_true(CampaignProfile.save_progress(earned))
	var before := FileAccess.get_file_as_string(CampaignProfile.path_for(PROBE))

	var inspecting := CampaignProfile.load_progress(PROBE)
	inspecting.unlock_all = true
	inspecting.complete(campaign, &"three", 3, 2)
	assert_false(CampaignProfile.save_progress(inspecting, {"version": 8, "day": 3}))
	assert_eq(
		FileAccess.get_file_as_string(CampaignProfile.path_for(PROBE)),
		before,
		"the profile is byte-for-byte the one the run opened"
	)
	assert_false(CampaignProfile.load_progress(PROBE).is_cleared(&"three"))


func test_erase_takes_the_siblings_with_it() -> void:
	var state := CampaignState.begin(campaign)
	assert_true(CampaignProfile.save_progress(state))
	var path := CampaignProfile.path_for(PROBE)
	var backup := FileAccess.open(path + CampaignProfile.BACKUP_SUFFIX, FileAccess.WRITE)
	backup.store_string("{}")
	backup.close()
	CampaignProfile.erase(PROBE)
	assert_false(FileAccess.file_exists(path))
	assert_false(FileAccess.file_exists(path + CampaignProfile.BACKUP_SUFFIX))


## Six campaigns progress independently, so one file each — finishing one must
## not be able to touch the record of another.
func test_each_campaign_keeps_its_own_file() -> void:
	var other := &"__probe_campaign_two"
	CampaignProfile.erase(other)
	var mine := CampaignState.begin(campaign)
	mine.complete(campaign, &"one", 3, 2)
	assert_true(CampaignProfile.save_progress(mine))
	var theirs := CampaignState.new()
	theirs.campaign_id = other
	theirs.unlocked[&"one"] = true
	assert_true(CampaignProfile.save_progress(theirs))
	assert_eq(CampaignProfile.load_progress(PROBE).stars_for(&"one"), 3, "untouched")
	assert_ne(CampaignProfile.path_for(PROBE), CampaignProfile.path_for(other))
	CampaignProfile.erase(other)
