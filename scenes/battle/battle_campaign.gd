class_name BattleCampaign
extends RefCounted
## This battle's side of being part of a campaign: the launch a mission capture
## stages, the board a mission's tally counts from, and the mission's verdict on a
## committed command. Battle keeps the flow — which interaction state a verdict
## leads to is still its call — and still holds no mission field of its own.
##
## Static where its sibling collaborators are constructed, because it owns
## nothing: the mission lives on `CampaignSession` and the card on `BattleView`,
## so an instance would hold only a back-reference. Every entry here is silent
## outside a campaign, which is what leaves a skirmish on the code it ran before
## campaigns existed.


## Stages a mission capture's own launch, before Battle asks `MatchConfig` for a
## request. A campaign board is not in the map catalogue, so no `--map=` can name
## one and the capture deploys the way the hub does; inert for every other run.
static func stage() -> void:
	BattleMissionScenario.stage()


## Opens the board a mission is played on: the army the war remembers stands in
## the board's carry slots, and the tally takes what results as its baseline — so
## the first command of either a fresh board or a resumed one is diffed against
## something rather than becoming the baseline itself.
##
## `fresh` is false for a **resumed** mission, whose board is the one the player
## left: its carry slots were filled when it first opened and its units are
## wherever the fight has since put them, so standing the war's army on it again
## would deploy onto a board that has already been played.
static func open_board(game: GameState, fresh: bool) -> void:
	if fresh:
		CampaignSession.deploy_army(game)
	CampaignSession.open_board(game)


## Fires every scripted beat the board is now due, in the order the mission lists
## them, and lets each say its piece before the next one lands (campaign-depth
## D3). Silent for every skirmish.
##
## Each beat is a `MissionEventCommand` through `Battle.execute_command` — the one
## live broker a click and a plan already reach (D1) — so it lands in the log, the
## save and the replay with no special case, and its dialogue is the *command's*
## presentation rather than something this layer draws.
##
## **It cannot re-enter.** `conclude_command` is what calls this and this never
## calls `conclude_command`, so a beat's own command settles inside the pipeline
## and opens no second round of firing; the board is read once per boundary, which
## is `CampaignSession.due_events`' own rule.
##
## Called from the two boundaries a mission has: after every committed command,
## and on the board the mission opens on. That second one is the only boundary
## with no command behind it — the day turns *inside* `EndTurnCommand`, so a beat
## waiting for day five is already due when that command settles — and it is what
## "at the opening", `DayReached { day: 1 }`, is written against.
##
## An army felled by a scripted removal is announced exactly as one felled by a
## shot, and from here rather than back in `conclude_command`, because the banner
## has to land on the board that emptied the seat.
##
## A beat an earlier one of the batch ended the match on is moot rather than
## wrong — the board was read before it was decided, and `MissionEventCommand`
## refuses a decided board by design — so the batch stops there. What is left
## rejected is a beat no board could carry, which is an authoring fault and is
## said out loud.
static func fire_due(battle: Battle) -> void:
	for event: MissionEvent in CampaignSession.due_events(battle.game):
		if battle.game.winner != 0:
			return
		var command := MissionEventCommand.new(event, CampaignSession.mission.player_team)
		var receipt := await battle.execute_command(command)
		if receipt.rejected():
			push_error("campaign: event '%s' — %s" % [event.id, receipt.validation_error])
			continue
		CampaignSession.record_event(command)
		await battle.announce_fallen(receipt.fallen)


## Repaints the mission's marks. Rides the fog pass, which is the one that already
## reruns after every committed command and turn change — and what the mission
## still wants changes exactly there, when ground turns over or a beat reveals an
## objective.
static func refresh_marks(battle: Battle) -> void:
	battle.overlays.show_objective_marks(objective_cells(battle.game))


## Every square this mission still wants, for the board to ring. Empty for a
## skirmish, so a match outside a campaign paints nothing.
##
## Live objectives only, asked of `is_live` — the same authority the card prints
## through, so a held-back objective is no more marked on the board than it is
## named on the card — and **unmet** ones only, because a target already taken is
## a ring the player has to learn to ignore. Primary and bonus alike: a bonus is
## ground you have to find as much as the main goal is. Failures name no ground.
##
## Deliberately unfogged. What the mission is about is public — the briefing says
## it, the card says it — so hiding the square behind ground nobody has scouted
## would withhold the one thing the player was told, not a thing they must
## discover. The same reading fog gets everywhere else: it costs you what is
## *standing* there, never what you were told to go and take.
static func objective_cells(game: GameState) -> Array[Vector2i]:
	if not CampaignSession.active():
		return []
	var mission := CampaignSession.mission
	var tally := CampaignSession.tally
	var cells: Array[Vector2i] = []
	for objective: MissionObjective in mission.objectives + mission.bonus_objectives:
		if objective == null or not objective.is_live(tally):
			continue
		if objective.is_met(game, mission.player_team, tally):
			continue
		for cell in objective.marker_cells():
			if not cells.has(cell):
				cells.append(cell)
	return cells


## The words this mission opened with, for the pause menu to say again. Empty for
## a skirmish, so the row that asks for them is offered nowhere else.
##
## Read through `MissionLine.spoken` against the ledger, which is the same walk
## the hub's briefing card makes: a briefing that reads differently after a
## different mission five has to read that way here too (campaign-depth D5), and a
## second walk over the conditions is a second answer to what was said.
static func briefing_lines() -> Array[MissionLine]:
	if not CampaignSession.active():
		return []
	return MissionLine.spoken(CampaignSession.mission.briefing, CampaignSession.progress)


## Says those words again over the board, at the player's asking from the pause
## menu. Presentation from end to end: no command is issued, nothing under `core/`
## learns it happened, and a skirmish never gets here, its menu offering no such
## row.
##
## ANIMATING for as long as the card is up, because the board behind it is the
## player's own and a briefing they stopped to read must not also be a board they
## can act on. `rest_state()` is what hands it back, so a briefing read from a
## paused computer turn returns to that paused turn.
static func say_briefing(battle: Battle) -> void:
	battle.state = Battle.State.ANIMATING
	await battle.animator.speak_until_dismissed(briefing_lines(), battle.commander_db)
	battle.state = battle.rest_state()


## Whether the mission just ended, and false for every skirmish — which is what
## leaves a match outside a campaign unchanged. Its answer outranks the receipt's
## own winner, and it is asked after the fallen-army banner and before the turn
## hands over, because the tally advances here and a condition asking how long the
## ridge has been ours is about this board (campaign-depth D3).
##
## The redraw belongs to the same seam: the pipeline drew the HUD before the tally
## moved, so the objective card is a board behind unless `start_turn` is about to
## draw it again — and the victory lockup leaves the card on screen beside it.
static func decide(battle: Battle, receipt: BattleCommandReceipt) -> bool:
	if not CampaignSession.active():
		return false
	var over := CampaignSession.decide(battle.game)
	if over or not receipt.turn_changed:
		battle.refresh_hud()
	return over
