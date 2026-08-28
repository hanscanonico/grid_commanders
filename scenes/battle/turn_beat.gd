class_name TurnBeat
extends RefCounted
## The pacing of a driven turn: how long the board rests before the first command
## and between two of them. `BattleAiRunner` and `BattleReplayRunner` both await
## it, so a recording hurries along exactly as the computer turn it recorded did —
## a promise the two docstrings used to make to each other and now cannot break.
##
## Node-free statics in `BoardBeat`'s idiom, handed the tree they wait on: a beat
## is a wait rather than a scene, so nothing here owns a node. Pacing lives in
## `scenes/` and stays there — nothing under `core/` or `ai/` may read
## `GameSpeed`, because pacing can never move an outcome.
##
## Deliberately not the pause: `Battle.pause_gate` is Battle's own seam, awaited
## by each runner beside these beats.


## The rest after the day banner clears, before the turn's first command. Padding
## only — Battle awaits the banner itself before handing the turn over.
static func opening(tree: SceneTree) -> void:
	await tree.create_timer(Settings.speed.start_delay_seconds()).timeout


## The think-beat between two commands, so a turn reads as decisions rather than
## as a slideshow. Paced off Settings, the same tier the animations it sits
## between run at — a computer turn, a replayed one and a player's move obey one
## setting.
##
## Instant drops the wait to a single frame rather than to nothing: the board
## still repaints once per command, so a forty-command turn is forty frames the
## eye can track as a fast flicker, the window keeps pumping events, and the AI
## runner's per-turn safety cap keeps meaning what it says.
##
## The held fast-forward key shortens the beat that is about to be waited, so a
## key let go is felt on the next command rather than inside this one — which is
## also what keeps Instant's single frame untouched at any rate.
static func between_commands(tree: SceneTree) -> void:
	var delay := Settings.speed.command_delay_seconds() / FastForward.rate()
	if delay <= 0.0:
		await tree.process_frame
		return
	await tree.create_timer(delay).timeout
