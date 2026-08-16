class_name GameState
extends RefCounted
## Authoritative battle state: the map, all units, property ownership, funds,
## and whose turn it is. Scenes render from this; commands mutate it.
## No Node dependencies.
##
## The seating/roster arithmetic `create` answers with — which seats a match
## fills, what a reduced roster leaves standing, where each army began — moved to
## `Seating` (COM-184), shared with `SaveCodec` rather than copied.

## Every team the rules recognise: the legal maximum, not this match's roster.
## Ask `teams` for who is actually playing — the bound is only for the questions
## that have no match to ask, such as whether a save names a side that could ever
## have existed. Re-exported from the board, which is the roster authority.
const TEAMS: Array[int] = MapData.PLAYER_TEAMS
## Kept as the constant a few golden-value tests and the capture cut-in read
## directly; the rules themselves ask `rules_config.capture_points` instead,
## which defaults to this same number (see RulesConfig).
const CAPTURE_POINTS := 20
## Kept for the same reason as CAPTURE_POINTS; the rules ask
## `rules_config.income_per_property`.
const INCOME_PER_PROPERTY := 1000
## The smallest roster a seating may leave. Below it there is no match: one army
## has already won and none has nobody to play. See `create`.
const MIN_SEATS := 2
## The stream every state opens on. Its value means nothing; what it buys is that
## an unseeded state cannot exist. See `rng`.
const DEFAULT_RNG_SEED := 1701

var map: MapData
## The armies this match seats, in turn order. Seeded by `create` from the map,
## which is the roster authority (four-players plan D1) — never a menu setting,
## never `TEAMS`. A state assembled by hand (a save being decoded, a movement
## fixture) plays the duel every board played before a map could say otherwise.
var teams: Array[int] = MapData.DEFAULT_TEAMS.duplicate()
## team -> side id, how the armies are grouped. Empty is a free-for-all, where
## every army is its own side — which is what every match was before groupings
## existed, and is why the empty dictionary makes `allied` answer exactly what
## `a == b` answered everywhere it replaced.
##
## The match's choice, not the board's (four-players plan D1): the same map hosts
## a free-for-all, a 2v2 and a 3v1. Written once at setup from the `MatchRequest`
## and never by a command. The side ids themselves are opaque — nothing compares
## them for anything but equality.
var sides: Dictionary[int, int] = {}
var units: Array[Unit] = []
var damage_chart: DamageChart
## Balance levers a rebuild would otherwise require to sweep — see RulesConfig.
## Ambient like the terrain and unit databases rather than match state: it is
## never written by `create`'s callers, never carried by SaveCodec or
## ReplayCodec, and defaults here to the shipped file, so a state built by
## hand (a save being decoded, a movement fixture) plays with the same
## numbers a match started from `create` does.
var rules_config: RulesConfig = RulesConfig.load_default()
## Match RNG (combat luck). Deterministic out of `create`, which pins
## `DEFAULT_RNG_SEED` — Godot's constructor otherwise seeds from the engine's own
## entropy, and a state nobody remembered to seed then draws luck nobody can
## reproduce. Every launch overrides it (BattleSetup pins the requested seed or
## randomizes; the Lab, the Bulwark measure and the demo driver pin their own),
## and a save restores `rng.state`. A test wanting a different stream assigns
## `rng.seed` itself, which fully re-seeds.
var rng := RandomNumberGenerator.new()

