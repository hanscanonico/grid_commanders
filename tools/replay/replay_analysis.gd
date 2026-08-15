class_name ReplayAnalysis
extends RefCounted
## Reads a recorded match and reports what the side playing it left on the table.
##
## It re-issues the recording command by command — the same rebuild `ReplayPlayer`
## hands the battle scene — and at each decision point compares what was done with
## what the **rules** say was available. Every counterfactual comes from
## `AttackRange`, `MovementResolver` and `CombatResolver.forecast_at`, which are
## the same authorities the planner scores through; that is what makes a finding
## here a fact about the *game* rather than about one revision of `ai/` (plan D6).
##
## Nothing under `ai/` gained a why-hook and no report claims to know what the
## computer was thinking. A finding says what happened, what was available
## instead, and roughly what the difference was worth. The judgement stays with
## the reader — several of these fire on a doctrine playing exactly as intended,
## which is why the report is evidence and never a gate.
##
## Node-free, like the rest of the offline toolchain, so GUT drives it directly.

## How many of its owner's turns a thing has to go on for before it is worth
## reporting. Tuned against real recorded matches rather than fixtures: one idle
## turn is a unit waiting for a friend, three is a unit nobody is playing.
const IDLE_TURNS := 3
const BANKED_TURNS := 3
const STRANDED_TURNS := 3

## What a finding is worth, before its own arithmetic scales it. Ranking is only
## ever "read this one first" — the numbers are a sort key, not a currency.
const SEVERITY := {
	"undefended_hq": 100,
	"walk_into_fire": 60,
	"worse_shot": 50,
	"hoarding": 40,
	"missed_capture": 35,
	"idle_unit": 30,
	"banked_power": 25,
	## Deliberately under the banked meter's: the two are opposite readings of the
	## same charge, and spending it at the wrong moment costs less than never
	## spending it at all.
	"spent_power": 20,
	"stranded_transport": 20,
	"oscillation": 10,
}


## One thing the side could have done better, with where and when to look.
class Finding:
	var kind := ""
	var day := 0
	var team := 0
	var cell := Vector2i.ZERO
	## The unit type it is about, or "" when it is about the side as a whole.
	var subject := ""
	var detail := ""
	## How much this *kind* of miss matters, and how bad this instance of it was.
	## Two numbers rather than their product, because the product ranks by whichever
	## happens to be measured in the larger unit — funds are in thousands and turns
	## are in ones, so a multiplied score sorts every hoarding finding above every
	## other kind whatever the board actually did.
	var severity := 0
	var magnitude := 0

	func line() -> String:
		var where := "day %d · team %d" % [day, team]
		if subject != "":
			where += " · %s at %s" % [subject, cell]
		return "%s — %s: %s" % [where, kind, detail]

	func to_dict() -> Dictionary:
		return {
			"kind": kind,
			"day": day,
			"team": team,
			"cell": [cell.x, cell.y],
			"subject": subject,
			"detail": detail,
			"severity": severity,
			"magnitude": magnitude,
		}


class Report:
	var label := ""
	var map_path := ""
	var days := 0
	var commands := 0
	var winner := 0
	## Non-empty when the recording could not be re-issued to its end — a stale
	## replay, or one this build no longer plays the same way. Everything up to
	## that point is still reported, and the reason says where it stopped.
	var stopped := ""
	var findings: Array[Finding] = []

	## kind -> how many, for the summary table.
	func counts() -> Dictionary:
		var tally: Dictionary = {}
		for finding in findings:
			tally[finding.kind] = int(tally.get(finding.kind, 0)) + 1
		return tally

	func to_dict() -> Dictionary:
		var listed: Array = []
		for finding in findings:
			listed.append(finding.to_dict())
		return {
			"label": label,
			"map_path": map_path,
			"days": days,
			"commands": commands,
			"winner": winner,
			"stopped": stopped,
			"counts": counts(),
			"findings": listed,
		}


