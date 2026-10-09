class_name BattleAnalytics
extends RefCounted
## What a battle tells the web page's analytics: that a match began and how it
## ended, and inside a campaign which mission. Static like BattleCampaign — it
## owns nothing — and silent everywhere but a web export, since `Analytics` is.
##
## Every prop is an id, a count or a verdict. A board the player authored is
## reported as "custom", never by the name they saved it under.

const CUSTOM_MAP := "custom"


static func started(battle: Battle, resumed: bool, humans: int) -> void:
	var props := _match_props(battle, humans)
	props["players"] = battle.game.teams.size()
	props["humans"] = humans
	props["difficulty"] = String(battle.difficulty.id)
	props["resumed"] = resumed
	Analytics.track("match_started", props)
	if CampaignSession.active() and not resumed:
		Analytics.track("campaign_mission_started", _mission_props())


## `result` is the human side's verdict: "won", "lost", or "other" when the
## table has no single human side to give one to.
static func ended(battle: Battle, humans: int, result: String) -> void:
	var props := _match_props(battle, humans)
	props["result"] = result
	props["day"] = battle.game.day
	Analytics.track("match_ended", props)
	if CampaignSession.active() and result == "won":
		Analytics.track("campaign_mission_cleared", _mission_props())


static func _match_props(battle: Battle, humans: int) -> Dictionary:
	return {"mode": _mode(humans), "map": _map_id(battle.game.map_path)}


static func _mode(humans: int) -> String:
	if CampaignSession.active():
		return "campaign"
	match humans:
		0:
			return "spectate"
		1:
			return "skirmish"
	return "hotseat"


static func _map_id(path: String) -> String:
	if not path.begins_with("res://"):
		return CUSTOM_MAP
	return path.get_file().get_basename()


static func _mission_props() -> Dictionary:
	return {
		"campaign": String(CampaignSession.campaign_id()),
		"mission": String(CampaignSession.mission_id()),
	}
