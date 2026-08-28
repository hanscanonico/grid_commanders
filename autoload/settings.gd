extends Node
## Device preferences: what this machine likes, as opposed to what this match is.
## Six of them today — how fast the battle's theatre plays out, whether a
## resolved attack cuts to the full-screen battle animation at all, whether the
## menus move at all, how loud the game is, whether ending the day stops to
## confirm when units can still act, and which of the first-match hints this
## player has already earned their way out of.
##
## Deliberately not MatchConfig and deliberately not in the save file: resuming a
## three-day-old save should play at the speed you like *today* and watch battles
## the way you like *today*, and a hot-seat pair share one screen anyway. The
## hints belong here for the same reason and one more (UX recovery plan D1): a
## player who has learned to capture has learned it for good, and tying that to a
## match would teach them again on every new one. All six are presentation only
## — nothing here may ever change a rule, a number, or what the sim does, so two
## players' "same seed, same commands" keep meaning the same result. Nothing here
## is ever handed to core/ or ai/, so the sim cannot observe a preference it never
## receives — see GameSpeed.
##
## Persisted to user://settings.cfg with ConfigFile, beside SaveGame's
## user://save.json.

const SETTINGS_PATH := "user://settings.cfg"
## Where an unreadable settings file is kept when one has to be written over. See
## `_set_aside`; nothing reads it back, and that is deliberate. Same name as
## `SaveGame`'s sibling in the same directory and the opposite thing: there the
## `.bak` is a step in an atomic replacement and is cleared on every successful
## swap, here it is a keepsake that is written once and then left alone.
const BACKUP_SUFFIX := ".bak"
const SECTION := "game"
const SPEED_KEY := "speed"
const BATTLE_ANIMATIONS_KEY := "battle_animations"
const MENU_ANIMATIONS_KEY := "menu_animations"
const VOLUME_KEY := "volume"
const END_TURN_CONFIRM_KEY := "end_turn_confirm"
## What a fresh install confirms with, and what `pin` stands a scripted launch
## back at.
const DEFAULT_END_TURN_CONFIRM := true
## What a fresh install's menus move with, and what `pin` stands them back at: the
## toggle's own checkmark is on the menu a capture photographs, so a machine that
## turned the motion off must not change the frame.
const DEFAULT_MENU_ANIMATIONS := true
## What a fresh install cuts to a battle with, and what `pin` stands it back at
## for the reason menu motion stands back: the toggle's own checkmark is on a
## photographed menu.
const DEFAULT_BATTLE_ANIMATIONS := true
const HINTS_KEY := "hints_retired"
## Overrides the stored tier for one launch, in the family of --map / --fog /
## --difficulty. Deliberately un-persisted: a scripted run must not edit what
## the player chose.
const SPEED_ARG := "--speed="
## Turns the battle cut-in off for one launch, same family as --speed= and just
## as un-persisted: how a capture run keeps `make screenshot` byte-stable without
## touching the stored preference.
const NO_ANIM_ARG := "--no-battle-anim"
## Silences the whole game for one launch, same family as --no-battle-anim and
## just as un-persisted: how a capture or a scripted run stays quiet without
## spending the player's own volume.
const MUTE_ARG := "--mute"

## How loud the game plays, quietest step last. The master bus is the whole
## surface — music and effects come down together — because the complaint this
## setting exists to answer is "turn it down", not "mix it". Off mutes the bus
## outright rather than trusting a very low decibel to be inaudible, the explicit
## branch GameSpeed's Instant tier is.
const VOLUME_STEPS: Array[Dictionary] = [
	{"id": &"full", "label": "Full", "db": 0.0},
	{"id": &"half", "label": "Half", "db": -8.0},
	{"id": &"quiet", "label": "Quiet", "db": -18.0},
	{"id": &"off", "label": "Off", "db": -80.0},
]
## The loudest step, which is what a fresh install plays at and what an id naming
## no step falls back to, and the silent one, which mutes rather than attenuates.
const FULL_ID := &"full"
const OFF_ID := &"off"
## What a fresh install plays at, and what `pin` stands the volume back at: the
## pause menu's Sound row reads its label off this preference and that row is in
## every photographed map menu, so a quiet machine must not change the frame.
const DEFAULT_VOLUME := FULL_ID
## The bus every step is applied to. Index 0 is Master, which always exists, so
## the game needs no bus layout resource of its own.
const MASTER_BUS := 0
## Forgets every retired first-match hint and writes that back, so the next
## launch meets the mission strip exactly as a fresh install does. The one flag
## here that *does* touch the file, because that is the whole point of it: the
## acceptance gate is "hints do not reappear across a relaunch", and checking it
## needs a way back to the start that a relaunch does not undo.
const RESET_HINTS_ARG := "--reset-hints"

