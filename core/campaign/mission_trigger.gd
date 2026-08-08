class_name MissionTrigger
extends Resource
## One condition a scripted event waits for. Subclasses live in
## `core/campaign/triggers/` and each answers exactly one question about a
## committed board.
##
## `is_met` is `MissionObjective.is_met`'s shape and inherits its whole contract
## (campaign-depth D2): it reads only authorities that already exist, it never
## mutates, and it re-derives nothing the sim owns. No timers, no callbacks and
## no `EventBus` subscription — an event can only fire at a command boundary,
## which is exactly where the mission is already asked for a verdict, so there is
## one place in the codebase to look.
##
## Ground and armies are read **by side** through `GameState.allied`, for the
## reason the objectives are: counting a bare team is how an ally's action makes
## a mission unwinnable.
##
## An event's triggers are a **conjunction** — every one of them must hold — and
## that is what makes a small vocabulary expressive: `ObjectiveMet` plus
## `DayBefore` is "did it, and did it fast", and either of them plus `Flag` is
## the same beat conditioned on how an earlier mission went.


## Does this condition hold on the board as it now stands? `team` is the
## mission's player team; a side-wide reading asks `state.allied`. `progress` is
## the mission's tally, for the conditions no single board can answer, and
## `ledger` is the campaign's consequence ledger — which `Flag` alone reads,
## being the one condition that reaches outside this mission. A null ledger is a
## mission played outside a campaign profile, where every fact reads zero.
func is_met(
	_state: GameState, _team: int, _progress: MissionProgress, _ledger: CampaignState = null
) -> bool:
	return false


## The band on the consequence ledger this condition reads, or null — `Flag` alone
## answers with anything. Declared here for the reason `MissionEffect.written_flag`
## is: the fact is the *war's* rather than the board's, and whether the campaign
## ever writes the name it asks after is a question only the whole campaign can
## answer (`CampaignDefinition.ledger_error`).
func read_condition() -> FlagCondition:
	return null


## Why this condition could never come true on this mission's board, or "".
## Called once when a mission loads, so an authoring mistake — a cell that is not
## a property, a unit this board never names — fails visibly at the door rather
## than as an event that never fires.
##
## `unit_db` is handed over rather than loaded here, so this stays the pure read
## it claims to be: the caller checking a mission already holds one.
func definition_error(_map: MapData, _team: int, _unit_db: UnitDB) -> String:
	return ""
