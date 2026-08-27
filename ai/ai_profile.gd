class_name AIProfile
extends Resource
## Everything AIController weighs when it picks a command. Pure data, so
## difficulty and iteration are edits to a .tres rather than to planner logic.
##
## The defaults here match `data/ai/default.tres`, so an install whose profile
## file is missing plays the same game as one with it. Same state plus same
## profile yields the same command; tests that care about a specific weight
## build a profile explicitly rather than leaning on the default file.
##
## Adding an `@export` here also means writing it into every profile under
## `data/ai/`: a tier that omits a field inherits the default below, so editing a
## default silently retunes exactly the tiers that left it out and no others.
## `tests/unit/test_ai_profile.gd` holds every shipped tier to that.
##
## Node-free like the rest of ai/ and core/, so it is usable from tests.

const DEFAULT_PATH := "res://data/ai/default.tres"
## bank_scope: one banking answer decides the whole board — the shipped planner.
const BANK_SCOPE_BOARD := 0
## bank_scope: every facility answers for itself, so what a port is saving for
## cannot silence a land base.
const BANK_SCOPE_FACILITY := 1

## Multiplier on an attack's value when the shot would finish the target off.
## The other correction to the valuation condition_weight prices, so the two
## overlap and are searched together — see that field.
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
## across turns, and a fleet of empty carriers is worse than none. The APC is not
## an exception to that — the planner still cannot ferry — so the one it wants as
## a *supplier* is asked for by supply_unit_target instead, above this list, the
## way the air answer is.
##
## The recon is absent on purpose, and the absence is the mechanism: a doctrine
## that wants scouts pulls one onto this list's tail with a negative build_bias
## (commander-doctrine-ai D1). Listing it would hand every commander the buy and
## take the doctrines that pay for it their signature.
##
## Three field one, and only two of them ask. Orin Flux and Cassian Rook name the
## recon in a scout list. Ines Calder reaches it by **cost** — her bias is every
## type at or under a cheap ceiling — so from her second cheap purchase the recon
## outranks her mech and her army carries scouts. That was an accident of the
## ceiling, and it was measured rather than assumed: narrowing her bias to
## capture-capable types cost her 2.3 pp over 480 seats and was not shipped. See
## docs/commander_balance.md, *Calder's cheap-breadth bias and the recon*.
##
## New entries join the tail rather than sorting into the middle. A doctrine's
## build_bias counts in places on this list, so every one of them is calibrated
## against where the units already sit; inserting above an entry silently weakens
## every bias aimed at it.
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
	&"rockets",
]
## The floor under the capture roster: infantry are bought until the team has at
## least this many capture-capable units, however little there is left to take.
## What raises it above the floor is capture_units_per_property.
@export var capture_unit_target: int = 3
## What to buy when the enemy is flying and we cannot reach them, best first.
## Nothing in build_priority is guaranteed to answer air, so this is asked ahead
## of it — otherwise an AI with a full bank watches bombers work unopposed.
@export var air_answer_ids: Array[StringName] = [&"anti_air", &"missiles", &"fighter", &"cruiser"]
## How many units that can shoot at aircraft the team wants while the enemy has
## any. Counted from the damage chart, not from this list.
@export var air_answer_target: int = 2
## How many supply units the team wants. Asked ahead of build_priority for the
## same reason the air answer is: nothing on that list refills anything, so an
## army that never buys one runs its artillery and its aircraft dry with no
## recourse. Counted from the roster's own can_resupply flag, not from a list of
## ids, and only wanted at all while supply_weight is on — a truck the planner
## would never drive is the empty carrier build_priority keeps out.
##
## One, on every tier: the planner has no route to a second. It cannot ferry, so
## a spare APC is a unit that follows the army doing nothing.
@export var supply_unit_target: int = 1
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

# --- Ranking capabilities -----------------------------------------------------
#
# Each gates a planner smart the base AI lacks. Every default is 0, which skips
# the capability entirely: at 0 the code that reads it never runs, and it never
# draws from the RNG stream. These change how the planner *ranks* its own
# candidate moves — never a combat number, which stays owned by CombatResolver.
#
# Not a Difficult-only block, whatever the shape of a capability suggests: a
# dial here is as usable to make a tier play badly as to make it play well, so
# every tier has a reason to reach for one. Which tier carries which value is a
# balance fact with one authority, the tier files under data/ai/ read beside
# docs/difficulty_check.md — do not restate it here.

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
## Denominated in TILES, because AIAdvance.position_rank is: the advance score steps by
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
## 0 keeps the static build_priority order exactly. Past 1.0 the blend in
## `AIProductionPlanner._reactive_order` runs its static-list coefficient
## negative and reads the list upside down, the same shape as condition_weight
## above — ranged for the same reason and clamped at the read for the same
## reason (COM-172).
@export_range(0.0, 1.0) var build_reactivity: float = 0.0

