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
##
## **Which mission the war offers next is the route's**, and the route is
## `open_mission`: the campaign's order narrowed by what the war has recorded
## (campaign-depth D7). Branching lives here rather than in the campaign, which
## owns the order and nothing about a particular player's way through it.
##
## **What a replay of a cleared mission does**, all three answers in one place:
## the ledger takes nothing and the carried army is not re-banked — first clear
## wins — while stars and best day take the best of any run. A star is a personal
## record, and beating one should count. A flag and an army are the war's own
## state, which later missions have already been briefed and opened off.

## Facts the campaign already knows and so never stores twice: `records` owns
## what a mission was cleared with, and a copy of it in `flags` would be a second
## opinion about it. Both kinds are read through `flag`, so a condition asks
## after a cleared mission in the same words it asks after an authored fact.
const CLEARED := "cleared:"
const STARS := "stars:"

var campaign_id: StringName = &""
## Mission ids the player may start, in no particular order. Only ever added to:
## `open_mission` decides which mission the route reaches next and `complete`
## latches its answer here, so a mission that has been opened stays open whatever
## the war goes on to record.
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


## A fresh profile: the first mission the route opens, nothing cleared.
static func begin(campaign: CampaignDefinition) -> CampaignState:
	var state := CampaignState.new()
	state.campaign_id = campaign.id
	var first := state.open_mission(campaign)
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


## The mission the route is waiting on: the first one this war opens that has not
## been cleared, or "" when there is nothing left to offer (campaign-depth D7).
##
## **The route is derived and its answer is latched.** It is read fresh against
## the ledger as it stands — which is what lets a mission the war closed be walked
## past and the one after it open instead — and `complete` writes what it says
## into `unlocked`, which nothing ever removes from. A mission already unlocked
## therefore opens here whatever the war goes on to record, so conditions cannot
## close a road the player is already standing on.
##
## It only ever moves forward, starting one past the furthest mission cleared:
## everything behind that has been decided, and a fact written late must not
## re-open ground the war has gone past. `CampaignDefinition.route_error` is what
## stops that hiding an authoring slip — a mission opening on a fact no earlier
## mission writes is refused at the door rather than silently skipped forever.
func open_mission(campaign: CampaignDefinition) -> StringName:
	for index in range(_reached(campaign), campaign.missions.size()):
		var entry: MissionDefinition = campaign.missions[index]
		if entry != null and _opens(entry):
			return entry.id
	return &""


## Has the route already gone past this mission without opening it? A road not
## taken, which the hub says differently from ground nobody has reached yet.
func is_skipped(campaign: CampaignDefinition, mission_id: StringName) -> bool:
	if is_unlocked(mission_id):
		return false
	var index := campaign.index_of(mission_id)
	if index < 0:
		return false
	var waiting := open_mission(campaign)
	var frontier := campaign.index_of(waiting) if waiting != &"" else campaign.missions.size()
	return index < frontier


## How many missions this war can still offer: the list, less the roads the route
## has already walked past. The denominator every surface counting progress reads,
## so the hub and the campaign list cannot disagree about how long a war is — and
## the reason it is not `CampaignDefinition.mission_count`: a mission nobody can
## play is one a total can never reach, and a count nobody can finish is a campaign
## that always reads unfinished.
func offered_count(campaign: CampaignDefinition) -> int:
	var offered := 0
	for entry: MissionDefinition in campaign.missions:
		if entry != null and not is_skipped(campaign, entry.id):
			offered += 1
	return offered


## Where the route stands: one past the furthest mission cleared.
func _reached(campaign: CampaignDefinition) -> int:
	var reached := 0
	for index in campaign.missions.size():
		var entry: MissionDefinition = campaign.missions[index]
		if entry != null and is_cleared(entry.id):
			reached = index + 1
	return reached


func _opens(mission: MissionDefinition) -> bool:
	if is_unlocked(mission.id) or mission.unlock_requires == null:
		return true
	return mission.unlock_requires.holds(self)


## Record a clear, open the next mission and take what this one wrote to the
## ledger.
##
## The record is replaced only where the new run is better, and the two halves
## are judged **separately**: a run can beat its predecessor on stars while
## taking longer, and a player who earns a third star on day 9 should not lose
## the day-5 they already have. Unlocking is one-way for the same reason: a
## mission already open cannot be closed by a worse replay, which is why the
## route's answer is latched into `unlocked` rather than asked again everywhere.
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
	var took := tally != null and record == null
	if took:
		_take_staged_flags(tally)
	# The route is read after the ledger has taken what this mission wrote,
	# because a mission's own facts are what decide which one opens behind it.
	var next := open_mission(campaign)
	if next != &"":
		unlocked[next] = true
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


## Has the war run out of missions to offer? Only the ones the route actually
## opened count (campaign-depth D7): one it walked past is a road not taken, and a
## player who was never offered it has finished the campaign.
func is_complete(campaign: CampaignDefinition) -> bool:
	return open_mission(campaign) == &""
