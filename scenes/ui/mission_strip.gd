class_name MissionStrip
extends PanelContainer
## The first-match teaching strip: the objective, then one step at a time —
## select, move, capture, build, end turn — each retiring for good the moment the
## player performs it (UX recovery plan U-08, decision D6: teach by doing, retire
## by success).
##
## It only runs on the tutorial board. Which board that is, is
## `MapCatalog.teaches`' answer and nothing else's (COM-122): a player who picked
## a board to play on picked a match, not a lesson, and the strip stays down —
## including its *retirement*, so an ordinary game can never burn through the
## steps of a tutorial its player has not opened yet.
##
## **It owns no rule and asks nothing of the sim.** Every step retires off the
## same `EventBus` signals the scene already animates, so this observes the game
## rather than instrumenting it: no command grew a callback, no state machine
## grew a tutorial branch, and deleting this file would leave the battle flow
## byte-identical. What to say and what comes next is `TutorialHints`', which is
## Node-free and tested; when to say it is here.
##
## Retirement is a device preference in `user://settings.cfg` beside the game
## speed (plan D1), never match state and never a save field: a player who has
## learned to capture has learned it on this machine, not in this match, and a
## resumed save must not teach them again.
##
## Only the *viewing* side's actions count. The AI emits the same events through
## the same bus (BattleAiRunner), and a strip that retired "Capture" because the
## computer took a city would have taught nobody anything.
##
## Floats over the board, unlike the two docked bars — which is allowed for
## exactly the reason the forecast and the action menu are: it is transient. It
## dismisses itself permanently after one match's worth of play and never comes
## back, so it is never chrome the board has to be laid out around.

## How far below the top bar the strip sits, and how far its own text sits inside
## its panel.
const _MARGIN := 4
const _PAD := 5

## Teams a human is playing. Only their actions retire a step; the computer plays
## through the same events and must not teach the strip anything.
var _human_teams: Array[int] = [1]
## Whether this match is being played on the tutorial board. False everywhere
## else, which is the whole of COM-122: no strip, and no step retired behind the
## player's back.
var _teaching := false
var _built := false
var _objective_label: Label
var _step_label: Label
var _body_label: Label
var _rest_label: Label
## The team whose turn was last announced. "End turn" retires when the turn
## passes *off* a human side, which is the only event that means the player ended
## one — `turn_started` alone fires on day one before anybody has done anything.
var _last_turn_team := 0


func _ready() -> void:
	_build()
	EventBus.unit_selected.connect(_on_unit_selected)
	EventBus.unit_moved.connect(_on_unit_moved)
	EventBus.unit_built.connect(_on_unit_built)
	EventBus.property_captured.connect(_on_property_captured)
	EventBus.turn_started.connect(_on_turn_started)


## Tells the strip whose actions to watch and whether this board teaches at all.
## Called once by BattleView.setup; nothing is drawn until `refresh`, because
## whether the strip shows also depends on a hint pin a capture run applies after
## the view is built.
func setup(human_teams: Array[int], teaching: bool) -> void:
	_human_teams = human_teams
	_teaching = teaching


## Redraws from `Settings.retired_hints` and hides the strip for good once they
## are all in. Safe to call at any time — it is a pure read of the preference.
func refresh() -> void:
	if not _built:
		return
	var step := TutorialHints.next_step(Settings.retired_hints)
	# Nobody to teach is as good a reason to stay down as nothing left to teach:
	# a `make balance-watch` replay is both sides' computer, and a strip asking
	# the empty chair to select a unit would sit there for the whole match. A
	# board that is not the tutorial is the third (COM-122).
	visible = _teaching and not step.is_empty() and not _human_teams.is_empty()
	if not visible:
		return
	_objective_label.text = TutorialHints.OBJECTIVE
	_step_label.text = "> %s" % step.label
	_body_label.text = step.body
	# The steps still to come, so a first turn can see its own shape rather than
	# meeting one instruction at a time with no idea how many are left.
	var later := TutorialHints.later_labels(Settings.retired_hints)
	_rest_label.visible = later.size() > 0
	_rest_label.text = "THEN  %s" % "  ·  ".join(later)
	_place()


## The step currently on the strip, or `&""` once every one has retired. Public
## for the smoke scenario, which checks *which* step is up rather than that a
## frame rendered — a strip stuck on SELECT after a completed move photographs
## perfectly well.
func current_step_id() -> StringName:
	return TutorialHints.next_step(Settings.retired_hints).get("id", &"")


# --- observation --------------------------------------------------------------


func _on_unit_selected(unit: Unit) -> void:
	_retire_for(unit.team, &"select")


func _on_unit_moved(unit: Unit) -> void:
	_retire_for(unit.team, &"move")


func _on_unit_built(unit: Unit) -> void:
	_retire_for(unit.team, &"build")


func _on_property_captured(_cell: Vector2i, team: int) -> void:
	_retire_for(team, &"capture")


## A turn opening for somebody else means the side before it ended theirs. Only a
## human's ended turn teaches the step, which in hot-seat is both of them.
func _on_turn_started(team: int, _day: int) -> void:
	if _last_turn_team != 0 and _last_turn_team != team:
		_retire_for(_last_turn_team, &"end_turn")
	_last_turn_team = team
	refresh()


func _retire_for(team: int, id: StringName) -> void:
	if not _teaching or team not in _human_teams or id in Settings.retired_hints:
		return
	Settings.retire_hint(id)
	refresh()


# --- the strip itself ---------------------------------------------------------


func _build() -> void:
	# The strip sits *on* the board, so it must not eat a click meant for the tile
	# under it: unlike the docked bars, which stop the pointer on purpose, every
	# control here is decoration. `make_decoration` walks the whole subtree, which
	# is what keeps that true when a label is added later.
	add_theme_stylebox_override("panel", UiTheme.dark_panel_box(UiTheme.SLATE_800, _PAD, _PAD - 1))

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	add_child(rows)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 5)
	rows.add_child(head)
	head.add_child(UiTheme.hud_label("OBJECTIVE", UiTheme.SIZE_STAT, UiTheme.INK_3))
	_objective_label = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.PAPER_2)
	head.add_child(_objective_label)

	var step := HBoxContainer.new()
	step.add_theme_constant_override("separation", 5)
	rows.add_child(step)
	# Amber is this design system's "your attention here" — the same token the
	# charge meter fills with — so the live step reads as the one thing to do.
	_step_label = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.AMMO)
	step.add_child(_step_label)
	_body_label = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.WHITE)
	step.add_child(_body_label)

	_rest_label = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.INK_3)
	rows.add_child(_rest_label)

	UiTheme.make_decoration(self)
	hide()
	_built = true


## Centres the strip under the top bar. Measured rather than anchored, for the
## same reason ActionMenu measures itself: a PanelContainer's size is only valid
## a frame after its labels changed, and this one's width changes with every step
## it teaches.
func _place() -> void:
	await get_tree().process_frame
	if not is_inside_tree():  # rematch, menu exit or a batch scene change freed the strip
		return
	if not visible:
		return
	reset_size()
	var view_w := get_viewport().get_visible_rect().size.x
	position = Vector2(roundf((view_w - size.x) / 2.0), UiTheme.HUD_TOP_H + _MARGIN)