## A run of consecutive turns one side ended having bought nothing it could
## afford. Held open while it lasts and reported once when it ends, because the
## reader is being told about the streak rather than about each of its turns.
class Hoard:
	var day := 0
	var turns := 0
	var peak := 0
	## The cheapest thing on the board at the turn the purse peaked, so the detail
	## line's two numbers are a reading of the same board.
	var cheapest := 0

	func note(p_day: int, purse: int, p_cheapest: int) -> void:
		if turns == 0:
			day = p_day
		turns += 1
		if purse > peak:
			peak = purse
			cheapest = p_cheapest

	func detail() -> String:
		if turns == 1:
			return (
				"ended the turn on %d funds having built nothing, against a %d build"
				% [peak, cheapest]
			)
		return (
			"built nothing for %d turns, peaking at %d funds against a %d build"
			% [turns, peak, cheapest]
		)


## Where a capturer stood when its turn opened and the property ground it could
## have started taking from there. The cell is carried with the ground because the
## finding is read on the board being handed over, where the unit has since walked:
## a line naming only where it ended would state a reach nobody can check.
class Opening:
	var cell := Vector2i.ZERO
	var takeable: Array[Vector2i] = []


## The board a Command Power was fired into, kept so the rest of the turn can be
## read against it. Taken before the power applies, which is the only board that
## says what the meter bought: afterwards the heal, the blast and the extra
## movement are already part of it.
class Spend:
	var day := 0
	var team := 0
	var commander := ""
	var power := ""
	var cost := 0
	## Total HP standing in every army hostile to the firing side. A census rather
	## than a list of shots, because Hammerfall takes units off the board with no
	## `AttackCommand` behind them.
	var enemy_hp := 0
	## Unit -> [hp, fuel, ammo] as the meter was spent.
	var condition: Dictionary = {}
	## Unit -> the cells it could have stopped on **without** the power.
	var reach: Dictionary = {}

	func detail() -> String:
		return (
			(
				"%s spent %s on day %d: nothing was hit, no ground changed hands, "
				+ "nothing was repaired and no unit went anywhere it could not already reach"
			)
			% [commander, power, day]
		)


## Everything carried across turns while the walk runs. A plain object rather than
## a pile of locals threaded through eight detectors.
class Walk:
	var report: Report
	## The roster, for the one question the board cannot answer on its own: what a
	## factory could have built and what it would have cost.
	var unit_db: UnitDB
	## Unit -> consecutive turns of its owner's it has ended without acting.
	var idle: Dictionary = {}
	## Unit -> the `Opening` its turn began on, which is the only board the capture
	## question has an answer on: by the end of the turn the unit has moved and its
	## budget is spent, so a reach measured there is a reading of next turn.
	var openings: Dictionary = {}
	## team -> the hoarding streak it is in the middle of, or absent.
	var hoard: Dictionary = {}
	## Unit -> the cells it has stood on at the end of its owner's last two turns.
	var tracks: Dictionary = {}
	## Unit -> consecutive turns of its owner's it has ended without firing or
	## capturing. A walk back onto the cell it left is only a circle if nothing was
	## done at the far end of it, and the window that has to be true over is the two
	## turns `tracks` covers.
	var quiet: Dictionary = {}
	## Unit -> consecutive turns it has held cargo without dropping any.
	var loaded: Dictionary = {}
	## team -> consecutive turns ended with a full meter unfired.
	var banked: Dictionary = {}
	## The board this turn's Command Power was fired into, or null — no power, or a
	## ROUND one, which buys the opponent's turn rather than this one.
	var spend: Spend = null
	## team -> whether its home HQ has already been reported as uncovered, and is
	## still uncovered. Cleared the moment the side can answer for it again, so a
	## second lapse is a second finding and a standing one is said once.
	var hq_exposed: Dictionary = {}
	## Units that issued a command during the turn being walked.
	var acted: Dictionary = {}
	## Units that captured something during it, and whether a power went off.
	var captured: Dictionary = {}
	## The property cells the side on turn started or finished taking during it.
	var captured_cells: Dictionary = {}
	## Units that fired during it.
	var fought: Dictionary = {}
	var fired_power := false
	## Whether the side on turn bought anything during it.
	var built := false
	var dropped: Dictionary = {}


