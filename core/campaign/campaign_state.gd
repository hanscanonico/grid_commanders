class_name CampaignState
extends RefCounted
## How far a player has got in one campaign: what is unlocked, what is cleared,
## and the best result each cleared mission was cleared with.
##
## Progress only. It holds no board, no units and no `GameState` — the battle a
## player is midway through is the ordinary skirmish snapshot, embedded by
## `CampaignSaveCodec` rather than re-modelled here.

var campaign_id: StringName = &""
## Mission ids the player may start, in no particular order.
var unlocked: Dictionary[StringName, bool] = {}
## `mission id -> best result`, present only for cleared missions.
var records: Dictionary[StringName, MissionRecord] = {}
## The mission the player is currently in, or "" between missions.
var active_mission: StringName = &""


## The best a mission has ever been finished with. Best, not last: a replay that
## goes badly must never cost the player a star they already earned.
class MissionRecord:
	extends RefCounted

	var stars: int = 0
	var best_day: int = 0

	func _init(p_stars: int = 0, p_best_day: int = 0) -> void:
		stars = p_stars
		best_day = p_best_day


## A fresh profile: mission one unlocked, nothing cleared.
static func begin(campaign: CampaignDefinition) -> CampaignState:
	var state := CampaignState.new()
	state.campaign_id = campaign.id
	var first := campaign.first_mission_id()
	if first != &"":
		state.unlocked[first] = true
	return state


func is_unlocked(mission_id: StringName) -> bool:
	return unlocked.get(mission_id, false)


func is_cleared(mission_id: StringName) -> bool:
	return records.has(mission_id)


func stars_for(mission_id: StringName) -> int:
	var record: MissionRecord = records.get(mission_id)
	return record.stars if record != null else 0


func total_stars() -> int:
	var total := 0
	for record: MissionRecord in records.values():
		total += record.stars
	return total


## Record a clear and open the next mission.
##
## The record is replaced only where the new run is better, and the two halves
## are judged **separately**: a run can beat its predecessor on stars while
## taking longer, and a player who earns a third star on day 9 should not lose
## the day-5 they already have. Unlocking is unconditional, because a mission
## already open cannot be closed by a worse replay.
func complete(campaign: CampaignDefinition, mission_id: StringName, stars: int, day: int) -> void:
	var record: MissionRecord = records.get(mission_id)
	if record == null:
		records[mission_id] = MissionRecord.new(stars, day)
	else:
		record.stars = maxi(record.stars, stars)
		record.best_day = day if record.best_day <= 0 else mini(record.best_day, day)
	var next := campaign.next_mission_id(mission_id)
	if next != &"":
		unlocked[next] = true
	active_mission = &""


## Where a returning player is put: the mission they were in, else the furthest
## unlocked mission they have not cleared, else the last one they did.
func resume_point(campaign: CampaignDefinition) -> StringName:
	if active_mission != &"" and is_unlocked(active_mission):
		return active_mission
	var furthest := campaign.first_mission_id()
	for entry: MissionDefinition in campaign.missions:
		if not is_unlocked(entry.id):
			continue
		furthest = entry.id
		if not is_cleared(entry.id):
			return entry.id
	return furthest


func is_complete(campaign: CampaignDefinition) -> bool:
	for entry: MissionDefinition in campaign.missions:
		if not is_cleared(entry.id):
			return false
	return true
