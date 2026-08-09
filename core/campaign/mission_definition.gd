class_name MissionDefinition
extends Resource
## One authored battle: the board it is fought on, who sits at its table, what
## wins it, what loses it, and the words around it.
##
## The match half of this is deliberately **`MatchRequest`'s field list, not the
## architecture plan's**. That plan predates four-army play, so its
## `player_team` / `ai_teams` pair cannot say "seats 1 and 3 play, 1 stands with
## 3" — and a mission that cannot state its own match is a mission the campaign
## cannot launch. `to_request()` below is the one conversion, so the campaign
## never assembles a launch a second way.
##
## Everything balance-shaped lives on the `.tres`, not here: starting armies are
## the map file's, and difficulty is a tier id rather than a tuned profile.

## Stable id, unique within a campaign; what a save records as "where I am".
@export var id: StringName = &""
@export var title: String = ""
## The place, shown under the title on the briefing card. Flavour, not a key.
@export var location: String = ""
@export var map_path: String = ""
## How the war has to read for this mission to open at all, or null for one every
## player plays (campaign-depth D7). The campaign's order is still the list's —
## this only says whether the route stops here or walks past. `at_most: 0` is the
## other route of a fork; a floor is a mission an earlier one earned.
@export var unlock_requires: FlagCondition

@export_group("The table")
## The army the human plays. Every objective is read from this seat's side.
@export var player_team: int = 1
## Seats the computer plays. Every other seated army is a human's, which in a
## campaign means only `player_team`.
@export var ai_teams: Array[int] = [2]
## Which of the board's seats play at all; empty means every seat it deals.
## A four-seat board runs a duel by naming two.
@export var seats: Array[int] = []
## Who stands with whom, as `team -> side`. Empty is a free-for-all, which is
## what every duel is.
@export var sides: Dictionary = {}
## `team -> commander id`. The story's casting; a seat with no entry plays the
## neutral commander.
@export var commanders: Dictionary = {}
@export var fog_enabled := false
## A shipped tier id (`easy` / `normal` / `difficult`), never a tuned profile —
## a campaign that shipped its own AI numbers would be balancing the planner
## through the back door.
@export var difficulty: StringName = Difficulty.DEFAULT_ID

@export_group("Winning and losing")
## Every one of these must be satisfied at once for the mission to be won.
## Empty means the mission is won only by ordinary tactical victory.
@export var objectives: Array[MissionObjective] = []
## Any one of these ends the mission in defeat. A deadline lives here.
@export var failures: Array[MissionObjective] = []
## Optional extras that earn a star each without being required to finish.
@export var bonus_objectives: Array[MissionObjective] = []
## The day count a perfect run is expected to finish inside; 0 disables the
## speed star.
@export var par_day: int = 0

@export_group("The script")
## The beats that happen during the fight, in the order they are due: each waits
## for its own conditions, speaks its own lines and changes the board through
## `MissionEventCommand`. Empty is a mission nothing happens in, which is every
## mission this vocabulary was written for.
@export var events: Array[MissionEvent] = []

@export_group("The carried army")
## Whether the army the war remembers stands in this board's carry slots
## (campaign-depth D6). False is the ordinary answer and the one a change of
## commander forces: the map's own units stand and the mission opens exactly as it
## was authored.
@export var carry_in := false
## Whether what survives this mission is what the next one carries. False ends the
## chain — the war forgets the army, which is what handing the front to another
## general means.
@export var carry_out := false
## The HP a carried unit is refit to at minimum before it deploys. The author's
## answer to "the campaign is unwinnable because mission six went badly": 0 refits
## nothing and a veteran lands exactly as it stood.
@export_range(0, Unit.MAX_HP) var carry_floor_hp := 0

@export_group("Story")
## What is said before the battle and after it is won, as lines with speakers —
## a campaign is a conversation between the generals fighting it. A line with no
## speaker is narration.
@export var briefing: Array[MissionLine] = []
@export var victory: Array[MissionLine] = []
## One narrator's sentence on a loss. Not dialogue: a defeat is the only beat
## nobody in the fiction is present to comment on.
@export_multiline var defeat: String = ""


## The launch this mission is, stated once. `BattleSetup` reads this exactly as
## it reads a menu launch, so a mission boots through the shipped path rather
## than a campaign-only one.
func to_request() -> MatchRequest:
	var request := MatchRequest.new()
	request.map_path = map_path
	request.ai_teams = ai_teams.duplicate()
	request.seats = seats.duplicate()
	request.sides = sides.duplicate()
	request.commanders = commanders.duplicate()
	request.fog_enabled = fog_enabled
	request.difficulty = difficulty
	return request


