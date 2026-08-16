class_name ArenaBlocks
extends RefCounted
## What the search may move, and in which company — the shelf of §5a and §5b, cut
## into blocks.
##
## Three decisions live in this file, and all three are about a result being
## attributable:
##
## - **Blocks, never one joint optimisation** (plan R5). Everything outside the
##   block a wave is searching is held at the base vector, so what a block
##   returns is a statement about those dials and not about twenty-odd at once.
## - **A coupling is declared, not discovered.** `couples` names dials another
##   block owns that this one has to move with its own, with the block they come
##   home to — because a dial that changes what a second dial *means* cannot be
##   fitted first and composed later. Each is a written coupling in `ai_profile.gd`
##   or in a plan, quoted in the block's note.
## - **Every live dial is in a block or in `EXCLUDED` with a reason.** A shelf
##   that quietly drops a dial searches a smaller space than it reports, and
##   nothing downstream can see that it did — which is what
##   `test_arena_blocks.gd`'s coverage check exists to make impossible.
##
## The permutations are not here at all: `build_priority` and `air_answer_ids` are
## ordered `Array[StringName]`s, and a permutation move and a step along an axis
## do not belong in one proposal distribution (plan D9). They get their own block
## when something searches them.
##
## Node-free, so GUT reads the search space without a process.

## Every dial the search may move, with the lattice it moves on.
##
## - `low` / `high` bound it. Both are enforced at the write (`apply`), so no
##   archived candidate can carry a value outside the space that was searched.
## - `min_step` is the precision: the lattice is `low + k * min_step`, and every
##   base value sits on it, so a search's first proposal moves the incumbent
##   rather than snapping it.
## - `step` is where a pattern search starts, and it contracts toward `min_step`.
##
## Whether a dial is an integer is asked of `AIProfile` rather than declared here
## (`integer`), so the table cannot disagree with the field it names. Ranges are
## sized to hold all three shipped tiers plus room past them: a space that cannot
## express `hard.tres` cannot reproduce the known answer AR5 is calibrated
## against.
const DIALS := {
	&"kill_bonus": {"low": 0.6, "high": 3.0, "step": 0.4, "min_step": 0.1},
	&"counter_weight": {"low": 0.0, "high": 1.6, "step": 0.2, "min_step": 0.05},
	&"min_useful_score": {"low": 0.0, "high": 200.0, "step": 40.0, "min_step": 10.0},
	&"condition_weight": {"low": 0.0, "high": 1.0, "step": 0.25, "min_step": 0.05},
	&"capture_score": {"low": 0.0, "high": 2700.0, "step": 300.0, "min_step": 50.0},
	&"capture_progress_bonus": {"low": 0.0, "high": 360.0, "step": 45.0, "min_step": 15.0},
	&"hq_capture_multiplier": {"low": 1.0, "high": 9.0, "step": 1.0, "min_step": 0.5},
	&"step_cost_penalty": {"low": 0.0, "high": 24.0, "step": 2.0, "min_step": 0.5},
	&"advance_score": {"low": 0.0, "high": 8.0, "step": 1.0, "min_step": 0.5},
	&"defend_weight": {"low": 0.0, "high": 6.0, "step": 1.0, "min_step": 0.25},
	&"threat_aversion": {"low": 0.0, "high": 0.6, "step": 0.1, "min_step": 0.025},
	&"advance_threat_tiles": {"low": 0.0, "high": 6.0, "step": 1.0, "min_step": 0.25},
	&"withdraw_weight": {"low": 0.0, "high": 1.0, "step": 0.2, "min_step": 0.05},
	&"cover_tiles": {"low": 0.0, "high": 2.0, "step": 0.5, "min_step": 0.125},
	&"cohesion_tiles": {"low": 0.0, "high": 4.0, "step": 0.5, "min_step": 0.125},
	&"cohesion_radius": {"low": 1.0, "high": 8.0, "step": 2.0, "min_step": 1.0},
	&"retreat_hp": {"low": 0.0, "high": 90.0, "step": 15.0, "min_step": 5.0},
	&"capture_unit_target": {"low": 0.0, "high": 10.0, "step": 2.0, "min_step": 1.0},
	&"duplicate_priority_cost": {"low": 0.0, "high": 8.0, "step": 2.0, "min_step": 1.0},
	&"save_up_turns": {"low": 0.0, "high": 6.0, "step": 1.0, "min_step": 1.0},
	&"air_answer_target": {"low": 0.0, "high": 6.0, "step": 1.0, "min_step": 1.0},
	&"build_reactivity": {"low": 0.0, "high": 1.0, "step": 0.4, "min_step": 0.1},
	&"capture_units_per_property": {"low": 0.0, "high": 1.0, "step": 0.2, "min_step": 0.05},
	&"capture_claim_depth": {"low": 0.0, "high": 4.0, "step": 1.0, "min_step": 1.0},
	&"production_capture_multiplier": {"low": 0.5, "high": 4.0, "step": 0.5, "min_step": 0.25},
	&"capture_goal_value_tiles": {"low": 0.0, "high": 8.0, "step": 2.0, "min_step": 0.5},
	&"join_weight": {"low": 0.0, "high": 1.5, "step": 0.3, "min_step": 0.05},
}

