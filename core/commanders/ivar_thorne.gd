class_name IvarThorne
extends CommanderType
## Verdant League. Wounded and dangerous: every displayed pip of health one of
## his units is missing is worth attack percentage points, so a hurt unit of his
## is worth keeping in the line rather than rotating home to a workshop.
##
## The bonus softens the health scaling the formula already applies and never
## reverses it — a unit on five pips deals 0.5 x 1.40 = 0.70 of a full one's
## damage instead of 0.50. He is paid for not going home, not for being hurt, and
## a bonus large enough to cancel the scaling would make shooting his own tanks
## the opening move.
##
## Cut Both Ways is that doctrine fired at the whole board: two pips off every
## unit standing on it, his own and his ally's included (D6), floored at one pip
## so nothing dies and GameState.remove_unit is never called. It costs his army
## output and hands it the bonus back; everyone else's line is simply worth less.

## Displayed HP a unit at full health shows — the scale Engagement counts in.
const FULL_HP := 10

## Attack percentage points per displayed pip the attacker is missing.
@export var wounded_attack_pct_per_pip: int = 8
## Internal HP the cut takes off every unit — 20 is two displayed pips.
@export var cut_harm_hp: int = 20
## The internal HP the cut may never take a unit below: one pip, still standing.
@export var cut_floor_hp: int = 10


## Off the Engagement and never off the unit (D7): a forecast's counter is priced
## at the defender's *projected* post-attack health, so reading the live unit
## would promise a counter the resolver then fires at a different number.
func attack_bonus(_state: GameState, fight: Engagement) -> int:
	return wounded_attack_pct_per_pip * (FULL_HP - fight.attacker_hp)


## Everybody pays. His army, his ally's and every hostile one alike — the
## deliberate exception to the ally rule (D6), and what being indiscriminate
## costs is what the floor buys back: nothing leaves the board.
func on_power_activated(state: GameState, _team: int, _target: Vector2i = Vector2i.ZERO) -> void:
	for unit in state.units:
		unit.hp -= _cut_hp(unit)


## The simplest gate on the roster, and the floor is why: nothing dies, so there
## are no losses to weigh against the gain — only whether there is an enemy army
## left to bleed and a fight to spend the bonus in. Contact is read both ways
## round, because his line is better in the fights it starts and in the ones
## started on it alike.
func wants_power(state: GameState, team: int) -> bool:
	if _hostile_cut_hp(state, team) <= 0:
		return false
	return super(state, team) or _opponents_can_strike(state, team, false)


## The internal HP firing would take off the armies it is aimed at, in the one
## currency the power is written in — so the gate and the effect cannot disagree
## about what a firing is worth. What it would take off his own side is
## deliberately unweighed: that bleed is what buys the bonus. Enemies are read
## through the sight authority, like every other doctrine gate.
func _hostile_cut_hp(state: GameState, team: int) -> int:
	var cut := 0
	for unit in state.units:
		if state.allied(unit.team, team) or Vision.is_hidden_from(state, team, unit):
			continue
		cut += _cut_hp(unit)
	return cut


## A floor rather than a level: a unit on two pips or less is left standing on
## one, and one already below the floor is left exactly where it stands.
func _cut_hp(unit: Unit) -> int:
	return maxi(0, mini(cut_harm_hp, unit.hp - cut_floor_hp))