## Plays the recording through and reports on it. `commander_db` is optional for
## the same reason `SaveCodec.decode`'s is: a match with no commanders resolves
## every id to neutral.
static func run(
	replay: ReplayCodec.Replay,
	terrain_db: TerrainDB,
	unit_db: UnitDB,
	chart: DamageChart,
	commander_db: CommanderDB = null
) -> Report:
	var report := Report.new()
	report.label = replay.label
	var player := ReplayPlayer.new(replay, unit_db)
	var loaded := player.opening(terrain_db, chart, commander_db)
	if loaded == null:
		report.stopped = "the opening board could not be rebuilt"
		return report
	var state := loaded.state
	report.map_path = state.map_path
	var walk := Walk.new()
	walk.report = report
	walk.unit_db = unit_db
	_open_turn(walk, state)

	while not player.finished():
		var command := player.next_command(state)
		if command == null:
			report.stopped = "command %d could not be rebuilt" % player.played()
			break
		var refusal := command.validate(state)
		if refusal != "":
			report.stopped = "command %d is no longer legal — %s" % [player.played(), refusal]
			break
		if command is EndTurnCommand:
			_close_turn(walk, state)
		else:
			_before_apply(walk, state, command)
		command.apply(state)
		report.commands += 1
		var drift := player.drift(state)
		if drift != "":
			report.stopped = drift
			break
		if command is EndTurnCommand:
			walk.acted = {}
			walk.captured = {}
			walk.captured_cells = {}
			walk.fought = {}
			walk.dropped = {}
			walk.fired_power = false
			walk.spend = null
			walk.built = false
			_open_turn(walk, state)
	_close_hoards(walk)
	report.days = state.day
	report.winner = state.winner
	report.findings.sort_custom(_by_weight)
	return report


static func _by_weight(a: Finding, b: Finding) -> bool:
	if a.severity != b.severity:
		return a.severity > b.severity
	if a.magnitude != b.magnitude:
		return a.magnitude > b.magnitude
	return a.day < b.day


# --- per command --------------------------------------------------------------


## Runs on the board as it was when the command was issued, which is where a
## forecast has to be asked: after the apply the shot has already happened.
static func _before_apply(walk: Walk, state: GameState, command: Command) -> void:
	var actor: Unit = command.get("unit")
	if actor != null:
		walk.acted[actor] = true
	if command is PowerCommand:
		walk.fired_power = true
		walk.spend = _snapshot_power(state)
	if command is BuildCommand:
		walk.built = true
	if command is CaptureCommand:
		var capture := command as CaptureCommand
		walk.captured[capture.unit] = true
		walk.captured_cells[capture.path[capture.path.size() - 1]] = true
	if command is DropCommand:
		walk.dropped[(command as DropCommand).unit] = true
	if command is AttackCommand:
		walk.fought[(command as AttackCommand).unit] = true
		_check_shot(walk, state, command as AttackCommand)
	elif actor != null and command.get("path") is Array:
		_check_landing(walk, state, command, actor)


## The board the meter was spent into, or null for a power there is nothing to
## judge. A ROUND power is the whole of that exclusion: it buys the *opponent's*
## turn, so the owner's turn produces nothing by construction and reporting it
## would name a defensive doctrine playing exactly as written.
static func _snapshot_power(state: GameState) -> Spend:
	var team := state.current_team
	var commander := state.commander_state(team).type
	if commander.power_duration == CommanderType.Duration.ROUND:
		return null
	var spend := Spend.new()
	spend.day = state.day
	spend.team = team
	spend.commander = commander.display_name
	spend.power = commander.power_name
	spend.cost = commander.power_cost
	spend.enemy_hp = _hostile_hp(state, team)
	for unit in state.units:
		if not state.allied(unit.team, team):
			continue
		spend.condition[unit] = [unit.hp, unit.fuel, unit.ammo]
		if unit.carrier == null:
			spend.reach[unit] = _stoppable_cells(state, unit)
	return spend