## The pause menu's value rows, in the order they are offered. Named here rather
## than in the menu that draws them because the values are this file's: a row
## reads its label off `row_label` and steps through `cycle_row`, so the label, the
## ladder and the stored preference are one thing and cannot drift apart.
const SPEED_ROW := &"speed"
const SOUND_ROW := &"sound"
const END_TURN_ROW := &"end_turn_confirm"
const VALUE_ROWS: Array[StringName] = [SPEED_ROW, SOUND_ROW, END_TURN_ROW]

## How fast moves and battles play out on screen. Never null. Callers read it at
## the moment they animate rather than caching it, so a mid-match change takes
## effect on the very next animation.
var speed: GameSpeed = GameSpeed.default_speed()

## Whether a resolved attack plays the full-screen battle cut-in. Off falls back
## to the on-map hit flash and shake, which is how combat looked before the
## cut-in existed — see BattleAnimator.animate_combat.
var battle_animations := DEFAULT_BATTLE_ANIMATIONS

## Whether the menus move at all — the main menu's drifting board backdrop and
## blinking PRESS START, and the staggered reveals on the campaign pages. Off
## leaves every one of them on its finished frame, which is also what a capture
## poses; the pages that read a line at a time still show every line.
var menu_animations := DEFAULT_MENU_ANIMATIONS

## Which step of VOLUME_STEPS the game plays at. Never a stranger: a stored id
## nothing answers to falls back to the loudest step, the same shape
## GameSpeed.by_id answers an unknown tier with.
var volume: StringName = DEFAULT_VOLUME

## Whether ending the day stops to confirm while units can still act. On is what
## the game has always done — EndTurnGuard names what the day would discard —
## and off ends the day on the first press, for a player who reads their own
## board. Presentation only like everything else here: nothing under core/ or
## ai/ learns it exists, and ReadyUnits still answers who is ready either way.
var end_turn_confirm := DEFAULT_END_TURN_CONFIRM

## Which first-match hints this player has already performed their way out of —
## `TutorialHints` ids, retired for good. MissionStrip reads it to pick what to
## teach next and stops drawing itself once it holds them all.
var retired_hints: Array[StringName] = []

## False once anything has spoken for this launch, so nothing written later
## reaches the file.
var _persistent := true
## True once `--speed=` has spoken. A capture pins the tier it needs, but an
## explicit flag outranks even that: it is the most specific thing anyone said,
## and asking for a capture *of* a tier is how you look at one you are tuning.
var _flag_wins := false
## True once --no-battle-anim or --mute has spoken, each guarding its own
## preference against the pin below on _flag_wins' terms: an explicit flag is the
## most specific thing anyone said, and both flags exist to be used on the runs
## that pin.
var _anim_flag_wins := false
var _volume_flag_wins := false


func _ready() -> void:
	_load()
	_apply_cmdline()
	_apply_volume()


## Changes the tier and writes it back. The only way the speed ever moves.
func set_speed(id: StringName) -> void:
	speed = GameSpeed.by_id(id)
	if _persistent:
		_save()


## Changes the volume, applies it to the master bus and writes it back. The only
## way the volume ever moves. Mirrors set_speed, and like it a pinned or scripted
## launch (see --mute) never touches the file.
func set_volume(id: StringName) -> void:
	volume = id if volume_index(id) >= 0 else FULL_ID
	_apply_volume()
	if _persistent:
		_save()


## Where `id` sits in VOLUME_STEPS; -1 when it names no step.
static func volume_index(id: StringName) -> int:
	for i in VOLUME_STEPS.size():
		if VOLUME_STEPS[i]["id"] == id:
			return i
	return -1


## What a step is called on screen. An unknown id reads as the loudest step, so a
## menu built from a file this version cannot read still says something true of
## what it is about to play.
static func volume_label(id: StringName) -> String:
	var i := volume_index(id)
	return VOLUME_STEPS[maxi(i, 0)]["label"]


static func volume_db(id: StringName) -> float:
	var i := volume_index(id)
	return VOLUME_STEPS[maxi(i, 0)]["db"]


