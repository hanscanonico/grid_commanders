class_name BattleRecording
extends RefCounted
## How a played match records itself: which slot it claims, what the replay menu
## calls it, and — inside a campaign — which mission's script its scripted beats
## belong to.
##
## Static like BattleCampaign, and for the same reason: it owns nothing. The
## recorder it hands back is the pipeline's to feed and Battle's to close.

## What a label joins the board to the table with. One statement, because the
## replays page reads a stored label back at it to set the two on two lines.
const LABEL_SEPARATOR := " · "


## Opens this match's recording, or null when there is nothing to record.
##
## `wanted` is Battle's own answer to whether there is: false for a playback,
## which is already a recording, and false for a capture run, whose scenarios
## would fill the player's ten slots with matches nobody played. The slot itself
## is claimed by the first command rather than here, so a match nobody played
## evicts none of the ten somebody did — see ReplayRecorder.
static func open(battle: Battle, wanted: bool) -> ReplayRecorder:
	if not wanted:
		return null
	# Sortable, and that is the whole of why the slot is named by a clock: the
	# directory then lists chronologically without reading a single file.
	var started := Time.get_datetime_string_from_system()
	var slot := started.replace(":", "-")
	var recorder := ReplayRecorder.new(func() -> ReplayFile: return ReplayFile.open_slot(slot))
	# The mission pair is empty for a skirmish and is what a recorded scripted beat
	# is resolved against on the way back, a `SaveCodec` opening naming no campaign.
	recorder.begin(
		battle.game,
		battle.ai_teams,
		battle.difficulty.id,
		_label(battle),
		started,
		CampaignSession.campaign_id(),
		CampaignSession.mission_id()
	)
	return recorder


## What the replay menu calls this match: the board, and who was at the table.
static func _label(battle: Battle) -> String:
	var sides := PackedStringArray()
	for team in battle.game.teams:
		sides.append(battle.view.identity.display_name(team))
	var board := MapCatalog.display_name(battle.game.map_path)
	return "%s%s%s" % [board, LABEL_SEPARATOR, " vs ".join(sides)]
