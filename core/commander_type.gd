# gdlint: ignore=max-public-methods
# The width is the contract, not an accretion: every public method here is one
# rule seam twenty-two doctrine subclasses may override, so "move something out"
# would mean a second hook tree beside this one — the split the commander plan's
# D1 rejects. The repo-wide ratchet stays where it is; this file alone answers
# for its own count, and a new method still needs to be a new doctrine seam.
class_name CommanderType
extends Resource
## One general: who they are, the Command Power they charge toward, and the
## hooks their doctrine is expressed through.
##
## This base class *is* the neutral commander. Every hook returns the value the
## rules had before commanders existed, so a side that picked no CO plays
## exactly as it did before this file — resolvers call the hooks unconditionally
## and never branch on "does this team have a commander".
##
## Each general is a small subclass in core/commanders/ overriding two or three
## of these, with its balance numbers as @export on a .tres in data/commanders/:
## behaviour in typed classes, numbers in data, like the rest of the repo.
##
## Three rules hold for every hook here:
##
## 1. Simulation state only. Never a Node, never a scene — this is core/.
## 2. Integer percentage points, never floats, so no doctrine can drift the
##    damage numbers a golden-value test pins down.
## 3. A hook checks `_is_active()` itself. A Command Power is not a separate
##    system; it is "this hook returns a bigger number while the power runs".
##
## `_is_active` and the `_can_*` predicates below are the subclass toolkit rather
## than hooks — underscored because nothing outside this hierarchy calls them.

## Inclusive bounds of the standard combat luck roll, matching
## `RulesConfig.luck_min` / `luck_max`. They live here too, rather than only on
## RulesConfig, because a doctrine may narrow or shift the range (Lyra Quill),
## which makes them commander data as well as balance data: `luck_min` /
## `luck_max` below are the hooks a doctrine overrides, and the base
## implementation reads the neutral defaults off `state.rules_config` so a
## custom config still moves the commander-less roll.
const LUCK_MIN := 0
const LUCK_MAX := 9

## Terrain defence stars cap after star_bonus and star_pierce have applied.
## Matches `RulesConfig.max_stars`, which is what `CombatResolver` actually
## reads — no hook overrides a star cap, so this constant has no reader of its
## own left; it survives as the number `data/rules.tres` must keep matching.
const MAX_STARS := 5

const NEUTRAL_ID := &"none"

## How long a Command Power lasts once fired. Two expiry points, both
## unambiguous — see PowerCommand.
enum Duration {
	## Ends when the owner ends the turn they fired it on.
	OWNER_TURN,
	## Survives the opponent's turn and ends at the owner's next turn start.
	ROUND,
}

## When the AI may consider firing the power. Most commanders act before their
## army; refresh doctrines wait until every ordinary action has been spent.
enum Timing {
	BEFORE_ACTIONS,
	AFTER_ACTIONS,
}

@export var id: StringName = NEUTRAL_ID
@export var display_name: String = "No Commander"
## Which of the four powers this general belongs to. Flavour and UI grouping;
## the rules never read it.
@export var faction: String = ""
## One line of doctrine, for the CO picker.
@export_multiline var doctrine_text: String = ""
@export var power_name: String = ""
@export_multiline var power_text: String = ""
## Short in-character lines spoken on the activation banner, rotated in order
## across a match. Presentation data in the battle_style tradition — a display
## key on a core-read resource that no rule ever reads.
@export var power_quotes: Array[String] = []
## Charge points the meter must hold before the power fires. 0 means this
## commander has no power, which also stops its meter ever filling.
@export var power_cost: int = 0
@export var power_duration: Duration = Duration.OWNER_TURN
@export var power_timing: Timing = Timing.BEFORE_ACTIONS


## The commander a side plays without one: every hook at its default, no power,
## and a meter that never fills.
##
## A fresh one each call rather than a shared instance. This is a Resource with a
## dozen writable exports, so one shared instance is a process-wide global that any
## stray write reaches — and the balance harness plays thousands of matches in a
## single process, where a poisoned neutral would move every match after it. The
## cost is one allocation per commander-less side per match, because
## `GameState.commander_state` caches the `CommanderState` this is wrapped in.
static func neutral() -> CommanderType:
	return CommanderType.new()


func has_power() -> bool:
	return power_cost > 0