## Was there a better target from the cell this shot was fired from?
##
## "Better" is the exchange the forecast prices, read in funds — what the damage
## dealt is worth less what the counter costs — because that is the currency the
## planner chooses a target in, so a finding is about the board and not about a
## second opinion on what a shot is for.
static func _check_shot(walk: Walk, state: GameState, attack: AttackCommand) -> void:
	var from: Vector2i = attack.path[attack.path.size() - 1]
	var target := state.unit_at(attack.target_cell)
	if target == null:
		return
	var taken := _exchange(state, attack.unit, from, target)
	var best := taken
	var best_target: Unit = null
	for other in state.units:
		if other == target or other.carrier != null:
			continue
		if state.allied(other.team, attack.unit.team):
			continue
		if not AttackRange.covers(state, attack.unit, from, other.cell):
			continue
		if AttackRange.ready_shot(state, attack.unit, other) == null:
			continue
		var value := _exchange(state, attack.unit, from, other)
		if value > best:
			best = value
			best_target = other
	if best_target == null:
		return
	_add(
		walk,
		"worse_shot",
		state,
		attack.unit,
		(
			"shot the %s (net %d funds) with the %s in range from the same cell for net %d"
			% [target.type.id, taken, best_target.type.id, best]
		),
		best - taken
	)


## Did this move walk into a killing ground it was standing outside of?
##
## Two conditions, and the second is what makes it a finding rather than a
## complaint. Only for a move that bought nothing else — a unit that traded,
## captured or unloaded paid for the cell it is on, and whether that was worth it
## is a judgement no detector should make. And only when **staying put was
## survivable**: a unit already inside the same fire did not walk into anything,
## and reporting it would bury the moves that did under the ones that could not
## have gone otherwise.
static func _check_landing(walk: Walk, state: GameState, command: Command, actor: Unit) -> void:
	if not (command is MoveCommand):
		return
	var path: Array = command.get("path")
	if path.size() <= 1:
		return  # a Wait is not a walk into anything
	var dest: Vector2i = path[path.size() - 1]
	var incoming := _incoming_damage(state, actor, dest)
	if incoming < actor.hp or _incoming_damage(state, actor, path[0]) >= actor.hp:
		return
	_add(
		walk,
		"walk_into_fire",
		state,
		actor,
		"moved to %s, where the enemy can deal %d to its %d HP" % [dest, incoming, actor.hp],
		incoming
	)


# --- start of turn -------------------------------------------------------------


## What the side on turn could reach before it spent anything. Only the capture
## question needs it, and it can only be asked here: a unit's movement allowance
## is gone by the end of its turn, so the same reach taken at the handover names
## the ground it will take next turn and blames it for not having taken it yet.
static func _open_turn(walk: Walk, state: GameState) -> void:
	walk.openings = {}
	for unit in state.units_of(state.current_team):
		if unit.carrier != null or not unit.type.can_capture:
			continue
		var takeable := _takeable_within_reach(state, unit)
		if takeable.is_empty():
			continue
		var opening := Opening.new()
		opening.cell = unit.cell
		opening.takeable = takeable
		walk.openings[unit] = opening


# --- end of turn ---------------------------------------------------------------


