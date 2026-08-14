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


## Everything carried across turns while the walk runs. A plain object rather than
## a pile of locals threaded through eight detectors.
class Walk:
	var report: Report
	## The roster, for the one question the board cannot answer on its own: what a
	## factory could have built and what it would have cost.
	var unit_db: UnitDB
	## Unit -> consecutive turns of its owner's it has ended without acting.
	var idle: Dictionary = {}
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
	## team -> whether its home HQ has already been reported as uncovered, and is
	## still uncovered. Cleared the moment the side can answer for it again, so a
	## second lapse is a second finding and a standing one is said once.
	var hq_exposed: Dictionary = {}
	## Units that issued a command during the turn being walked.
	var acted: Dictionary = {}
	## Units that captured something during it, and whether a power went off.
	var captured: Dictionary = {}
	## Units that fired during it.
	var fought: Dictionary = {}
	var fired_power := false
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
			walk.fought = {}
			walk.dropped = {}
			walk.fired_power = false
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
	if command is CaptureCommand:
		walk.captured[(command as CaptureCommand).unit] = true
	if command is DropCommand:
		walk.dropped[(command as DropCommand).unit] = true
	if command is AttackCommand:
		walk.fought[(command as AttackCommand).unit] = true
		_check_shot(walk, state, command as AttackCommand)
	elif actor != null and command.get("path") is Array:
		_check_landing(walk, state, command, actor)


## Was there a better target from the cell this shot was fired from?
##
## "Better" is the exchange the forecast already prices — damage dealt less damage
## taken back — because that is the same reading the planner scores with, so a
## finding is about the board and not about a second opinion on combat.
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
			"shot the %s (net %d) with the %s in range from the same cell for net %d"
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


# --- end of turn ---------------------------------------------------------------


## Runs on the board the side is about to hand over: everything it did *not* do is
## visible exactly here, and nowhere else.
static func _close_turn(walk: Walk, state: GameState) -> void:
	var team := state.current_team
	_check_hoarding(walk, state, team)
	_check_power(walk, state, team)
	_check_hq(walk, state, team)
	for unit in state.units_of(team):
		if unit.carrier != null:
			continue
		_check_idle(walk, state, unit)
		_check_capture_chance(walk, state, unit)
		_check_transport(walk, state, unit)
		_check_oscillation(walk, state, unit)


## Money left on an idle factory. Read through the same two facts `BuildCommand`
## reads — the terrain's move classes and what this side is actually charged, so
## a doctrine's price percentage moves the finding with it — and a property that
## builds nothing this side can afford is not reported.
static func _check_hoarding(walk: Walk, state: GameState, team: int) -> void:
	var purse := int(state.funds.get(team, 0))
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
	if cheapest < 0:
		return
	_add(
		walk,
		"hoarding",
		state,
		null,
		"ended the turn on %d funds with an idle factory that builds from %d" % [purse, cheapest],
		purse
	)


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


## Ground this footsoldier could have started taking and did not.
##
## A unit that fired buys its turn, the same `busy` reading `_check_oscillation`
## takes: the detector prices ground not taken, and a unit that took a shot
## instead made a trade this instrument cannot judge. A unit that merely *moved*
## is still reported — that is the miss the detector exists for.
static func _check_capture_chance(walk: Walk, state: GameState, unit: Unit) -> void:
	if not unit.type.can_capture or walk.captured.has(unit) or walk.fought.has(unit):
		return
	var takeable := _takeable_within_reach(state, unit)
	if takeable.is_empty():
		return
	_add(
		walk,
		"missed_capture",
		state,
		unit,
		"could have started on the property at %s" % takeable[0],
		SEVERITY["missed_capture"]
	)


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


## What this exchange is worth to the attacker: damage dealt less damage taken
## back, both in the forecast's own percentages.
static func _exchange(state: GameState, attacker: Unit, from: Vector2i, target: Unit) -> int:
	var shot := CombatResolver.forecast(state, attacker, from, target)
	if not shot.can_attack:
		return 0
	return shot.attack_damage - maxi(shot.counter_damage, 0)


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
	var finding := Finding.new()
	finding.kind = kind
	finding.day = state.day
	finding.team = state.current_team
	finding.detail = detail
	finding.severity = int(SEVERITY.get(kind, 1))
	finding.magnitude = magnitude
	if unit != null:
		finding.subject = String(unit.type.id)
		finding.cell = unit.cell
	walk.report.findings.append(finding)
