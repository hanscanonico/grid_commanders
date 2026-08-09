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
## The pages between the blocks, in no particular order — each names the block it
## follows. A block with no interlude simply hands the player back to the hub.
@export var interludes: Array[CampaignInterlude] = []


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


## The block this mission is the last of, or -1 — where an interlude belongs.
## The mission's place in the list rather than the route's, so a player who
## replays a mission mid-block is not shown the page that closed it.
func closes_block(mission_id: StringName) -> int:
	var block := block_of(mission_id)
	if block < 0:
		return -1
	var last := -1
	for length in block_lengths.slice(0, block + 1):
		last += length
	return block if index_of(mission_id) == last else -1


## The page that follows this block, or null.
func interlude_after(block: int) -> CampaignInterlude:
	for page: CampaignInterlude in interludes:
		if page != null and page.after_block == block:
			return page
	return null


## What the war has recorded, in the words the beats that wrote it put on those
## facts — the hub's answer to "what has my war come to". Mission order, and one
## line per fact: a `note` is the author's sentence about a flag, so a fact two
## missions can write is still one thing that happened.
func ledger_notes(ledger: CampaignState) -> Array[String]:
	var notes: Array[String] = []
	var said: Dictionary[StringName, bool] = {}
	for entry: MissionDefinition in missions:
		if entry == null:
			continue
		for event: MissionEvent in entry.events:
			if event == null:
				continue
			for effect: MissionEffect in event.effects:
				var fact := effect.written_flag() if effect != null else null
				if fact == null or fact.note == "" or said.has(fact.flag):
					continue
				if ledger.flag(fact.flag) > 0:
					said[fact.flag] = true
					notes.append(fact.note)
	return notes


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
	return _interludes_error()


## Why this campaign's between-block pages could not be placed, or "". A page
## after a block the campaign does not have is one nothing ever opens, and two
## after the same block are one page nobody chose between.
func _interludes_error() -> String:
	var placed: Dictionary[int, bool] = {}
	for page: CampaignInterlude in interludes:
		if page == null:
			return "campaign '%s' holds an empty interlude slot" % id
		if page.after_block < 0 or page.after_block >= block_titles.size():
			return (
				"campaign '%s' has an interlude after block %d, and it has %d"
				% [id, page.after_block, block_titles.size()]
			)
		if placed.has(page.after_block):
			return "campaign '%s' has two interludes after block %d" % [id, page.after_block]
		placed[page.after_block] = true
	return ""


## Why this campaign's carried army could never reach the mission expecting it, or
## "". `ledger_error`'s shape at the width a chain has, and the same kind of silent
## slip: a mission that carries an army in behind one that carries none out opens
## with the map's own units and nothing to say that anything was meant to arrive.
func carry_error() -> String:
	var carried := false
	for entry: MissionDefinition in missions:
		if entry == null:
			continue
		if entry.carry_in and not carried:
			return (
				"campaign '%s': mission '%s' carries an army in and the one before it carries none out"
				% [id, entry.id]
			)
		carried = entry.carry_out
	return ""


## Why this campaign's consequence ledger could never read the way its content
## asks, or "". The campaign-wide question a mission cannot ask about itself, and
## both slips it catches are otherwise **silent**: a fact nothing writes and a
## `cleared:` / `stars:` name for a mission this campaign does not run each read
## zero forever, so the variant line simply never speaks and the gated beat never
## fires. `MissionDefinition._hidden_objectives_error`'s shape, at the width a
## ledger has.
##
## A fact written **anywhere** in the campaign answers every read of it, whatever
## route a player takes: a fact only an optional mission writes is one the reader
## is meant to tolerate reading zero, and the failure this exists for is a typo
## rather than a road not travelled. So it catches a name no mission writes at all,
## and deliberately not a name written somewhere the player never went.
func ledger_error() -> String:
	var written := _written_flags()
	for entry: MissionDefinition in missions:
		if entry == null:
			continue
		for flag: StringName in entry.read_flags():
			var error := _read_error("mission '%s'" % entry.id, flag, written)
			if error != "":
				return error
	for page: CampaignInterlude in interludes:
		if page == null:
			continue
		var where := "the interlude after block %d" % page.after_block
		for flag: StringName in page.read_flags():
			var error := _read_error(where, flag, written)
			if error != "":
				return error
	return ""


func _written_flags() -> Dictionary[StringName, bool]:
	var written: Dictionary[StringName, bool] = {}
	for entry: MissionDefinition in missions:
		if entry != null:
			for flag: StringName in entry.written_flags():
				written[flag] = true
	return written


func _read_error(where: String, flag: StringName, written: Dictionary[StringName, bool]) -> String:
	var about := CampaignState.derived_mission(flag)
	if about != &"":
		if mission(about) == null:
			return (
				"campaign '%s': %s reads '%s', and no mission of it is '%s'"
				% [id, where, flag, about]
			)
	elif not written.has(flag):
		return "campaign '%s': %s reads '%s', which no mission of it writes" % [id, where, flag]
	return ""


