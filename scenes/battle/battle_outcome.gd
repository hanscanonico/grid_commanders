class_name BattleOutcome
extends RefCounted
## Owns how a match ends: the victory lockup, fronting it with the winning
## commander, and — for a `make balance-watch` run — the day cap that stops a
## watched replay and the one line the fidelity check diffs.
##
## Split out of Battle the same way BattleView, BattleAnimator, BattleAiRunner and
## BattleScenarioDriver were: it drives Battle's own state machine and scene nodes
## rather than deciding anything itself. The board decides who won; a watched match
## stopped by the day cap is scored on the harness's own tiebreak, not here. Battle
## holds one for the whole scene and calls `enter_victory`/`end_watch_on_day_cap`
## at the same points it used to call the private methods these were.
##
## Holds the scene like BattleAiRunner (it sets Battle.state and needs get_tree()),
## and is handed the victory lockup at build time like BattleAnimator's banner —
## this reporter words it and arms it, and nothing else does. How it is dressed is
## the lockup's own (VictoryLockup), the way the banner's dress is the banner's.

## Buffered cut-in presses die here before either outcome action can own them.
## Fixed rather than tier-scaled: this is an input safety window, not theatre.
const INPUT_GUARD_MS := 500

## The horizon a spectated match is scored on when nobody has won it — the arena's
## own 100 days, deliberately not the Lab's 20: a watched row is a measurement of a
## match that was already played, a spectated one is a game somebody is watching.
## Used only where the launch named no `--days=` of its own.
const SPECTATOR_DAYS := 100

var _battle: Battle
var victory_screen: VictoryLockup

## True for a `make balance-watch` run: both sides are the computer's and the
## match came from a Balance Lab spec. Makes the scene announce its result and
## exit, which is what turns BS3's replay-fidelity check into a diff.
var _watching := false
## The day this match is scored on if nobody has won it: `--days=` when the launch
## wrote one, otherwise the Lab's default for a watched row and `SPECTATOR_DAYS`
## for a spectated one. Read **only** for a match no person is playing, so a
## hot-seat or player-vs-AI match is untouched by this and has no day limit.
var _days_cap := BalanceMatchEngine.DEFAULT_DAYS
## The team the victory lockup and the watch line report. `game.winner` for a
## match the board decided; a watched match stopped by the day cap is scored on
## BalanceMatchEngine.tiebreak instead — the harness's own authority, so the
## window and the CSV row agree — and that scored winner is not sim state.
var _result_winner := 0
## The computer's seats as the match was *staged*, which is what the verdict
## wording is gated on. Never the live `ai_teams`: handing a seat to the computer
## mid-match through the Auto row must not change what the end card calls the
## result.
var _seated_ai: Array[int] = []
var _input_guard_until_ms := 0
var _action_armed := false


func _init(battle: Battle) -> void:
	_battle = battle


## Takes the lockup and wires its three actions. All of them are this class's and
## BattleExit's between them — each is guarded by the same `accepts_action`
## window and leaves through BattleExit — so Battle holds no half of any of them.
func bind_screen(screen: VictoryLockup) -> void:
	victory_screen = screen
	screen.rematch_button.pressed.connect(_request_rematch)
	screen.watch_button.pressed.connect(_request_watch_replay)
	screen.menu_button.pressed.connect(_request_main_menu)


func _request_watch_replay() -> void:
	if accepts_action(victory_screen.watch_button):
		_battle.exit.watch_replay()


func _request_rematch() -> void:
	if accepts_action(victory_screen.rematch_button):
		_battle.exit.rematch()


func _request_main_menu() -> void:
	if accepts_action(victory_screen.menu_button):
		_battle.exit.to_main_menu()


## Watch mode's flags and the staged seating, from the setup. Set once at build;
## a launch that named no `--days=` is given the horizon its kind of match is
## scored on, and a match with a human seat never reads either.
func configure(watching: bool, days_cap: int, seated_ai: Array[int]) -> void:
	_watching = watching
	_seated_ai = seated_ai.duplicate()
	_days_cap = days_cap
	if days_cap == MatchRequest.DAYS_UNSET:
		_days_cap = BalanceMatchEngine.DEFAULT_DAYS if watching else SPECTATOR_DAYS