## Runs on the board the side is about to hand over: everything it did *not* do is
## visible exactly here, and nowhere else.
static func _close_turn(walk: Walk, state: GameState) -> void:
	var team := state.current_team
	_check_hoarding(walk, state, team)
	_check_power(walk, state, team)
	_check_spent_power(walk, state)
	_check_hq(walk, state, team)
	var claimed := _claimed_ground(walk, state, team)
	for unit in state.units_of(team):
		if unit.carrier != null:
			continue
		_check_idle(walk, state, unit)
		_check_capture_chance(walk, state, unit, claimed)
		_check_transport(walk, state, unit)
		_check_oscillation(walk, state, unit)


## A side that spent nothing on a turn it could have spent. The question is
## **refusal to buy**, never spare capacity: a side holding five bases always has
## a free one, so "some property stood idle" is arithmetic rather than judgement
## and saturated on every multi-property board it was measured on. A turn
## qualifies only when the side issued no `BuildCommand` at all while its purse
## covered the cheapest thing one of its free properties builds.
##
## Affordability is read through the same two facts `BuildCommand` reads — the
## terrain's move classes and what this side is actually charged, so a doctrine's
## price percentage moves the finding with it — and a purse short of everything on
## the board is not reported.
##
## Latched over the streak, the way `banked_power` and `undefended_hq` are: a side
## that banks for five turns is one thing that happened, not five, and said once a
## turn it was more than half of everything the analyser printed. The finding is
## held open while the streak runs and released when it ends — or at the end of the
## recording, for a side still sitting on its purse when the match stopped.
static func _check_hoarding(walk: Walk, state: GameState, team: int) -> void:
	if walk.built:
		_release_hoard(walk, team)
		return
	var purse := int(state.funds.get(team, 0))
	var cheapest := _cheapest_build(walk, state, team, purse)
	if cheapest < 0:
		_release_hoard(walk, team)
		return
	var streak: Hoard = walk.hoard.get(team, Hoard.new())
	streak.note(state.day, purse, cheapest)
	walk.hoard[team] = streak


## The cheapest unit an idle property of `team`'s could have built out of `purse`,
## or -1 when nothing on the board could have.
static func _cheapest_build(walk: Walk, state: GameState, team: int, purse: int) -> int:
	var cheapest := -1
	for cell in state.properties_of(team):
		if state.unit_at(cell) != null:
			continue
		var terrain := state.map.terrain_at(cell)
		if terrain == null or terrain.builds.is_empty():
			continue
		for type in walk.unit_db.all():
			if not terrain.can_build(type.move_class):
				continue
			var price := UnitPricing.cost_for(state, team, type)
			if price <= purse and (cheapest < 0 or price < cheapest):
				cheapest = price
	return cheapest


static func _release_hoard(walk: Walk, team: int) -> void:
	var streak: Hoard = walk.hoard.get(team)
	if streak == null:
		return
	walk.hoard.erase(team)
	_add_at(walk, "hoarding", streak.day, team, null, streak.detail(), streak.peak)


## Every streak still open when the recording ran out.
static func _close_hoards(walk: Walk) -> void:
	var teams: Array = walk.hoard.keys()
	teams.sort()
	for team: int in teams:
		_release_hoard(walk, team)


static func _check_power(walk: Walk, state: GameState, team: int) -> void:
	var co_state := state.commander_state(team)
	if walk.fired_power or not co_state.is_ready():
		walk.banked[team] = 0
		return
	var streak := int(walk.banked.get(team, 0)) + 1
	walk.banked[team] = streak
	if streak < BANKED_TURNS:
		return
	walk.banked[team] = 0  # reported; start counting again rather than repeat every turn
	_add(
		walk,
		"banked_power",
		state,
		null,
		"%s has held a charged Command Power for %d turns" % [co_state.type.id, streak],
		streak
	)