# --- Judgement capabilities ---------------------------------------------------
#
# The AI Judgement plan's dials. Noticing an enemy taking your ground and moving
# as an army are basic competence rather than a tier's smarts, which is why
# these were never written as one tier's block.
#
# 0 still skips a capability entirely — that is the code property, and the
# per-capability suites under tests/unit/ build explicit profiles to prove it.
# These defaults track data/ai/default.tres so an install with no profile file
# plays the same game as one with it, which is what
# test_default_profile_matches_the_built_in_defaults is for; tuning one of these
# means editing both, in the same commit. Which tier ships which value, and what
# it cost the difficulty ladder, is docs/difficulty_check.md's to say.
#
# withdraw_weight was held at 0 by the code rather than by balance: at 0.05 it
# stopped an artillery short of maximum standoff. That was a defect in how the
# refuge was priced and AR6d fixed it — a refuge is now ranked by the weapon it
# costs as well as the fire it dodges (tests/unit/test_ai_withdrawal.gd). The
# measurement has since been taken: the arena's first search campaign priced the
# repaired dial and found it worthless, which data/ai/brutal.tres's own header
# records. It ships at 0 everywhere as a measured result rather than a pending
# question, and a re-try means a fresh campaign, not a hand-picked value.

## What removing an enemy from ground our own side holds is worth, as a multiple
## of what taking that ground would be worth to us. The price list is the capture
## one read backwards — capture_score, capture_progress_bonus and
## hq_capture_multiplier, in that arithmetic — so at 1.0 denying a capture is
## worth exactly what making one is (AI Judgement D3). 0 skips it entirely.
##
## Denominated in VALUE, like _attack_score and like _consider_captures, which is
## what lets the three compete in one AIUnitPlan without a conversion — and which
## is also this dial's ceiling: the bonus is linear and priced on the same scale
## as a kill, so a rich enough target outbids even a match-ending capture no
## matter how high the weight goes (docs/difficulty_check.md §4c).
@export var defend_weight: float = 2.0
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
## also reset this one. It was probed together with cohesion_tiles and never
## apart, so move the pair together — see docs/difficulty_check.md.
@export var cohesion_radius: int = 2

# --- Economy capabilities -----------------------------------------------------
#
# The AI Economy plan's dials: a model of the map as an economy rather than as a
# fight. Same contract as the two blocks above — 0 skips the code, and the
# defaults here track data/ai/default.tres. Which tier ships which value is
# docs/difficulty_check.md's to say.

