class_name DialogueCast
extends RefCounted
## Who says a spoken beat and where on the board each voice stands — what the
## 3D board's cinematic frames. The flat card needs only the words; a cinematic
## needs a place for every voice, and that is a question about the match, which
## the 3D board never asks (it is a view of the flat board, never of the sim).
## So the battle answers it here and hands the answer over.
##
## Fog holds as it does on the board: a general is framed at their HQ, ground
## everybody can see, or failing that among what the viewer can see of their
## army — never at a unit the viewer cannot see.

const NOWHERE := Vector2i(-1, -1)

var lines: Array[MissionLine] = []
var commanders: CommanderDB
## Commander id → the cell that general is framed at.
var posts: Dictionary[StringName, Vector2i] = {}
## What the beat put on the board that the viewer can see — units it landed, the
## ground of an objective it revealed — for the narrator to look at.
var subject: Array[Vector2i] = []
## The viewer's own post, where a voice with no seat on this board is heard.
var home := NOWHERE
## Waits for a press after each line rather than timing out: the briefing, read
## again because the player asked for it.
var untimed := false


static func of_lines(battle: Battle, spoken: Array[MissionLine]) -> DialogueCast:
	var cast := DialogueCast.new()
	cast.lines = spoken
	cast.commanders = battle.commander_db
	for team in battle.game.teams:
		var commander := battle.game.commander_of(team)
		if commander == null or cast.posts.has(commander.id):
			continue
		var post := post_of(battle, team)
		if post != NOWHERE:
			cast.posts[commander.id] = post
	cast.home = post_of(battle, battle.perspective.viewing_team())
	return cast


## A scripted beat's words, with what it put on the board as the subject.
static func of_beat(battle: Battle, command: MissionEventCommand) -> DialogueCast:
	var cast := of_lines(battle, command.event.lines)
	var landed := command.event.spawned_tags()
	for unit in battle.game.units:
		if unit.tag != &"" and landed.has(unit.tag) and battle.perspective.can_see_unit(unit):
			cast.subject.append(unit.cell)
	if CampaignSession.active():
		var mission := CampaignSession.mission
		for objective: MissionObjective in mission.objectives + mission.bonus_objectives:
			if objective != null and command.revealed.has(objective.id):
				cast.subject.append_array(objective.marker_cells())
	return cast


## The briefing, said again at the player's asking.
static func of_briefing(battle: Battle, spoken: Array[MissionLine]) -> DialogueCast:
	var cast := of_lines(battle, spoken)
	cast.untimed = true
	return cast


## The cell `team`'s general is framed at: their home HQ, or the unit of theirs
## the viewer can see nearest the middle of all of them; NOWHERE when neither.
## The home HQ rather than any HQ they own now: a living army always holds its
## home, while an HQ taken in the fog still shows its last-seen owner.
static func post_of(battle: Battle, team: int) -> Vector2i:
	if battle.game.home_hq.has(team) and not battle.game.is_eliminated(team):
		return battle.game.home_hq[team]
	var seen: Array[Vector2i] = []
	for unit in battle.game.units_of(team):
		if battle.perspective.can_see_unit(unit):
			seen.append(unit.cell)
	if seen.is_empty():
		return NOWHERE
	var middle := Vector2.ZERO
	for cell in seen:
		middle += Vector2(cell)
	middle /= seen.size()
	var nearest := seen[0]
	for cell in seen:
		if Vector2(cell).distance_squared_to(middle) < Vector2(nearest).distance_squared_to(middle):
			nearest = cell
	return nearest
