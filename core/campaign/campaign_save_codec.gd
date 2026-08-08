class_name CampaignSaveCodec
extends RefCounted
## Encodes and decodes campaign progress, plus the battle a player is midway
## through.
##
## Two rules carry this class. **It never serialises a board**: the mission in
## progress is `SaveCodec.encode`'s dictionary, embedded whole under `battle`,
## so units, RNG, commanders, carriers and property state have exactly one
## encoder and a campaign save inherits every validation the skirmish save
## already has. And **it never touches the skirmish file**: campaign progress
## lives beside it under its own name, so "Continue" means one unambiguous thing
## on each of the two cards and finishing a campaign mission cannot overwrite an
## unrelated match.

## 2 carries the mission tally beside the battle — its counters, and since the
## event system the beats that have already fired and the hidden objectives they
## revealed, all of which are counters like any other and so needed no second
## format. A version 1 profile loads with an empty tally, which is what it was
## playing with.
const VERSION := 2


## The whole of a campaign profile, as a plain dictionary.
static func encode(
	state: CampaignState, battle: Dictionary = {}, tally: MissionProgress = null
) -> Dictionary:
	var unlocked: Array[String] = []
	for mission_id: StringName in state.unlocked:
		if state.unlocked[mission_id]:
			unlocked.append(String(mission_id))
	unlocked.sort()
	var records: Dictionary = {}
	for mission_id: StringName in state.records:
		var record: CampaignState.MissionRecord = state.records[mission_id]
		records[String(mission_id)] = {"stars": record.stars, "best_day": record.best_day}
	var data := {
		"version": VERSION,
		"campaign_id": String(state.campaign_id),
		"unlocked": unlocked,
		"records": records,
		"active_mission": String(state.active_mission),
	}
	# The tally rides with the battle and is dropped with it: bookkeeping for a
	# mission nobody is in the middle of is bookkeeping nobody can use, and it is
	# what stops a restarted mission opening with the last attempt's losses.
	if not battle.is_empty():
		data["battle"] = battle
		if tally != null and not tally.is_empty():
			data["mission_progress"] = tally.to_dict()
	return data


## The progress in this dictionary, or null when it could not have been written
## by any profile. `validate` is what says why.
static func decode(data: Dictionary) -> CampaignState:
	var error := validate(data)
	if error != "":
		push_error("CampaignSaveCodec: %s" % error)
		return null
	var state := CampaignState.new()
	state.campaign_id = StringName(data["campaign_id"])
	for mission_id: String in data["unlocked"]:
		state.unlocked[StringName(mission_id)] = true
	var records: Dictionary = data["records"]
	for mission_id: String in records:
		var record: Dictionary = records[mission_id]
		state.records[StringName(mission_id)] = CampaignState.MissionRecord.new(
			int(record["stars"]), int(record["best_day"])
		)
	state.active_mission = StringName(data.get("active_mission", ""))
	return state


## The embedded battle, or an empty dictionary when the profile is between
## missions. Handed straight to `SaveCodec.decode`, never re-read here.
static func battle_of(data: Dictionary) -> Dictionary:
	var battle = data.get("battle", {})
	return battle if battle is Dictionary else {}


## The tally that battle was being kept with, empty when the profile holds none —
## which is every version 1 profile, and every profile between missions.
static func tally_of(data: Dictionary) -> MissionProgress:
	var counters = data.get("mission_progress", {})
	return MissionProgress.from_dict(counters if counters is Dictionary else {})


## Why this dictionary is not a campaign profile, or "".
##
## Refuses the shape rather than the content: a mission id this campaign no
## longer has is *not* an error, because a save outliving a renamed mission
## should lose that mission's record rather than the whole profile. What cannot
## be tolerated is a file no writer could have produced.
static func validate(data: Dictionary) -> String:
	if not data.has("version"):
		return "save has no version"
	var version := int(data["version"])
	if version <= 0 or version > VERSION:
		return "save claims version %d; this build writes %d" % [version, VERSION]
	if not data.has("campaign_id") or not (data["campaign_id"] is String):
		return "save names no campaign"
	if String(data["campaign_id"]) == "":
		return "save names an empty campaign"
	if not data.has("unlocked") or not (data["unlocked"] is Array):
		return "save has no unlocked list"
	for entry in data["unlocked"]:
		if not (entry is String) or String(entry) == "":
			return "unlocked list holds %s, which is not a mission id" % [entry]
	if not data.has("records") or not (data["records"] is Dictionary):
		return "save has no records"
	var records: Dictionary = data["records"]
	for key in records:
		if not (key is String):
			return "records are keyed by %s, which is not a mission id" % [key]
		var record = records[key]
		if not (record is Dictionary) or not record.has("stars") or not record.has("best_day"):
			return "record for '%s' is not a result" % key
		if int(record["stars"]) < 0:
			return "record for '%s' holds %d stars" % [key, int(record["stars"])]
	if data["unlocked"].is_empty() and records.is_empty():
		return "save has neither an unlocked mission nor a cleared one"
	if data.has("battle") and not (data["battle"] is Dictionary):
		return "save holds a battle that is not a snapshot"
	if data.has("battle") and String(data.get("active_mission", "")) == "":
		return "save holds a battle but names no mission it belongs to"
	if data.has("mission_progress"):
		if not (data["mission_progress"] is Dictionary):
			return "save holds a tally that is not a set of counters"
		if not data.has("battle"):
			return "save holds a tally but no battle it was kept for"
		var error := MissionProgress.tally_error(data["mission_progress"])
		if error != "":
			return error
	return ""