## A Command Power fired into a board it could not move. `banked_power` reports
## the opposite mistake and firing zeroes its streak whatever the power achieved,
## so the most wasted activation there is was the one thing the instrument could
## not see.
##
## Judged here and only here, which is also the last-turn exclusion: a recording
## that stops before the side hands the board over never reaches this, and the
## turn the meter was meant to buy may be off the end of the file. `Report.stopped`
## is what tells the reader that happened.
static func _check_spent_power(walk: Walk, state: GameState) -> void:
	var spend := walk.spend
	if spend == null or _power_bought_something(walk, state, spend):
		return
	_add_at(walk, "spent_power", spend.day, spend.team, null, spend.detail(), spend.cost)


## The four things a power can buy, read off the committed board rather than off
## what was issued: an enemy hurt, ground changed hands, an army topped up, or a
## unit standing where its own legs could not have carried it. Any one of them
## and the meter did something.
static func _power_bought_something(walk: Walk, state: GameState, spend: Spend) -> bool:
	if _hostile_hp(state, spend.team) < spend.enemy_hp:
		return true
	if not walk.captured_cells.is_empty():
		return true
	for unit in state.units:
		var opened: Variant = spend.condition.get(unit)
		if opened == null:
			continue
		var was: Array = opened
		if unit.hp > int(was[0]) or unit.fuel > int(was[1]) or unit.ammo > int(was[2]):
			return true
		var reach: Variant = spend.reach.get(unit)
		if unit.carrier == null and reach != null and not (reach as Dictionary).has(unit.cell):
			return true
	return false


## Is anything standing within a turn's reach of this side's home HQ that it
## cannot answer? Losing the home HQ takes the army out of the match, so this is
## the one finding that is about the whole side rather than a unit.
##
## Latched the way `banked_power` is, and for the same reason: one lapse is one
## finding. This is the heaviest severity in the table, so an HQ left uncovered
## for a dozen turns would otherwise fill the printed summary with a dozen copies
## of one sentence and push every other kind off the page.
static func _check_hq(walk: Walk, state: GameState, team: int) -> void:
	var home: Variant = state.home_hq.get(team)
	if home == null:
		return
	var hq: Vector2i = home
	if state.owner_at(hq) != team:
		return  # already lost; nothing left to warn about
	var threat := _hq_threat(state, team, hq)
	if threat == null or _can_contest(state, team, hq):
		walk.hq_exposed[team] = false
		return
	if walk.hq_exposed.get(team, false):
		return
	walk.hq_exposed[team] = true
	_add(
		walk,
		"undefended_hq",
		state,
		null,
		"a %s can reach the home HQ at %s and nothing of ours can" % [threat.type.id, hq],
		SEVERITY["undefended_hq"]
	)


## The first enemy that could stand on `team`'s home HQ this turn, or null.
static func _hq_threat(state: GameState, team: int, hq: Vector2i) -> Unit:
	for enemy in state.units:
		if enemy.carrier != null or state.allied(enemy.team, team):
			continue
		if not enemy.type.can_capture:
			continue
		if MovementResolver.reachable(state, enemy).can_stop_at(hq):
			return enemy
	return null


static func _can_contest(state: GameState, team: int, hq: Vector2i) -> bool:
	for friend in state.units_of(team):
		if friend.carrier != null:
			continue
		if MovementResolver.reachable(state, friend).can_stop_at(hq):
			return true
	return false


static func _check_idle(walk: Walk, state: GameState, unit: Unit) -> void:
	if walk.acted.has(unit):
		walk.idle[unit] = 0
		return
	if not _has_something_to_do(state, unit):
		walk.idle[unit] = 0
		return
	var streak := int(walk.idle.get(unit, 0)) + 1
	walk.idle[unit] = streak
	if streak < IDLE_TURNS:
		return
	walk.idle[unit] = 0
	_add(
		walk,
		"idle_unit",
		state,
		unit,
		"has stood still for %d turns with something in reach" % streak,
		streak * 10
	)


## Something worth doing: an enemy it could bring under fire, or ground it could
## take. Asked of the rules, so a unit with nothing to do is not reported for
## having nothing to do.
static func _has_something_to_do(state: GameState, unit: Unit) -> bool:
	if AttackRange.has_ready_weapon(state, unit):
		for cell in AttackRange.threat_cells(state, unit):
			var other := state.unit_at(cell)
			if other != null and not state.allied(other.team, unit.team):
				return true
	return not _takeable_within_reach(state, unit).is_empty()


