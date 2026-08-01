class_name AIProfile
extends Resource
## Everything AIController weighs when it picks a command. Pure data, so
## difficulty and iteration are edits to a .tres rather than to planner logic.
##
## The defaults here match `data/ai/default.tres` and reproduce the behaviour
## the planner had when these were constants: same state plus same profile
## yields the same command. Tests that care about a specific weight build a
## profile explicitly rather than leaning on the default file.
##
## Adding an `@export` here also means writing it into every profile under
## `data/ai/`: a tier that omits a field inherits the default below, so editing a
## default silently retunes exactly the tiers that left it out and no others.
## `tests/unit/test_ai_profile.gd` holds every shipped tier to that.
##
## Node-free like the rest of ai/ and core/, so it is usable from tests.

const DEFAULT_PATH := "res://data/ai/default.tres"

## Multiplier on an attack's value when the shot would finish the target off.
@export var kill_bonus: float = 1.6
## How heavily the expected counter-attack discounts an attack's value. Below
## 1.0 because the AI is willing to trade.
@export var counter_weight: float = 0.6
## Base value of taking a property, tuned to sit near a city's worth.
@export var capture_score: float = 900.0
## Capturing an enemy HQ takes that army out of the match (four-players plan D3),
## which in a duel is the win, so it is worth a multiple of a city. Priced when an
## HQ ended the match outright and left there on purpose until the FP6 soak.
@export var hq_capture_multiplier: float = 3.0
## Added per capture point already chipped off, so the AI finishes what it
## started instead of wandering to a fresh property.
@export var capture_progress_bonus: float = 45.0
## Charged per step of movement, so all else equal the closer option wins.
@export var step_cost_penalty: float = 4.0
## At or below this HP a unit's *advance goal* becomes a friendly property that
## repairs it. Only the fallback, so a unit with anything worth doing never
## reaches it — leaving a shot to save itself is withdraw_weight's job.
@export var retreat_hp: int = 45
## Scores below this are not worth acting on; the unit advances instead.
@export var min_useful_score: float = 40.0
## What advancing is worth. Deliberately tiny: it is the fallback.
@export var advance_score: float = 1.0
## Build preference once enough capture units exist, strongest first. Walked at
## every production property and filtered by what that property can actually
## build, so one list covers bases and airports without an entry per facility.
##
## Transports are deliberately absent: the planner cannot plan a load-move-unload
## across turns, and a fleet of empty carriers is worse than none.
@export var build_priority: Array[StringName] = [
	&"md_tank",
	&"bomber",
	&"battleship",
	&"fighter",
	&"sub",
	&"cruiser",
	&"tank",
	&"b_copter",
	&"missiles",
	&"artillery",
	&"mech",
]
## Infantry are bought until the team has this many capture-capable units.
@export var capture_unit_target: int = 3
## What to buy when the enemy is flying and we cannot reach them, best first.
## Nothing in build_priority is guaranteed to answer air, so this is asked ahead
## of it — otherwise an AI with a full bank watches bombers work unopposed.
@export var air_answer_ids: Array[StringName] = [&"anti_air", &"missiles", &"fighter", &"cruiser"]
## How many units that can shoot at aircraft the team wants while the enemy has
## any. Counted from the damage chart, not from this list.
@export var air_answer_target: int = 2
## How many places down the build priority each copy already fielded pushes a
## unit. Without it the list has exactly one winner and the AI buys that unit and
## nothing else — the strongest thing a base makes, forever, while the port and
## the airfield it owns never produce at all. This is the diminishing return a
## player applies without thinking: a sixth tank is worth less than a first hull.
@export var duplicate_priority_cost: int = 3
## How many turns of income the planner will bank for a better unit than the one
## it could buy today. Without it the AI spends whatever it holds every turn and
## never accumulates, which does not merely make the expensive half of the roster
## rare — it makes it unreachable, since a 20 000 airframe cannot be bought out of
## a treasury that never passes ten thousand. Zero restores the spend-it-all
## behaviour; large values stall production waiting for units out of reach.
##
## Two rather than three deliberately, and the difference is measured: banking is
## what lets the AI field aircraft and hulls at all, but it also hands whoever
## moves first a timing edge, since they cross a price threshold a turn earlier.
## `make commander-balance --scenarios=clash,ridge --seeds=3` reports a first-side
## bias of +5.6 pp with no banking, +14.9 at two turns, +20.2 at three — and both
## the air and naval soaks still build their expensive rosters at two. Raising it
## buys nothing the game needs and costs first-move fairness.
@export var save_up_turns: int = 2
## What taking a submarine under (or bringing it back up) is worth. Above
## advance_score so it beats drifting, and well below what an attack scores, so a
## boat with a target sinks it rather than hiding from the escort beside it.
@export var dive_score: float = 200.0
## Turns of fuel margin an air or sea unit keeps before it breaks off to refuel:
## below this it heads for the nearest property that services it. Zero disables
## the behaviour and lets units fly until they drop.
@export var refuel_margin_turns: int = 1
## How strongly a commander's advisory hooks re-rank the planner's own
## candidates — stand_value on the advance path, build_bias on the build list,
## retreat_hp_delta on the repair gate (see CommanderType's AI-advice section).
## 1.0 takes the doctrine's numbers as written; 0 never calls the hooks and
## restores the doctrine-blind planner byte for byte. A commander's personality
## is a match fact rather than a difficulty smart, so every tier ships with it
## on — a tier may retune the strength, never gate the behaviour.
@export var doctrine_weight: float = 1.0

