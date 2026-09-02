class_name ProseLine
extends RefCounted
## One spoken line of campaign dialogue, with enough provenance to find it again.
##
## The loader hands back resources, not files, so nothing in the corpus carries a
## `file:line`. What it carries instead is where the line *sits in the war* —
## campaign, mission (or the block an interlude follows), which slot of that
## mission spoke it, and its index in that slot — which is what
## `tools/run_prose_check.gd` prints so an author can grep the `.tres` for the
## words and know which one of four identical-looking lines it is.
##
## A plain record: no scoring lives here. `ProseMetrics` reads `text`, and
## `ProseReport` groups on `campaign_id` / `mission_id` / `speaker`.

## The `CampaignDefinition.id` this was gathered from.
var campaign_id: StringName = &""
## The `MissionDefinition.id`, or "" for an interlude, which has no mission.
var mission_id: StringName = &""
## The block an interlude follows, or -1 for a line that belongs to a mission.
var after_block: int = -1
## Which run of words said it: "briefing", "victory", "defeat", "interlude",
## "event:<id>", or "power_quote" / "doctrine" in the commander reference corpus.
var slot: String = ""
## Position in that slot, from 0 — the only thing telling two same-speaker lines
## of one briefing apart.
var index: int = 0
## A commander id, or "" for narration.
var speaker: StringName = &""
var text: String = ""


static func of(
	p_campaign: StringName, p_mission: StringName, p_slot: String, p_index: int, line: MissionLine
) -> ProseLine:
	var prose := ProseLine.new()
	prose.campaign_id = p_campaign
	prose.mission_id = p_mission
	prose.slot = p_slot
	prose.index = p_index
	prose.speaker = line.speaker
	prose.text = line.text
	return prose


static func narration(
	p_campaign: StringName, p_mission: StringName, p_slot: String, p_text: String
) -> ProseLine:
	var prose := ProseLine.new()
	prose.campaign_id = p_campaign
	prose.mission_id = p_mission
	prose.slot = p_slot
	prose.text = p_text
	return prose


## The grouping key the worst-files table counts on: a mission, or the interlude
## page, rather than one slot of it.
func source() -> String:
	if mission_id != &"":
		return "%s/%s" % [campaign_id, mission_id]
	return "%s/interlude@%d" % [campaign_id, after_block]


## Where to look, spoken the way the report prints it.
func where() -> String:
	return "%s %s#%d" % [source(), slot, index]


## The slot a line is counted under in the per-slot table. An event's id is
## provenance rather than a kind of slot, so every `event:<id>` folds into one
## "event" row beside briefing, victory, defeat and interlude.
func slot_kind() -> String:
	return "event" if slot.begins_with("event:") else slot


## Said by a commander rather than by the narrator.
func is_spoken() -> bool:
	return speaker != &""


## Who is talking, for a per-speaker table. Narration is a voice too — it is a
## third of the corpus and the one nobody thinks to characterise — so it is
## named rather than skipped.
func voice() -> StringName:
	return speaker if is_spoken() else &"(narration)"


## The first `width` characters, on one line, for a grep-able report row. An
## authored line may carry newlines; a table row may not.
func excerpt(width: int = 40) -> String:
	var flat := " ".join(text.replace("\n", " ").split(" ", false))
	if flat.length() <= width:
		return flat
	return flat.substr(0, width - 1) + "…"