## The blocks, in the order the plan lists them. `fields` are the block's own;
## `couples` are dials another block owns that this one moves with them, keyed to
## the block they belong to. Both are searched together — the split is what the
## report reads to say why a dial from elsewhere was on the table.
const BLOCKS := [
	{
		"name": "combat",
		"fields": [&"kill_bonus", &"counter_weight", &"min_useful_score", &"condition_weight"],
		"couples": {},
		"note":
		(
			"The axis the tiers differ most on. condition_weight is here rather than on the"
			+ " shelf of its own because kill_bonus is the other correction to the same"
			+ " valuation: a search that fits one first fits it to a price the other then"
			+ " changes (plan R5, and both dials' own doc comments)."
		),
	},
	{
		"name": "economy",
		"fields":
		[
			&"capture_score",
			&"capture_progress_bonus",
			&"hq_capture_multiplier",
			&"step_cost_penalty",
			&"advance_score",
			&"defend_weight",
		],
		"couples": {},
		"note":
		(
			"defend_weight is built from the first three by the same arithmetic read"
			+ " backwards (Judgement D3), so moving one moves attack and defence at once and"
			+ " it cannot sit in a block of its own. step_cost_penalty is also the rate the"
			+ " attack path converts cover_tiles at."
		),
	},
	{
		"name": "threat",
		"fields": [&"threat_aversion", &"advance_threat_tiles", &"withdraw_weight", &"cover_tiles"],
		"couples": {},
		"note":
		(
			"Three dials over one ThreatMap can price one enemy three times (Judgement R3),"
			+ " so they move together. cover_tiles joins them because a cell a forecast has"
			+ " already priced scores no stars — turning a threat dial on takes cover out of"
			+ " exactly those cells (plan §5b), so the two cannot be measured apart."
		),
	},
	{
		"name": "formation",
		"fields": [&"cohesion_tiles", &"cohesion_radius", &"retreat_hp"],
		"couples": {},
		"note":
		(
			"The first two were probed together and never apart, and tight beat loose by the"
			+ " largest margin the Judgement plan measured, so the pair moves as a pair."
		),
	},
	{
		"name": "production",
		"fields":
		[
			&"capture_unit_target",
			&"duplicate_priority_cost",
			&"save_up_turns",
			&"air_answer_target",
			&"build_reactivity",
		],
		"couples": {},
		"note":
		(
			"save_up_turns buys a measured first-mover edge (+5.6 pp at 0, +20.2 at 3), which"
			+ " the search will happily take; both seatings counted is what stops it scoring"
			+ " (D5)."
		),
	},
	{
		"name": "economy_map",
		"fields":
		[
			&"capture_units_per_property",
			&"capture_claim_depth",
			&"production_capture_multiplier",
			&"capture_goal_value_tiles",
		],
		"couples": {&"capture_unit_target": "production", &"cohesion_tiles": "formation"},
		"per_board": true,
		"note":
		(
			"Three couplings, none optional. capture_units_per_property raises the"
			+ " capture_unit_target floor rather than replacing it; capture_claim_depth is the"
			+ " only limit on how thin a capture line gets, because spreading is untaxed by"
			+ " cohesion_tiles; and the AE3 pair multiplies out to zero at either dial's inert"
			+ " value, so moving one alone is inert half the time. Read per board: the first"
			+ " dial counts what is left to take, so one board measures the map rather than"
			+ " the dial."
		),
	},
	{
		"name": "join",
		"fields": [&"join_weight"],
		"couples": {&"condition_weight": "combat"},
		"note":
		(
			"What a merge carries is priced by _unit_value, which is condition_weight's, and a"
			+ " join only ever happens to damaged units — so at condition_weight 0 the dial is"
			+ " being fitted against a valuation that calls a 10-HP tank a whole one."
		),
	},
]

