class_name ViewChip
extends Node
## The 2D/3D switch, on the screen rather than in a menu: a chip that reads which
## board is up and flips it, printed on the battle's top bar and on the main menu.
##
## The chip itself is `UiKit.action_chip`'s, so a press is the V key and goes where
## V goes. In a battle that is Board3D, which holds the key still under a story
## scene or a cut-in and then asks `Settings.set_board_3d`. The main menu has no
## board to answer V, so there the chip answers it itself, through the same call.
## This node rides under the chip and relabels it whenever the view changes.

const ACTION := &"toggle_view"

var _chip: Button
var _answers_key := false


func _init(chip: Button, answers_key: bool) -> void:
	_chip = chip
	_answers_key = answers_key


## A chip naming the current view. `answers_key` is for a screen with no Board3D.
static func build(answers_key := false) -> Button:
	var chip := UiKit.action_chip(label(), ACTION)
	chip.add_child(ViewChip.new(chip, answers_key))
	return chip


## The main menu's chip, at the far end of the header row it is added to, so the
## board can be chosen before a match. Inked as the tagline beside it is, since the
## page under it is lighter than the bar a battle's chip sits on.
static func for_menu() -> Button:
	var chip := build(true)
	chip.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	UiTheme.hud_chip_ink(chip, UiTheme.NEUTRAL_LIGHT)
	return chip


static func label() -> String:
	var face := ControlHints.VIEW_3D_CHIP if Settings.board_3d else ControlHints.VIEW_2D_CHIP
	return ControlHints.chip_for(face)


func _ready() -> void:
	Settings.board_view_changed.connect(_relabel)
	set_process_unhandled_input(_answers_key)


func _relabel() -> void:
	_chip.text = label()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION):
		Settings.set_board_3d(not Settings.board_3d)
		get_viewport().set_input_as_handled()
