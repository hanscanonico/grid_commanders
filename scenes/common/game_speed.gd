class_name GameSpeed
extends RefCounted
## How fast the battle's theatre plays out on screen: one of three tiers, picked
## on the main menu and switchable mid-match.
##
## Presentation pacing and nothing else. No file under core/ or ai/ imports this
## or can reach a tier through Settings, so a speed change cannot move an
## outcome, a save, a replay or a seeded roll — the sim never observes the clock
## the theatre runs on. That is also why these numbers live here as constants
## rather than as .tres files under data/, breaking the difficulty-tier symmetry
## on purpose: data/ is for numbers the *sim* reads, and the whole safety
## argument of this setting is that the sim cannot read the speed.
##
## Which tier is active is Settings' answer and nobody else's. Callers ask it at
## the moment they animate rather than caching it at scene load, so a speed
## changed from the in-battle menu lands on the very next move.

## The tier a fresh install plays at, and the gentlest one there is: playtest
## said the old Normal still read as hurried and the old Slow was what people
## meant by normal, so the tiers moved down a rung (COM-226). Quick is the pace
## Normal used to be, one dropdown away.
const DEFAULT_ID := &"normal"
## Captures and scripted scenario runs *of the board* pin this tier instead of
## reading the device preference: a screenshot must not depend on which machine
## took it.
##
## Instant, because a still frame has nothing to photograph in an animation and
## every second one runs for is a second `make smoke` spends waiting. Scenarios
## advance on the scene's own state machine rather than a frame count, which is
## what makes that safe — see BattleScenarioDriver._until_state. An explicit
## `--speed=` still wins, so a tier stays inspectable through a capture.
##
## The menu is the one exception, and it has its own name below rather than an
## unexplained second answer at the call site.
const CAPTURE_ID := &"instant"
## What a *menu* capture pins, same rule and a different tier. The menu has no
## animation to skip, and it draws the speed setting: the Speed row highlights
## whichever tier is in hand, so pinning Instant would photograph a preference no
## fresh install has. The tier a fresh install plays at is the honest frame.
const MENU_CAPTURE_ID := DEFAULT_ID

## The durations the game shipped with, before any tier scaled them. No tier
## plays them unscaled any more: the gentlest is three times these and the
## briskest twice, which is what the retier below moved.
const BASE_MOVE_STEP_SECONDS := 0.06
const BASE_FLASH_IN_SECONDS := 0.08
const BASE_FLASH_OUT_SECONDS := 0.12
const BASE_DEATH_FADE_SECONDS := 0.25
const BASE_COMMAND_DELAY_SECONDS := 0.2
## Banners are information, not theatre: they hold at a readable length whatever
## the tier and only tighten under Instant, because whose day it is must still
## register even when nothing else is being shown. The power banner holds longer
## than the day banner because its card opens with the general's spoken line
## (plan PQ1) — a sentence needs more of a beat than a title.
const BANNER_SECONDS := 1.2
## Read at reading speed rather than glanced at: the card carries a spoken line,
## a power name and the exact effect text, and playtest (COM-247) said 1.5s was
## over before the words were. Any press still retires it early — see
## BattleAnimator.consume_banner_skip — so the longer hold costs an impatient
## player nothing.
const POWER_BANNER_SECONDS := 2.6
const INSTANT_BANNER_SECONDS := 0.5
## A scripted mission beat is the one card whose length is not known in advance:
## it may be a five-word order or two generals arguing, so it holds for as long
## as its own words take to read (COM-255) rather than for the power card's fixed
## beat. Below, that is a moment to notice the card plus a reading rate, floored
## at the power card's own beat so the shortest order is never *quicker* than the
## card this one is modelled on, and capped so a long exchange cannot park the
## board for a quarter of a minute — a player who has finished reading presses
## on, exactly as they do over the power card.
const SPEECH_BASE_SECONDS := 1.2
const SPEECH_SECONDS_PER_CHAR := 1.0 / 22.0
const SPEECH_MAX_SECONDS := 8.0
## How long the board's power marks take to lift and fade once the card clears.
## Scaled like the other theatre rather than held at a readable length, because
## the marks are on the board a player is already looking at.
const BASE_POWER_MARK_SECONDS := 0.3
## The AI opens its turn just after the awaited day banner clears. This is only
## the breathing room after it, never a second copy of the banner's own hold.
const START_DELAY_PADDING := 0.1

## Every tier, gentlest first — the order the menu lists and the in-battle row
## cycles in. `anim` scales movement, the hit flash and the death fade; `pace`
## scales the AI's think-beat between commands; `instant` skips the tweens
## outright instead of shortening them (an explicit branch, in the tradition of
## BattleAnimator's `capturing` flag, not a zero multiplied through the maths).
##
## This is the whole tuning surface: retuning a tier after playtest is one line,
## and COM-226 is that retune — Normal took the old Slow's numbers, Quick took
## the old Normal's, and Slow was dropped rather than left as a fourth rung
## nobody was picking. A `slow` stored in `user://settings.cfg` by an older
## build needs no migration code: `by_id` answers a stranger with the default,
## which is now the tier carrying exactly the numbers that preference asked for.
const TIERS: Array[Dictionary] = [
	{"id": &"normal", "display_name": "Normal", "anim": 3.0, "pace": 1.5, "instant": false},
	{"id": &"quick", "display_name": "Quick", "anim": 2.0, "pace": 1.0, "instant": false},
	{"id": &"instant", "display_name": "Instant", "anim": 0.0, "pace": 0.0, "instant": true},
]