## The step `step` places along VOLUME_STEPS from `id`, wrapping. Signed rather
## than a plain "next" because the pause menu walks it both ways, and one piece
## of arithmetic is what makes left the exact inverse of right.
static func stepped_volume(id: StringName, step: int) -> StringName:
	var i := maxi(volume_index(id), 0)
	return VOLUME_STEPS[wrapi(i + step, 0, VOLUME_STEPS.size())]["id"]


## The same, over GameSpeed's own tier order — which stays that class's, read
## here rather than re-stated.
static func stepped_speed(id: StringName, step: int) -> StringName:
	var ids := GameSpeed.ids()
	var i := maxi(ids.find(String(id)), 0)
	return StringName(ids[wrapi(i + step, 0, ids.size())])


## What a value row reads on the pause menu at its current setting — before a
## press and after one, since a stepped row is rewritten where it stands. One
## string with one owner, so the row a player is reading and the setting the game
## is playing at can never word themselves differently.
func row_label(row: StringName) -> String:
	match row:
		SPEED_ROW:
			return "Speed: %s" % speed.display_name
		SOUND_ROW:
			return "Sound: %s" % volume_label(volume)
		END_TURN_ROW:
			return "End-turn check: %s" % ("On" if end_turn_confirm else "Off")
	push_error("Settings: %s names no value row" % row)
	return ""


## Steps a value row along its own ladder, persists it and answers with the row's
## new label — the setting being otherwise invisible until something moves. `step`
## is +1 for the next value and -1 for the one before; a two-state row takes
## either as the other one.
func cycle_row(row: StringName, step: int = 1) -> String:
	match row:
		SPEED_ROW:
			set_speed(stepped_speed(speed.id, step))
		SOUND_ROW:
			set_volume(stepped_volume(volume, step))
		END_TURN_ROW:
			set_end_turn_confirm(not end_turn_confirm)
	return row_label(row)


func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(MASTER_BUS, volume_db(volume))
	AudioServer.set_bus_mute(MASTER_BUS, volume == OFF_ID)


## The setter the menu's checkbox is wired to. Mirrors set_speed: writes through
## immediately so a preference set in one session is honoured in the next even if
## the game is closed the hard way, but a pinned or scripted launch (see pin and
## _apply_cmdline) never touches the file.
func set_battle_animations(enabled: bool) -> void:
	battle_animations = enabled
	if _persistent:
		_save()


## The setter the Menu motion checkbox is wired to. Mirrors set_battle_animations,
## down to a pinned or scripted launch leaving the file alone.
func set_menu_animations(enabled: bool) -> void:
	menu_animations = enabled
	if _persistent:
		_save()


## The setter the End-turn check row is wired to. Mirrors set_battle_animations,
## down to a pinned or scripted launch leaving the file alone.
func set_end_turn_confirm(enabled: bool) -> void:
	end_turn_confirm = enabled
	if _persistent:
		_save()


## Marks a first-match hint as earned and writes it back immediately, like the
## two setters above: a hint the player has performed must not come back because
## the game was closed the hard way. Repeats are ignored, so the caller may hand
## the same id over every time the event it watches fires.
func retire_hint(id: StringName) -> void:
	if id in retired_hints:
		return
	retired_hints.append(id)
	if _persistent:
		_save()


## Pins the whole strip for this launch, the way `pin` pins the speed tier and
## for the same reason: a capture must not depend on which machine took it, and
## whether *this* machine's player has already learned to capture is exactly the
## sort of thing a screenshot would otherwise photograph. `all_retired` hides the
## strip outright; false is the fresh-install state a scenario stages it in.
func pin_hints(all_retired: bool) -> void:
	_persistent = false
	# Built as a typed local rather than a ternary: the empty branch of
	# `ids() if x else []` is an untyped Array, which the engine refuses to assign
	# here at *runtime* — a script error the scene walks straight past, leaving the
	# capture reading whatever this machine's player had already learned.
	var pinned: Array[StringName] = []
	if all_retired:
		pinned = TutorialHints.ids()
	retired_hints = pinned


