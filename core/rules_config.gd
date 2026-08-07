class_name RulesConfig
extends Resource
## Balance levers that used to be constants under `core/` and so needed a
## rebuild to sweep: capture speed, property income, repair strength,
## property vision, Command Power charge rates, purchase pricing, and the
## neutral combat-luck bounds. Pure data, so tuning one is an edit to
## `data/rules.tres` rather than to a rules file — the same move the AI's
## `AIProfile` made for its own dials.
##
## Ambient like the terrain and unit databases: `GameState.rules_config`
## defaults to `load_default()` on the field itself, so a state built with no
## config named — every existing caller, every loaded save — plays with
## these same numbers. `tests/unit/test_rules_config.gd` pins that a missing
## or broken file falls back to them too.

const DEFAULT_PATH := "res://data/rules.tres"

## Capture points a property takes to flip, full strength. Matches
## `GameState.CAPTURE_POINTS`, which stays the constant the capture cut-in
## and a few golden-value tests read directly.
@export var capture_points: int = 20
## Funds paid per property a team holds, once a turn. Matches
## `GameState.INCOME_PER_PROPERTY`, kept for the same reason.
@export var income_per_property: int = 1000
## Internal HP (= 2 displayed) a serviced property heals per turn.
@export var repair_hp: int = 20
## Tiles a held property extends its owner's sight, on top of any unit
## standing there.
@export var property_vision: int = 2
## Percentage of the value lost a losing army banks to its Command Power
## meter.
@export var charge_pct_lost: int = 100
## Percentage of the value dealt the attacking army banks to its own meter.
@export var charge_pct_dealt: int = 50
## Floor under a unit's purchase price, however steep a doctrine's discount.
@export var min_price: int = 500
## A purchase price rounds down to a multiple of this.
@export var price_step: int = 100
## Neutral inclusive lower bound of the combat luck roll. `CommanderType`'s
## base `luck_min` reads this; a doctrine that narrows the range overrides
## the hook itself and stays untouched by this file (Lyra Quill).
@export var luck_min: int = 0
## Neutral inclusive upper bound of the combat luck roll. `CommanderType`'s
## base `luck_max` reads this.
@export var luck_max: int = 9
## Terrain defence stars cap after `star_bonus` and `star_pierce` have
## applied.
@export var max_stars: int = 5


## The config the game plays with. Falling back to an unmodified instance
## keeps a missing or broken file from taking balance out entirely — it
## plays with the defaults above, which are the same numbers.
static func load_default() -> RulesConfig:
	var config: RulesConfig = load(DEFAULT_PATH) as RulesConfig
	if config == null:
		push_error("RulesConfig: cannot load %s; using built-in defaults" % DEFAULT_PATH)
		return RulesConfig.new()
	return config
