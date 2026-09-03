extends GutTest
## Every shipped mission, played with its own script live.
##
## The bar is **legality**, not winnability: a seeded opening, every army played
## by its own planner, and every beat that comes due firing at the boundary the
## live scene fires it at — with no command refused, by the board or by the
## mission, and no stall. **A mission reaching a verdict here says nothing about a
## player being able to win it**, and that sentence is the whole reason this file
## exists. The scratch tool it replaces reported the same fact as
## `never-decided=0`, which reads like a winnability check; it was played with no
## campaign session at all, so not one scripted beat fired in it and five missions
## it called decided cannot be cleared with their script live.
##
## It plays through `BattleSetup.build(mission.to_request())` and drives
## `CampaignSession` itself rather than reimplementing either — the boundary order
## is `BattleCampaign`'s (apply, then the beats due, then the verdict), and a soak
## that spelled its own would be proving a shape nothing ships.
##
## What a planner-against-planner game does not produce, it cannot fire: about
## half the shipped beats wait for a named unit dead, ground held or a fact an
## earlier mission wrote. Those are the second test's, which applies every beat of
## every mission to the board it opens on.

## Days played per mission. A mission that has not reached a verdict by then is
## left undecided rather than failed, so raising it buys reach at the cost of the
## suite's wall clock, which is what stops it being a full match each.
const DAYS := 12
## The one seed, so a failure is reproducible. The planner is RNG-free; this is
## the combat luck.
const SEED := 7

var terrain_db: TerrainDB
var unit_db: UnitDB
var commander_db: CommanderDB
var db: CampaignDB


func before_all() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	commander_db = Fixture.commander_db()
	db = CampaignDB.load_default()


func after_each() -> void:
	CampaignSession.clear()


func test_every_mission_plays_with_its_own_script_live() -> void:
	for campaign in db.all():
		for mission: MissionDefinition in campaign.missions:
			_play(campaign, mission)


## Every authored beat against a real board, including the ones no planner will
## ever bring about. `check_campaigns` asks each effect whether it *could* be
## applied; this applies it, so an effect that validates and then falls over —
## a tag nothing carries, a seat nobody is playing — is caught by the same run
## that proves the mission plays.
##
## Each beat gets its **own** opening board, which is the state `check_campaigns`
## asks the same question of. Sharing one board between a mission's beats would
## make a first beat that decides the match refuse every beat after it, and the
## fault reported would be authoring rather than the beat order this test never
## claims to exercise — `_play` above is where beats meet one another.
func test_every_beat_applies_to_the_board_its_mission_opens_on() -> void:
	var authored := 0
	var applied := 0
	for campaign in db.all():
		for mission: MissionDefinition in campaign.missions:
			var where := "%s/%s" % [campaign.id, mission.id]
			authored += mission.events.size()
			for event: MissionEvent in mission.events:
				var built := BattleSetup.build(
					mission.to_request(), terrain_db, unit_db, commander_db
				)
				if built == null:
					fail_test("%s: the mission would not build" % where)
					continue
				var command := MissionEventCommand.new(event, mission.player_team)
				var error := command.validate(built.game)
				if error != "":
					fail_test("%s: beat '%s' was refused — %s" % [where, event.id, error])
					continue
				command.apply(built.game)
				applied += 1
	assert_eq(applied, authored, "every shipped beat lands on the board its mission opens on")


## One mission, from the board it opens on to the day cap. Every refusal is a
## failure: the planner only ever issues commands the rules offered it, and the
## beats reaching `_fire_due` are the ones the campaign layer still offers, so
## one the board will not carry is the authoring fault
## `MissionEventCommand.validate` exists to name rather than an army this game
## happened to rout.
func _play(campaign: CampaignDefinition, mission: MissionDefinition) -> void:
	var where := "%s/%s" % [campaign.id, mission.id]
	var built := BattleSetup.build(mission.to_request(), terrain_db, unit_db, commander_db)
	assert_not_null(built, "%s: the mission would not build" % where)
	if built == null:
		return
	var game := built.game
	game.rng.seed = SEED
	CampaignSession.begin(campaign, mission, CampaignState.new())
	CampaignSession.deploy_army(game)
	CampaignSession.open_board(game)
	_fire_due(game, where)
	var planners: Dictionary[int, AIController] = {}
	for team in game.teams:
		planners[team] = AIController.new(unit_db, built.difficulty.profile())
	var ceiling := game.map.width * game.map.height * DAYS
	var commands := 0
	while CampaignSession.outcome == null and game.winner == 0 and game.day <= DAYS:
		if commands >= ceiling:
			fail_test("%s: stalled after %d commands" % [where, commands])
			return
		var command := planners[game.current_team].plan_next_command(game)
		var error := command.validate(game)
		if error != "":
			fail_test("%s: the planner's command was refused — %s" % [where, error])
			return
		command.apply(game)
		commands += 1
		_fire_due(game, where)
		CampaignSession.decide(game)


## The beats due on this board, in the order and at the boundary `BattleCampaign`
## fires them: each is its own command, one that ends the match closes the batch,
## and one aimed at an army an earlier beat of the batch routed is skipped. Both
## are what the campaign layer already refuses to offer; they are repeated here
## because the board is read once per boundary, so the batch can decide or empty a
## seat after that read.
func _fire_due(game: GameState, where: String) -> void:
	for event: MissionEvent in CampaignSession.due_events(game):
		if game.winner != 0:
			return
		if event.names_fallen_army(game):
			continue
		var command := MissionEventCommand.new(event, CampaignSession.mission.player_team)
		var error := command.validate(game)
		if error != "":
			fail_test("%s: beat '%s' was refused — %s" % [where, event.id, error])
			return
		command.apply(game)
		CampaignSession.record_event(command)