## Live dials the search deliberately does not move, each with the reason. Read by
## the coverage check, which is the only thing that can catch a dial that fell off
## the shelf between a plan and a table.
const EXCLUDED := {
	&"doctrine_weight":
	"no commander is ever seated in the arena, so the hooks it weighs are never called (R8)",
	&"focus_fire_bonus":
	"refuted three times, most recently with cohesion live — it starts and stays at 0",
	&"dive_score": "submarines only, and every naval board is out of the pools (naval R1)",
	&"refuel_margin_turns":
	(
		"air and sea only. The plan calls it inert on excluded boards, which stopped being"
		+ " true when AR4 seated jet_stream: it is live on one training board of four and"
		+ " one validation board of three, which is too little of a pool to read a dial on."
	),
	&"supply_weight":
	(
		"landed with COM-65 after the first campaign was measured, so no search has touched"
		+ " it — live on every tier, and the first thing a second campaign should cover."
	),
	&"supply_unit_target":
	(
		"landed with COM-65 beside supply_weight and is equally unsearched — it moves with"
		+ " the weight it only matters under, in the same second campaign."
	),
	&"spend_ceiling_turns":
	(
		"one of the three banking dials — they answer one question between them and a"
		+ " search that stepped one alone would credit it with what its siblings were"
		+ " already doing. Seated at 3.0 on Normal, Difficult and Brutal by"
		+ " docs/causeway_measure.md's V4, which measured the triple on one four-army"
		+ " board rather than searching it; the other two stay inert and unmeasured."
	),
	&"bank_scope":
	(
		"a mode rather than a magnitude: board-wide or per facility, with nothing between"
		+ " them for a lattice to step along."
	),
	&"bank_rank_margin":
	(
		"the third banking dial, unmeasured with the other two — and denominated in places"
		+ " on the build list, so it only means anything beside duplicate_priority_cost."
	),
	&"goal_engageability":
	(
		"a flag rather than a magnitude — an enemy is engageable or it is not, with nothing"
		+ " between the two settings for a lattice to step. Seated at 1.0 on Normal,"
		+ " Difficult and Brutal by docs/causeway_measure.md's V4, and the pools are the"
		+ " wrong ruler for it besides: no board in them holds a drop of water, so the"
		+ " fleet aimed at land it was diagnosed on cannot happen there."
	),
	&"capture_threat_aversion":
	(
		"the fourth reader of one ThreatMap, so a lattice that stepped it alone would credit"
		+ " it with what threat_aversion, advance_threat_tiles and withdraw_weight already"
		+ " price. It moves with them or not at all — and it ships unmeasured."
	),
	&"standoff_band_tolerance":
	(
		"a flag rather than a magnitude: any value above 0 flattens the band and there is"
		+ " nothing between the two settings for a lattice to step along."
	),
}