## True while this commander's team is running its Command Power. Hooks that a
## power touches gate on this; the passive half of a doctrine ignores it.
func _is_active(state: GameState, team: int) -> bool:
	return state.power_active(team)


# --- combat ------------------------------------------------------------------


## Percentage points added to the damage dealt. Asked of the *attacker's*
## commander, including when the attacker is a defender shooting back.
func attack_bonus(_state: GameState, _fight: Engagement) -> int:
	return 0


## Percentage points of damage resistance. Asked of the *defender's* commander.
## The formula reads it as (200 - def) / 100, so +10 is x0.9 damage taken and
## -10 is x1.1 — the classic Advance Wars defence shape.
func defense_bonus(_state: GameState, _fight: Engagement) -> int:
	return 0


## Terrain defence stars added for the defender. Defender's commander.
func star_bonus(_state: GameState, _fight: Engagement) -> int:
	return 0


## Terrain defence stars the attack ignores. Attacker's commander.
func star_pierce(_state: GameState, _fight: Engagement) -> int:
	return 0


## Inclusive lower bound of the luck roll. Attacker's commander. The neutral
## default is `state.rules_config.luck_min`, not a constant, so a custom
## config still moves the roll for every doctrine that does not override this
## hook.
func luck_min(state: GameState, _fight: Engagement) -> int:
	return state.rules_config.luck_min


## Inclusive upper bound of the luck roll. Attacker's commander, same rule as
## luck_min above.
func luck_max(state: GameState, _fight: Engagement) -> int:
	return state.rules_config.luck_max


# --- movement ----------------------------------------------------------------


## Movement points added on top of the unit type's own.
func move_bonus(_state: GameState, _unit: Unit) -> int:
	return 0


## Movement points this commander strips from an *enemy* unit (Orin Flux's
## Signal Jam). The second of the two hooks that reach across the table, and it
## reads exactly like `enemy_vision_bonus`: asked of every commander hostile to
## the unit, `team` passed rather than recovered so two armies playing the same
## general each answer for their own meter.
##
## MovementResolver.move_budget floors the total at one point — a jammed unit is
## slowed, never frozen — the same shape as vision's floor at zero.
func enemy_move_bonus(_state: GameState, _team: int, _unit: Unit) -> int:
	return 0


## What one step onto `terrain` costs `unit`; `base` is the terrain's own cost
## for that movement class. Called from the Dijkstra flood fill *and* from the
## fuel spend in GameState.advance_unit, so a discount never leaves fuel
## disagreeing with the path the player was shown.
##
## MovementResolver.step_cost enforces two of the three invariants a doctrine
## cannot break: impassable stays impassable, and a step never costs less than 1.
## The third is this signature's own — no cell is handed over, and none may be
## reached around for, because the fill memoises one answer per kind of ground.
func terrain_cost(_state: GameState, _unit: Unit, _terrain: TerrainType, base: int) -> int:
	return base


## Tiles added to the unit's maximum firing range.
func range_bonus(_state: GameState, _unit: Unit) -> int:
	return 0


# --- vision ------------------------------------------------------------------


## Vision range added to this commander's own units.
func vision_bonus(_state: GameState, _unit: Unit) -> int:
	return 0


## Vision this commander strips from an *enemy* unit (Orin Flux's Signal Jam).
## Asked of every commander hostile to the unit, so it is the one hook a team's
## doctrine uses to reach across the table.
##
## `team` is the army this commander leads. It is passed rather than recovered,
## because "the other side" stopped being a single team the moment a board could
## seat four: two armies both playing Orin Flux each answer for their own meter,
## and neither can be mistaken for the other.
func enemy_vision_bonus(_state: GameState, _team: int, _unit: Unit) -> int:
	return 0


## True when `unit` sees into concealing terrain at range, ignoring the standing
## rule that cover is only revealed from an adjacent tile. Woods and reefs both,
## since which terrain conceals is TerrainType.conceals and not a fixed list.
func sees_into_cover(_state: GameState, _unit: Unit) -> bool:
	return false


## True while `unit` is hidden from every enemy, adjacent ones included
## (Sable Wren's Vanish). Fog only — the unit is still on the board, and an
## enemy that tries to move into its cell still finds it there.
func hides_unit(_state: GameState, _unit: Unit) -> bool:
	return false


