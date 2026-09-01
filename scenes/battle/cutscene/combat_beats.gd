class_name CombatBeats
extends RefCounted
## The battle cut-in's beat sheet: which windows one exchange has, and where each
## one sits on the clock.
##
## Node-free and pure. `plan` reads the result's flags and the two weapon
## signatures' presentation numbers and hands back a sheet; it touches no `Node`,
## no scene and no clock, so the cut-in's timing is checkable without staging
## one — which it never was while this lived as a private static inside a
## `CanvasLayer`. CombatCutscene owns what is painted in each window; this owns
## when they open.
##
## A window of zero length is a beat this exchange does not have — an unanswered
## volley has no counter, a survivor has no death — and `CutscenePlayback.window`
## reads it as a flat 0, which switches that branch of the frame off.
##
## Beat budgets, in seconds at the default speed tier. A clean exchange runs
## ~1.5 s, one with a counter ~2.6 s, and the worst the roster can produce 2.9 s:
## long enough to read, short enough to sit through two hundred times.
## CutscenePlayback is the one place a tier scales them.

## The letterbox opening, and the plates sliding in behind it.
const WIPE_IN := 0.20
const PLATES := 0.22
## Where the squad has finished rolling into its firing slot. The arrive beat
## opens at WIPE_IN rather than earlier because that is where the wipe's own
## 60 px inward slide ends, and two opposed translations on one axis make the
## squad slide in, jerk back out and settle.
const ARRIVE_END := 0.34
## The volley's travel budget before a style's `travel_scale` is applied.
const TRAVEL := 0.29
const IMPACT := 0.34
const DEATH := 0.35
const HOLD := 0.18
const WIPE_OUT := 0.20
## The hold can be trimmed away entirely when the pacing asks for it, but the
## wipe cannot: a cut-in that vanishes on one frame reads as a glitch rather than
## as a fast exit.
const MIN_WIPE_SCALE := 0.4
## How far the impact opens before the round strictly arrives, and how far the
## death blast opens before the beat it takes over from settles. Both are the
## overlap that keeps one beat from visibly ending before the next begins.
const IMPACT_LEAD := 0.02
const DEATH_LEAD := 0.05

## The rate above which the wind-up stops being compressed. `speed` on the
## director is a global rate over the whole sheet, so a fourth-in-a-row cut-in at
## the Quick tier runs the clock at 2.16x — which converges every weapon's
## wind-up onto a spread nobody can see. Stretching the aim window against this
## ceiling holds each style's *real* wind-up at `aim_seconds / 1.5` once the rate
## is past it, so a howitzer still reads longer than a rifle at every setting.
##
## A flat floor (`max(aim, floor)`) is the rejected alternative: it collapses
## every style onto the same number at high rates, defending legibility by
## destroying the differentiation it exists to protect.
const AIM_RATE_CEILING := 1.5

## The recoil ramp ends as the barrel lights and runs backward for this share of
## the wind-up, floored. The floor is what keeps small arms' 24 ms of pull and
## thrust — 11 ms of real time at the Quick tier on a four-cut-in streak, under
## one frame at 60 Hz — from disappearing outright. It is allowed to open before
## the wind-up does, overlapping the tail of the arrive: a hull settling back as
## it finishes rolling in is the correct read, and the alternative is lengthening
## every short-aim style's sheet to make room for it.
const RECOIL_SHARE := 0.4
const RECOIL_FLOOR := 0.10

## The casualty beat opens just after the round lands, and outlives the impact by
## a flat two steps: nothing for a side that kept its whole squad, one step for a
## single loss, and the same step twice for two or more.
##
## Flat rather than per figure, and the cap costs something worth saying plainly:
## four figures lost buys only ~0.10 s more than one — about 33 ms per extra
## death — and `CutsceneSide`'s `reach` compresses the per-figure stagger into
## whatever window it is handed, so four deaths still land close together. The
## per-figure form (`0.13 * (lost - 1)`) does let them read separately, and it
## reaches +0.39; combined with the gating below that puts the worst counter at
## 3.44 s, which is over every bar in the design record. If playtest disagrees the
## lever is a third step here, with the counter budgets re-measured — not the
## uncapped form.
const CASUALTY_LEAD := 0.06
const CASUALTY_TAIL_ONE := 0.10
const CASUALTY_TAIL_MANY := 0.20

## How far after the impact opens a damage callout appears, and how far past the
## beat it belongs to it stays up.
const CALLOUT_LEAD := 0.08
const CALLOUT_TAIL := 0.3

## The letterbox and the plates, which every exchange has in the same place.
var wipe_in := Vector2.ZERO
var plates := Vector2.ZERO
## Both squads rolling the last stretch into their firing slots and halting.
## Concurrent with `plates`, so it costs the sheet nothing.
var arrive := Vector2.ZERO
## The attacker's wind-up, its recoil ramp, and the moment its barrels light.
var atk_ready := Vector2.ZERO
var atk_recoil := Vector2.ZERO
var atk_fire := 0.0
var atk_travel := Vector2.ZERO
var def_impact := Vector2.ZERO
## The defender's surplus figures going down. It gates the counter: ungated, a
## four-figure topple is still in the air 430 ms after the counter's muzzle
## lights, which reads as the wrong side dying.
var def_casualty := Vector2.ZERO
## How many figures `def_casualty`'s tail was sized for — zero for a dying
## side, which keeps its whole squad standing for the blast rather than
## toppling first. A seam field rather than private: CutsceneSide's own
## knock-back used to re-derive this from squad counts, which is the kind of
## second opinion that drifts the moment the two sides' notion of "died" part
## ways — the measured symptom was a kill's knock-back landing at ~47 ms of
## its intended 80.
var def_lost := 0
var def_death := Vector2.ZERO
## And the counter's mirror of all of it, off the defender's own signature.
var ctr_ready := Vector2.ZERO
var def_recoil := Vector2.ZERO
var def_fire := 0.0
var def_travel := Vector2.ZERO
var atk_impact := Vector2.ZERO
var atk_casualty := Vector2.ZERO
var atk_lost := 0
var atk_death := Vector2.ZERO
var wipe_out := Vector2.ZERO
var total := 0.0


