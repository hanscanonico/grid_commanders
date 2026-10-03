class_name BattleMenus
extends RefCounted
## Which rows each of the battle scene's menus offers.
##
## Contents only. Battle still decides when a menu opens, where on screen it
## sits, and what choosing a row does; this decides what is on it. Split out of
## Battle for the same reason BattleView and BattleAnimator were — it is a
## separate job, and this one turns out to need nothing from the scene at all:
## every row below is gated by the command that would run it, or by the same
## terrain data that command validates against.
##
## That gating is the point rather than a convenience. A menu that worked out
## for itself whether a Load were legal would be a second opinion on the rules,
## and the day it disagreed with the command the player would be offered an
## action that is then refused. So each row asks the authority: Capture, Load and
## Join ask their commands, Supply asks SupplyCommand who is in reach, and
## production asks the terrain what it builds — exactly what BuildCommand checks.
##
## No scene tree and no sprite here, like the rest of the layers Battle delegates
## to. The two autoloads it reads are Settings, for the device-preference rows'
## labels and the ladders they step along, and CampaignSession, for whether there
## is a briefing to re-read at all — and that is the same rule as everything above
## rather than an exception to it: whoever owns the answer is who gets asked. So
## is a production row's picture: UnitIcons3D answers it for the view being
## played, the board's pixel tile or a still of the 3D model.

const CANCEL := {"id": &"cancel", "label": "Cancel"}
## The Auto ladder's first rung: the seat is the player's own.
const AUTO_OFF := &"off"
## What the Auto row and its list are for, said where they are (playtest SK-18):
## "Auto: Off" alone never said it hands the army over.
const AUTO_HEADING := "Let the computer play your side"
const AUTO_DETAIL := AUTO_HEADING + ".\nL/R picks a level, Enter hands it over."

## What a refused Fire row says after its verb. `UNARMED` is deliberately absent:
## a transport has no shot to explain, so it keeps getting no row at all, while
## the other three are the confusions this table exists for — an artillery whose
## Fire row vanished the moment it moved, and a tank that "refuses to shoot".
const FIRE_REFUSALS: Dictionary = {
	BattlePerspective.FireBlock.MOVED: "Moved",
	BattlePerspective.FireBlock.NO_AMMO: "No ammo",
	BattlePerspective.FireBlock.NO_TARGET: "No target",
}


## Rows for a unit whose move preview has finished on `dest` (the last cell of
## `path`). `fire_block` and `drop_options` are passed in because working them
## out needs the viewing team's fog, which is Battle's to know and not ours.
##
## A refused Fire row is shown greyed rather than dropped. Removing it answered
## "why can this not shoot?" by deleting the question, which is the one thing a
## player cannot read; the row that stays names the reason the perspective gave.
##
## Each droppable passenger gets its own row — a Lander can hold two and only one
## of them might fit the ground beside it — so a row names the unit it unloads and
## its id carries the option's index.
static func unit_actions(
	game: GameState,
	unit: Unit,
	path: Array[Vector2i],
	fire_block: BattlePerspective.FireBlock,
	drop_options: Array[BattlePerspective.DropOption]
) -> Array[Dictionary]:
	var dest: Vector2i = path[path.size() - 1]
	var actions: Array[Dictionary] = []
	if fire_block == BattlePerspective.FireBlock.NONE:
		actions.append({"id": &"fire", "label": "Fire"})
	elif FIRE_REFUSALS.has(fire_block):
		var reason: String = FIRE_REFUSALS[fire_block]
		actions.append({"id": &"fire", "label": "Fire · %s" % reason, "disabled": true})
	if CaptureCommand.new(unit, path).validate(game) == "":
		actions.append({"id": &"capture", "label": "Capture"})
	for i in drop_options.size():
		# One passenger drops under a plain "Drop"; a Lander's two are named apart.
		var label := "Drop"
		if drop_options.size() > 1:
			label += " %s" % drop_options[i].passenger.type.display_name
		actions.append({"id": StringName("drop_%d" % i), "label": label})
	if (
		unit.type.can_resupply
		and not SupplyCommand.new(unit, path).friendlies_in_reach(game, dest).is_empty()
	):
		actions.append({"id": &"supply", "label": "Supply"})
	if unit.type.can_dive:
		# One row, whichever way the boat is not currently facing. DiveCommand
		# validates the same flag, so the menu cannot offer a dive to something
		# already under.
		actions.append(
			(
				{"id": &"surface", "label": "Surface"}
				if unit.dived
				else {"id": &"dive", "label": "Dive"}
			)
		)
	actions.append({"id": &"wait", "label": "Wait"})
	actions.append(CANCEL)
	return actions