## Pins a tier for this launch and latches the file shut behind it. Captures and
## scripted scenario runs pin, so a frame never depends on which machine took it
## — and it is pinned *here* rather than inside the animator because the setting
## has one owner: the in-battle menu row reads its label off this too, and a
## capture whose animations were pinned but whose label was not would photograph
## the preference it was meant to ignore.
##
## The end-turn check stands back at its shipped default for the same reason: it
## decides whether a scripted End Turn opens the guard or hands the day over, so
## a machine whose player turned it off would drive a scenario differently from
## one that never touched it. The volume, the cut-in toggle and menu motion stand
## back for the plainer half of the same reason: a capture poses the menu still
## and suppresses the cut-in whatever these preferences say, so all a stored
## "off" or "Quiet" could reach is the map menu's own Sound row and the toggles'
## own checkmarks in the frame.
##
## --no-battle-anim and --mute outrank the pin exactly as --speed= does, each on
## its own latch: both are per-launch overrides asked for on the very runs that
## pin, so a pin that stood them back would leave neither flag anything to do.
func pin(id: StringName) -> void:
	_persistent = false
	end_turn_confirm = DEFAULT_END_TURN_CONFIRM
	menu_animations = DEFAULT_MENU_ANIMATIONS
	if not _anim_flag_wins:
		battle_animations = DEFAULT_BATTLE_ANIMATIONS
	if not _volume_flag_wins:
		volume = DEFAULT_VOLUME
		_apply_volume()
	if not _flag_wins:
		speed = GameSpeed.by_id(id)


## A missing or malformed file is not an error: the defaults simply stand, which
## is what a first launch on a new machine looks like.
func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	var stored: Variant = config.get_value(SECTION, SPEED_KEY, "")
	if stored is String:
		speed = GameSpeed.by_id(StringName(stored))
	var stored_anim: Variant = config.get_value(SECTION, BATTLE_ANIMATIONS_KEY, battle_animations)
	if stored_anim is bool:
		battle_animations = stored_anim
	var stored_menu_anim: Variant = config.get_value(SECTION, MENU_ANIMATIONS_KEY, menu_animations)
	if stored_menu_anim is bool:
		menu_animations = stored_menu_anim
	# A String here for the reason the hint ids are: ConfigFile has no StringName.
	# An id this version answers to nothing with falls back to the loudest step
	# rather than muting a player who cannot see why.
	var stored_volume: Variant = config.get_value(SECTION, VOLUME_KEY, "")
	if stored_volume is String and volume_index(StringName(stored_volume)) >= 0:
		volume = StringName(stored_volume)
	var stored_confirm: Variant = config.get_value(SECTION, END_TURN_CONFIRM_KEY, end_turn_confirm)
	if stored_confirm is bool:
		end_turn_confirm = stored_confirm
	# Stored as strings and read back as StringNames: ConfigFile has no
	# StringName, and a hint id written by one version must still match the
	# TutorialHints id in the next. An id nothing answers to any more is kept
	# rather than dropped — it costs a string and it is the only thing standing
	# between a renamed step and a veteran being taught to capture again.
	var stored_hints: Variant = config.get_value(SECTION, HINTS_KEY, PackedStringArray())
	if stored_hints is PackedStringArray:
		for id: String in stored_hints as PackedStringArray:
			retired_hints.append(StringName(id))


func _save() -> void:
	var config := _open_for_merge()
	if config == null:
		return
	config.set_value(SECTION, SPEED_KEY, String(speed.id))
	config.set_value(SECTION, BATTLE_ANIMATIONS_KEY, battle_animations)
	config.set_value(SECTION, MENU_ANIMATIONS_KEY, menu_animations)
	config.set_value(SECTION, VOLUME_KEY, String(volume))
	config.set_value(SECTION, END_TURN_CONFIRM_KEY, end_turn_confirm)
	var hints := PackedStringArray()
	for id in retired_hints:
		hints.append(String(id))
	config.set_value(SECTION, HINTS_KEY, hints)
	if config.save(SETTINGS_PATH) != OK:
		push_error("Settings: cannot write %s" % SETTINGS_PATH)


## The file, opened so that writing this version's keys back cannot drop anyone
## else's. Null means write nothing at all.
##
## Every write here is a *merge*: the file is read first so a key a later version of
## the game wrote survives a save by this one. That makes the read's answer
## load-bearing, and its three cases genuinely different (COM-59) — which is why
## both writers ask this rather than each spelling out a `load` whose result is easy
## to drop on the floor, as both of them did.
##
## A file that parses is merged into. A file that is simply *absent* is the ordinary
## first launch: nothing to keep, and a fresh one is exactly right. A file that is
## there and *unreadable* is the case that used to be destroyed in silence — the
## config came back holding only whatever parsed before the error, and the save
## rewrote the file from that, discarding precisely the foreign keys the read exists
## to preserve. It is now set aside first, so the preference still persists and what
## could not be read is still on disk for a person to look at.
##
## Deliberately not the save slot's treatment. `SaveGame` recovers from its backup on
## *read*, because a lost match is unrecoverable; a device preference is a speed and
## two flags, so nothing reads this copy back and it exists for a human.
func _open_for_merge() -> ConfigFile:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK or not FileAccess.file_exists(SETTINGS_PATH):
		return config
	if not _set_aside():
		return null  # refuse to write over what could not be preserved
	return config