## Built once from TIERS by `ordered()`; the tiers are immutable, so every
## caller shares the same instances and `by_id(x) == by_id(x)` holds.
static var _ordered: Array[GameSpeed] = []

var id: StringName
var display_name: String
var anim_scale: float
var pace_scale: float
## True for the tier that shows results rather than playing them out.
var instant: bool


func _init(tier: Dictionary) -> void:
	id = tier["id"]
	display_name = tier["display_name"]
	anim_scale = tier["anim"]
	pace_scale = tier["pace"]
	instant = tier["instant"]


# --- the tier table ----------------------------------------------------------


## Every tier in menu order, gentlest first.
static func ordered() -> Array[GameSpeed]:
	if _ordered.is_empty():
		for tier: Dictionary in TIERS:
			_ordered.append(GameSpeed.new(tier))
		# Handed out by reference to every caller, so the table itself is frozen
		# rather than copied per call — the shared instances are the point. The
		# freeze is the Array's; a tier's own fields are never written after
		# _init.
		_ordered.make_read_only()
	return _ordered


## The tier a fresh install plays at. Never null.
static func default_speed() -> GameSpeed:
	for tier in ordered():
		if tier.id == DEFAULT_ID:
			return tier
	return ordered()[0]


## Never null: an id naming no tier falls back to the default, the same
## defensive shape DifficultyDB answers a bad tier id with.
static func by_id(wanted: StringName) -> GameSpeed:
	for tier in ordered():
		if tier.id == wanted:
			return tier
	return default_speed()


## True when `wanted` names a tier. `by_id` answering a stranger with the default
## is right for stored state, which may predate a renamed tier, but wrong for an
## id someone typed just now: a caller that must say so out loud asks this first.
static func has_id(wanted: StringName) -> bool:
	for tier in ordered():
		if tier.id == wanted:
			return true
	return false


## Every tier id in menu order — what a diagnostic lists when an id names none.
static func ids() -> PackedStringArray:
	var known := PackedStringArray()
	for tier in ordered():
		known.append(String(tier.id))
	return known


# --- the durations a tier answers with ---------------------------------------


func move_step_seconds() -> float:
	return BASE_MOVE_STEP_SECONDS * anim_scale


func flash_in_seconds() -> float:
	return BASE_FLASH_IN_SECONDS * anim_scale


func flash_out_seconds() -> float:
	return BASE_FLASH_OUT_SECONDS * anim_scale


func death_fade_seconds() -> float:
	return BASE_DEATH_FADE_SECONDS * anim_scale


## How fast the cut-in clock runs, as a multiplier on delta — the one duration a
## tier states as a rate rather than as seconds, because a cut-in's beat sheet is
## already written in seconds and `anim_scale` applied to it outright would
## stretch a two-second exchange to six. The sheets are authored at the default
## tier, so that tier plays them unchanged and every other tier is a ratio of it.
##
## Instant never reaches a cut-in — BattleAnimator._cut_in_applies gates the tier
## out and plays the on-map path instead — so it answers 1.0 rather than dividing
## by its zero scale, keeping Instant an explicit branch rather than a limit.
func cutscene_rate() -> float:
	if instant or anim_scale <= 0.0:
		return 1.0
	return default_speed().anim_scale / anim_scale


## Zero under Instant, where BattleAiRunner awaits a single frame instead so the
## board still repaints once per command.
func command_delay_seconds() -> float:
	return BASE_COMMAND_DELAY_SECONDS * pace_scale


func banner_seconds() -> float:
	return INSTANT_BANNER_SECONDS if instant else BANNER_SECONDS


func power_banner_seconds() -> float:
	return INSTANT_BANNER_SECONDS if instant else POWER_BANNER_SECONDS


## How long a scripted beat's card holds, given how many characters it says.
## Information rather than theatre, like the two banners above: it is the words
## that scale it and not `anim_scale`, so Quick reads at the same speed Normal
## does and only Instant tightens it.
func speech_seconds(characters: int) -> float:
	if instant:
		return INSTANT_BANNER_SECONDS
	var read := SPEECH_BASE_SECONDS + maxi(characters, 0) * SPEECH_SECONDS_PER_CHAR
	return clampf(read, POWER_BANNER_SECONDS, SPEECH_MAX_SECONDS)


## Zero under Instant, where BattleAnimator skips the marks outright rather than
## drawing them for no frames.
func power_mark_seconds() -> float:
	return BASE_POWER_MARK_SECONDS * anim_scale


## How long the AI waits after the day banner clears before its first command.
func start_delay_seconds() -> float:
	return START_DELAY_PADDING