## The horizon for a match nobody is playing, and true when it ended the match
## here. The harness plays while `day <= days_cap` and scores what is left on the
## board, so most of its rows terminate `day_cap`; without the same seam a watched
## replay of one would run forever and never print the line the fidelity check
## diffs (balance plan BS3). A spectated match — every seat given to the computer
## on the seat strip — has the same defect and no CSV row to end it, so it gets
## the same seam on `SPECTATOR_DAYS`. Either way the result is scored on the
## harness's own tiebreak and held beside the sim rather than written into
## `game.winner`, because the board did not decide this one.
##
## A match with a human seat has no day limit and must not grow one.
func end_watch_on_day_cap() -> bool:
	var game := _battle.game
	if not _watching and not _all_seats_ai():
		return false
	if game.winner != 0 or game.day <= _days_cap:
		return false
	_result_winner = BalanceMatchEngine.tiebreak(game)
	enter_victory()
	return true


## Whether nobody at this table is a person. Asked of the match's own roster —
## `teams`, which elimination never shrinks — against the *staged* seating, for the
## reason `_human_team` reads that one: a seat handed to the computer mid-match
## through the Auto row is still a game somebody is playing, and must not grow a
## horizon under them. A playback seats no computer at all, so it is never this.
func _all_seats_ai() -> bool:
	for team: int in _battle.game.teams:
		if team not in _seated_ai:
			return false
	return true


## Idempotent: a rout resolved inside _begin_turn is seen again by whatever was
## driving that turn, and the match is only won once however many callers notice.
func enter_victory() -> void:
	if _battle.state == Battle.State.VICTORY:
		return
	_battle.state = Battle.State.VICTORY
	if _result_winner == 0:
		_result_winner = _battle.game.winner
	_battle.animator.hide_banner()
	# The profile is written here, on the one screen a finished mission always
	# reaches, rather than where the verdict was reached: a mission decided
	# mid-turn is still being animated then, and progress written before the
	# player has seen the result is progress they cannot connect to anything.
	CampaignSession.record(_battle.game)
	Music.stop()  # the theme fades out under the fanfare
	Sfx.play(&"fanfare")
	victory_screen.announce(_result_text(), _day_text(), _action_word(), _menu_word())
	victory_screen.offer_replay(_has_recording())
	_bind_victory_commander()
	victory_screen.show()
	victory_screen.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_action_armed = false
	_input_guard_until_ms = Time.get_ticks_msec() + INPUT_GUARD_MS
	victory_screen.rematch_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	victory_screen.watch_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	victory_screen.menu_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_release_mouse_guard()
	var focused := victory_screen.get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	if _watching:
		_report_watched_result()


## What pressing the action button does, which is what the word on it has to
## name: a playback has no match to play again, so it restarts the recording; a
## campaign mission is retried through the session, never rematched as the
## skirmish its finished board looks like — and one already won is replayed, since
## "Retry" over "Mission complete!" says it was not; everything else plays itself
## again.
func _action_word() -> String:
	if _battle.replay_path != "":
		return "Restart"
	if not CampaignSession.active():
		return "Rematch"
	var outcome := CampaignSession.outcome
	if outcome != null and outcome.status == MissionRuntime.Status.SUCCESS:
		return "Replay"
	return "Retry"


## Where the menu button leads, which is what the word on it has to name. The
## exit is the same one everywhere — `BattleExit.to_main_menu` — but a finished
## mission's main menu plays the debrief and then the hub, so "Main Menu" over it
## read as quitting the war: after a win the next thing is the next mission, after
## a loss it is the generals' account of what went wrong. Keyed to the verdict,
## never the winner, because a tactical victory can still fail a mission.
func _menu_word() -> String:
	var outcome := CampaignSession.outcome
	if outcome == null:
		return "Main Menu"
	match outcome.status:
		MissionRuntime.Status.SUCCESS:
			return "Continue"
		MissionRuntime.Status.FAILURE:
			return "Debrief"
	return "Main Menu"