## Asked for a field's type and existence rather than declared beside the range,
## so the table cannot claim a dial `AIProfile` does not carry. Static because the
## shape is the class's and not one profile's.
static var _shape := AIProfile.new()


static func names() -> Array[String]:
	var listed: Array[String] = []
	for entry: Dictionary in BLOCKS:
		listed.append(String(entry["name"]))
	return listed


## One block by name, or an empty dictionary when nothing answers to it.
static func block(name: String) -> Dictionary:
	for entry: Dictionary in BLOCKS:
		if String(entry["name"]) == name:
			return entry
	return {}


## Every dial a block searches: its own first, then the ones it borrows. One
## order, so a wave's proposals and the report's columns cannot disagree.
static func fields_of(name: String) -> Array[StringName]:
	var listed: Array[StringName] = []
	var entry := block(name)
	if entry.is_empty():
		return listed
	var own: Array = entry["fields"]
	for field: StringName in own:
		listed.append(field)
	var couples: Dictionary = entry["couples"]
	for field: StringName in couples:
		listed.append(field)
	return listed


static func dial(field: StringName) -> Dictionary:
	var found: Dictionary = DIALS.get(field, {})
	return found


## Whether `AIProfile` carries this field as a number the search can step along.
## An array export answers false, which is what keeps the two permutations out of
## a continuous block by construction rather than by a list.
static func numeric(field: StringName) -> bool:
	var value: Variant = _shape.get(field)
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func integer(field: StringName) -> bool:
	return typeof(_shape.get(field)) == TYPE_INT


## The range the `@export` itself declares, as `[low, high]`, or empty when it
## declares none. `condition_weight` is the one that does, and it declares one
## because past 1.0 the interpolation prices a wounded unit below nothing — so a
## dial range wider than the export's is a sampler licensed to invert the whole
## valuation. The check that the table respects it lives in the suite.
static func declared_range(field: StringName) -> Array[float]:
	for property: Dictionary in _shape.get_property_list():
		if StringName(property["name"]) != field:
			continue
		if int(property["hint"]) != PROPERTY_HINT_RANGE:
			return []
		var parts := String(property["hint_string"]).split(",")
		if parts.size() < 2:
			return []
		return [float(parts[0]), float(parts[1])]
	return []


## What `profile` currently says for each of `fields` — the vector a search starts
## from, read off the base profile rather than restated here.
static func vector(profile: AIProfile, fields: Array) -> Dictionary:
	var found: Dictionary = {}
	for field: StringName in fields:
		found[field] = profile.get(field)
	return found


## Writes a vector onto a profile. Returns "" when it took, otherwise why it did
## not — an unknown dial, a value that is not a number, or one outside the space
## that was searched. Refusing the last is what makes an archived candidate
## re-runnable as evidence: a profile on disk carrying a value no lattice could
## produce would be a champion nobody can explain.
static func apply(profile: AIProfile, overrides: Dictionary) -> String:
	for key: Variant in overrides:
		var field := StringName(key)
		if not DIALS.has(field):
			return "'%s' is not a searchable dial" % field
		if not numeric(field):
			return "'%s' is not a number on AIProfile" % field
		var value: Variant = overrides[key]
		if not (value is float or value is int):
			return "'%s' takes a number, got %s" % [field, type_string(typeof(value))]
		var number := float(value)
		var bounds := dial(field)
		if number < float(bounds["low"]) or number > float(bounds["high"]):
			return (
				"'%s' is %s, outside the searched range %s..%s"
				% [field, number, bounds["low"], bounds["high"]]
			)
		profile.set(field, int(roundf(number)) if integer(field) else number)
	return ""
