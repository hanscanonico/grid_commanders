class_name CampaignDefinition
extends Resource
## One campaign: its identity, its ordered missions, and the blocks they group
## into.
##
## The order is the list's order — there is no `next_mission_id` chain, because
## two sources for "what comes after this" is how a campaign ends up with a
## mission nothing reaches. A block is a label over a run of that same list, so
## the blocks cannot disagree with the order either.

@export var id: StringName = &""
@export var title: String = ""
@export_multiline var premise: String = ""
## The general the campaign opposes, for the select screen's card.
@export var antagonist: String = ""
## Missions in play order. Mission one is unlocked from a fresh profile.
@export var missions: Array[MissionDefinition] = []
## Optional labels over runs of `missions`, in order — "Ferrow", "Vale". A block
## states only how many missions it covers, so it can never name one that moved.
@export var block_titles: Array[String] = []
@export var block_lengths: Array[int] = []


func mission_count() -> int:
	return missions.size()


## The mission with this id, or null.
func mission(mission_id: StringName) -> MissionDefinition:
	for entry: MissionDefinition in missions:
		if entry != null and entry.id == mission_id:
			return entry
	return null


func index_of(mission_id: StringName) -> int:
	for i in missions.size():
		if missions[i] != null and missions[i].id == mission_id:
			return i
	return -1


func first_mission_id() -> StringName:
	return missions[0].id if not missions.is_empty() and missions[0] != null else &""


## The mission after this one, or "" at the end of the campaign.
func next_mission_id(mission_id: StringName) -> StringName:
	var index := index_of(mission_id)
	if index < 0 or index + 1 >= missions.size():
		return &""
	return missions[index + 1].id


## Which block a mission sits in, or -1. Read by the hub to group its path.
func block_of(mission_id: StringName) -> int:
	var index := index_of(mission_id)
	if index < 0:
		return -1
	var seen := 0
	for block in block_lengths.size():
		seen += block_lengths[block]
		if index < seen:
			return block
	return -1


## Why this campaign could never be played, or "". Structural only: a mission's
## own board checks live on `MissionDefinition.definition_error`, because those
## need the map loaded and this does not.
func definition_error() -> String:
	if id == &"":
		return "campaign has no id"
	if missions.is_empty():
		return "campaign '%s' has no missions" % id
	var seen: Dictionary = {}
	for entry: MissionDefinition in missions:
		if entry == null:
			return "campaign '%s' holds an empty mission slot" % id
		if seen.has(entry.id):
			return "campaign '%s' names mission '%s' twice" % [id, entry.id]
		seen[entry.id] = true
	if block_titles.size() != block_lengths.size():
		return (
			"campaign '%s' has %d block titles and %d block lengths"
			% [id, block_titles.size(), block_lengths.size()]
		)
	if not block_lengths.is_empty():
		var total := 0
		for length in block_lengths:
			total += length
		if total != missions.size():
			return "campaign '%s' blocks cover %d missions of %d" % [id, total, missions.size()]
	return ""