# --- economy -----------------------------------------------------------------


## Percentage points added to a capture unit's chip per turn.
func capture_bonus_pct(_state: GameState, _unit: Unit) -> int:
	return 0


## How far a supply unit reaches, in tiles.
func supply_range(_state: GameState, _unit: Unit) -> int:
	return 1


## What a paid repair costs, as a percentage of the standard price.
func repair_cost_pct(_state: GameState, _unit: Unit) -> int:
	return 100


## What this army pays to build `unit_type`, as a percentage of its base value.
## UnitPricing applies the floor and rounding; the base value itself remains the
## currency used by charge, repair, target scoring and balance valuation.
func build_cost_pct(_state: GameState, _team: int, _unit_type: UnitType) -> int:
	return 100


## Percentage of a destroyed unit's base value transferred from its owner to
## this commander's army. Zero is the neutral rule; CombatResolver owns the
## kill gate and the victim-funds clamp.
func kill_bounty_pct(_state: GameState, _team: int, _victim: Unit) -> int:
	return 0


# --- powers ------------------------------------------------------------------


## One-shot effects fired the instant the power activates: refills, heals, the
## square a meteor lands on. Anything that
## lasts for the duration of the power belongs in the hooks above, gated on
## _is_active(), not here.
##
## `target` is the cell an aimed power was pointed at and is meaningless to every
## power that fires at the board, which is why it is defaulted rather than split
## off into a sibling hook: aimed or not, this is the one concept "what fires the
## instant the meter is spent", and two hooks for one concept is the seam
## drifting (plan D2).
func on_power_activated(_state: GameState, _team: int, _target: Vector2i = Vector2i.ZERO) -> void:
	pass


## True when this power is pointed at a cell rather than fired at the board. What
## the battle scene asks before entering its aiming state, and the whole of what
## decides whether `PowerCommand.target` means anything.
func aims_power() -> bool:
	return false


## The tiles an aimed power lands on, clipped to the board — the single authority
## for the footprint (plan D3). The overlay paints exactly what this returns, the
## computer scores exactly what it returns, and `on_power_activated` destroys
## exactly what it returns, so a preview showing nine tiles and a power clearing
## sixteen has nowhere to come from.
func power_blast_cells(_state: GameState, _team: int, _target: Vector2i) -> Array[Vector2i]:
	return []


## Where the computer aims. Asked only by AIController, and only of a commander
## that aims; measured with the same function `wants_power` is, so a doctrine can
## never want to fire and then aim somewhere it did not want (plan D5).
func power_target(_state: GameState, _team: int) -> Vector2i:
	return Vector2i.ZERO


## Whether the AI should spend a full meter now. Asked at this commander's
## declared timing; the meter being full and the power being legal are already
## settled by PowerCommand, so this is only the doctrine's board question.
##
## The default is the offensive read — "there is a fight to have this turn" —
## which is correct for every power whose value lands on the turn it fires: the
## attack and movement doctrines. The powers that are not about this turn's
## fight override it, and each does so in its own subclass, so a general's sense
## of timing lives beside the rest of its doctrine instead of in the planner.
##
## Rule-based, lookahead-free and RNG-free, like the planner that calls it.
func wants_power(state: GameState, team: int) -> bool:
	return _can_strike_an_opponent(state, team, true)


# --- AI advice ---------------------------------------------------------------
#
# Advisory hooks the computer planner may ask, on wants_power's terms:
# rule-based, lookahead-free, RNG-free, and reading only what the planner
# already reads — anything of the enemy's goes through Vision.is_hidden_from,
# never around it. The base class advises nothing, so the neutral commander and
# any general with no opinion leave planning bit-for-bit unchanged; the planner
# scales every answer by its own doctrine_weight and skips the hooks entirely
# at zero. A hook never reads the damage chart: expected damage is the
# forecast's job, and the forecasts already carry every combat hook above, so
# advice that re-priced one would count the same doctrine twice.


## How many tiles of forward progress standing on `cell` is worth to this
## doctrine when `unit` has nothing better to do this turn — the currency of
## the planner's advance path. Positive prefers the cell.
func stand_value(_state: GameState, _unit: Unit, _cell: Vector2i) -> int:
	return 0