## Capture-capable units the team wants per property its side does not hold. The
## target is max(capture_unit_target, ceil(this x unowned)), so this raises the
## floor rather than replacing it, and 0 leaves the floor as the whole answer
## (AI Economy D5).
##
## It counts what is left to take rather than the size of the board, which is
## what makes it self-damping: the target falls as the map fills, and an army
## that has taken everything wants no more infantry. That is also how the board
## reaches the banking rule without the banking rule changing (D6) — a short
## roster is already urgent, so a property-rich board spends and a property-poor
## one banks, out of the same branch.
##
## Seated at 0.15 on Normal, Difficult and Brutal as the first of
## docs/causeway_measure.md's V4; Easy keeps it at 0 with its floor of 2.
@export var capture_units_per_property: float = 0.15
## How many capture units may claim one property as their goal. 0 turns claiming
## off and leaves the plain goal walk untouched; 1 is classic
## claiming, the nearest unit takes it and the next one is pushed to the next
## property; higher values let that many units travel to one contested property
## together.
##
## Denominated in UNITS, not tiles or value: it is a count of places rather than a
## price, because a claim is about who goes where and never about what the ground
## is worth. Derived from the board every time a goal is asked for and never
## stored (AI Economy D3) — the goal cache is one command deep by design, and a
## claim that outlived a command would have to be invalidated against a board
## that moves after every one.
##
## Spreading is untaxed by cohesion_tiles, which exempts every errand, so this
## number is the only thing limiting how thin a line the capture units form. Probe
## it against cohesion_tiles as a pair, never alone — see docs/difficulty_check.md.
@export var capture_claim_depth: int = 0
## What taking ground that *builds* is worth, as a multiple of taking ground that
## only pays. Asked of `TerrainType.builds` being non-empty — the same authority
## BuildCommand, the build menu and the production planner's facility scan read —
## so a base, a port and an airport are production and a city is not. 1.0 prices a
## factory exactly as a plains city, which is the shipped planner.
##
## Denominated in VALUE, because capture_score is: it multiplies the capture score
## beside hq_capture_multiplier rather than competing with it, so neither dial can
## shadow the other on ground both would price (AI Economy D4). On shipped terrain
## they never both apply — a headquarters builds nothing.
@export var production_capture_multiplier: float = 1.0
## How many tiles out of its way a unit will walk for the *whole* of what a
## production property is worth above an ordinary one. The detour is this times
## `production_capture_multiplier - 1`, so it is zero at either dial's inert
## value and the two readings can never disagree about the sign.
##
## Denominated in TILES, because the goal path is: `_consider_captures` competes
## in value against `_attack_score`, while a goal is chosen by how far away it is.
## That is the same split threat_aversion and advance_threat_tiles already live
## on, and it is why one judgement needs two fields. A unit that walks to a
## factory because it is valuable must then score it as valuable when it arrives,
## or it turns around on the doorstep.
@export var capture_goal_value_tiles: float = 0.0
## How many turns of income the treasury may exceed before the banking rule stops
## applying: past that ceiling the team buys the best thing it can reach today
## instead of waiting for something better. 0 never asks and is the shipped
## planner.
##
## Denominated in TURNS OF INCOME rather than in funds, because what makes a
## treasury a hoard is how long it took to fill: the same 20 000 is one turn's
## takings on a rich board and four on a poor one. It is a ceiling on the wait
## and not a second budget — the purchase itself is still whatever `_pick_build`
## already ranked best.
##
## Seated at 3.0 on Normal, Difficult and Brutal as the third of
## docs/causeway_measure.md's V4; the other two banking dials stay inert.
@export var spend_ceiling_turns: float = 3.0
## Whose banking answer a facility obeys: BANK_SCOPE_BOARD asks once for every
## empty facility together, which is the shipped planner; BANK_SCOPE_FACILITY
## asks each one about what it alone can produce.
##
## Board-wide, the most expensive thing any facility could eventually build
## silences all of them — a port saving for a hull stops two land bases that have
## the money for tanks today. Per facility, each one waits only for something it
## could build itself.
@export var bank_scope: int = BANK_SCOPE_BOARD
## How many places better than today's purchase the unit worth waiting for has to
## rank before the team banks for it. 0 banks for a one-place improvement, which
## is the shipped planner.
##
## Denominated in PLACES on the build list, the currency `_build_rank` answers in.
## That list is dense and one copy already fielded costs `duplicate_priority_cost`
## places, so a margin below that value is inside the noise a single purchase
## makes: it takes about that much before the wait is buying a genuinely better
## unit rather than the same list re-sorted.
@export var bank_rank_margin: int = 0

# --- Logistics capabilities ---------------------------------------------------
#
# Resupply, one of the two things the rules have always offered that the planner
# never asked for. Same contract as the blocks above — 0 skips the capability's
# code entirely, and the default here tracks data/ai/default.tres. Unlike those
# blocks it ships live on every tier: an inert dial here is a command type nobody
# can reach, which is the defect it exists to end. A tier scales it to its own
# character rather than switching it off. (Merging is the other, and it is the
# arena shelf's join_weight below.)
#
# Load and Drop stay unreachable on purpose: the planner cannot plan a ferry
# (naval plan R1), so a transport it could fill is a transport it would strand.

## What refilling the friendlies an APC can reach is worth, as a fraction of each
## one's value times the shortfall in the pool it is emptiest in. 0 skips it.
##
## Denominated in VALUE — the currency _attack_score and _consider_captures are
## already in, so a top-up competes with a shot and a capture in one AIUnitPlan
## without a conversion — and capped per unit at that unit's whole value, read
## through the planner's one _unit_value, since a refill can never be worth more
## than the thing it refills. Only what the AI can
## *field* limits how often this fires: build_priority names no transport, so it
## reaches an APC a board deals.
@export var supply_weight: float = 0.25