## The scripted beat with this id, or null. `CampaignDefinition.mission`'s shape,
## and it exists for the same reason: a replay line names an event by id, because
## a reference is not something a recording can carry.
func event(event_id: StringName) -> MissionEvent:
	for entry: MissionEvent in events:
		if entry != null and entry.id == event_id:
			return entry
	return null


## Every fact this mission reads the war for: the condition it opens on, the
## conditions on its variant story lines, and the `Flag` triggers on its beats.
## Its beats' lines carry none — `story_error` refuses them there — so the story
## half is the briefing and the victory dialogue.
##
## Gathered rather than judged here, because whether the campaign ever writes a
## name is the one question a mission cannot ask about itself.
func read_flags() -> Array[StringName]:
	var read: Array[StringName] = []
	if unlock_requires != null:
		read.append(unlock_requires.flag)
	for line: MissionLine in briefing + victory:
		if line == null:
			continue
		for condition: FlagCondition in line.conditions():
			read.append(condition.flag)
	for event: MissionEvent in events:
		if event != null:
			read.append_array(event.read_flags())
	return read


## Every fact this mission's beats write to the war. The other half of the same
## question, and the reason it is not `written_flag` singular: a mission writes the
## war from as many beats as it has.
func written_flags() -> Array[StringName]:
	var written: Array[StringName] = []
	for event: MissionEvent in events:
		if event != null:
			written.append_array(event.written_flags())
	return written


## Why this mission could never be played or won, or "". Checked at load so an
## authoring slip — a board that does not seat the player, a relay that is not a
## property — is loud at the door instead of silent in the middle of an act.
func definition_error(map: MapData, unit_db: UnitDB) -> String:
	if id == &"":
		return "mission has no id"
	if map_path == "":
		return "mission '%s' names no map" % id
	if unlock_requires != null:
		var gate_error := unlock_requires.definition_error()
		if gate_error != "":
			return "mission '%s' opens on %s" % [id, gate_error]
	var table_error := _table_error(map)
	if table_error != "":
		return table_error
	if objectives.is_empty() and failures.is_empty():
		return "mission '%s' can be neither won nor lost by objective" % id
	for objective: MissionObjective in objectives + failures + bonus_objectives:
		if objective == null:
			return "mission '%s' holds an empty objective slot" % id
		var error := objective.definition_error(map, player_team, unit_db)
		if error != "":
			return "mission '%s': %s" % [id, error]
	var script_error := _events_error(map, unit_db)
	if script_error != "":
		return script_error
	var ids_error := _objective_ids_error()
	if ids_error != "":
		return ids_error
	var hidden_error := _hidden_objectives_error()
	if hidden_error != "":
		return hidden_error
	return _carry_error(map)


## Why the board could not seat the table this mission states, or "". A seat the
## board never deals and a seat given to both sides at once are the same slip in
## two directions, so they are asked in one place.
func _table_error(map: MapData) -> String:
	var roster := seats if not seats.is_empty() else map.teams()
	if not roster.has(player_team):
		return (
			"mission '%s' seats %s, which leaves out the player's team %d"
			% [id, roster, player_team]
		)
	for team: int in ai_teams:
		if not roster.has(team):
			return (
				"mission '%s' gives the computer team %d, off its seating %s" % [id, team, roster]
			)
	if ai_teams.has(player_team):
		return "mission '%s' gives the player's team %d to the computer" % [id, player_team]
	return ""


## Why this mission's scripted beats could not play, or "". Ids are unique
## because the fired set records them: two events called the same thing are one
## event that fires once.
##
## The names its beats give the units they land are counted **across the whole
## script and against the board's own units**, because that is the width of what
## a tag promises: `UnitTag` is the authority and a tag naming two units names
## neither — an objective watching one has two answers, and `SaveCodec` refuses
## the mid-mission save outright, which costs the player the mission they are in.
func _events_error(map: MapData, unit_db: UnitDB) -> String:
	var seen: Dictionary[StringName, bool] = {}
	var named := MissionObjective.board_tags(map)
	for event: MissionEvent in events:
		if event == null:
			return "mission '%s' holds an empty event slot" % id
		if seen.has(event.id):
			return "mission '%s' has two events called '%s'" % [id, event.id]
		seen[event.id] = true
		var error := event.definition_error(map, player_team, unit_db)
		if error != "":
			return "mission '%s': %s" % [id, error]
		named.append_array(event.spawned_tags())
	var tag_error := UnitTag.duplicate_error(named)
	if tag_error != "":
		return "mission '%s': %s" % [id, tag_error]
	return ""


