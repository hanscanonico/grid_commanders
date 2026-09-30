class_name CaptureBeats
extends RefCounted
## The capture cut-in's beat sheet: the march, one to three mashes, the flip on a
## completing capture, the banner and the wipe — and the point chips each mash
## knocks off the meter.
##
## Node-free and pure, like CombatBeats. `plan` reads only the CaptureResult it is
## handed, so the flat cut-in and the 3D stage land every mash on the same beat
## and knock off the same chips. The chips are a presentation split of the
## committed delta (`points_before - points_after`), never a call back into
## `capture_strength`, so a press mid-mash lands on the number the terrain panel
## reports.
##
## Beat budgets, in seconds at the default speed tier. A completing capture runs
## ~2.4 s and a partial ~2.0 — deliberately faster than the design handoff's 4.6 s
## reference, because captures are the most frequent ceremony in the game (plan
## R1). CutscenePlayback is the one place a tier scales them.

const WIPE_IN := 0.22
const PLATES := 0.22
const MARCH := 0.34
const HOP_DUR := 0.24
const HOP_GAP := 0.03
const FLIP := 0.30
const BANNER := 0.55
const HOLD := 0.20
const WIPE_OUT := 0.20
const MIN_WIPE_SCALE := 0.4
## At most three mashes, however many points came off — a strength-12 doctrine
## turn still reads as three hops, not twelve.
const MAX_HOPS := 3

## A window of zero length is a beat this capture does not have: a partial has no
## flip, and its banner opens where the flip would have.
var plates := Vector2.ZERO
var march := Vector2.ZERO
var hops: Array[Vector2] = []
var lands := PackedFloat32Array()
var flip := Vector2.ZERO
var banner := Vector2.ZERO
var wipe_out := Vector2.ZERO
var total := 0.0
## The points each mash knocks off, largest first, summing to the meter's drop.
var chips := PackedInt32Array()


## The whole sheet for one capture. `tail` trims the closing hold and wipe, the
## only part the pacing is allowed to take — the mashes and the flip keep their
## length, because those carry what the cut-in is for.
static func plan(result: CaptureCommand.CaptureResult, tail: float) -> CaptureBeats:
	var removed := maxi(result.points_before - result.points_after, 0)
	var count := clampi(removed, 1, MAX_HOPS)
	var beats := lay_out(result.captured, count, tail)
	beats.chips = split(removed, count)
	return beats


## Splits the points removed across the mashes, largest first: 10 over 3 hops is
## 4/3/3, a doctrine's 12 is 4/4/4, a finishing 1 is a single hop of 1.
static func split(removed: int, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var base := removed / count
	var extra := removed % count
	for i in count:
		out.append(base + (1 if i < extra else 0))
	return out


## The windows alone, laid out on the clock for `count` mashes.
static func lay_out(captured: bool, count: int, tail: float) -> CaptureBeats:
	var beats := CaptureBeats.new()
	beats.plates = Vector2(WIPE_IN * 0.5, WIPE_IN * 0.5 + PLATES)
	beats.march = Vector2(WIPE_IN, WIPE_IN + MARCH)
	var t := beats.march.y
	for i in count:
		var start := t + i * (HOP_DUR + HOP_GAP)
		beats.hops.append(Vector2(start, start + HOP_DUR))
		beats.lands.append(start + HOP_DUR)
	var settled: float = beats.lands[beats.lands.size() - 1]
	var banner_start := settled + 0.05
	if captured:
		beats.flip = Vector2(settled + 0.05, settled + 0.05 + FLIP)
		banner_start = beats.flip.x + FLIP * 0.4
	beats.banner = Vector2(banner_start, banner_start + BANNER)
	var hold := beats.banner.y + HOLD * tail
	beats.wipe_out = Vector2(hold, hold + WIPE_OUT * maxf(tail, MIN_WIPE_SCALE))
	beats.total = beats.wipe_out.y
	return beats


## What the meter reads at `t`: the points going in, less every chip whose mash
## has landed by then.
func points_at(points_before: int, t: float) -> int:
	var shown := points_before
	for i in lands.size():
		if t >= lands[i]:
			shown -= chips[i]
	return shown
