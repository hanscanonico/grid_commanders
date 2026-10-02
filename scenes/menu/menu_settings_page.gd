class_name MenuSettingsPage
extends Control
## The main menu's Settings page (SK-14): the pause menu's own value rows —
## sound, the end-turn check, the window — on a page reached from the menu's
## Settings button or Esc, so a player can set them before a match rather than only
## inside one.
##
## Not a second settings screen: the rows are `Settings.value_actions`, the list
## the pause menu draws, in the same `ActionMenu`, so a row reads and steps the
## same way in both places. Speed is left out because the setup panel already has
## its own Speed control — two controls writing one fact is the drift a single
## authority exists to prevent — and the two animation toggles are on that panel
## too.
##
## Shown over the menu without tearing it down, like the replays page: the menu
## behind it is hidden so no focus or click leaks through, and Back lands on the
## Settings button.

const _BACK := {"id": &"cancel", "label": "Back"}
## Over the menu, so the page draws above every row of it.
const _LAYER := 5

var _menu_root: Control
var _return_to: Button
var _menu: ActionMenu


## Builds the page behind `button` and the Esc that also opens it. Parented on its
## own layer as `menu`'s *first* child, because a node hears unhandled input after
## every node after it: a page open over the menu (the replays, a map's delete
## prompt) answers its own Esc before this one would treat it as a request for
## settings.
static func attach(menu: Control, menu_root: Control, button: Button) -> void:
	var layer := CanvasLayer.new()
	layer.layer = _LAYER
	var page := MenuSettingsPage.new(menu_root, button)
	layer.add_child(page)
	menu.add_child(layer)
	menu.move_child(layer, 0)
	button.pressed.connect(page.open)


func _init(menu_root: Control, return_to: Button) -> void:
	_menu_root = menu_root
	_return_to = return_to


func _ready() -> void:
	UiKit.page_veil(self)
	var body := UiKit.page_body(self, 6)
	body.add_child(UiKit.page_title("SETTINGS"))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)
	body.add_child(UiKit.key_legend("UP/DOWN  BROWSE      LEFT/RIGHT  CHANGE      ESC  BACK"))
	_menu = ActionMenu.new()
	var rows := VBoxContainer.new()
	rows.name = "MenuRows"
	_menu.add_child(rows)
	# `ActionMenu` finds its rows by unique name, which is how battle.tscn hands
	# them over; a page built in code owns them the same way.
	rows.owner = _menu
	rows.unique_name_in_owner = true
	add_child(_menu)
	_menu.hide()
	_menu.action_chosen.connect(_on_chosen)
	# A stepped row can widen the panel ("Sound: Half"), so it re-centres on every
	# resize rather than only where it opened.
	_menu.resized.connect(_centre)
	hide()


## Esc on the menu itself opens the page — the key a pause menu answers in a
## battle, answered the same way before one.
func _unhandled_input(event: InputEvent) -> void:
	if visible or not _menu_root.visible or not event.is_action_pressed(&"cancel"):
		return
	get_viewport().set_input_as_handled()
	open()


func open() -> void:
	_menu_root.hide()
	show()
	var rows := Settings.value_actions([Settings.SPEED_ROW])
	rows.append(_BACK)
	_menu.open(rows, Vector2.ZERO)
	_centre()


func _centre() -> void:
	_menu.position = ((get_viewport_rect().size - _menu.size) / 2.0).round()


## Only Back leaves: every other row is a value row, which `ActionMenu` steps where
## it stands rather than handing out.
func _on_chosen(id: StringName) -> void:
	if id != _BACK["id"]:
		return
	_menu.close()
	hide()
	_menu_root.show()
	_return_to.grab_focus()