## Why this mission's objective ids could not be recorded, or "". An id is a save
## key — `MissionProgress` writes the revealed set under it — so it is held to
## exactly what a counter key may be, and two objectives cannot share one: a
## reveal names a single objective, and the mission whose second one came live
## with it is a mission nobody authored.
func _objective_ids_error() -> String:
	var seen: Dictionary[StringName, bool] = {}
	for objective: MissionObjective in objectives + failures + bonus_objectives:
		if objective.id == &"":
			continue
		var key_error := MissionProgress.name_error(objective.id)
		if key_error != "":
			return "mission '%s': objective id %s" % [id, key_error]
		if seen.has(objective.id):
			return "mission '%s' has two objectives called '%s'" % [id, objective.id]
		seen[objective.id] = true
	return ""


## Why this mission's hidden objectives could never come out of hiding, or "".
##
## Both halves are authoring slips with no other symptom: a hidden objective
## nothing reveals is a mission that cannot be won, and a reveal naming nothing
## is a beat that plays and changes nothing anybody can see.
func _hidden_objectives_error() -> String:
	var hidden_ids: Dictionary[StringName, bool] = {}
	for objective: MissionObjective in objectives + failures + bonus_objectives:
		if not objective.hidden:
			continue
		if objective.id == &"":
			return "mission '%s' hides an objective that has no id" % id
		hidden_ids[objective.id] = false
	for event: MissionEvent in events:
		for effect: MissionEffect in event.effects:
			var revealed := effect.revealed_objective()
			if revealed == &"":
				continue
			if not hidden_ids.has(revealed):
				return (
					"mission '%s': event '%s' reveals '%s', which is not a hidden objective of it"
					% [id, event.id, revealed]
				)
			hidden_ids[revealed] = true
	for objective_id: StringName in hidden_ids:
		if not hidden_ids[objective_id]:
			return "mission '%s' hides '%s' and no event reveals it" % [id, objective_id]
	return ""


## Why this mission's carried army could not land, or "". Three authoring slips
## with no other symptom, because a slot that is never filled looks exactly like a
## board opening as authored: a floor no unit could be refit to, a carry mark on
## another army's row — the roster is the player's, so nothing will ever stand
## there — and a mission that carries the war's army in onto a board with nowhere
## to put it.
func _carry_error(map: MapData) -> String:
	if carry_floor_hp < 0 or carry_floor_hp > Unit.MAX_HP:
		return "mission '%s' refits a carried unit to %d HP" % [id, carry_floor_hp]
	var slots := 0
	for entry: Dictionary in map.starting_units:
		if not entry.carry:
			continue
		if entry.team != player_team:
			return (
				"mission '%s': the carry slot at %s is team %d's, not the player's"
				% [id, entry.cell, entry.team]
			)
		slots += 1
	if carry_in and slots == 0:
		return "mission '%s' carries an army in and its board has no carry slot" % id
	return ""


## Why this mission could not be launched at the tier it names, or "". Split out
## because `DifficultyDB.by_id` falls back to Normal for an unknown id rather
## than failing — which is right for a save naming a retired tier, and silent
## for a mission whose author typed the tier's name wrong. Thirty missions
## claimed a tier that does not exist and played at Normal without a word.
func difficulty_error(difficulty_db: DifficultyDB) -> String:
	if not difficulty_db.has(difficulty):
		return "mission '%s' asks for tier '%s', which does not exist" % [id, difficulty]
	return ""


## Why a line of this mission's story could not be spoken, or "". Split from
## `definition_error` because it needs the roster and that one needs the board,
## and a caller holding only one of them should still be able to ask.
##
## An event's lines are held to the same bar as the briefing's — they are spoken
## by the same drawer, so a speaker nobody has heard of is the same slip in both.
## What a beat's lines may **not** carry is a ledger condition: a recording
## re-issues the beat and has to speak the same words, so a beat the war decides
## is a beat with a `Flag` trigger.
func story_error(commander_db: CommanderDB) -> String:
	var error := MissionLine.list_error(briefing + victory, commander_db, true)
	if error != "":
		return "mission '%s': %s" % [id, error]
	for event: MissionEvent in events:
		if event == null:
			return "mission '%s' holds an empty event slot" % id
		error = MissionLine.list_error(event.lines, commander_db, false)
		if error != "":
			return "mission '%s': event '%s': %s" % [id, event.id, error]
	return ""