var current_team: int = 1
var day: int = 1
var funds: Dictionary[int, int] = {}
## Runtime property ownership. Starts from the map's [owners] section; capture
## changes it here, never in MapData.
var property_owners: Dictionary[Vector2i, int] = {}
## Capture points still owed on each property being taken. Cleared when the
## capturing unit leaves the cell or dies.
var capture_progress: Dictionary[Vector2i, int] = {}
## 0 while the match runs; once decided, the winning **side's lead army** — its
## lowest seat. Kept scalar on purpose (four-players plan D3): every command's
## `winner != 0` gate, the Balance Lab's outcome and watch mode's diffable
## `watch: team %d wins on day %d` line all read it and none of them changed.
## `winners()` is the whole side, for presentation.
var winner: int = 0
## team -> true for every army that has fallen — routed off the board, or its HQ
## taken. A fallen army holds nothing, fields nothing, takes no turn and earns no
## income; `active_teams` is the roster without them.
##
## Modelled rather than inferred from an empty unit list, because the two are not
## the same question: an army with no units on day one has not fallen, and an army
## whose HQ was taken still had units the moment before.
var eliminated: Dictionary[int, bool] = {}
## team -> the cell its HQ **started** on. Recorded by `create` for every seat the
## match fills, and by the codec for every match it loads; nothing else writes it,
## because where an army began is not something a turn can change.
##
## It exists because "capturing an HQ eliminates its owner" is only exact while
## every HQ has a living owner and no army holds two (open-seats plan D3). A
## vacant seat's HQ has no owner to fell, and a survivor who takes a fallen army's
## HQ owns two — so that rule would let a rival behead them through the outpost
## they conquered. Only a team's *home* HQ fells it; every other one is a
## high-value property with HQ terrain stars, captured like a city.
##
## A team with no entry — a hand-built fixture, a board that deals it no HQ —
## cannot be eliminated by capture at all, which is the honest answer when nothing
## ever recorded a home to lose.
var home_hq: Dictionary[int, Vector2i] = {}
## Fog of war (a match option; see Vision for the rules).
var fog_enabled := false
## A team with no entry plays the neutral commander, which is created on demand
## — see commander_state().
var commanders: Dictionary[int, CommanderState] = {}
## res:// path of the map this match runs on; kept for save files.
var map_path := ""


## Builds the starting state from a parsed map. Returns null (with a pushed
## error) if any starting unit is invalid. The damage chart is optional for
## states that never resolve combat (e.g. movement-only tests). `p_rules_config`
## is optional too and left null keeps the field's own default (RulesConfig's
## shipped file) — a caller only ever names one to pin a non-default value.
##
## `p_commanders` (team -> CommanderType) is assigned *before* the opening
## begin_turn, so the first player's day-1 start-of-turn doctrine — a supply
## radius, a repair discount — is resolved against its real commander rather
## than the neutral one. Callers that name commanders must pass them here, not
## set_commander after: begin_turn only runs once, and it runs inside create.
##
## `p_seats` is which of the board's seats this match fills — empty means every
## one of them, which is today's behaviour verbatim (open-seats plan D1). The map
## still owns how many seats exist and where they sit; the match only chooses
## which are taken, and the choice bends downward only. A seat left out **never
## enters the state**: no purse, no commander, no turn, no banner. Its starting
## units are skipped and its properties open neutral, so its HQ and base become
## ground anyone may take — the same semantics a fallen army's ground gets.
##
## Which is the invariant worth holding onto, and the reason nothing downstream
## needed changing: **a reduced match on a big board produces exactly the state a
## small board would have produced.**
##
## Refused (null, with a pushed error) three ways, because `create` is the one
## authority every route in — the menu, a rematch, `--seats=` — has to pass, and it
## does not guess: a seating naming the same seat twice, one naming a seat the board
## never dealt, and one leaving fewer than `MIN_SEATS` armies. Which is the same
## reading of a legal seating `SaveCodec._is_seatable` holds a save to, so the sim
## and the loader cannot disagree about what a match may have been played with.
static func create(
	p_map: MapData,
	unit_db: UnitDB,
	p_damage_chart: DamageChart = null,
	p_commanders: Dictionary = {},
	p_seats: Array[int] = [],
	p_rules_config: RulesConfig = null
) -> GameState:
	var state := GameState.new()
	state.rng.seed = DEFAULT_RNG_SEED
	state.map = p_map
	state.damage_chart = p_damage_chart
	if p_rules_config != null:
		state.rules_config = p_rules_config
	var repeated := Seating._repeated_seat(p_seats)
	if repeated != 0:
		push_error("GameState: seats %s name seat %d twice" % [p_seats, repeated])
		return null
	var unseated := Seating._unseated(p_map.teams(), p_seats)
	if not unseated.is_empty():
		push_error(
			(
				"GameState: seats %s name %s, which the board's %s does not deal"
				% [p_seats, unseated, p_map.teams()]
			)
		)
		return null
	state.teams = Seating._filled_seats(p_map.teams(), p_seats)
	if state.teams.size() < MIN_SEATS:
		push_error(
			(
				"GameState: seats %s leave %d of the board's %s, which is no match"
				% [p_seats, state.teams.size(), p_map.teams()]
			)
		)
		return null
	state.property_owners = Seating._owners_of(p_map, state.teams)
	state.home_hq = Seating.home_hqs(p_map, state.teams)
	state.current_team = state.teams[0]
	for team in state.teams:
		state.funds[team] = 0
	for entry: Dictionary in p_map.starting_units:
		if not state.teams.has(entry.team):
			continue  # a vacant seat fields nothing
		var type: UnitType = unit_db.by_symbol(entry.symbol)
		if type == null:
			push_error("GameState: unknown unit symbol '%s'" % entry.symbol)
			return null
		var cell: Vector2i = entry.cell
		if state.unit_at(cell) != null:
			push_error("GameState: two starting units on cell %s" % cell)
			return null
		if not p_map.terrain_at(cell).is_passable(type.move_class):
			push_error(
				(
					"GameState: %s cannot stand on %s at %s"
					% [type.id, p_map.terrain_at(cell).id, cell]
				)
			)
			return null
		var unit := Unit.create(type, entry.team, cell)
		unit.tag = entry.tag
		state.units.append(unit)
	for team: int in p_commanders:
		# D1 once more: a vacant seat never enters the state, and a commander is state.
		if not state.teams.has(team):
			continue
		state.set_commander(team, p_commanders[team])
	TurnRules.begin_turn(state)  # day-1 income and upkeep for the first player
	return state


