class_name ArenaPools
extends RefCounted
## Who plays, on which boards, over which seeds — fixed here rather than on a
## command line.
##
## Three decisions live in this file, and all three are about being able to read
## a leaderboard *across* generations:
##
## - **The anchors are the three shipped tiers, never re-tuned mid-run** (plan
##   D7). Everything else a generation plays is selection pressure; the anchor
##   score is the only measurement comparable from one generation to the next.
## - **The pools are split by board *and* by seed**, and the validation half is
##   held out. A pool that moves between generations cannot be compared, and a
##   validation pool the search can see is not held out at all (R1).
## - **The boards are chosen for resolution, not variety.** A match that cannot
##   conclude tells fitness nothing, and `the_straits` at Easy is 100%
##   command-cap stalls in the Grand Atlas — a known instrument failure that
##   must never be fed to a fitness function.
##
## Node-free, so GUT reads the split without a process.

const TRAINING := "training"
const VALIDATION := "validation"
## What `pool_of` answers for a board or seed in neither pool. Deliberately a
## bucket of its own rather than a silent drop: a deliberate off-pool run — a
## calibration, a one-off matchup — is still scored, and still cannot be read as
## a pool result by mistake.
const OFF_POOL := "unpooled"
## The two pools a reported result carries, in report order (R1).
const POOLS: Array[String] = [TRAINING, VALIDATION]

## The fixed anchor set (D7). Paths rather than tier ids, because a candidate is
## a profile and the anchors have to be seatable the same way every rival is.
const ANCHORS: Array[String] = [
	"data/ai/easy.tres",
	"data/ai/default.tres",
	"data/ai/hard.tres",
]

## The day cap every pooled match is played at (D6): the horizon that resolves.
const DAYS := 100

## Land duel boards that resolve inside the cap. Measured 2026-08-04, anchors
## round-robin at a 100-day cap: all ten shipped land duel boards at one seed
## (60 of 60 decisive), then these four plus the reserve at twelve (72 matches a
## board).
##
## Four here and three held out — different boards, so a candidate is never
## validated on ground it was selected on. Naval boards are excluded while the
## planner cannot ferry, and every board seating three or four armies is
## excluded because a match seats exactly two candidates.
const TRAINING_BOARDS: Array[String] = [
	"scrimmage",  # 12x9, the starting armies decide it before big builds land
	"riverline",  # 18x13, a river front with two crossings
	"arsenal",  # 18x13, build-first: three bases and an airport a side
	"jet_stream",  # 20x14, four airfields: the pools' one air board
]
const VALIDATION_BOARDS: Array[String] = [
	"timberline",  # 16x14, three lanes, two of them foot-only
	"crossfire",  # 20x15, a central lake and a ring road
	"first_steps",  # 20x15, open and road-laced
]

## Seeds per board, per pool. The two ranges are adjacent and disjoint:
## validation starts where training stops, so the split holds on the seed axis
## as well as the board one.
const TRAINING_SEEDS := 12
const VALIDATION_SEEDS := 8
const VALIDATION_OFFSET := TRAINING_SEEDS

## Boards a pool could take and does not, each for a stated reason. `forge` asks
## the build-first question `arsenal` already asks (measured clean: 72 of 72
## decisive); `steelworks` is the slowest of the ten and the largest.
##
## `ironworks` is the one that was measured *out*: it is the only board of the
## ten that reaches `BalanceMatchEngine.COMMAND_CAP`, once in 72 matches, on a
## day-91 board holding 55 units against 3. Nothing was failing to resolve — a
## 3 000-command net sized for 20-day gates is simply short of a 100-day horizon
## on the roster's biggest economy — but a stalled match is a hard invariant
## failure of the run (D6), and a pool that fails its own run is not a pool.
## Read that as a cap to revisit rather than a board to distrust; the arena
## wants this board back.
const RESERVE_BOARDS: Array[String] = ["forge", "steelworks", "ironworks"]


## The boards of a pool, or an empty list when nothing answers to that name.
static func boards(pool: String) -> Array[String]:
	match pool:
		TRAINING:
			return TRAINING_BOARDS
		VALIDATION:
			return VALIDATION_BOARDS
	return []


## Where a pool starts in each board's seed range, and how many seeds it takes.
static func seed_offset(pool: String) -> int:
	return VALIDATION_OFFSET if pool == VALIDATION else 0


static func seeds(pool: String) -> int:
	return VALIDATION_SEEDS if pool == VALIDATION else TRAINING_SEEDS


## Which pool a played match belongs to, read back off the board and seed it was
## played with. The seed range is a board's own, so the index is recovered from
## `BalanceMatchSchedule` rather than guessed — one authority for the range, in
## both directions.
static func pool_of(map_name: String, seed_val: int) -> String:
	var index := seed_val - BalanceMatchSchedule.seed_at(map_name, 0)
	for pool: String in POOLS:
		var first := seed_offset(pool)
		if map_name in boards(pool) and index >= first and index < first + seeds(pool):
			return pool
	return OFF_POOL


## Every pairing of a candidate list: each unordered pair once, and **never a
## candidate against itself** (D5). A self-pairing is two identical vectors, so
## with both seatings counted it is a guaranteed level score and pure spent
## compute — and played from one seat only it would be nothing but seat credit,
## which is the reading that must never reach a leaderboard.
##
## A list that names the same candidate twice pairs it with itself by another
## name; that is the caller's to avoid, and the report's unpaired check is what
## catches the seat-credit half of it either way.
static func pairings(candidates: Array[String]) -> Array[Array]:
	var result: Array[Array] = []
	for first in candidates.size():
		for second in range(first + 1, candidates.size()):
			result.append([candidates[first], candidates[second]])
	return result


## The pool driver's arguments for one pool of the anchor round-robin — the one
## spelling of "play this pool", so a command line can never drift from the
## split `pool_of` reads matches back against.
static func pool_args(pool: String) -> String:
	var pairs: Array[String] = []
	for pairing: Array in pairings(ANCHORS):
		pairs.append("%s::%s" % [pairing[0], pairing[1]])
	return (
		"--maps=%s --pairings=%s --seeds=%d --seed-offset=%d --days=%d"
		% [
			",".join(boards(pool)),
			",".join(pairs),
			seeds(pool),
			seed_offset(pool),
			DAYS,
		]
	)