# --- The arena's shelf --------------------------------------------------------
#
# The AI Arena plan's shelf (AR6): the things the planner could not express at
# any setting of the dials above. Same contract as the three blocks before it —
# 0 skips the code, and the defaults here track data/ai/default.tres.
#
# The shelf shipped unmeasured on purpose and has since been priced: AR5's
# search campaign ran over it, cover_tiles and condition_weight earned places in
# the vector data/ai/brutal.tres seats and join_weight measured worthless and
# stayed benched beside focus_fire_bonus. docs/ai_arena_results.md is the
# measurement and the tier files are where the values live — not this comment.

## How many tiles of walking a unit will give up for one defence star of the
## ground it stops on. 0 skips it entirely.
##
## Denominated in TILES on both paths that read it, which is what keeps it one
## dial where threat_aversion and advance_threat_tiles had to be two: the advance
## path counts in tiles already, and on the attack path a tile costs
## step_cost_penalty, so the cover is spent out of the walk at the planner's own
## price of a tile rather than through a second field. One number and one
## sentence — how much further this unit will go to fight from that wood.
##
## The scale to keep in view is a mountain's four stars against a road's none:
## much above 1.0 the cover outweighs four tiles of advance, which parks an army
## on the high ground and leaves it there.
##
## Read with step_cost_penalty, because the attack path spends this through it:
## `_cover_score` is `step_cost_penalty * cover_tiles(...)`, so a tier pricing a
## tile at nothing prices cover at nothing there while the advance path, which
## counts tiles directly, still pays. That is what a tier shipping
## step_cost_penalty = 0.0 alongside a live cover_tiles buys, and it is
## consistent rather than broken — cover bought out of a walk costs nothing when
## the walk is free.
@export var cover_tiles: float = 0.0
## How much of a unit's price is its condition: 0 values every unit at its
## roster cost however little of it is left, 1 values it at cost x hp/100, and
## the values between interpolate. 0 skips it entirely.
##
## Defined on 0 to 1 and on nothing else, which is why it is the one dial here
## that declares its range rather than only documenting it: past 1 the
## interpolation extrapolates and prices a wounded unit below nothing, which
## inverts every valuation in the planner. A search that samples wider is held to
## the range by _unit_value, so the worst it gets is the strongest defined
## setting rather than a suicidal planner.
##
## Denominated as a FRACTION of the price rather than in the price's own units,
## because it is the shape of the valuation rather than a number added to it —
## which is what lets one dial answer for a unit as a target and as an asset at
## once. Whose unit it is is priced elsewhere and already: counter_weight
## discounts our own losses against their damage, and threat_aversion and
## withdraw_weight price our own skin.
##
## Deliberately an interpolation and not a switch. What 1.0 prices is what is
## left of the unit at the board's own rate — TurnRules._repair sells the missing
## HP back at `cost * heal / 100`, so the surviving half and the repair bill add
## up to the roster price exactly — and that is a floor rather than the whole
## answer: the unit is also on the board *now*, holding the tile it holds, and
## repair costs turns as well as money.
##
## kill_bonus is the other correction to this same valuation: it pays extra for
## finishing a target precisely because a nearly-dead one was priced like a fresh
## one. Move the two together and never one alone (arena plan R5) — a search that
## fits kill_bonus first will fit it to a valuation this dial then changes.
@export_range(0.0, 1.0) var condition_weight: float = 0.0
## What merging two damaged units of a kind is worth, as a multiple of the price
## of the HP that survives the merge. 0 skips it entirely.
##
## Denominated in VALUE, because a join is a candidate in the same AIUnitPlan an
## attack, a capture, a dive and a withdrawal compete for, and that competition
## is in funds (AI Judgement D4). The quantity it multiplies is the HP that
## actually lands: JoinCommand caps the merge at 100 and refunds nothing, so the
## overflow is destroyed, and it is charged back at face value — a loss the file
## can already price needs no dial of its own, while what concentration is worth
## is a judgement and needs exactly this one.
##
## A multiple rather than a flat score like dive_score, because consolidating
## thirty points of md tank is worth ten times consolidating thirty points of
## infantry, and a constant cannot say so.
##
## Expect a tuned value well below 1.0. At 1.0 the carried HP is priced as though
## the merge were free, and it is not: a join spends the mover's turn *and* the
## target's, and leaves one exhausted unit where two ready ones stood. That price
## is deliberately not a second dial — it is the reason this one is small.
@export var join_weight: float = 0.0