# --- commanders --------------------------------------------------------------


## A team's commander record, created neutral on demand so no caller ever has to
## branch on "does this side have a CO".
func commander_state(team: int) -> CommanderState:
	if not commanders.has(team):
		commanders[team] = CommanderState.create(CommanderType.neutral())
	return commanders[team]


## The doctrine hooks to ask about a team's units. Never null.
func commander_of(team: int) -> CommanderType:
	return commander_state(team).type


func set_commander(team: int, type: CommanderType) -> void:
	commanders[team] = CommanderState.create(type)


func power_active(team: int) -> bool:
	return commander_state(team).power_active


## Banks charge for a team, capped at what its power costs: an idle meter can
## never hold a second power's worth. A commander with no power banks nothing,
## which is what keeps a no-CO match free of the whole economy. And a team whose
## power is *running* banks nothing either: firing empties the meter, and letting
## the combat the power enables refill it would mean the meter never has to be
## earned again — you fire, and it is READY the moment the power comes down. So it
## only fills once the power is back down, which is what makes the reset stick.
func add_charge(team: int, points: int) -> void:
	var co_state := commander_state(team)
	if not co_state.type.has_power() or points <= 0 or co_state.power_active:
		return
	co_state.charge = mini(co_state.charge + points, co_state.type.power_cost)


# --- allegiance --------------------------------------------------------------


## Whether two armies stand together. **The single hostility authority** — ask
## it, never re-derive (four-players plan D2). Every site that used to write
## `team != mine` routes through here, which is what makes a 2v2 and a
## free-for-all differ by one dictionary instead of by a dozen expressions that
## have to be found and kept in step.
##
## An army always stands with itself, and an army with no side entry stands alone.
## So on an empty `sides` this is exactly `a == b`, and every routed site answers
## what it always answered — the regression guarantee the whole milestone rests on.
##
## What allies share is sight and purpose: they cannot shoot or capture each
## other, they pass through each other, and they never spring an ambush. What they
## never share is infrastructure — funds, production, repair, resupply, joining
## and transports all stay strictly `owner == unit.team`, each noted where an ally
## might be expected.
func allied(a: int, b: int) -> bool:
	if a == b:
		return true
	return sides.has(a) and sides.has(b) and sides[a] == sides[b]


## Every army standing with `team`, itself included, in seat order. What a side's
## shared sight is composed over.
func side_of(team: int) -> Array[int]:
	var members: Array[int] = []
	for other in teams:
		if allied(team, other):
			members.append(other)
	return members


## Every army in the roster hostile to `team`, in seat order. One element in a
## duel, which is why every shipped doctrine keeps the behaviour it had.
func enemies_of(team: int) -> Array[int]:
	var others: Array[int] = []
	for other in teams:
		if not allied(team, other):
			others.append(other)
	return others


# --- board -------------------------------------------------------------------


func unit_at(cell: Vector2i) -> Unit:
	for unit in units:
		if unit.carrier == null and unit.cell == cell:
			return unit
	return null


