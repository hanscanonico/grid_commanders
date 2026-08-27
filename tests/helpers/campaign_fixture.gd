class_name CampaignFixture
extends RefCounted
## The war a test plays through, in one call: `CampaignFixture.campaign(&"probe", missions)`.
##
## `Fixture` retired the same duplication for boards. The campaign half never
## got it: fifteen suites carried a `_mission()` and ten a `_campaign()`, whose
## bodies were the same six lines — `res://maps/first_steps.txt`, `player_team`
## 1, a `CaptureCellObjective` at the origin — and differed only in whether the
## objective was appended and whether the id was a parameter.
##
## Node-free like `Fixture`, so it is a `RefCounted` with statics and no scene.
##
## `mission` and `capture_mission` are two functions rather than one with a
## flag because both shapes are wanted: a route or an interlude suite is about
## the order missions are offered in and builds objective-less missions on
## purpose, while a ledger or roster suite needs one a match can actually win.

const MAP_PATH := "res://maps/first_steps.txt"


## A mission with no objective — enough to be offered, ordered and gated.
static func mission(id: StringName, map_path: String = MAP_PATH) -> MissionDefinition:
	var definition := MissionDefinition.new()
	definition.id = id
	definition.title = String(id)
	definition.map_path = map_path
	definition.player_team = 1
	return definition


## `mission`, plus the one capture objective that makes it winnable.
static func capture_mission(id: StringName, cell: Vector2i = Vector2i(0, 0)) -> MissionDefinition:
	var definition := mission(id)
	var objective := CaptureCellObjective.new()
	objective.cell = cell
	definition.objectives.append(objective)
	return definition


## A campaign offering `missions` in the order they are given.
static func campaign(id: StringName, missions: Array[MissionDefinition]) -> CampaignDefinition:
	var definition := CampaignDefinition.new()
	definition.id = id
	definition.title = String(id)
	for entry: MissionDefinition in missions:
		definition.missions.append(entry)
	return definition
