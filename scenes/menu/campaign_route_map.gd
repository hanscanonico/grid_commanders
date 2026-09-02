class_name CampaignRouteMap
extends Control
## The shape of a war, drawn over the hub's rows: one route line across the page,
## an act per stretch of it with its title above, a node per mission along it, and
## the war's standing at the right. A mission the route opens on a condition hangs
## under the line as a branch, and an interlude sits between two acts as a mark.
##
## It has no campaign logic of its own. Which node is cleared, open, locked or a
## road not taken is `CampaignState`'s answer, asked node by node through `plot`,
## and the standing is the same count the hub's subtitle reads — `offered_count`,
## never `mission_count`, or a war with a road not taken reads unfinished forever.
##
## The rows stay the way to deploy. Pressing a node only focuses the matching row,
## and a row taking focus lights its node, so the keyboard walks the route without
## ever leaving the list.
##
## Drawn, not assembled, for `MapThumbnail`'s reason: a node is a few pixels of
## faction colour on a line, and a button that small is chrome nobody can read.
## `plot` and `standing` are static and argument-taking so the shape is checked
## without building the control (docs/testing_exceptions.md).

signal mission_pressed(mission_id: StringName)

## How a node reads. A mission the route walked past is not the same as one nobody
## has reached — `CampaignState.is_skipped` is the difference — so it has its own.
enum NodeState { CLEARED, OPEN, LOCKED, NOT_TAKEN }


## One mission's place on the route.
class RouteNode:
	extends RefCounted

	var id: StringName
	var block: int
	var state: NodeState
	var stars: int
	## Opens on a condition, so it hangs under the line rather than sitting on it.
	var branch: bool

	func _init(
		p_id: StringName, p_block: int, p_state: NodeState, p_stars: int, p_branch: bool
	) -> void:
		id = p_id
		block = p_block
		state = p_state
		stars = p_stars
		branch = p_branch


const HEIGHT := 42
## The column the standing stands in, at the right end of the route.
const _STANDING_W := 72
const _INSET := 6
const _LABEL_Y := 0
const _LINE_Y := 25
## How far under the line a branch node hangs.
const _BRANCH_DROP := 9
const _NODE_R := 3.0
const _RING_R := 4.0
const _LOCKED_R := 2.0
const _PIP_PITCH := 2
## How far from a node's centre its pips sit — above a node on the line, under a
## branch node, so they never land on the line itself.
const _PIP_LIFT := 8
## The open node's ring breathes between these two, once per `PULSE_SECONDS`.
const _PULSE_GROW := 1.5
const PULSE_SECONDS := 1.2
## The reach a press has around a node's centre.
const _HIT_R := 8.0
const _INTERLUDE_R := 2.5

var _nodes: Array[RouteNode] = []
var _campaign: CampaignDefinition
var _theme: CommanderVisuals.FactionTheme
var _labels: Array[Label] = []
var _standing: Label
var _lit: StringName = &""
var _moving := true
var _phase := 0.0
var _focus_ink: Color = UiTheme.focus_box().border_color


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_standing = ListRow.cell("", UiTheme.NEUTRAL_LIGHT)
	_standing.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_standing)
	resized.connect(_layout)
	set_process(false)


## Reads the war's shape and the profile's answer for every mission of it. The
## theme is the war's foe's, resolved by the hub through `SideIdentity` — this
## control never asks who is fighting.
func show_war(
	campaign: CampaignDefinition, progress: CampaignState, theme: CommanderVisuals.FactionTheme
) -> void:
	_campaign = campaign
	_theme = theme
	_nodes = plot(campaign, progress)
	_lit = &""
	_standing.text = standing(campaign, progress)
	for label in _labels:
		label.queue_free()
	_labels.clear()
	for title: String in campaign.block_titles:
		var label := ListRow.clipped(ListRow.detail(title.to_upper(), UiTheme.INK_3))
		add_child(label)
		_labels.append(label)
	_layout()
	_apply_motion()


## Lights the node of the row that has focus, and no other.
func highlight(mission_id: StringName) -> void:
	if _lit == mission_id:
		return
	_lit = mission_id
	queue_redraw()


## Whether the open node breathes. A posed capture holds it at rest, and so does
## the Menu motion preference — the same two answers the menu's own scenery obeys.
func set_moving(moving: bool) -> void:
	_moving = moving
	_apply_motion()


## Every mission's place and state, in list order, read from the one authority.
static func plot(campaign: CampaignDefinition, progress: CampaignState) -> Array[RouteNode]:
	var nodes: Array[RouteNode] = []
	for mission: MissionDefinition in campaign.missions:
		if mission == null:
			continue
		var state := NodeState.LOCKED
		if progress.is_cleared(mission.id):
			state = NodeState.CLEARED
		elif progress.is_unlocked(mission.id):
			state = NodeState.OPEN
		elif progress.is_skipped(campaign, mission.id):
			state = NodeState.NOT_TAKEN
		nodes.append(
			RouteNode.new(
				mission.id,
				campaign.block_of(mission.id),
				state,
				progress.stars_for(mission.id),
				mission.unlock_requires != null
			)
		)
	return nodes


## The war's tally in the route's own words: cleared of offered, and the stars.
static func standing(campaign: CampaignDefinition, progress: CampaignState) -> String:
	return (
		"%d / %d · %d ★"
		% [progress.records.size(), progress.offered_count(campaign), progress.total_stars()]
	)


## Breathing is for a ring somebody can see: a hub hidden under the menu, or under
## its own briefing, has nothing to redraw every frame.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_apply_motion()


