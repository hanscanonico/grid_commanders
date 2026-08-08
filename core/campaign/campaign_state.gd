class_name CampaignState
extends RefCounted
## How far a player has got in one campaign: what is unlocked, what is cleared,
## the best result each cleared mission was cleared with, and what the war has
## recorded along the way.
##
## Progress only. It holds no board and no `GameState` — the battle a player is
## midway through is the ordinary skirmish snapshot, embedded by
## `CampaignSaveCodec` rather than re-modelled here. The one thing it knows about
## units is `roster`, and that is a record of condition rather than a board: a
## `CarriedUnit` has no cell, no fuel and no turn.

## Facts the campaign already knows and so never stores twice: `records` owns
## what a mission was cleared with, and a copy of it in `flags` would be a second
## opinion about it. Both kinds are read through `flag`, so a condition asks
## after a cleared mission in the same words it asks after an authored fact.
const CLEARED := "cleared:"
const STARS := "stars:"

var campaign_id: StringName = &""
## Mission ids the player may start, in no particular order.
var unlocked: Dictionary[StringName, bool] = {}
## `mission id -> best result`, present only for cleared missions.
var records: Dictionary[StringName, MissionRecord] = {}
## The mission the player is currently in, or "" between missions.
var active_mission: StringName = &""
## The consequence ledger: named facts one mission wrote and a later one reads
## (campaign-depth D5). Integers rather than booleans so it can count — "cities
## saved: 4" — without a second kind of fact. Written by `complete` alone, out of
## what the finished mission staged; nothing in `core/rules/` or `ai/` reads one,
## because a flag chooses authored content and never tunes a number.
var flags: Dictionary[StringName, int] = {}
## The army the war remembers: what stood at the end of the last mission that
## carried its survivors out (campaign-depth D6). Condition and identity only —
## `CampaignRoster` is what banks it and what stands it in the next board's carry
## slots. Empty outside a chain, which is almost everywhere, and emptied by a
## mission that carries nothing out.
var roster: Array[CarriedUnit] = []


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


## What the ledger holds for `name`, and zero for a fact nothing has written.
## The one read: a derived name is answered from the record it is about rather
## than from a stored copy, so the two kinds of fact cannot disagree.
func flag(name: StringName) -> int:
	var key := String(name)
	if key.begins_with(CLEARED):
		return 1 if is_cleared(StringName(key.trim_prefix(CLEARED))) else 0
	if key.begins_with(STARS):
		return stars_for(StringName(key.trim_prefix(STARS)))
	return flags.get(name, 0)


## Is this a fact the campaign answers itself? What stops a beat writing one, and
## what keeps a stored ledger to authored facts alone.
static func is_derived(name: StringName) -> bool:
	var key := String(name)
	return key.begins_with(CLEARED) or key.begins_with(STARS)


## The mission a derived name is about, and &"" for a fact a beat writes. The one
## place that split is spelled, so the ledger and the campaign's content gate
## cannot disagree about which mission a name names.
static func derived_mission(name: StringName) -> StringName:
	var key := String(name)
	return StringName(key.substr(key.find(":") + 1)) if is_derived(name) else &""


## Why `name` could not name a fact, or "". An identifier, so a flag reads in a
## profile exactly as an event id does — or one of the derived names, which is a
## prefix and the mission it is about.
static func flag_name_error(name: StringName) -> String:
	var key := String(name)
	if key == "":
		return "a flag with no name"
	if is_derived(name):
		var mission := String(derived_mission(name))
		return "" if mission.is_valid_ascii_identifier() else "'%s' names no mission" % key
	return "" if key.is_valid_ascii_identifier() else "'%s' is not an identifier" % key


## Record a clear, open the next mission and take what this one wrote to the
## ledger.
##
## The record is replaced only where the new run is better, and the two halves
## are judged **separately**: a run can beat its predecessor on stars while
## taking longer, and a player who earns a third star on day 9 should not lose
## the day-5 they already have. Unlocking is unconditional, because a mission
## already open cannot be closed by a worse replay.
##
## **The ledger is written the first time a mission is finished and never again.**
## A replay is for stars; the war already happened, and later missions have
## already been briefed and opened off what it recorded — rewriting it behind
## them is the one thing a replay must not do.
##
## Returns whether the ledger took what the mission staged, which is the debrief's
## answer to whether the war moved: a replay stages the same facts and writes none
## of them, and a screen claiming a change that did not happen is worse than one
## that says nothing.
func complete(
	campaign: CampaignDefinition,
	mission_id: StringName,
	stars: int,
	day: int,
	tally: MissionProgress = null
) -> bool:
	var record: MissionRecord = records.get(mission_id)
	if record == null:
		records[mission_id] = MissionRecord.new(stars, day)
	else:
		record.stars = maxi(record.stars, stars)
		record.best_day = day if record.best_day <= 0 else mini(record.best_day, day)
	var next := campaign.next_mission_id(mission_id)
	if next != &"":
		unlocked[next] = true
	var took := tally != null and record == null
	if took:
		_take_staged_flags(tally)
	active_mission = &""
	return took


## Fold what the mission staged into the ledger — the ledger's one writer.
##
## Here rather than at the beat that wrote it, for the reason the tally itself is
## dropped with its board: a mission that was abandoned or lost is retried, and a
## fact banked by the attempt that went wrong would be counted twice.
##
## Assignments settle before increments, and both in name order, so a profile
## that has been through JSON commits exactly as the run did.
func _take_staged_flags(tally: MissionProgress) -> void:
	var assignments := tally.flag_assignments()
	for name: String in _in_order(assignments):
		flags[StringName(name)] = assignments[name]
	var increments := tally.flag_increments()
	for name: String in _in_order(increments):
		flags[StringName(name)] = flags.get(StringName(name), 0) + increments[name]


static func _in_order(staged: Dictionary[String, int]) -> Array:
	var names := staged.keys()
	names.sort()
	return names


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