## Places this doctrine moves `unit_type` on the planner's build list —
## negative pulls it up, positive pushes it down. Advisory only: the planner's
## urgent tiers (answering aircraft, filling the capture roster) outrank any
## bias, and no bias reaches a transport, which has no rank anywhere to move.
func build_bias(_state: GameState, _team: int, _unit_type: UnitType) -> int:
	return 0


## Internal HP added to the planner's retreat threshold for `unit` — 10 is one
## displayed pip — so a doctrine that repairs cheaply can rotate its wounded
## home earlier. The scale is the profile's own: the delta lands on
## `AIProfile.retreat_hp`, which is measured on `Unit.MAX_HP` = 100.
func retreat_hp_delta(_state: GameState, _unit: Unit) -> int:
	return 0


# --- subclass toolkit --------------------------------------------------------


## Every army hostile to this one, in seat order — asked of the one allegiance
## authority rather than worked out here (four-players plan D2). One element in a
## duel, which is what pins every shipped doctrine to the behaviour it had.
func _opponents_of(state: GameState, team: int) -> Array[int]:
	return state.enemies_of(team)


## True when any army hostile to `team` can bring one of `team`'s own side into
## range. The offensive read's mirror, and the gate the powers that fire on being
## attacked are measured with: they want to know whether anyone out there can
## reach them, not which one.
##
## Each rival is measured against `team`'s side and never against another rival,
## so a fight between two other armies is not mistaken for a threat to this one.
func _opponents_can_strike(state: GameState, team: int, ready_only: bool) -> bool:
	for other in _opponents_of(state, team):
		if _can_strike(state, team, other, team, ready_only):
			return true
	return false


## True when `team`'s own units can bring some rival's side into range. The
## offensive read every power whose value lands on the turn it fires is gated on.
## `team` measures its own army's reach, never its ally's.
func _can_strike_an_opponent(state: GameState, team: int, ready_only: bool) -> bool:
	for other in _opponents_of(state, team):
		if _can_strike(state, team, team, other, ready_only):
			return true
	return false


## True when a unit of `attacker_team` can bring a unit of `defender_team`'s side
## into range. The two sides are named separately because the question is asked
## both ways round: "can I reach them" and "can they reach me" differ in which
## army shoots *and* in whose army is being shot at, and reusing one filter for
## both counted a fight between two other armies as a threat to a third.
## `ready_only` limits the attackers to units that have not acted, which is the
## right question about the side whose turn it is and the wrong one about the
## side waiting to reply.
##
## Reach is AttackRange's own, so the gate answers with the geometry the shot
## would actually be resolved on. It used to be a manhattan guess against
## strike_reach, which counted enemies across water and behind walls: two live
## recordings caught offensive powers firing on turns that then held no attack at
## all — Vale x12, Marr x6, Ferrow x5 — while over-firing outnumbered banking
## 36:0 and 11:6 across the same two matches, so the old "over-estimate on
## purpose" was buying nothing the banked-meter failure needed.
##
## Anything hidden from `team` — the commander doing the asking — is skipped on
## both sides of the question, so no doctrine plans around a unit its own side
## cannot see. Vision owns that judgement; it is not re-derived here.
##
## The two sides are gathered in their own passes because firing geometry is a
## fact about the shooter alone: resolved once per attacker it costs one fill an
## army, and resolved inside the target walk it costs one per pair.
func _can_strike(
	state: GameState, team: int, attacker_team: int, defender_team: int, ready_only: bool
) -> bool:
	var targets := _strike_targets(state, team, defender_team)
	if targets.is_empty():
		return false
	var attackers: Array[int] = [attacker_team]
	for unit in state.units:
		if not _is_striker(state, team, unit, attackers, ready_only):
			continue
		if _unit_can_strike(state, unit, targets):
			return true
	return false


## Every unit of `defender_team`'s side `team` could shoot at.
func _strike_targets(state: GameState, team: int, defender_team: int) -> Array[Unit]:
	var targets: Array[Unit] = []
	for target in state.units:
		if state.allied(target.team, defender_team) and _is_target(state, team, target):
			targets.append(target)
	return targets


## The same list over every army hostile to `team`, for a doctrine asking about
## its own units rather than about one rival — the union `_can_strike_an_opponent`
## takes one opponent at a time.
func _hostile_targets(state: GameState, team: int) -> Array[Unit]:
	var targets: Array[Unit] = []
	for target in state.units:
		if not state.allied(target.team, team) and _is_target(state, team, target):
			targets.append(target)
	return targets