## Whether there is a recording to offer. Whether one was *written* is the
## recorder's own answer and nobody else's: a playback and a capture run were
## handed none at all, and a match nobody moved in claims no slot, so an empty
## path is the whole test.
##
## A finished mission is the one match that wrote a recording and is not offered
## it. Its session is still armed on this screen — the debrief is owed the words
## it says about what just happened — and a playback started from here would boot
## with that mission live: the war's army would be stood on the recorded opening
## board a second time (`CampaignSession.deploy_army`), which is a board the
## recording does not describe and a checkpoint that cannot match. Every other
## route into a playback clears the session first, and the Replays page is where
## a mission is watched back.
func _has_recording() -> bool:
	if CampaignSession.active():
		return false
	return _battle.recorder != null and _battle.recorder.path() != ""


func _release_mouse_guard() -> void:
	await _battle.get_tree().create_timer(float(INPUT_GUARD_MS) / 1000.0).timeout
	if not is_instance_valid(_battle):
		return  # the lockup was left for a rematch or the menu; that run is not ours to end
	if _battle.state != Battle.State.VICTORY:
		return
	victory_screen.rematch_button.mouse_filter = Control.MOUSE_FILTER_STOP
	victory_screen.watch_button.mouse_filter = Control.MOUSE_FILTER_STOP
	victory_screen.menu_button.mouse_filter = Control.MOUSE_FILTER_STOP


## Claims transition presses before Battle's board flow sees them. During the
## guard they do nothing at all; afterwards the first fresh press only reveals
## the visible focus state and cannot activate an action.
func consume_input(event: InputEvent) -> bool:
	if not TransitionInput.is_press(event):
		return false
	if Time.get_ticks_msec() < _input_guard_until_ms:
		return true
	if not _action_armed:
		_action_armed = true
		victory_screen.rematch_button.grab_focus()
		return true
	return false


## Mouse presses reach a Button before Battle's unhandled-input seam. Every button
## asks here before leaving: a click inside the guard — where a press buffered
## under the cut-in lands — is swallowed and unfocused.
##
## A later click acts on that same press, unlike the keyboard route above: a click
## already names the button it wants, so there is nothing for a first press to
## reveal, and asking for a second one read as a dead button (COM-244). It arms the
## keyboard as well, so a key press after a click acts on what the pointer focused.
func accepts_action(button: Button) -> bool:
	if Time.get_ticks_msec() < _input_guard_until_ms:
		button.release_focus()
		return false
	_action_armed = true
	button.grab_focus()
	return true


## The winner lockup — "Verdant League wins!", or "Meridian Coalition & Iron
## Dominion win!" when a side won together — or "Draw" for the one case with no
## winner: a watched match that hit the day cap with every tiebreak level.
##
## With exactly one human side at the table it is that side's own verdict
## instead, the way a mission's already is: a solo player should not have to work
## out from a faction name whether that was them. The faction is not lost — it
## moves to the line below.
func _result_text() -> String:
	# A mission says whether *it* was completed, not who was left standing: its
	# verdict already accounts for a tactical victory, and "Mission complete" is
	# what a player who just took a relay on a deadline is waiting to read.
	var outcome := CampaignSession.outcome
	if outcome != null:
		return (
			"Mission complete!"
			if outcome.status == MissionRuntime.Status.SUCCESS
			else "Mission failed"
		)
	if _result_winner == 0:
		return "Draw"
	var human := _human_team()
	if human != 0:
		return "Victory!" if _battle.game.allied(human, _result_winner) else "Defeat"
	return "%s!" % _winner_sentence()


## The seat the people at the table play, and 0 when "did *you* win?" has no
## single answer: a hot-seat match has two players owed opposite verdicts and a
## watched or replayed one has none at all. Any seat of the one human side will
## do — they share a verdict — so this is its lowest.
##
## Read off the staged seating rather than the live `ai_teams` or the live
## viewer, both of which the Auto row moves: handing a seat to the computer
## mid-match must not reword the result, and a player who put their *own* seat on
## Auto is watching through the seat on turn, which at the end of the match is the
## winner's — so the viewer would call every outcome a victory.
func _human_team() -> int:
	var game := _battle.game
	var humans: Array[int] = []
	for team: int in game.teams:
		if team not in _seated_ai:
			humans.append(team)
	if humans.is_empty():
		return 0
	for team: int in humans:
		if not game.allied(humans[0], team):
			return 0
	return humans[0]