## Why a fact this campaign records could never read two ways, or "" — the fourth
## question that needs the whole war at once, and the one with no symptom on any
## screen: a fact every route writes the same way is not a consequence, so the
## condition reading it is not a choice. One side of a variant pair is content
## nobody can reach; the other is a line that would have played anyway.
##
## A beat varies a fact when it waits for anything the player decides. What it
## cannot vary is a beat waiting only on the calendar, at a day the mission's own
## par allows — every player who takes par records it, and only one who beats par
## does not. A beat on a **route-gated** mission is left alone for `ledger_error`'s
## reason: a road the player may decline is the ordinary shape of a fact that
## sometimes goes unwritten.
func constant_fact_error() -> String:
	var varying: Dictionary[StringName, bool] = {}
	var written: Array[StringName] = []
	for entry: MissionDefinition in missions:
		if entry == null:
			continue
		var optional := entry.unlock_requires != null
		for event: MissionEvent in entry.events:
			if event == null:
				continue
			for flag: StringName in event.written_flags():
				written.append(flag)
				if optional or not _certain(event, entry):
					varying[flag] = true
	var read := _flag_readers()
	for flag: StringName in written:
		if varying.has(flag) or not read.has(flag):
			continue
		return (
			"campaign '%s': '%s' reads the same on every route, and %s asks it as if it could differ"
			% [id, flag, read[flag]]
		)
	return ""


## Whether this beat fires for every player who takes the mission at par. Only
## `DayReached` can be answered without a board, which is exactly the point: any
## other condition is something the player did or did not do.
static func _certain(event: MissionEvent, mission: MissionDefinition) -> bool:
	if event.triggers.is_empty():
		return false
	for trigger: MissionTrigger in event.triggers:
		if not (trigger is DayReachedTrigger):
			return false
		if (trigger as DayReachedTrigger).day > maxi(1, mission.par_day):
			return false
	return true


## Every fact some condition of this campaign reads, and the first place reading
## it — the half of `ledger_error`'s walk that names where, so a constant fact can
## say which line believed it was a variant.
func _flag_readers() -> Dictionary[StringName, String]:
	var readers: Dictionary[StringName, String] = {}
	for entry: MissionDefinition in missions:
		if entry != null:
			for flag: StringName in entry.read_flags():
				if not readers.has(flag):
					readers[flag] = "mission '%s'" % entry.id
	for page: CampaignInterlude in interludes:
		if page != null:
			for flag: StringName in page.read_flags():
				if not readers.has(flag):
					readers[flag] = "the interlude after block %d" % page.after_block
	return readers


## Why a block of this campaign could close without its page, or "".
##
## `closes_block` names the block's last mission structurally, so an interlude is
## shown by winning that one mission and by nothing else (campaign-depth CD6).
## Gate it and a player the route sends past it never sees the page — the block
## simply ends, with the war's own summary of it unspoken and nothing anywhere
## saying so.
func block_error() -> String:
	for entry: MissionDefinition in missions:
		if entry == null or entry.unlock_requires == null:
			continue
		var block := closes_block(entry.id)
		if block >= 0 and interlude_after(block) != null:
			return (
				"campaign '%s': mission '%s' closes block %d and opens on a condition, so its page is optional"
				% [id, entry.id, block]
			)
	return ""


## Why a mission of this campaign could never open, or "" — campaign-depth D7's
## own check, and the third question that needs the whole war at once.
##
## The route walks the list forward and stops at the first mission whose
## condition holds, so a condition asking for a fact no **earlier** mission
## writes is a mission the route passes every time, on every route. Silent
## otherwise: the campaign simply plays without it and nothing says so.
##
## Only the floor is held to that. A condition asking for a fact to be *absent*
## is the ordinary shape of the road not taken, and a fact only an optional
## mission writes is a road the player may decline rather than an authoring slip
## — which is `ledger_error`'s rule read at the width the route has.
func route_error() -> String:
	var behind: Dictionary[StringName, bool] = {}
	for index in missions.size():
		var entry := missions[index]
		if entry == null:
			continue
		var gate := entry.unlock_requires
		if gate != null and gate.at_least > 0:
			var error := _gate_error(entry.id, index, gate.flag, behind)
			if error != "":
				return error
		for flag: StringName in entry.written_flags():
			behind[flag] = true
	return ""


func _gate_error(
	mission_id: StringName, index: int, flag: StringName, behind: Dictionary[StringName, bool]
) -> String:
	var about := CampaignState.derived_mission(flag)
	if about != &"":
		var at := index_of(about)
		if at >= 0 and at < index:
			return ""
		return (
			"campaign '%s': mission '%s' opens on '%s', which is not behind it"
			% [id, mission_id, flag]
		)
	if behind.has(flag):
		return ""
	return (
		"campaign '%s': mission '%s' opens on '%s', which no mission before it writes"
		% [id, mission_id, flag]
	)