func units_of(team: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in units:
		if unit.team == team:
			result.append(unit)
	return result


## Units riding inside the given transport.
func cargo_of(transport: Unit) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in units:
		if unit.carrier == transport:
			result.append(unit)
	return result


func remove_unit(unit: Unit) -> void:
	_take_off_board(unit)
	_check_rout(unit.team)


## The mechanics of taking a unit off the board — cargo cascades with its
## transport, the abandoned capture clears — without the rout check that
## follows it in `remove_unit`. Split out so `remove_units` can take a whole
## batch off the board before anyone's rout is judged; see its comment.
func _take_off_board(unit: Unit) -> void:
	# Cargo goes down with its transport.
	for passenger in cargo_of(unit):
		_take_off_board(passenger)
	units.erase(unit)
	# A dying unit abandons any capture in progress. A passenger owns no cell of
	# its own — its stored cell is stale from wherever it last boarded — so it can
	# hold no capture, and erasing by that cell would wipe an unrelated one.
	if unit.carrier == null:
		capture_progress.erase(unit.cell)


## Removes many units in one atomic sweep, deferring rout and victory to a
## single pass after the whole batch is off the board.
##
## `remove_unit` checks rout as each unit comes off, which is exactly right
## for a single kill but wrong for a caller that can empty more than one army
## in the same command — Hammerfall's blast (COM-179). Checked one at a time,
## the army whose last unit happens to be removed first is eliminated first,
## and `_check_victory` then finds the other emptied army's doomed unit still
## standing (it hasn't been removed yet) and crowns it — a winner chosen by
## the scan order of the caller's own list rather than by the board. Taking
## the whole batch off the board first, eliminating every army it emptied in
## one ascending-team-id pass, and checking victory exactly once afterward
## makes the outcome a function of the board alone, whatever order `doomed`
## was built in.
func remove_units(doomed: Array[Unit]) -> void:
	var touched: Dictionary[int, bool] = {}
	for unit in doomed:
		touched[unit.team] = true
		_take_off_board(unit)
	var emptied: Array[int] = []
	for team in touched:
		if not is_eliminated(team) and units_of(team).is_empty():
			emptied.append(team)
	emptied.sort()
	for team in emptied:
		_fall(team)
	_check_victory()


func owner_at(cell: Vector2i) -> int:
	return property_owners.get(cell, MapData.NEUTRAL)


func set_owner(cell: Vector2i, team: int) -> void:
	property_owners[cell] = team


func properties_of(team: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in property_owners:
		if property_owners[cell] == team:
			cells.append(cell)
	cells.sort()
	return cells


## Commits a unit's move along `path`: an abandoned capture on the vacated cell
## resets to the full point count, fuel is spent per terrain cost, cargo rides
## along, and the unit is exhausted. Sole move-commit entry point, shared by
## every movement-type command's apply.
##
## The path was planned with the mover's knowledge, so it may run onto or through
## an enemy the mover could not see (fogged, or a dived sub it was not next to).
## When it does, the move is cut short at the last free cell before that enemy —
## the Advance Wars trap — and the return says so, telling the caller to drop any
## follow-on it had bound to the move. Fuel is charged only for the steps taken.
func advance_unit(unit: Unit, path: Array[Vector2i]) -> bool:
	var stop := path.size() - 1
	var ambushed := false
	for i in range(1, path.size()):
		var blocker := unit_at(path[i])
		if blocker != null and not allied(blocker.team, unit.team):
			ambushed = true
			# Never end on a cell a friendly is passing-through, nor past the
			# origin: back up to the last cell that is actually free to stand on.
			stop = i - 1
			while stop > 0 and unit_at(path[stop]) != null:
				stop -= 1
			break
	var walked: Array[Vector2i] = path.slice(0, stop + 1)
	var dest: Vector2i = walked[walked.size() - 1]
	if dest != walked[0]:
		capture_progress.erase(walked[0])
	var fuel_spent := 0
	for i in range(1, walked.size()):
		# Through MovementResolver, not the terrain directly, so a doctrine that
		# discounts terrain charges the discounted fuel too — the player is never
		# billed for a step the range overlay showed them as cheaper.
		fuel_spent += MovementResolver.step_cost(self, unit, map.terrain_at(walked[i]))
	unit.fuel = maxi(0, unit.fuel - fuel_spent)
	unit.cell = dest
	unit.acted = true
	unit.refreshable = true
	for passenger in cargo_of(unit):
		passenger.cell = dest
	return ambushed


## The next army to play, skipping the fallen. Falls back to the current team
## when nobody else survives — the match is over by then, and a rotation that
## could not answer would be a rotation that hangs.
func next_team() -> int:
	var index := teams.find(current_team)
	for step in range(1, teams.size() + 1):
		var candidate: int = teams[(index + step) % teams.size()]
		if not is_eliminated(candidate):
			return candidate
	return current_team


# --- elimination and victory -------------------------------------------------


func is_eliminated(team: int) -> bool:
	return eliminated.has(team)


## The armies still in the match, in seat order.
func active_teams() -> Array[int]:
	var alive: Array[int] = []
	for team in teams:
		if not is_eliminated(team):
			alive.append(team)
	return alive


## The winning side, in seat order — empty while the match runs. The presentation
## half of `winner`, which stays the side's lead army so nothing that reads a
## single victor had to change.
##
## Survivors only. An ally that fell on the way did not win the match, and naming
## it on the victory screen beside the army that outlived it would be the one
## place elimination went unsaid.
func winners() -> Array[int]:
	if winner == 0:
		return []
	var standing: Array[int] = []
	for team in side_of(winner):
		if not is_eliminated(team):
			standing.append(team)
	return standing


## Takes an army off the board for good: its units are removed and its ground
## reverts to **neutral** rather than to whoever beat it.
##
## Its ground changing hands resets the capture progress standing on it, the same
## as any other ownership change. That progress is a *survivor's*, not the fallen
## army's — these are the cells it owned, so the only unit that can be part-way
## through one is somebody else's — so a nearly-finished capture is lost the moment
## the city under it goes loose, and has to be started again.
##
## Neutral rather than forfeit is the deliberate half (plan D3). Handing a fallen
## empire wholesale to its conqueror would snowball a side that was already
## winning; leaving it loose makes it contested ground that any survivor can go
## and take. The one exception falls out of ordering rather than a rule: an HQ
## taken by capture belongs to the capturer before this runs, so a conqueror keeps
## the seat it actually stood on and nothing else.
func eliminate(team: int) -> void:
	_fall(team)
	_check_victory()


## `eliminate`'s mechanics without the victory check that follows it — the
## half `remove_units` runs per emptied army before checking victory once for
## the whole batch, so a call already inside a rout check (or a bulk removal)
## never runs it twice. Idempotent, guarded here rather than by a caller: an
## army already flagged fallen has nothing left for this to take off the board.
func _fall(team: int) -> void:
	if is_eliminated(team):
		return
	eliminated[team] = true
	for unit in units_of(team):
		_take_off_board(unit)
	for cell in properties_of(team):
		property_owners[cell] = MapData.NEUTRAL
		capture_progress.erase(cell)


## An army with nothing left on the board has fallen. Reached from `remove_unit`,
## so it answers on the shot that took the last unit rather than at the next turn
## boundary — including a counter-attack that kills the attacker on its own turn.
func _check_rout(dead_team: int) -> void:
	if winner != 0 or is_eliminated(dead_team) or not units_of(dead_team).is_empty():
		return
	eliminate(dead_team)


## The match ends when every surviving army stands on one side. In a duel that is
## the first elimination, which is why this replaced the old "award it to the
## first other team" without moving a single duel outcome.
func _check_victory() -> void:
	if winner != 0:
		return
	var alive := active_teams()
	if alive.is_empty():
		# Every death used to remove one army at a time, so the last team
		# standing was always found before the second-to-last one could finish
		# falling too. A blast that empties more than one army in the same
		# command breaks that: `remove_units` (COM-179) can legitimately land
		# here when it eliminates every remaining side in one pass. Nothing
		# past this point models a draw — `winner` stays 0 and `next_team()`
		# has nobody to hand the turn to — so this is flagged loud rather than
		# silent, the same refusal `SaveCodec._eliminated_error` already gives
		# this exact shape in a save file, rather than let the match spin
		# forever on an empty board with nobody told why.
		push_error("GameState: every remaining army fell at once; no side is left to win")
		return
	for team in alive:
		if not allied(alive[0], team):
			return
	winner = alive[0]  # the side's lead army; `winners()` lists the rest