## Ground this side attended to during the turn: the property cells one of its
## units took or started taking, and the cells its units are standing on as the
## turn is handed over. Each maps to the unit that claimed it, so a unit's own
## occupancy never excuses it: ground it walked onto and did not take is the miss
## the detector exists for, and only a *sibling*'s claim strikes a cell off.
##
## Capturing is a **side**-level decision and this is what says so. Two
## footsoldiers opening beside the same neutral city is the side playing
## correctly: one takes it and the other goes elsewhere, and a per-unit
## counterfactual blames the second for the first having got there.
static func _claimed_ground(walk: Walk, state: GameState, team: int) -> Dictionary:
	var claimed: Dictionary = {}
	for unit in state.units:
		if unit.carrier == null and state.allied(unit.team, team):
			claimed[unit.cell] = unit
	for cell: Vector2i in walk.captured_cells:
		claimed[cell] = null
	return claimed


## Ground this footsoldier could have started taking and did not.
##
## A unit that fired buys its turn, the same `busy` reading `_check_oscillation`
## takes: the detector prices ground not taken, and a unit that took a shot
## instead made a trade this instrument cannot judge. A unit that merely *moved*
## is still reported — that is the miss the detector exists for.
##
## What was in reach is `_open_turn`'s answer, never a fresh one from here: this
## runs on the board being handed over, where the unit is standing at the end of
## its walk with its budget spent, so ground measured here is ground it can take
## *next* turn. Ground the side claimed is struck off that answer first, and a
## unit with nothing left on its list missed nothing.
static func _check_capture_chance(
	walk: Walk, state: GameState, unit: Unit, claimed: Dictionary
) -> void:
	if not unit.type.can_capture or walk.captured.has(unit) or walk.fought.has(unit):
		return
	var opening: Opening = walk.openings.get(unit)
	if opening == null:
		return
	for cell in opening.takeable:
		if claimed.has(cell) and claimed[cell] != unit:
			continue
		_add(
			walk,
			"missed_capture",
			state,
			unit,
			(
				"opened the turn at %s and could have started on the property at %s"
				% [opening.cell, cell]
			),
			SEVERITY["missed_capture"]
		)
		return


static func _check_transport(walk: Walk, state: GameState, unit: Unit) -> void:
	if state.cargo_of(unit).is_empty() or walk.dropped.has(unit):
		walk.loaded[unit] = 0
		return
	var streak := int(walk.loaded.get(unit, 0)) + 1
	walk.loaded[unit] = streak
	if streak < STRANDED_TURNS:
		return
	walk.loaded[unit] = 0
	_add(
		walk,
		"stranded_transport",
		state,
		unit,
		"has carried its cargo for %d turns without unloading" % streak,
		streak * 5
	)


## Back where it was two turns ago, having done nothing in between: a unit being
## walked in a circle by a planner that keeps changing its mind.
##
## A unit that fired or captured at either end of the walk is not one of those —
## it went somewhere to do something and came back — so it is skipped rather than
## reported with a detail line the board contradicts.
static func _check_oscillation(walk: Walk, state: GameState, unit: Unit) -> void:
	var busy := walk.fought.has(unit) or walk.captured.has(unit)
	var quiet := 0 if busy else int(walk.quiet.get(unit, 0)) + 1
	walk.quiet[unit] = quiet
	var seen: Array = walk.tracks.get(unit, [])
	if seen.size() >= 2 and seen[0] == unit.cell and seen[1] != unit.cell and quiet >= 2:
		_add(
			walk,
			"oscillation",
			state,
			unit,
			"is back on %s after leaving it, having fought nothing" % unit.cell,
			SEVERITY["oscillation"]
		)
	seen = [seen[1] if seen.size() >= 2 else unit.cell, unit.cell]
	walk.tracks[unit] = seen


