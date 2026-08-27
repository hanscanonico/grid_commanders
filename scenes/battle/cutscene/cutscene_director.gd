class_name CutsceneDirector
extends CanvasLayer
## The lifecycle a cut-in is played through: one clock, one skip, one exit.
##
## `CutscenePlayback` is the shell a director composes — the clock, the
## letterbox, the camera's return to rest and the cue ledger — and this is the
## `Node` half around it: the process pump that drives that clock, the press that
## cuts it short, the single `finished`, and the two ways in. Both were written
## twice, once per director, which is the second opinion the shell exists to
## prevent.
##
## A subclass owns its beat sheet and what it paints in the band, and answers two
## questions: `_total()`, how long its sheet runs, and `_apply()`, the whole frame
## as a pure function of `_play.t`. It builds its own layers in `_ready`, because
## what a cut-in stages is its own.

## Emitted once per cut-in, when the wipe has cleared and control belongs to the
## caller again. Every branch funnels through `_finish`, which is the only place
## that emits it.
signal finished

## The board the cut-in is staged over. Assigned by Battle before first use —
## the same assignment-not-constructor shape BattleView and BattleAnimator use,
## so a cut-in never learns what a Battle is.
var view: BattleView
## Playback rate, and how much of the closing hold and wipe is kept. Both are the
## AI-pacing levers: a side acting over and over gets a faster cut-in with most
## of its ceremony cut away, while the beats that carry the information keep
## their full length at every setting. The animator sets them.
var speed := 1.0
var tail_scale := 1.0

## The clock, the letterbox and the single exit. It also owns the board's return
## to rest: the cut-in eases the entry flinch's zoom back out over the closing
## wipe, so the board is already at rest on the frame it is uncovered.
var _play := CutscenePlayback.new()


## A director rests until it is run. Set here rather than in a `_ready` the
## subclasses would have to remember to call up to.
func _init() -> void:
	set_process(false)
	set_process_unhandled_input(false)


## Shows the posed cut-in and starts its clock. The caller awaits `finished`.
func run() -> void:
	_play.begin(_total(), view)
	_play.layout()
	_apply()
	_play.root.show()
	set_process(true)
	set_process_unhandled_input(true)


## Freezes the posed cut-in at one moment of its own clock and leaves it there.
## No clock runs, no sound plays and `finished` is never emitted — a still, not a
## playthrough, which is what makes it byte-stable. A still never punched the
## board either, so `pose` keeps `_apply` off its zoom.
func hold(at: float) -> void:
	_play.pose(_total(), at)
	_play.layout()
	_apply()
	_play.root.show()


## Fast-forwards every remaining beat to its end state. Never aborts: the clock is
## simply set to the end, the final tableau is applied, and the same exit runs —
## which is what makes a skip at any beat land on the right board.
func skip() -> void:
	_play.skip()


## A side's accent colour, asked of the identity that resolved the match rather
## than of the commander directly. SideIdentity gives a commanded side its own
## faction's colour and a commander-less one the classic its slot falls back to,
## and it is the only one that knows about the mirror borrow: in an Iron v Iron
## the later side's army is drawn in a borrowed classic, so asking
## CommanderVisuals for its general's faction would put slate on both name
## plates, in the very frame the borrow exists to tell apart.
func accent_of(team: int) -> Color:
	return view.identity.theme(team).color_light


func _process(delta: float) -> void:
	if not _play.playing:
		return
	var done := _play.advance(delta * speed)
	_apply()
	if done:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if _play.consume_skip(event):
		get_viewport().set_input_as_handled()


## The single exit. Every branch reaches it, and it emits once.
func _finish() -> void:
	if not _play.playing:
		return
	_play.end()
	set_process(false)
	set_process_unhandled_input(false)
	finished.emit()


## Everything the cut-in shows, as a pure function of `_play.t`. Called once per
## frame while playing and once more by `skip`, so it may never do anything that
## only makes sense the first time.
func _apply() -> void:
	push_error("CutsceneDirector: %s paints no frame" % get_script().resource_path)


## How long this cut-in's beat sheet runs, in seconds of its own clock.
func _total() -> float:
	return 0.0
