extends Node
## Device preferences: what this machine likes, as opposed to what this match is.
## Three of them today — how fast the battle's theatre plays out, whether a
## resolved attack cuts to the full-screen battle animation at all, and which of
## the first-match hints this player has already earned their way out of.
##
## Deliberately not MatchConfig and deliberately not in the save file: resuming a
## three-day-old save should play at the speed you like *today* and watch battles
## the way you like *today*, and a hot-seat pair share one screen anyway. The
## hints belong here for the same reason and one more (UX recovery plan D1): a
## player who has learned to capture has learned it for good, and tying that to a
## match would teach them again on every new one. All three are presentation only
## — nothing here may ever change a rule, a number, or what the sim does, so two
## players' "same seed, same commands" keep meaning the same result. Nothing here
## is ever handed to core/ or ai/, so the sim cannot observe a preference it never
## receives — see GameSpeed.
##
## Persisted to user://settings.cfg with ConfigFile, beside SaveGame's
## user://save.json.

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "game"
const SPEED_KEY := "speed"
const BATTLE_ANIMATIONS_KEY := "battle_animations"
const HINTS_KEY := "hints_retired"
## Overrides the stored tier for one launch, in the family of --map / --fog /
## --difficulty. Deliberately un-persisted: a scripted run must not edit what
## the player chose.
const SPEED_ARG := "--speed="
## Turns the battle cut-in off for one launch, same family as --speed= and just
## as un-persisted: how a capture run keeps `make screenshot` byte-stable without
## touching the stored preference.
const NO_ANIM_ARG := "--no-battle-anim"
## Forgets every retired first-match hint and writes that back, so the next
## launch meets the mission strip exactly as a fresh install does. The one flag
## here that *does* touch the file, because that is the whole point of it: the
## acceptance gate is "hints do not reappear across a relaunch", and checking it
## needs a way back to the start that a relaunch does not undo.
const RESET_HINTS_ARG := "--reset-hints"

## How fast moves and battles play out on screen. Never null. Callers read it at
## the moment they animate rather than caching it, so a mid-match change takes
## effect on the very next animation.
var speed: GameSpeed = GameSpeed.default_speed()

## Whether a resolved attack plays the full-screen battle cut-in. Off falls back
## to the on-map hit flash and shake, which is how combat looked before the
## cut-in existed — see BattleAnimator.animate_combat.
var battle_animations := true

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


func _ready() -> void:
	_load()
	_apply_cmdline()


## Changes the tier and writes it back. The only way the speed ever moves.
func set_speed(id: StringName) -> void:
	speed = GameSpeed.by_id(id)
	if _persistent:
		_save()


## The setter the menu's checkbox is wired to. Mirrors set_speed: writes through
## immediately so a preference set in one session is honoured in the next even if
## the game is closed the hard way, but a pinned or scripted launch (see pin and
## _apply_cmdline) never touches the file.
func set_battle_animations(enabled: bool) -> void:
	battle_animations = enabled
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
func pin(id: StringName) -> void:
	_persistent = false
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
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # keep any key a later version of the game wrote
	config.set_value(SECTION, SPEED_KEY, String(speed.id))
	config.set_value(SECTION, BATTLE_ANIMATIONS_KEY, battle_animations)
	var hints := PackedStringArray()
	for id in retired_hints:
		hints.append(String(id))
	config.set_value(SECTION, HINTS_KEY, hints)
	if config.save(SETTINGS_PATH) != OK:
		push_error("Settings: cannot write %s" % SETTINGS_PATH)


func _apply_cmdline() -> void:
	# Walked in order rather than read through CmdArgs' last-wins lookups: the
	# pin below latches, so here the *first* valid --speed= is the one that
	# lands, and --reset-hints has to see the writes the flags before it made.
	for arg in CmdArgs.user():
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
			var config := ConfigFile.new()
			config.load(SETTINGS_PATH)  # keep every other key as the file has it
			config.set_value(SECTION, HINTS_KEY, PackedStringArray())
			if config.save(SETTINGS_PATH) != OK:
				push_error("Settings: cannot write %s" % SETTINGS_PATH)
		elif arg == NO_ANIM_ARG:
			# Same family as --speed=: a per-launch override that never reaches
			# the file. Latches it shut exactly as a pin does, so a scripted or
			# capture run cannot rewrite what the player chose.
			_persistent = false
			battle_animations = false