# --- shared readings -----------------------------------------------------------


## What this exchange is worth to the attacker, **in funds**: the value of the
## damage dealt less the value of the counter taken back.
##
## The currency is the point. A unit's HP is worth its cost by the hundredth —
## the board's own rate, since `TurnRules._repair` sells missing HP back at it —
## so a quarter of a 16,000 md tank outbids two thirds of a 1,000 infantry, and a
## detector reading raw HP percentages would report the first as the worse shot
## every time it was offered. That is the same shape the planner scores an attack
## in, without its dials: `kill_bonus`, `counter_weight` and `condition_weight`
## are opinions about the game and this instrument only asks it for prices.
static func _exchange(state: GameState, attacker: Unit, from: Vector2i, target: Unit) -> int:
	var shot := CombatResolver.forecast(state, attacker, from, target)
	if not shot.can_attack:
		return 0
	var dealt := mini(shot.attack_damage, target.hp) * target.type.cost
	var taken := mini(maxi(shot.counter_damage, 0), attacker.hp) * attacker.type.cost
	return (dealt - taken) / 100


## Everything the board could put on `unit` if it stopped at `cell` this turn.
## Summed over enemies rather than maxed: what matters is whether standing there
## is survivable, and a unit inside three fire rings is not.
static func _incoming_damage(state: GameState, unit: Unit, cell: Vector2i) -> int:
	var total := 0
	for enemy in state.units:
		if enemy.carrier != null or state.allied(enemy.team, unit.team):
			continue
		if AttackRange.ready_shot(state, enemy, unit) == null:
			continue
		for from in AttackRange.firing_cells(state, enemy):
			if not AttackRange.covers(state, enemy, from, cell):
				continue
			total += CombatResolver.forecast_at(state, enemy, from, unit, cell).attack_damage
			break
	return total


## How much army every side hostile to `team` has standing, in HP.
static func _hostile_hp(state: GameState, team: int) -> int:
	var total := 0
	for unit in state.units:
		if not state.allied(unit.team, team):
			total += unit.hp
	return total


## Every cell this unit could end its move on, as a set.
static func _stoppable_cells(state: GameState, unit: Unit) -> Dictionary:
	var found: Dictionary = {}
	var reach := MovementResolver.reachable(state, unit)
	for cell in reach.cells():
		if reach.can_stop_at(cell):
			found[cell] = true
	return found


## Properties this unit could stand on and start taking this turn.
static func _takeable_within_reach(state: GameState, unit: Unit) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	if not unit.type.can_capture:
		return found
	var reach := MovementResolver.reachable(state, unit)
	for cell in reach.cells():
		if not reach.can_stop_at(cell):
			continue
		var terrain := state.map.terrain_at(cell)
		if terrain == null or not terrain.is_property:
			continue
		if state.allied(state.owner_at(cell), unit.team):
			continue
		found.append(cell)
	found.sort()
	return found


static func _add(
	walk: Walk, kind: String, state: GameState, unit: Unit, detail: String, magnitude: int
) -> void:
	_add_at(walk, kind, state.day, state.current_team, unit, detail, magnitude)


## A finding whose day and team are stated rather than read off the board, which a
## latched detector needs: a streak is released on the turn it ends or after the
## recording has run out, and either way it is about where it began.
static func _add_at(
	walk: Walk, kind: String, day: int, team: int, unit: Unit, detail: String, magnitude: int
) -> void:
	var finding := Finding.new()
	finding.kind = kind
	finding.day = day
	finding.team = team
	finding.detail = detail
	finding.severity = int(SEVERITY.get(kind, 1))
	finding.magnitude = magnitude
	if unit != null:
		finding.subject = String(unit.type.id)
		finding.cell = unit.cell
	walk.report.findings.append(finding)
