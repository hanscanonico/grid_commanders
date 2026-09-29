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

## Where a speaker's screen floats over their post, and the height the close
## shot looks at — between the roof it stands over and the face on the screen.
const HOLO_FLOAT := 1.05
const CLOSE_LOOK := 1.1
## Low and near, pushing in as the line is said, and swinging round the post
## from one side of the board's own bearing — `side` picks which, so two voices
## trade sides like a shot and its reverse.
const CLOSE_REACH := Vector2(7.6, 6.4)
const CLOSE_PITCH_DEG := Vector2(24.0, 16.0)
const CLOSE_SWING_DEG := 30.0
const CLOSE_DRIFT_DEG := 16.0
## How far the lens looks past the post, across the frame: the speaker stands on
## a third of the picture rather than in its middle.
const CLOSE_THIRD := 1.0
const CLOSE_DRIFT_SECONDS := 3.5
## Cells either side of straight ahead within which the board's middle picks no
## side for a speaker.
const SIDE_DEAD_ZONE := 1.0
## A second line from the same voice keeps the camera moving round them.
const MORE_DRIFT_DEG := 14.0
const MORE_PUSH := 0.92
const MORE_PITCH_DEG := 3.0
const LOWEST_PITCH_DEG := 10.0
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
## The Command Power: a fast swoop from high on one side to low on the other,
## ending under the general's screen.
const POWER_REACH := Vector2(10.5, 5.6)
const POWER_PITCH_DEG := Vector2(34.0, 13.0)
const POWER_SWING_DEG := Vector2(-60.0, 20.0)
const POWER_LOOK := Vector2(1.2, 1.45)
const POWER_DRIFT_SECONDS := 1.2

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


## A speaker's close shot on `post`, from `side` (+1 or -1) of `bearing`.
static func close(post: Vector3, bearing: float, side: int) -> CinemaShot3D:
	var yaw_from := bearing + side * deg_to_rad(CLOSE_SWING_DEG)
	var yaw_to := yaw_from - side * deg_to_rad(CLOSE_DRIFT_DEG)
	var middle := CinemaPose3D.new(Vector3.ZERO, 1.0, (yaw_from + yaw_to) / 2.0)
	var look := post + Vector3.UP * CLOSE_LOOK + middle.across() * side * CLOSE_THIRD
	return CinemaShot3D.new(
		CinemaPose3D.new(look, CLOSE_REACH.x, yaw_from, deg_to_rad(CLOSE_PITCH_DEG.x)),
		CinemaPose3D.new(look, CLOSE_REACH.y, yaw_to, deg_to_rad(CLOSE_PITCH_DEG.y)),
		CLOSE_DRIFT_SECONDS
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


## The same voice again: carry on from wherever the lens is, a little further
## round and a little closer, so a speech in two lines is one continuous move.
static func more(from: CinemaPose3D, side: int) -> CinemaShot3D:
	var pitch := maxf(from.pitch - deg_to_rad(MORE_PITCH_DEG), deg_to_rad(LOWEST_PITCH_DEG))
	var onward := CinemaPose3D.new(
		from.target, from.reach * MORE_PUSH, from.yaw - side * deg_to_rad(MORE_DRIFT_DEG), pitch
	)
	return CinemaShot3D.new(from, onward, CLOSE_DRIFT_SECONDS)


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


## The Command Power's swoop onto `post`.
static func power(post: Vector3, bearing: float) -> CinemaShot3D:
	var yaw_from := bearing + deg_to_rad(POWER_SWING_DEG.x)
	var yaw_to := bearing + deg_to_rad(POWER_SWING_DEG.y)
	var landed := CinemaPose3D.new(Vector3.ZERO, 1.0, yaw_to)
	var look_to := post + Vector3.UP * POWER_LOOK.y + landed.across() * CLOSE_THIRD
	return CinemaShot3D.new(
		CinemaPose3D.new(
			post + Vector3.UP * POWER_LOOK.x, POWER_REACH.x, yaw_from, deg_to_rad(POWER_PITCH_DEG.x)
		),
		CinemaPose3D.new(look_to, POWER_REACH.y, yaw_to, deg_to_rad(POWER_PITCH_DEG.y)),
		POWER_DRIFT_SECONDS
	)