## Rows for confirming onto a reachable cell a friendly already stands on:
## boarding a transport with room, or merging into a damaged twin. Empty when
## neither applies, which is how Battle tells an ordinary move from one of these.
static func destination_actions(
	game: GameState, unit: Unit, path: Array[Vector2i]
) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if path.is_empty():
		return actions
	if LoadCommand.new(unit, path).validate(game) == "":
		actions.append({"id": &"load", "label": "Load"})
	if JoinCommand.new(unit, path).validate(game) == "":
		actions.append({"id": &"join", "label": "Join"})
	return actions


## Rows for a production property: what this particular facility builds,
## cheapest first, greyed out when the funds fall short.
##
## Filtered by the terrain's own build list, so a hangar never offers a tank and
## a base never offers a bomber — the same list BuildCommand rejects them with.
static func build_actions(
	game: GameState, unit_db: UnitDB, terrain: TerrainType, team: int, identity: SideIdentity
) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var row := identity.atlas_row(team)  # the building side's faction art, not a team int
	for unit_type in unit_db.all():
		if not terrain.can_build(unit_type.move_class):
			continue
		var price := UnitPricing.cost_for(game, team, unit_type)
		(
			actions
			. append(
				{
					"id": unit_type.id,
					"label": "%s  %d" % [unit_type.display_name, price],
					"disabled": game.funds[team] < price,
					"icon": UnitIcons3D.icon_for(unit_type, row),
					"detail": UnitBrief.text(game, unit_db, unit_type, price, game.funds[team]),
				}
			)
		)
	actions.append(CANCEL)
	return actions


## Rows for the menu opened on empty ground: the turn-level actions. The HUD has
## a button for the Command Power, and this keeps it reachable from the keyboard
## too, which the rest of the game already is.
##
## The device-preference rows read their labels off Settings for the same reason
## every row above asks its command: the tier the player is watching at, the
## volume they are listening at and whether they want the end-of-day check each
## have one owner, and a menu that remembered its own copy would eventually show
## a setting the game is not playing at. Which rows there are is Settings' too —
## a new preference is a new entry in its table, not a line here. Left and right
## walk one either way in place and Enter is the right press — every gesture that
## moves a setting leaves the menu standing over the row it moved (COM-246,
## `ActionMenu._step_value`), which is what the `cycle` callable is for. None of
## these rows ever reaches Battle's map handler.
##
## The two exit rows are the only way out of a running match that is not winning,
## losing or killing the application, so they are spelled out rather than folded
## into one: which of the two a player wants turns entirely on whether the single
## save slot may be overwritten, and a row that decided that quietly would be
## wrong for half of them either way.
##
## The Auto row is offered only for a seat the player themselves may hand to
## the computer: a team not currently AI (their own live turn) or one already
## on Auto (`auto_tiers` names it) — never a genuine CPU opponent's turn,
## which is in `ai_teams` but never in `auto_tiers`. Its label mirrors the
## Speed row's own reasoning: read fresh off `auto_tiers` rather than kept
## anywhere else, so it can never show a tier the seat is not actually
## playing at.
##
## Its value steps under left and right like the device rows' do, through
## `auto_step` (BattleAuto's), but the step is only a pick: handing an army over
## ends the player's turn, so it `chooses` — Enter takes the level the row shows,
## and Enter on the level already playing opens the list instead.
##
## `commandable` is false when this opens over a turn that is not the player's —
## the pause they may take while the computer plays. The two rows that would *act*
## for the side on turn go with it; everything else stays, because the match, the
## device settings and the ways out are exactly what a pause is opened for.
##
## `savable` is false over a replay, and takes the two save rows with it. A
## recording is a match already played: there is no turn to come back to, and
## writing it would spend the single save slot on a board the player can only
## watch — resumed, it would come up as a hot-seat match nobody is sitting at,
## because a replay seats no computer. The Auto row goes with them for the same
## reason: a recording seats no computer, so there is no seat to hand over — the
## commands are already written, and a planner handed one would think it owned a
## turn the recording is playing. The Briefing row goes with them too: a mission's
## words belong to the mission being played, and a recording is watched from
## outside the war it was recorded in. And the way out says "Stop Watching": with
## nothing a save could keep, "Without Saving" warned of a loss there is not.
##
## Briefing is offered only inside a campaign, asked of CampaignSession, because
## outside one there is nothing to re-read. It stays on a paused computer turn —
## reading the orders is not acting on them, which is what `commandable` drops.
##
## Objectives is the mission card's own O key, said out loud for a player who
## never found the key — the card covers board, and a lens nobody can turn off
## from the menu is the complaint this row answers. Its gate is the card's gate
## and nothing else, `CampaignSession.active()`: the row exists exactly while
## there is a card to raise, over a replay included, because a card on screen the
## player cannot lower is the same annoyance either way. `objectives_up` is the
## card's own answer, passed in like the Auto row's tier and for the same reason
## — the state has one owner and this only prints it.
static func map_actions(
	game: GameState,
	commandable: bool = true,
	savable: bool = true,
	ai_teams: Array[int] = [],
	auto_tiers: Dictionary = {},
	difficulty_db: DifficultyDB = null,
	objectives_up: bool = true,
	auto_step: Callable = Callable()
) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if commandable:
		var co_state := game.commander_state(game.current_team)
		if co_state.is_ready():
			actions.append({"id": &"power", "label": co_state.type.power_name})
	actions.append({"id": &"commanders", "label": "Commanders"})
	if savable and CampaignSession.active():
		actions.append({"id": &"briefing", "label": "Briefing"})
	if CampaignSession.active():
		var card := "On" if objectives_up else "Off"
		actions.append({"id": &"objectives", "label": "Objectives: %s" % card})
	actions.append_array(Settings.value_actions())
	var auto_eligible := game.current_team not in ai_teams or auto_tiers.has(game.current_team)
	if savable and difficulty_db != null and auto_eligible:
		var tier: StringName = auto_tiers.get(game.current_team, AUTO_OFF)
		var row := {"id": &"auto", "label": auto_label(tier, difficulty_db), "detail": AUTO_DETAIL}
		if auto_step.is_valid():
			row["cycle"] = auto_step
			row["chooses"] = true
		actions.append(row)
	if commandable:
		actions.append({"id": &"end_turn", "label": "End Turn"})
	if savable:
		actions.append({"id": &"save", "label": "Save"})
		actions.append({"id": &"save_and_quit", "label": "Save & Main Menu"})
	var leave := "Main Menu Without Saving" if savable else "Stop Watching"
	actions.append({"id": &"quit", "label": leave})
	actions.append(CANCEL)
	return actions