# --- Against the milling ------------------------------------------------------
#
# Three dials against one measured defect: 86-94% of unit actions in a live
# four-army match are pure repositioning, and a free-for-all on causeway decides
# none of 24 matches at any tier (docs/causeway_measure.md). Each answers one of
# the three mechanisms the analysed recordings named — a goal the unit could
# never engage, a capture walk nothing prices, and a stand-off potential with a
# limit cycle in it.
#
# Same contract as the blocks above: 0 skips the capability's code entirely.
# goal_engageability no longer ships inert — it is one of the three dials seated
# on Normal, Difficult and Brutal by docs/causeway_measure.md's V4, which took
# Causeway's 2v2 from 1 of 8 decided to 5 of 8; Easy keeps every one of them at 0.

## Whether the advance filters the enemies it may orient on down to the ones this
## unit could actually shoot. 0 walks at the nearest enemy of any kind, which is
## the pre-V4 planner; >0 asks AttackRange.can_engage.
##
## A flag rather than a magnitude — there is no half-engageable enemy — and it is
## a float only so it reads like every dial beside it. A unit with nothing it can
## engage anywhere still advances on the nearest enemy: freezing a cruiser on a
## land board reads worse than milling it up the coast.
@export var goal_engageability: float = 1.0
## How heavily a capture cell's expected incoming damage discounts the capture,
## as a fraction of the capturer's cost. 0 skips it entirely and never builds the
## threat map for a capture; >0 builds it on its own.
##
## Denominated in VALUE, in _threat_penalty's exact arithmetic, because
## _consider_captures is: the capture and the shot compete for one AIUnitPlan, so
## the fear that discounts them has to be in one currency.
##
## The fourth reader of the one ThreatMap, which is why it is its own dial rather
## than a wider threat_aversion — a capturer strolling into a firing ring is the
## defect, and pricing it through the attack path's dial would move every shot on
## the board to fix it. Tune it with threat_aversion, advance_threat_tiles and
## withdraw_weight, never alone: four dials over one map can price one enemy four
## times (AI Judgement R3).
@export var capture_threat_aversion: float = 0.0
## Whether an indirect unit already inside its own firing band is content there.
## 0 makes it want exactly maximum stand-off, which is the shipped planner; any
## value above 0 flattens the rank across the band.
##
## Maximum stand-off is measured against a nearest-enemy goal recomputed every
## turn, so it is a potential that repels up close and attracts from afar — a
## battleship was observed cycling between two cells for eight days. Flat inside
## the band lets AIAdvance.command_for's own cost tie-break hold the unit still.
##
## The cost is real and is the reason this ships inert: stand-off is a tactical
## preference, and a gun content at minimum range is a gun easier to close on.
@export var standoff_band_tolerance: int = 0


## The profile the game plays with. Falling back to an unmodified profile keeps
## a missing or broken file from taking the AI out entirely — it plays with the
## defaults above, which are the same numbers.
static func load_default() -> AIProfile:
	var profile := load(DEFAULT_PATH) as AIProfile
	if profile == null:
		push_error("AIProfile: cannot load %s; using built-in defaults" % DEFAULT_PATH)
		return AIProfile.new()
	return profile


## Whether any dial that builds the threat map is live, and the one place the
## four are listed: each gates its own read in AIUnitActionPlanner, while
## AIPlanCache asks the same question of a plan it is about to keep. A fifth
## dial stated in one of those two and not the other would let the cache keep a
## plan made before the map existed.
##
## `dive_score` is deliberately not a fifth, and reads the map only where one of
## these four already warrants it. It is live in every profile, so listing it
## would keep nothing on any board — including every board with no submarine on
## it — for a read only a submarine makes. Where a dial does warrant the map, the
## dive's read is the last branch of a plan whose earlier branches decide whether
## it is reached, so a re-score the cache skipped would have taken the same
## branch and the moment the map is built cannot move; where none does, the dive
## reads no map at all and there is nothing to guard. The narrow sea in
## tests/unit/test_ai_plan_cache.gd is what holds that.
func builds_threat_map() -> bool:
	return (
		threat_aversion > 0.0
		or advance_threat_tiles > 0.0
		or withdraw_weight > 0.0
		or capture_threat_aversion > 0.0
	)
