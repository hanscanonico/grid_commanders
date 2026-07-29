class_name BattleVictoryScenario
extends RefCounted
## The victory poses: a duel's lockup, the same fronted by the winner's face, and
## a 2v2 won together (COM-47, four-players plan FP4).
##
## Their own class rather than three more methods on BattleScenarioDriver, the way
## BattleFeedbackScenario and BattleTransitionScenario are: the poses are
## self-contained, they belong together, and that file is at its length ratchet.

var _battle: Battle


func _init(battle: Battle) -> void:
	_battle = battle


func run(mode: String) -> void:
	if mode == "side_victory":
		await _run_side_victory()
		return
	await _run_duel_victory(mode == "commander_victory")


## The staged rout, dressed for a capture: `with_commander` gives Red a general
## first, so the victory lockup is fronted by a portrait.
func _run_duel_victory(with_commander: bool) -> void:
	if with_commander:
		_battle.game.set_commander(1, _battle.commander_db.by_id(&"viktor_draeg"))
		_battle.view.restage_identity()  # so the win lockup reads the winner's faction, not First Army
	await BattleScenarioDriver.stage_rout(_battle)


## A 2v2 won together: the outcome frame that only exists once a victory can
## belong to a side rather than to an army (four-players plan D3/D5). Runs on
## maps/fixtures/quartet.txt — tools/smoke_scenarios.sh hands it that board — so
## all four liveries are on screen behind the lockup.
##
## The grouping is set here rather than through the menu — the seat strip writes
## the same `sides`, and a capture should not depend on walking a menu to reach
## it. The two losing armies are eliminated through the sim's own `eliminate`, so the
## banner, the standings line and the neutralised ground are the real ones.
func _run_side_victory() -> void:
	var game := _battle.game
	if game.teams.size() < 4:
		push_error("side_victory needs a four-army board; got %d seats" % game.teams.size())
		return
	game.sides = {1: 0, 3: 0, 2: 1, 4: 1}
	# One commander per faction, so the four liveries behind the lockup are the
	# four the atlas ships rather than two plus two borrowed classics.
	const SIDE_VICTORY_COS: Array[StringName] = [
		&"alina_ward", &"viktor_draeg", &"lyra_quill", &"nia_rowan"
	]
	for i in game.teams.size():
		game.set_commander(game.teams[i], _battle.commander_db.by_id(SIDE_VICTORY_COS[i]))
	_battle.view.restage_identity()  # so the lockup reads factions, not ordinals
	game.eliminate(4)
	game.eliminate(2)
	_battle.view.sync_sprites()
	# The live path repaints forfeited ground inside BattleCommandPipeline, which
	# a posed elimination never goes through — so the pose does it for itself.
	for cell: Vector2i in game.property_owners:
		_battle.view.repaint_property(cell)
	_battle.enter_victory()
	# Synchronous, so there is no transition to wait on — only the one frame the
	# lockup needs to have drawn before the shutter opens.
	await _battle.get_tree().process_frame
