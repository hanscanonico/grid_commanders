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


## Takes the board a mission opens on as its tally's baseline — a fresh board or a
## resumed one — so the first command of either is diffed against something rather
## than becoming the baseline itself.
static func open_board(game: GameState) -> void:
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
static func fire_due(battle: Battle) -> void:
	for event: MissionEvent in CampaignSession.due_events(battle.game):
		var command := MissionEventCommand.new(event, CampaignSession.mission.player_team)
		var receipt := await battle.execute_command(command)
		if receipt.rejected():
			push_error("campaign: event '%s' — %s" % [event.id, receipt.validation_error])
			continue
		CampaignSession.record_event(command)
		await battle.announce_fallen(receipt.fallen)


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
