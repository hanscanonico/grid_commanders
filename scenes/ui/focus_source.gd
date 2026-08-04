class_name FocusSource
extends Node
## How the player last spoke to the game. `focus_entered` never says whether focus
## arrived by Tab or by click, and Godot grabs focus for any focusable control the
## pointer presses, so this one flag is what lets a caller answer the question the
## signal cannot — the same distinction a browser draws with `:focus-visible`.
##
## One node in the scene, not a hook on each control that asks: the deciding event
## is the press *before* the answer is wanted, so the tracker has to be listening
## whether or not anybody is currently asking. `_input` runs ahead of the
## viewport's GUI pass, so the flag is already right by the time focus moves.
##
## The state is static because there is exactly one player: every reader asks the
## same question about the same last event. `ensure` is how a reader gets one into
## the tree — reading `by_keyboard` with no source mounted answers "not by
## keyboard" forever.

const NODE_NAME := "FocusSource"

static var by_keyboard := false


## Mounts the one source under `parent`, if it is not already there.
static func ensure(parent: Node) -> void:
	if parent.get_node_or_null(NodePath(NODE_NAME)) != null:
		return
	var source := FocusSource.new()
	source.name = NODE_NAME
	parent.add_child(source)


func _init() -> void:
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		by_keyboard = false
	elif (
		event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion
	):
		by_keyboard = true
