class_name ArenaFitness
extends RefCounted
## What "better" means, one match at a time.
##
## Win or lose over twenty continuous dials is a step function: almost every
## mutation changes nothing measurable and the search spends its compute on
## noise. So a match is scored rather than counted, and the score is built only
## from what an arena record carries (plan D4).
##
## Three ordered classes, and the order is the point: a decisive win outranks an
## unresolved match, which outranks a decisive loss, and no amount of grading
## inside a class can cross the boundary. Inside the decisive class an earlier
## win outranks a later one.
##
## The score is **zero-sum** — the loser scores exactly the negative of the
## winner — which is what makes counting both seatings cancel the seat instead
## of reporting it (D5). Two identical vectors playing both seats therefore
## score exactly level, whatever the seat is worth on that board.
##
## Node-free, so GUT scores a record without a process.

## The horizon the arena plays at (D6), and the reference the speed term is
## measured against — deliberately a constant rather than the day cap of
## whichever run produced the record, so that a score means the same thing in
## every run that is compared. A shorter cap simply scores in the upper part of
## the range, and the ordering inside such a run is unchanged.
const HORIZON := 100
## What winning is worth. It dominates the speed term, so the *fact* of the win
## always outranks how quickly it came.
const DECISIVE := 1.0
## What winning early is worth on top of that, at most — a win on day 1 scores
## 1.5, a win on day 100 scores 1.0.
const SPEED_WEIGHT := 0.5
## What two candidates that could not beat each other are worth: nothing, to
## either of them. Deliberately *not* the engine's day-cap tiebreak, which ranks
## a stalemate on property count and so pays whoever hoards better (D6).
const UNRESOLVED := 0.0

## How a match ended, as fitness sees it. `INVALID` is a rejected command or a
## command-cap stall: the AI and the rules disagreed, which is a failure of the
## run rather than a result, and it is never scored.
enum Result { DECISIVE, UNRESOLVED, INVALID }

## The seats a record's `red` and `blue` sit in, which is what `winner` names.
const RED_TEAM := 1
const BLUE_TEAM := 2


## Which class a record falls in. `day_cap` is the unresolved one: the engine
## fills `winner` in from its score tiebreak there, and that is precisely the
## number D6 forbids fitness to read.
static func result_of(record: Dictionary) -> Result:
	if int(record["rejected"]) > 0 or bool(record["cap_stall"]):
		return Result.INVALID
	if String(record["termination"]) == "day_cap":
		return Result.UNRESOLVED
	return Result.DECISIVE


## What this match was worth to the side sitting in `team`. Positive for a win,
## its exact negative for the loss, zero for an unresolved match and for a match
## that never should have been played.
static func score(record: Dictionary, team: int) -> float:
	if result_of(record) != Result.DECISIVE:
		return UNRESOLVED
	var worth := DECISIVE + SPEED_WEIGHT * speed(record)
	return worth if int(record["winner"]) == team else -worth


## How much of the horizon the winner had left, in [0, 1]. Clamped rather than
## assumed, because a run played past HORIZON would otherwise pay a negative
## bonus and invert the ordering it exists to set.
static func speed(record: Dictionary) -> float:
	return clampf(float(HORIZON - int(record["day_ended"])) / float(HORIZON), 0.0, 1.0)


## The candidate seated in `team`, as the record names it.
static func candidate_at(record: Dictionary, team: int) -> String:
	return String(record["red"] if team == RED_TEAM else record["blue"])
