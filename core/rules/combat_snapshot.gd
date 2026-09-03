class_name CombatSnapshot
extends RefCounted
## What CombatResolver hands back about one exchange: `Forecast`, the luck-free
## prediction the damage preview shows and the AI scores moves with, and
## `CombatResult`, the record of an exchange that already happened.
##
## Data only. Every number in them is filled by the pass in CombatResolver that
## worked it out, so nothing here — and nothing reading them — ever recomputes a
## shot. A second opinion on combat is the bug class this repo already paid for
## once with movement.


class Forecast:
	var can_attack := false
	var attack_damage := 0
	## -1 when no counter is possible (defender dead, indirect, unarmed
	## against the attacker, or the attacker fires from beyond range 1).
	var counter_damage := -1
	## The same exchange in displayed HP (1-10) — the unit every other HP display
	## in the game speaks, and so the unit the damage preview leads with.
	##
	## `_after_min` / `_after_max` bound the HP a side is left standing at across
	## the luck range `resolve` rolls inside, worst and best case for its owner.
	## The attacker's span answers for the opening roll as well as the counter's:
	## a luckier shot leaves the defender a weaker band to shoot back from, and a
	## lethal one means no counter at all, so the best case is taken from the
	## luckiest shot and the worst from the unluckiest. The percentages above stay
	## luck-free, so they are a *floor* under a doctrine with a lucky floor; these
	## bounds are not. Nothing in core/ or ai/ reads them.
	var attacker_hp_before := 0
	var attacker_hp_after_min := 0
	var attacker_hp_after_max := 0
	var defender_hp_before := 0
	var defender_hp_after_min := 0
	var defender_hp_after_max := 0


class CombatResult:
	var attack_damage := 0
	var countered := false
	var counter_damage := 0
	var defender_died := false
	var attacker_died := false
	## Displayed HP (1-10) each side went into the exchange with and came out of it
	## holding, snapshotted by `resolve` as it spends each point.
	##
	## These exist for the presentation layer. By the time the battle cut-in is
	## handed a result the command has already applied, so the units themselves can
	## only say where the exchange ended and never where it began. Both ends are
	## recorded here rather than half-read off the board there, because the cut-in
	## must replay the exchange and never recompute it. Nothing in core/ or ai/
	## reads them.
	var attacker_hp_before := 0
	var defender_hp_before := 0
	var attacker_hp_after := 0
	var defender_hp_after := 0
	## Weapon slots selected by the rules, snapshotted for that cut-in to replay.
	## An empty counter slot means the defender never fired.
	var attacker_weapon_slot: StringName
	var counter_weapon_slot: StringName
	## Whether the opening shot was lobbed, which is how the cut-in tells an
	## artillery apart from the tank it shares a signature with. AttackRange is
	## still the one authority on who is indirect; this is its answer, taken at the
	## moment the shot was resolved. The counter needs none: only a max_range of 1
	## ever answers, so a returning volley is never a lob.
	var attacker_indirect := false
	## The terrain cover each side actually fought with, taken off the cells the
	## exchange resolved on. CombatResolver is still the one authority on what a
	## tile gives a unit; this is its answer at the moment of the shot, so the
	## cut-in can plate the defence the formula priced without asking a rule — or
	## the live board, which by then has already moved on.
	var attacker_cover_stars := 0
	var defender_cover_stars := 0
