class_name CinemaShot3D
extends RefCounted
## One shot of a board cinematic: the pose the lens opens on, the pose it drifts
## toward, and how fast — a pure function of the shot's own clock, so a frame
## posed at a time and a line skipped to its end land on the same picture.
##
## The drift is an ease that never arrives rather than a move of fixed length:
## an untimed line (the briefing read again) holds for as long as the player
## reads, and a camera that stopped dead after three seconds would read as a
## freeze.
##
## One world unit is one cell (`BoardSpace3D`), and every anchor handed in is a
## point on the ground: the builders decide how high above it to look.

## Framing a general standing on the board: how far back, how low and how far
## off-centre, for the medium shot a speaker is introduced in and the closer one
## the rest of their lines are said in. Each swings round the general from one
## side of the board's own bearing — `side` picks which, so two voices trade
## sides like a shot and its reverse — and pushes in as the line is said.
const MEDIUM_REACH := Vector2(3.2, 2.7)
const MEDIUM_PITCH_DEG := Vector2(15.0, 10.0)
const MEDIUM_THIRD := 0.42
const NEAR_REACH := Vector2(2.2, 1.9)
const NEAR_PITCH_DEG := Vector2(11.0, 8.0)
const NEAR_THIRD := 0.3
const ACTOR_SWING_DEG := 32.0
const ACTOR_DRIFT_DEG := 12.0
const ACTOR_DRIFT_SECONDS := 3.5
## The lens looks a little over the head, so the general stands in the lower
## half of the frame and the window over them has the sky to stand in; the
## closer shot looks a little lower, or it would crop the face at the bar.
const LOOK_AT_EYES := 1.3
const NEAR_LOOK_AT_EYES := 1.1
## Cells either side of straight ahead within which the board's middle picks no
## side for a speaker.
const SIDE_DEAD_ZONE := 1.0
## The establishing shot: high, craning down and turning a little, so a board
## the narrator describes is seen whole.
const WIDE_PITCH_DEG := Vector2(60.0, 50.0)
const WIDE_SWING_DEG := 12.0
const WIDE_PULL := 1.18
const WIDE_DRIFT_SECONDS := 4.5
## How far back the establishing shot stands per cell of the board: across it,
## and up it, which the pitch foreshortens.
const WIDE_PER_COLUMN := 0.9
const WIDE_PER_ROW := 1.5
const WIDE_REACH_MIN := 10.0
const WIDE_REACH_MAX := 44.0
## Framing what a beat just put on the board: close enough to see who arrived,
## far enough to see all of them.
const SUBJECT_REACH_BASE := 7.0
const SUBJECT_PER_CELL := 1.6
const SUBJECT_REACH_MAX := 20.0
## The Command Power: a low orbit that starts at the general's boots on one
## side and rises and pulls back round to the other, taking in the pillar of
## light as it climbs.
const LIMIT_REACH := Vector2(2.4, 3.8)
const LIMIT_PITCH_DEG := Vector2(6.0, 20.0)
const LIMIT_SWING_DEG := Vector2(-65.0, 25.0)
const LIMIT_LOOK := Vector2(0.7, 1.15)
const LIMIT_DRIFT_SECONDS := 1.6

var start: CinemaPose3D
var end: CinemaPose3D
var drift_seconds: float


func _init(p_start: CinemaPose3D, p_end: CinemaPose3D, p_drift_seconds: float) -> void:
	start = p_start
	end = p_end
	drift_seconds = p_drift_seconds


## The pose `t` seconds into the shot.
func pose_at(t: float) -> CinemaPose3D:
	var eased := 1.0 - exp(-maxf(t, 0.0) / maxf(drift_seconds, 0.001))
	return start.toward(end, eased)


