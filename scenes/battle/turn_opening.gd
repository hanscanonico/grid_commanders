class_name TurnOpening
extends RefCounted
## What a turn says as it opens: the day card, and then whatever an empty tank
## took as the turn began.
##
## That second line belongs to the turn rather than to the EndTurnCommand that
## opened it. The command's presentation ends with a fog pass already drawn
## through the *incoming* team's eyes, and the hot-seat blackout does not go up
## until `Battle.start_turn`; anything that suspends between those two holds the
## outgoing player on the incoming player's board. Said here it cannot, because
## the device has already changed hands.


## The lines to show, in order, none of them empty. `posing` is the animator's
## capture flag: a frame staged for a screenshot gains no card nothing staged,
## the rule `Battle.announce_fallen` already holds to.
static func lines(
	game: GameState,
	identity: SideIdentity,
	perspective: BattlePerspective,
	starved: Array[Unit],
	posing: bool
) -> Array[String]:
	var said: Array[String] = ["Day %d - %s" % [game.day, identity.display_name(game.current_team)]]
	if posing:
		return said
	var told := perspective.reportable_losses(starved)
	if not told.is_empty():
		said.append(_starvation_line(told))
	return said


## One name for a single loss, a count for a flight of them — the shape the
## elimination banner uses for an army.
static func _starvation_line(told: Array[Unit]) -> String:
	var what := told[0].type.display_name if told.size() == 1 else "%d units" % told.size()
	return "%s lost - out of fuel" % what