## Moves an unreadable settings file out of the way so the next write cannot
## destroy it. True when a preserved copy is on disk and writing may proceed;
## false when it could not be moved, in which case the caller writes nothing — a
## preference this launch fails to remember costs less than a file from a version
## this one cannot read.
##
## A copy that is already there is never replaced, and it is the *first* one that
## is worth keeping: it holds the foreign keys this version never understood,
## while a second corruption is by definition a corruption of a file this version
## itself wrote and therefore already understands. So the write is allowed through
## with nothing set aside rather than renaming over the copy that matters.
func _set_aside() -> bool:
	var backup_path := SETTINGS_PATH + BACKUP_SUFFIX
	if FileAccess.file_exists(backup_path):
		push_warning(
			(
				"Settings: %s is unreadable; %s already holds an earlier copy, kept as it is"
				% [SETTINGS_PATH, backup_path]
			)
		)
		return true
	var absolute := ProjectSettings.globalize_path(SETTINGS_PATH)
	var error := DirAccess.rename_absolute(absolute, absolute + BACKUP_SUFFIX)
	if error != OK:
		push_error(
			(
				"Settings: %s is unreadable and could not be set aside (error %d); leaving it alone"
				% [SETTINGS_PATH, error]
			)
		)
		return false
	push_warning(
		(
			"Settings: %s was unreadable; kept as %s and rewritten from whatever parsed before the error"
			% [SETTINGS_PATH, backup_path]
		)
	)
	return true


func _apply_cmdline() -> void:
	apply_args(CmdArgs.user())


## The flag walk, over the arguments it is handed rather than the ones this
## process was launched with — the terms MatchRequest.apply_cmdline is on, and for
## the same reason: which flags outrank a pin is checkable without a command line.
func apply_args(args: PackedStringArray) -> void:
	# Walked in order rather than read through CmdArgs' last-wins lookups: the
	# pin below latches, so here the *first* valid --speed= is the one that
	# lands, and --reset-hints has to see the writes the flags before it made.
	for arg in args:
		if arg.begins_with(SPEED_ARG):
			var wanted := StringName(arg.get_slice("=", 1).strip_edges())
			# Checked here rather than inside pin(), which is only ever handed an
			# id from the source: a capture must not pay for the check or risk a
			# spurious error. A name nothing answers to is said out loud and then
			# dropped entirely — the shape battle_setup answers an unknown --map=
			# with. Half-applying it would be worse than ignoring it: the pin
			# below latches the file shut, so a typo would silently stop writing
			# every speed the player picked for the rest of the session.
			if not GameSpeed.has_id(wanted):
				push_error(
					(
						"Settings: unknown speed '%s'; keeping %s. Known: %s"
						% [wanted, speed.id, ", ".join(GameSpeed.ids())]
					)
				)
				continue
			pin(wanted)
			# Latched after that pin, so the flag's own lands and every later
			# one — a capture's — is declined.
			_flag_wins = true
		elif arg == RESET_HINTS_ARG:
			# Unlike every other flag here this one writes: see RESET_HINTS_ARG.
			# It writes the hints key alone, never through _save(): a --speed= or
			# --no-battle-anim earlier on the same command line has already moved
			# the in-memory value, and a full save would persist that launch-only
			# override — the exact thing those flags promise never to do.
			retired_hints = []
			# Through the same merge as _save, and for the same reason: this writes
			# one key and must not cost the file the others.
			var config := _open_for_merge()
			if config == null:
				continue
			config.set_value(SECTION, HINTS_KEY, PackedStringArray())
			if config.save(SETTINGS_PATH) != OK:
				push_error("Settings: cannot write %s" % SETTINGS_PATH)
		elif arg == NO_ANIM_ARG:
			# Same family as --speed=: a per-launch override that never reaches
			# the file. Latches it shut exactly as a pin does, so a scripted or
			# capture run cannot rewrite what the player chose.
			_persistent = false
			battle_animations = false
			_anim_flag_wins = true
		elif arg == MUTE_ARG:
			# Same terms as --no-battle-anim. _ready applies the volume once this
			# walk is over, so nothing here has to touch the bus itself.
			_persistent = false
			volume = OFF_ID
			_volume_flag_wins = true