## The beat sheet, laid out on the clock. Reads only the result's flags, so an
## exchange with no counter is genuinely shorter rather than padded with a pause.
##
## The travel and wind-up budgets come off the firing styles — an arcing shell is
## given longer to get there than a burst of tracer, and a howitzer elevates for
## nearly five times as long as a rifle squad shoulders. `tail` trims the closing
## hold and wipe, which is the only part the pacing is allowed to take. `rate` is
## how fast the clock this sheet is played on will run, and the only thing it
## changes is the wind-up (see AIM_RATE_CEILING) — read once by the caller, never
## per frame, or the sheet would re-plan itself mid-run.
static func plan(
	result: CombatSnapshot.CombatResult,
	atk_style: BattleStyle,
	def_style: BattleStyle,
	tail: float,
	rate: float
) -> CombatBeats:
	var beats := CombatBeats.new()
	var stretch := aim_stretch(rate)
	beats.wipe_in = Vector2(0.0, WIPE_IN)
	beats.plates = Vector2(WIPE_IN * 0.5, WIPE_IN * 0.5 + PLATES)
	beats.arrive = Vector2(WIPE_IN, ARRIVE_END)
	beats.atk_ready = Vector2(ARRIVE_END, ARRIVE_END + atk_style.aim_seconds * stretch)
	beats.atk_recoil = recoil_window(beats.atk_ready)
	beats.atk_fire = beats.atk_ready.y
	beats.atk_travel = Vector2(beats.atk_fire, beats.atk_fire + TRAVEL * atk_style.travel_scale)
	beats.def_impact = _impact_window(beats.atk_travel)
	beats.def_lost = _lost(
		result.defender_hp_before, result.defender_hp_after, result.defender_died
	)
	beats.def_casualty = casualty_window(beats.def_impact, beats.def_lost)
	var settled := maxf(beats.def_impact.y, beats.def_casualty.y)
	if result.defender_died:
		beats.def_death = Vector2(settled - DEATH_LEAD, settled - DEATH_LEAD + DEATH)
		settled = beats.def_death.y
	elif result.countered:
		beats.ctr_ready = Vector2(settled, settled + def_style.aim_seconds * stretch)
		beats.def_recoil = recoil_window(beats.ctr_ready)
		beats.def_fire = beats.ctr_ready.y
		beats.def_travel = Vector2(beats.def_fire, beats.def_fire + TRAVEL * def_style.travel_scale)
		beats.atk_impact = _impact_window(beats.def_travel)
		beats.atk_lost = _lost(
			result.attacker_hp_before, result.attacker_hp_after, result.attacker_died
		)
		beats.atk_casualty = casualty_window(beats.atk_impact, beats.atk_lost)
		settled = maxf(beats.atk_impact.y, beats.atk_casualty.y)
		if result.attacker_died:
			beats.atk_death = Vector2(settled - DEATH_LEAD, settled - DEATH_LEAD + DEATH)
			settled = beats.atk_death.y
	var hold := settled + HOLD * tail
	beats.wipe_out = Vector2(hold, hold + WIPE_OUT * maxf(tail, MIN_WIPE_SCALE))
	beats.total = beats.wipe_out.y
	return beats


## How much longer the wind-up runs on a clock going this fast. 1.0 at and below
## the ceiling, so the authored sheet is exactly what the default tier plays.
static func aim_stretch(rate: float) -> float:
	return maxf(1.0, rate / AIM_RATE_CEILING)


## The pull-thrust-settle ramp, ending as the barrel lights.
static func recoil_window(ready: Vector2) -> Vector2:
	if ready == Vector2.ZERO:
		return Vector2.ZERO
	return Vector2(ready.y - maxf(RECOIL_SHARE * (ready.y - ready.x), RECOIL_FLOOR), ready.y)


## The window surplus figures topple over, sized by how many this side lost.
static func casualty_window(impact: Vector2, lost: int) -> Vector2:
	if impact.y <= impact.x:
		return Vector2.ZERO
	var tail := 0.0
	if lost == 1:
		tail = CASUALTY_TAIL_ONE
	elif lost >= 2:
		tail = CASUALTY_TAIL_MANY
	return Vector2(impact.x + CASUALTY_LEAD, impact.y + tail)


## The window a damage callout is shown over: it outlives the impact, and a
## death holds it until the explosion has finished.
static func callout_window(impact: Vector2, death: Vector2) -> Vector2:
	if impact.y <= impact.x:
		return Vector2.ZERO
	var end := (death.y if death.y > death.x else impact.y) + CALLOUT_TAIL
	return Vector2(impact.x + CALLOUT_LEAD, end)


static func _impact_window(travel: Vector2) -> Vector2:
	return Vector2(travel.y - IMPACT_LEAD, travel.y - IMPACT_LEAD + IMPACT)


## How many figures a side puts on the ground. A side that dies loses none: the
## blast takes the squad whole, and toppling it first would leave the explosion
## going off over an empty patch of ground.
static func _lost(before: int, after: int, died: bool) -> int:
	if died:
		return 0
	return CutsceneSide.figures_for(before) - CutsceneSide.figures_for(after)