## Who won, in words: "Verdant League wins", or "Meridian Coalition & Iron
## Dominion win" when a side won together.
##
## Reads `winners()` rather than the scalar, because a victory that belongs to a
## side has to name the side; the scalar is still what the lockup is *keyed* to,
## so a duel prints exactly the sentence it always did. A scored day-cap win has
## no elimination behind it and names its one team.
func _winner_sentence() -> String:
	var side := _battle.game.winners()
	if side.size() <= 1:
		return "%s wins" % _battle.view.identity.display_name(_result_winner)
	# Distinct names, because two allies may share a faction — a mirror keeps both
	# sides named for it and leans on the livery to tell them apart (SideIdentity).
	# "Meridian Coalition & Meridian Coalition win!" is not a sentence.
	var names := PackedStringArray()
	for team: int in side:
		var name := _battle.view.identity.display_name(team)
		if not names.has(name):
			names.append(name)
	if names.size() == 1:
		return "%s wins" % names[0]
	return "%s win" % " & ".join(names)


## The line under the lockup: the day it took, who won where the title above said
## only whether the player did, and on a longer match who fell on the way.
func _day_text() -> String:
	var day := "Day %d" % _battle.game.day
	var outcome := CampaignSession.outcome
	if outcome != null:
		# The stars and the reason, because a mission's line has to say what was
		# earned and — on a failure, where there is nothing to count — why.
		if outcome.status != MissionRuntime.Status.SUCCESS:
			return "%s  ·  %s" % [day, outcome.reason]
		var most := CampaignSession.max_stars()
		var stars := UiKit.star_bar(outcome.stars, most)
		return "%s  ·  %s" % [day, stars]
	var clauses := PackedStringArray([day])
	if _result_winner != 0 and _human_team() != 0:
		clauses.append(_winner_sentence())
	var standings := _standings_text()
	if standings != "":
		clauses.append(standings)
	return "  ·  ".join(clauses)


## Who fell, in the order they fell — the standings half of the line above. Read
## straight off `eliminated`, whose keys are in insertion order, so this is the
## order of the match rather than of the seating.
##
## Empty on a duel, where the one elimination *is* the victory and saying so twice
## adds nothing; a longer match earned the account of how it got there.
func _standings_text() -> String:
	var fallen := PackedStringArray()
	for team: int in _battle.game.eliminated:
		fallen.append(_battle.view.identity.display_name(team))
	if fallen.size() < 2:
		return ""
	return "Eliminated: %s" % ", ".join(fallen)


## The one line BS3's replay-fidelity check reads: a watched match must end with
## the same winner on the same day as the matches.csv row it was launched from.
## Printed rather than asserted here, because the assertion belongs to whoever is
## comparing the two — and printing it is what lets that be a diff instead of
## someone watching a window and remembering.
##
## The wording is fixed, day-cap rows included: the row's `winner` and
## `day_ended` are what it is checked against, and a scored win is still that
## row's winner.
func _report_watched_result() -> void:
	print("watch: team %d wins on day %d" % [_result_winner, _battle.game.day])
	await _battle.get_tree().create_timer(1.5).timeout  # let the lockup land on screen
	if not is_instance_valid(_battle):
		return  # the lockup was left for a rematch or the menu; that run is not ours to end
	_battle.get_tree().quit()


## Fronts the victory screen with the winning commander. A draw has no winner to
## front at all; the lockup takes null for it and for a side that played without a
## general, and renders the plain "<team> wins!" card in both cases.
func _bind_victory_commander() -> void:
	if _result_winner == 0:
		victory_screen.front_with(null)
		return
	victory_screen.front_with(_battle.game.commander_of(_result_winner))
