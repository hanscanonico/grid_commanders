class_name TutorialHints
extends RefCounted
## The first-match script: the objective line and the five steps the mission
## strip teaches, in the order a first turn performs them (UX recovery plan D6 —
## teach by doing, retire by success).
##
## Copy and ordering only. This owns no rule and observes no event: which step is
## next is a pure function of the ids already retired, and *when* one retires is
## MissionStrip's job, decided off the same EventBus events the scene already
## animates. Nothing under `core/` or `ai/` learns any of this exists.
##
## Node-free on purpose, like SideIdentity and GameSpeed beside it: the step list
## and the character cap are the two things a test can hold the copy to, and a
## surface that needed a scene tree to answer "what comes next" could not be.

## The one line the strip leads with. Both routes to a win, in the vocabulary the
## board already uses — the two things `GameState` actually ends a match on.
const OBJECTIVE := "Take the enemy HQ, or wipe out every enemy unit."

## The editorial ruler `tests/unit/test_tutorial_copy.gd` enforces. Not a
## rendering fact: the strip clips nothing and would happily draw a paragraph.
## It is the width past which a hint stops being a hint, and 640x360 logical is
## what makes it a short one (plan R2/R3 — one line each).
const MAX_BODY_CHARS := 62
const MAX_LABEL_CHARS := 10

## The steps, in teaching order. Each `id` is what `Settings` stores once the
## player has performed it, so renaming one un-retires it for everybody who
## already earned it — treat these as persisted values, not as labels.
const STEPS: Array[Dictionary] = [
	{
		"id": &"select",
		"label": "SELECT",
		"body": "Put the cursor on one of your units and press ENTER.",
	},
	{
		"id": &"move",
		"label": "MOVE",
		"body": "Press ENTER on a blue cell, then pick an action.",
	},
	{
		"id": &"capture",
		"label": "CAPTURE",
		"body": "Walk a foot unit onto a city or HQ and choose Capture.",
	},
	{
		"id": &"build",
		"label": "BUILD",
		"body": "Press ENTER on your own empty base to buy a unit.",
	},
	{
		"id": &"end_turn",
		"label": "END TURN",
		"body": "Press ESC on open ground for the field menu, then End Turn.",
	},
]


## Every step id, in teaching order. What `Settings.pin_hints(true)` retires in
## one go, and what a test iterates.
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for step: Dictionary in STEPS:
		out.append(step.id)
	return out


## The step the strip is currently teaching: the first one not yet retired.
## Empty once the player has done all five, which is what permanently retires
## the strip itself.
static func next_step(retired: Array[StringName]) -> Dictionary:
	for step: Dictionary in STEPS:
		if step.id not in retired:
			return step
	return {}


## The labels of the steps still to come after `next_step`, for the dimmed tail
## the strip shows so a player can see what the first turn is going to ask of
## them. Retired steps are gone from it, not greyed: the plan retires by success.
static func later_labels(retired: Array[StringName]) -> PackedStringArray:
	var out := PackedStringArray()
	var current := next_step(retired)
	for step: Dictionary in STEPS:
		if step.id in retired or step.id == current.get("id"):
			continue
		out.append(step.label)
	return out