## Whether `team` could shoot at `target` at all: not cargo, a carried unit being
## unreachable, and not hidden — Vision owns that judgement and it is not
## re-derived here, so no doctrine plans around a unit its own side cannot see.
func _is_target(state: GameState, team: int, target: Unit) -> bool:
	return target.carrier == null and not Vision.is_hidden_from(state, team, target)


## True when `unit` could actually open fire on one of `targets` this turn: the
## cell is inside AttackRange.threat_cells — the single authority for the ground
## a unit brings under fire — and AttackRange.can_fire says the weapon and the
## matchup are there. Terrain, water, blockers, minimum range and ammo are all
## that authority's to answer, so no doctrine spells the geometry a second time.
##
## One fill per striker, and the gate above it runs only on a ready meter, so at
## most once per turn per commander.
func _unit_can_strike(state: GameState, unit: Unit, targets: Array[Unit]) -> bool:
	var under_fire: Dictionary[Vector2i, bool] = {}
	for cell in AttackRange.threat_cells(state, unit):
		under_fire[cell] = true
	for target in targets:
		if under_fire.has(target.cell) and AttackRange.can_fire(state, unit, target):
			return true
	return false


## True when `unit` could open fire for one of `attacker_teams` this turn, as far
## as `team` can tell: on one of those armies, not cargo, armed, still to act when
## `ready_only`, and not hidden. The one owner of that skip list, so every reading
## of "can that cell be brought under fire" — `_can_strike`'s over a whole army,
## Mara Voss's `stand_value` over one square of empty ground — grades the same
## shooters. Where each of them reaches is AttackRange's, asked by the caller
## because only the caller knows whether the question is about a live target
## (`_unit_can_strike`, exact) or about one square of empty ground (Voss's
## `strike_reach` screen, which nothing stands on to fire at).
func _is_striker(
	state: GameState, team: int, unit: Unit, attacker_teams: Array[int], ready_only: bool
) -> bool:
	if not attacker_teams.has(unit.team) or unit.carrier != null or unit.type.max_range <= 0:
		return false
	if ready_only and unit.acted:
		return false
	return not Vision.is_hidden_from(state, team, unit)


## True when a capture unit of `team` that has not acted can finish this turn on
## a property it does not already own. This one asks the real flood fill rather
## than a distance guess: "the ground is actually takeable" is the whole
## question for a power measured in capture points.
##
## `extra_move` is the movement the power being weighed would itself grant, and
## has to be counted because the gate is asked *before* the power fires, so the
## doctrine's own move_bonus is still switched off. Measuring without it refuses
## to fire in exactly the case the power exists for: a property one step beyond
## normal reach that only firing puts in range. The allowance goes through
## MovementResolver, so the budget keeps one owner and fuel still caps it.
##
## Erring toward firing matches _can_strike above: a banked meter that is never
## spent is the failure worth avoiding.
func _can_reach_capture(state: GameState, team: int, extra_move: int = 0) -> bool:
	for unit in state.units_of(team):
		if unit.acted:
			continue
		if _unit_can_reach_capture(state, team, unit, extra_move):
			return true
	return false


## The same question about one unit, so a doctrine weighing an army that has
## already acted — Iris Colt's Second Wind revives exactly those — asks the walk
## above rather than spelling a second one. Whose turn it still is stays the
## caller's judgement; everything else about takeable ground is here.
func _unit_can_reach_capture(state: GameState, team: int, unit: Unit, extra_move: int = 0) -> bool:
	if unit.carrier != null or not unit.type.can_capture:
		return false
	var reach := MovementResolver.reachable(state, unit, extra_move)
	for cell in reach.cells():
		if not reach.can_stop_at(cell):
			continue
		var terrain := state.map.terrain_at(cell)
		if terrain == null or not terrain.is_property:
			continue
		# Through the allegiance authority, not `!= team`: an ally's ground is
		# already the side's and `CaptureCommand` turns the attempt down, so a
		# doctrine measuring it would spend a full meter on a march the rules
		# refuse.
		if not state.allied(state.owner_at(cell), team):
			return true
	return false
