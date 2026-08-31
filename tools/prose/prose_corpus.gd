class_name ProseCorpus
extends RefCounted
## Every word the campaigns say aloud, gathered off the shipped resources.
##
## Walks what `CampaignDB.load_default()` already loads — no directory scan, no
## second list of missions to drift out of date — so the corpus is exactly the
## dialogue the game plays: each mission's briefing, its victory debrief, its one
## narrator's defeat sentence and every scripted beat's lines, plus each
## interlude page between two blocks.
##
## **Every authored variant is gathered, not the route's.** `MissionLine.spoken`
## filters by the ledger for a player; a measurement of the writing wants the
## line nobody's route reached as much as the one everybody hears.
##
## `MissionObjective.text` is deliberately excluded. Objective wording is a
## convention `docs/campaign_authoring.md` owns — an imperative fragment, not a
## sentence somebody says — and scoring it would report the convention as slop.
##
## The commander corpus (`commander_lines`) is gathered separately and is not
## campaign dialogue: power quotes and doctrine blurbs are single-beat lines
## written to a different brief, so they are the control the campaign numbers are
## read against rather than rows in the same table.

## The commander lines are held under one pseudo-campaign id so a report row can
## say where they came from without inventing a war.
const REFERENCE_ID := &"(commanders)"


## Every spoken line of every shipped campaign, in authoring order.
static func gather(db: CampaignDB) -> Array[ProseLine]:
	var lines: Array[ProseLine] = []
	for campaign: CampaignDefinition in db.all():
		for mission: MissionDefinition in campaign.missions:
			_gather_mission(lines, campaign.id, mission)
		for page: CampaignInterlude in campaign.interludes:
			_gather_interlude(lines, campaign.id, page)
	return lines


## The control corpus: what the commanders say outside a war. Scored by the same
## metrics and reported apart, because a power quote is *meant* to be one
## aphorism and would otherwise top every worst-N list on that alone.
static func commander_lines(commander_db: CommanderDB) -> Array[ProseLine]:
	var lines: Array[ProseLine] = []
	for commander: CommanderType in commander_db.all():
		if commander.doctrine_text.strip_edges() != "":
			var doctrine := ProseLine.narration(
				REFERENCE_ID, commander.id, "doctrine", commander.doctrine_text
			)
			doctrine.speaker = commander.id
			lines.append(doctrine)
		for i in commander.power_quotes.size():
			var quote := ProseLine.narration(
				REFERENCE_ID, commander.id, "power_quote", commander.power_quotes[i]
			)
			quote.speaker = commander.id
			quote.index = i
			lines.append(quote)
	return lines


## The corpus narrowed to one campaign and/or one speaker, as the report's
## `--campaign=` and `--speaker=` flags ask for it. An empty filter keeps
## everything, so a caller passes what it was given rather than branching.
static func narrow(lines: Array[ProseLine], campaign: String, speaker: String) -> Array[ProseLine]:
	var kept: Array[ProseLine] = []
	for line: ProseLine in lines:
		if campaign != "" and String(line.campaign_id) != campaign:
			continue
		if speaker != "" and String(line.voice()) != speaker:
			continue
		kept.append(line)
	return kept


static func _gather_mission(
	lines: Array[ProseLine], campaign_id: StringName, mission: MissionDefinition
) -> void:
	_gather_slot(lines, campaign_id, mission.id, "briefing", mission.briefing)
	_gather_slot(lines, campaign_id, mission.id, "victory", mission.victory)
	if mission.defeat.strip_edges() != "":
		lines.append(ProseLine.narration(campaign_id, mission.id, "defeat", mission.defeat))
	for event: MissionEvent in mission.events:
		if event == null:
			continue
		_gather_slot(lines, campaign_id, mission.id, "event:%s" % event.id, event.lines)


static func _gather_interlude(
	lines: Array[ProseLine], campaign_id: StringName, page: CampaignInterlude
) -> void:
	for i in page.lines.size():
		var line: MissionLine = page.lines[i]
		if line == null:
			continue
		var prose := ProseLine.of(campaign_id, &"", "interlude", i, line)
		prose.after_block = page.after_block
		lines.append(prose)


static func _gather_slot(
	lines: Array[ProseLine],
	campaign_id: StringName,
	mission_id: StringName,
	slot: String,
	said: Array[MissionLine]
) -> void:
	for i in said.size():
		var line: MissionLine = said[i]
		if line != null:
			lines.append(ProseLine.of(campaign_id, mission_id, slot, i, line))