func _apply_motion() -> void:
	var breathing := (
		_moving and Settings.menu_animations and is_visible_in_tree() and _open_index() >= 0
	)
	set_process(breathing)
	if not breathing:
		_phase = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta, PULSE_SECONDS)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var press := event as InputEventMouseButton
	if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_LEFT:
		return
	for index in _nodes.size():
		if _node_centre(index).distance_to(press.position) <= _HIT_R:
			accept_event()
			mission_pressed.emit(_nodes[index].id)
			return


# --- geometry ----------------------------------------------------------------


func _route_left() -> float:
	return float(_INSET)


func _route_right() -> float:
	return size.x - _STANDING_W - _INSET


func _pitch() -> float:
	return (_route_right() - _route_left()) / maxf(1.0, float(_nodes.size()))


func _node_centre(index: int) -> Vector2:
	var y := _LINE_Y + (_BRANCH_DROP if _nodes[index].branch else 0)
	return Vector2(roundf(_route_left() + (index + 0.5) * _pitch()), y)


func _open_index() -> int:
	for index in _nodes.size():
		if _nodes[index].state == NodeState.OPEN:
			return index
	return -1


## Where each act's stretch of the route starts and how far it runs — the label's
## rect, and the mark between two acts.
func _block_span(block: int) -> Vector2:
	var first := -1
	var count := 0
	for index in _nodes.size():
		if _nodes[index].block == block:
			if first < 0:
				first = index
			count += 1
	if first < 0:
		return Vector2.ZERO
	return Vector2(_route_left() + first * _pitch(), count * _pitch())


func _layout() -> void:
	_standing.size = Vector2(_STANDING_W, _standing.get_minimum_size().y)
	_standing.position = Vector2(size.x - _STANDING_W, _LINE_Y - _standing.size.y * 0.5)
	for block in _labels.size():
		var span := _block_span(block)
		var label := _labels[block]
		label.position = Vector2(roundf(span.x), _LABEL_Y)
		label.size = Vector2(floorf(span.y) - 2, label.get_minimum_size().y)
	queue_redraw()


# --- paint -------------------------------------------------------------------


func _draw() -> void:
	if _nodes.is_empty() or _theme == null:
		return
	_draw_line_segments()
	_draw_interludes()
	for index in _nodes.size():
		_draw_node(index)


## The route line, walked as far as the open mission in the foe's colour and
## unwalked past it. A branch node's stub drops from the line to it.
func _draw_line_segments() -> void:
	var open := _open_index()
	var walked_to := _route_left()
	if open >= 0:
		walked_to = _node_centre(open).x
	elif _nodes[_nodes.size() - 1].state == NodeState.CLEARED:
		walked_to = _route_right()
	var y := float(_LINE_Y)
	draw_line(Vector2(_route_left(), y), Vector2(walked_to, y), _theme.color_light, 1.0)
	if walked_to < _route_right():
		draw_line(Vector2(walked_to, y), Vector2(_route_right(), y), UiTheme.SLATE_700, 1.0)
	for index in _nodes.size():
		if _nodes[index].branch:
			var centre := _node_centre(index)
			var ink := _theme.color_light if centre.x <= walked_to else UiTheme.SLATE_700
			draw_line(Vector2(centre.x, y), Vector2(centre.x, centre.y - _NODE_R), ink, 1.0)


func _draw_interludes() -> void:
	for block in _campaign.block_titles.size() - 1:
		if _campaign.interlude_after(block) == null:
			continue
		var span := _block_span(block)
		var at := Vector2(roundf(span.x + span.y), float(_LINE_Y))
		var diamond := PackedVector2Array(
			[
				at + Vector2(0, -_INTERLUDE_R),
				at + Vector2(_INTERLUDE_R, 0),
				at + Vector2(0, _INTERLUDE_R),
				at + Vector2(-_INTERLUDE_R, 0),
			]
		)
		draw_colored_polygon(diamond, UiTheme.NEUTRAL_LIGHT)


func _draw_node(index: int) -> void:
	var node := _nodes[index]
	var centre := _node_centre(index)
	match node.state:
		NodeState.CLEARED:
			draw_circle(centre, _NODE_R, _theme.color_light)
			_draw_pips(centre, node.stars, node.branch)
		NodeState.OPEN:
			var swell := _PULSE_GROW * (0.5 - 0.5 * cos(TAU * _phase / PULSE_SECONDS))
			draw_arc(centre, _RING_R + swell, 0.0, TAU, 24, UiTheme.PAPER, 1.0)
			draw_circle(centre, _LOCKED_R, UiTheme.PAPER)
		NodeState.LOCKED:
			draw_circle(centre, _LOCKED_R, UiTheme.NEUTRAL_DARK)
		NodeState.NOT_TAKEN:
			draw_arc(centre, _LOCKED_R + 0.5, 0.0, TAU, 12, UiTheme.NEUTRAL_DARK, 1.0)
	if node.id == _lit:
		var box := Rect2(
			centre - Vector2(_RING_R + 2, _RING_R + 2), Vector2.ONE * (_RING_R * 2 + 4)
		)
		draw_rect(box, _focus_ink, false, 1.0)


## The stars a cleared mission earned, as gold pips beside its node.
func _draw_pips(centre: Vector2, stars: int, under: bool) -> void:
	if stars <= 0:
		return
	var left := centre.x - float((stars - 1) * _PIP_PITCH) * 0.5
	var y := centre.y + (_PIP_LIFT if under else -_PIP_LIFT)
	for pip in stars:
		draw_rect(Rect2(roundf(left + pip * _PIP_PITCH), y, 1, 1), UiTheme.SELECT_GOLD)
