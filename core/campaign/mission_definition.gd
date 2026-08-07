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


## Why this mission could never be played or won, or "". Checked at load so an
## authoring slip — a board that does not seat the player, a relay that is not a
## property — is loud at the door instead of silent in the middle of an act.
func definition_error(map: MapData) -> String:
	if id == &"":
		return "mission has no id"
	if map_path == "":
		return "mission '%s' names no map" % id
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
	if objectives.is_empty() and failures.is_empty():
		return "mission '%s' can be neither won nor lost by objective" % id
	for objective: MissionObjective in objectives + failures + bonus_objectives:
		if objective == null:
			return "mission '%s' holds an empty objective slot" % id
		var error := objective.definition_error(map, player_team)
		if error != "":
			return "mission '%s': %s" % [id, error]
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
func story_error(commander_db: CommanderDB) -> String:
	for line: MissionLine in briefing + victory:
		if line == null:
			return "mission '%s' holds an empty story line" % id
		var error := line.definition_error(commander_db)
		if error != "":
			return "mission '%s': %s" % [id, error]
	return ""
