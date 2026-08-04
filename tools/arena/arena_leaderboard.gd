class_name ArenaLeaderboard
extends RefCounted
## One row per candidate: what it scored, in each pool it played.
##
## Every match is counted **twice** — once for the side in each seat — which is
## what makes the seat cancel: a candidate that played both seatings of a
## pairing holds the first-seat edge exactly as often as it faced it, and a
## zero-sum score then sums it away (plan D5).
##
## That only holds if both seatings are actually present, so this refuses to
## report a pairing it saw from one seat only. The Balance Lab plays a mirror
## from one seat on purpose — with both sides the same, the first seat's win
## rate *is* what the seat is worth — and that reading is a bias measurement.
## Letting it into a leaderboard is exactly the failure D5 names, so it is
## refused here rather than documented.
##
## Node-free, so GUT tallies records without a process.

## Rows in report order, best first.
var rows: Array[Row] = []
## Matches whose hard invariants did not hold — a rejected command, or a match
## that would not resolve. Counted, never scored.
var invalid := 0
## Pairings seen from one seat only, as readable keys. Any at all and the run is
## not reportable.
var unpaired: Array[String] = []


## What one candidate did in one pool.
class Tally:
	var matches := 0
	var wins := 0
	var losses := 0
	var unresolved := 0
	var total := 0.0

	func mean() -> float:
		return total / matches if matches > 0 else 0.0

	func to_dict() -> Dictionary:
		return {
			"matches": matches,
			"wins": wins,
			"losses": losses,
			"unresolved": unresolved,
			"score": snappedf(total, 0.001),
			"mean": snappedf(mean(), 0.001),
		}


class Row:
	var candidate := ""
	## pool name -> Tally, for the pools this candidate actually played.
	var pools: Dictionary = {}

	func tally(pool: String) -> Tally:
		if not pools.has(pool):
			pools[pool] = Tally.new()
		var found: Tally = pools[pool]
		return found

	func mean(pool: String) -> float:
		return pools[pool].mean() if pools.has(pool) else 0.0

	func matches(pool: String) -> int:
		return pools[pool].matches if pools.has(pool) else 0

	func to_dict() -> Dictionary:
		var by_pool: Dictionary = {}
		for pool: String in pools:
			by_pool[pool] = pools[pool].to_dict()
		return {"candidate": candidate, "pools": by_pool}


## Tallies every record. A record scores both its sides, in the pool the board
## and seed it was played with belong to.
static func build(records: Array) -> ArenaLeaderboard:
	var board := ArenaLeaderboard.new()
	var by_candidate: Dictionary = {}
	var seats_seen: Dictionary = {}
	for record: Dictionary in records:
		var pairing := _pairing_key(record)
		var seats: Array = seats_seen.get(pairing, [])
		seats.append(int(record["seat"]))
		seats_seen[pairing] = seats
		if ArenaFitness.result_of(record) == ArenaFitness.Result.INVALID:
			board.invalid += 1
			continue
		var pool := ArenaPools.pool_of(String(record["map"]), int(record["seed"]))
		for team: int in [ArenaFitness.RED_TEAM, ArenaFitness.BLUE_TEAM]:
			var candidate := ArenaFitness.candidate_at(record, team)
			if not by_candidate.has(candidate):
				var fresh := Row.new()
				fresh.candidate = candidate
				by_candidate[candidate] = fresh
			var row: Row = by_candidate[candidate]
			_count(row.tally(pool), record, team)
	for pairing: String in seats_seen:
		var seats: Array = seats_seen[pairing]
		if not (0 in seats and 1 in seats):
			board.unpaired.append(pairing)
	board.unpaired.sort()
	board.rows = _ordered(by_candidate.values())
	return board


## Empty when the run can be read as a leaderboard; otherwise why it cannot.
func problem() -> String:
	if not unpaired.is_empty():
		return (
			"%d pairing(s) were played from one seat only, so the seat has not cancelled: %s"
			% [unpaired.size(), ", ".join(unpaired.slice(0, 3))]
		)
	if invalid > 0:
		return "%d match(es) rejected a command or would not resolve" % invalid
	return ""


func to_dict() -> Dictionary:
	var listed: Array[Dictionary] = []
	for row in rows:
		listed.append(row.to_dict())
	return {
		"fitness":
		{
			"decisive": ArenaFitness.DECISIVE,
			"speed_weight": ArenaFitness.SPEED_WEIGHT,
			"unresolved": ArenaFitness.UNRESOLVED,
			"horizon": ArenaFitness.HORIZON,
		},
		"invalid": invalid,
		"unpaired": unpaired,
		"candidates": listed,
	}


static func _count(tally: Tally, record: Dictionary, team: int) -> void:
	tally.matches += 1
	tally.total += ArenaFitness.score(record, team)
	if ArenaFitness.result_of(record) == ArenaFitness.Result.UNRESOLVED:
		tally.unresolved += 1
	elif int(record["winner"]) == team:
		tally.wins += 1
	else:
		tally.losses += 1


## Best first: the held-out number leads, because a candidate that leads on the
## pool it was selected on and not on the one it was not has overfitted (R1).
static func _ordered(found: Array) -> Array[Row]:
	var listed: Array[Row] = []
	for row: Row in found:
		listed.append(row)
	listed.sort_custom(
		func(a: Row, b: Row) -> bool:
			for pool: String in [ArenaPools.VALIDATION, ArenaPools.TRAINING, ArenaPools.OFF_POOL]:
				if not is_equal_approx(a.mean(pool), b.mean(pool)):
					return a.mean(pool) > b.mean(pool)
			return a.candidate < b.candidate
	)
	return listed


## One pairing on one board at one seed, however it was seated: the two seats of
## a matchup have to land on the same key or the pairing check cannot see them
## as a pair.
static func _pairing_key(record: Dictionary) -> String:
	var sides: Array[String] = [String(record["red"]), String(record["blue"])]
	sides.sort()
	return "%s#%s_vs_%s#s%d" % [record["map"], sides[0], sides[1], int(record["seed"])]