## Rows for the submenu the Auto row opens: hand this seat to the computer at
## one of the four difficulty tiers, or take it back with Off. Off leads,
## like the abandon confirmation's safe row, so a menu opened only to look
## changes nothing under an accidental Enter.
static func auto_actions(difficulty_db: DifficultyDB) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for tier: StringName in auto_ladder(difficulty_db):
		actions.append({"id": tier, "label": _tier_words(tier, difficulty_db)})
	actions.append(CANCEL)
	return actions


## The rungs the Auto row steps along, in the list's own order: Off, then every
## tier the computer plays at.
static func auto_ladder(difficulty_db: DifficultyDB) -> Array[StringName]:
	var ladder: Array[StringName] = [AUTO_OFF]
	for tier in difficulty_db.all():
		ladder.append(tier.id)
	return ladder


## The Auto row's words at `tier`, before a step and after one.
static func auto_label(tier: StringName, difficulty_db: DifficultyDB) -> String:
	return "Auto: %s" % _tier_words(tier, difficulty_db)


static func _tier_words(tier: StringName, difficulty_db: DifficultyDB) -> String:
	return "Off" if tier == AUTO_OFF else difficulty_db.by_id(tier).display_name


## Rows for the second press "Main Menu Without Saving" asks for. Leaving is the
## one map-menu action nothing undoes — the board is gone, and the slot it walks
## past may hold a match days older than the one on screen — so it is the one that
## gets asked twice.
##
## A menu rather than a dialog of its own, which is what makes the confirmation
## reachable by every route the row that opened it was: ActionMenu already owns the
## keyboard, the mouse and the Esc that backs out, and already clamps itself inside
## the board band. The safe row leads deliberately — ActionMenu arms its first
## enabled row when it opens, so a confirmation that led with the abandon would put
## "throw the match away" under the Enter the player is already pressing — and it
## carries the plain `cancel` id, so the row, Esc and a click past it all mean the
## same thing.
##
## Over a replay the same two rows speak of watching (playtest SK-28): there is no
## match being played there and nothing a save could keep.
static func abandon_confirm_actions(watching: bool = false) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	actions.append({"id": &"cancel", "label": "Keep Watching" if watching else "Keep Playing"})
	var leave := "Stop Watching" if watching else "Leave Without Saving"
	actions.append({"id": &"abandon", "label": leave})
	return actions


## The line over that confirmation: what leaving loses (playtest SK-29). Named by
## the day of the match's last save when there is one — `saved_day`, 0 for a
## match never written — because the slot is single and "since your last save"
## alone does not say how much that is. A replay loses nothing and says nothing.
static func abandon_consequence(watching: bool, saved_day: int) -> String:
	if watching:
		return ""
	if saved_day > 0:
		return "Progress since your Day %d save is lost." % saved_day
	return "This match was never saved: all of it is lost."