## A shot of the general standing at `mark` with their eyes `eyes` above it,
## from `side` (+1 or -1) of `bearing`: the medium shot, or the closer one when
## `near`. The general stands on the third `side` names.
static func actor(
	mark: Vector3, eyes: float, bearing: float, side: int, near: bool
) -> CinemaShot3D:
	var reach := NEAR_REACH if near else MEDIUM_REACH
	var pitch := NEAR_PITCH_DEG if near else MEDIUM_PITCH_DEG
	var third := NEAR_THIRD if near else MEDIUM_THIRD
	var look_at := NEAR_LOOK_AT_EYES if near else LOOK_AT_EYES
	var yaw_from := bearing + side * deg_to_rad(ACTOR_SWING_DEG)
	var yaw_to := yaw_from - side * deg_to_rad(ACTOR_DRIFT_DEG)
	var middle := CinemaPose3D.new(Vector3.ZERO, 1.0, (yaw_from + yaw_to) / 2.0)
	var look := mark + Vector3.UP * eyes * look_at + middle.across() * side * third
	return CinemaShot3D.new(
		CinemaPose3D.new(look, reach.x, yaw_from, deg_to_rad(pitch.x)),
		CinemaPose3D.new(look, reach.y, yaw_to, deg_to_rad(pitch.y)),
		ACTOR_DRIFT_SECONDS
	)


## Which side of `post` a close shot stands on so the open third of the frame
## looks into the board rather than off its edge: +1 puts the speaker on the
## left third with the board's `middle` to their right. `fallback` answers for a
## post the middle is straight ahead of, which is how two voices on one axis
## still trade sides.
static func side_facing(post: Vector3, middle: Vector2, bearing: float, fallback: int) -> int:
	var across := CinemaPose3D.new(Vector3.ZERO, 1.0, bearing).across()
	var inward := Vector2(middle.x - post.x, middle.y - post.z).dot(Vector2(across.x, across.z))
	if absf(inward) < SIDE_DEAD_ZONE:
		return fallback
	return 1 if inward > 0.0 else -1


## The establishing shot over `focus`, from `reach` away.
static func wide(focus: Vector3, reach: float, bearing: float) -> CinemaShot3D:
	var swing := deg_to_rad(WIDE_SWING_DEG)
	return CinemaShot3D.new(
		CinemaPose3D.new(focus, reach * WIDE_PULL, bearing - swing, deg_to_rad(WIDE_PITCH_DEG.x)),
		CinemaPose3D.new(focus, reach, bearing + swing, deg_to_rad(WIDE_PITCH_DEG.y)),
		WIDE_DRIFT_SECONDS
	)


## How far back the establishing shot stands to take in a whole board.
static func board_reach(board: Vector2i) -> float:
	var reach := maxf(board.x * WIDE_PER_COLUMN, board.y * WIDE_PER_ROW)
	return clampf(reach, WIDE_REACH_MIN, WIDE_REACH_MAX)


## How far back a shot stands to take in every one of `cells`, around their
## middle.
static func subject_reach(cells: Array[Vector2i]) -> float:
	var middle := middle_of(cells)
	var spread := 0.0
	for cell in cells:
		spread = maxf(spread, BoardSpace3D.cell_centre(cell).distance_to(middle))
	return minf(SUBJECT_REACH_BASE + spread * SUBJECT_PER_CELL, SUBJECT_REACH_MAX)


## The middle of `cells` on the ground plane; the board's origin for none.
static func middle_of(cells: Array[Vector2i]) -> Vector2:
	if cells.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for cell in cells:
		sum += BoardSpace3D.cell_centre(cell)
	return sum / cells.size()


## The Command Power's orbit round the general at `mark`, eyes `eyes` high.
static func limit(mark: Vector3, eyes: float, bearing: float) -> CinemaShot3D:
	var yaw_from := bearing + deg_to_rad(LIMIT_SWING_DEG.x)
	var yaw_to := bearing + deg_to_rad(LIMIT_SWING_DEG.y)
	var landed := CinemaPose3D.new(Vector3.ZERO, 1.0, yaw_to)
	var look_to := mark + Vector3.UP * eyes * LIMIT_LOOK.y + landed.across() * MEDIUM_THIRD
	return CinemaShot3D.new(
		CinemaPose3D.new(
			mark + Vector3.UP * eyes * LIMIT_LOOK.x,
			LIMIT_REACH.x,
			yaw_from,
			deg_to_rad(LIMIT_PITCH_DEG.x)
		),
		CinemaPose3D.new(look_to, LIMIT_REACH.y, yaw_to, deg_to_rad(LIMIT_PITCH_DEG.y)),
		LIMIT_DRIFT_SECONDS
	)