# --- Difficult-tier capabilities ---------------------------------------------
#
# Each gates a planner smart the base AI lacks. Every default is 0, which skips
# the capability entirely: at 0 the code that reads it never runs, and it never
# draws from the RNG stream. These four stay Difficult-only — data/ai/hard.tres
# is the one profile that turns them on, so Normal and Easy plan without them.
# (The Judgement dials below are the ones every tier now carries.) These change
# how the planner *ranks* its own candidate moves — never a combat number, which
# stays owned by CombatResolver.

## How heavily a destination's expected incoming damage next turn discounts an
## *attack's* score, as a fraction of the exposed unit's cost. >0 builds a
## per-turn threat map (S1); 0 leaves it unbuilt.
##
## Denominated in VALUE, because that is what _attack_score is: cost x damage
## fraction. It cannot be reused on the advance path, whose score is counted in
## tiles — see advance_threat_tiles.
@export var threat_aversion: float = 0.0
## How many tiles of forward progress a unit will give up to dodge a would-be
## lethal incoming shot when it is only advancing (S1, same threat map).
##
## Denominated in TILES, because _position_rank is: the advance score steps by
## whole integers of distance, so a value-denominated dial small enough to keep
## threat_aversion sane on the attack path can only ever break ties here. That
## scale difference is the entire reason this is a second field rather than a
## second use of threat_aversion. A shot forecast to take half of the HP a unit
## has left costs half this many tiles; one that would finish it costs all of
## them, so a wounded unit flinches harder than a fresh one.
##
## Below ~1.6 the dial cannot buy even one tile for a healthy unit against a
## full-strength artillery shot (63 of its 100 points, through the plains
## defence), so it is inert there; that is the floor a tuned value has to clear.
## >0 builds the threat map on its own, with or without threat_aversion.
@export var advance_threat_tiles: float = 0.0
## Bonus for attacking a target other ready friendlies can still add damage to
## this turn, so the AI piles fire to finish a unit instead of scattering it
## (S2). Scaled by that follow-up potential; 0 disables it.
@export var focus_fire_bonus: float = 0.0
## How strongly the build choice re-ranks toward what the damage chart says beats
## the enemy's actual cost-weighted roster, blended over the static list (S3).
## 0 keeps the static build_priority order exactly.
@export var build_reactivity: float = 0.0

# --- Judgement capabilities ---------------------------------------------------
#
# The AI Judgement plan's dials, and unlike the block above these are *not* a
# tier's smarts: noticing an enemy taking your ground and moving as an army are
# basic competence, so every tier carries a value and Easy's is weaker rather
# than absent.
#
# 0 still skips a capability entirely — that is the code property, and the
# per-capability suites under tests/unit/ build explicit profiles to prove it.
# What is no longer true is that the *shipped* value is 0. These defaults track
# data/ai/default.tres so an install with no profile file plays the same game as
# one with it, which is what test_default_profile_matches_the_built_in_defaults
# is for; tuning one of these means editing both, in the same commit.
#
# They went live against the difficulty ladder's advice, which is recorded rather
# than hidden: no tier split found could hold the DF4 ordering once Normal became
# competent, because that gate measures the *gap* between tiers and improving the
# middle rung closes it. `docs/difficulty_check.md` carries the failing numbers
# and the reasoning. withdraw_weight stays at 0 for a stronger reason than the
# ladder — at 0.05 it stops an artillery short of maximum standoff, which is a
# positioning regression rather than a matter of taste.

## What removing an enemy from ground our own side holds is worth, as a multiple
## of what taking that ground would be worth to us. The price list is the capture
## one read backwards — capture_score, capture_progress_bonus and
## hq_capture_multiplier, in that arithmetic — so at 1.0 denying a capture is
## worth exactly what making one is (AI Judgement D3). 0 skips it entirely.
##
## Denominated in VALUE, like _attack_score and like _consider_captures, which is
## what lets the three compete in one UnitPlan without a conversion.
@export var defend_weight: float = 0.35
## What stepping out of the enemy's reach is worth, as a fraction of the cost of
## the unit doing the stepping, per point of HP the incoming fire would have
## taken. 0 skips it entirely; >0 builds the per-turn threat map on its own, with
## or without threat_aversion.
##
## Denominated in VALUE — cost x damage avoided — which is the whole reason it is
## a third dial rather than a wider advance_threat_tiles: that one is counted in
## tiles, so it cannot say "this shot costs me sixteen thousand funds". Here an
## md tank facing certain death outbids a marginal trade and an infantry facing
## the same shot does not.
##
## Reads the same ThreatMap threat_aversion and advance_threat_tiles read. Three
## dials over one map can price a single enemy three times, so tune them together
## and never alone — see docs/difficulty_check.md.
@export var withdraw_weight: float = 0.0
## How many tiles of forward progress a unit gives up per tile it is adrift of
## the nearest unit it travels with. 0 skips it entirely.
##
## Denominated in TILES, because _advance_value is. The waiting is emergent and
## deliberately not coded: the goal term still pulls forward, so the equilibrium
## is a column that advances at the speed of its rear rather than a formation
## with a state to enter and get stuck in.
@export var cohesion_tiles: float = 1.0
## How far apart units may drift before cohesion_tiles starts charging them.
## Inert while cohesion_tiles is 0, so a tier that switches cohesion off need not
## also reset this one. The tiers that mean it ship radius 2; Easy's looser 4 is
## deliberately the setting the probe read as weak.
@export var cohesion_radius: int = 2


## The profile the game plays with. Falling back to an unmodified profile keeps
## a missing or broken file from taking the AI out entirely — it plays with the
## defaults above, which are the same numbers.
static func load_default() -> AIProfile:
	var profile: AIProfile = load(DEFAULT_PATH)
	if profile == null:
		push_error("AIProfile: cannot load %s; using built-in defaults" % DEFAULT_PATH)
		return AIProfile.new()
	return profile
