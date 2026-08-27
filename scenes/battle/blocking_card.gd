class_name BlockingCard
extends RefCounted
## One card the battle holds itself still for: the turn banner, the Command Power
## activation card, the scripted-beat speech card.
##
## All three are the same beat — put a control up, hold it for a length the speed
## tier decides, and take it down again on time or on a press — and each used to
## carry its own tween field, its own signal and its own show/hide/finish triple,
## so a fourth card would have got one of those details wrong in silence.
##
## It decides nothing about what the card *says*: `raise` takes the caller's own
## bind or announce, so what a card is filled with stays with the card's owner.
##
## `holds_while_capturing` is why a photographed run still has the power card and
## the speech card in the frame: they are the frame's subject, so they are raised
## and never timed out. The turn banner is not, and does not.

signal finished

var holds_while_capturing: bool

var _card: Control
var _node: Node
var _tween: Tween


func _init(card: Control, node: Node, p_holds_while_capturing: bool) -> void:
	_card = card
	_node = node
	holds_while_capturing = p_holds_while_capturing


## Whether the card is on screen.
func is_up() -> bool:
	return _card.visible


## Puts the card up immediately and cancels any pending auto-hide.
func raise(after: Callable) -> void:
	_kill()
	after.call()
	_card.show()
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)


## Holds the raised card for `seconds`, then takes it down. Awaitable, and it
## returns however the card was retired — the interval running out, or `dismiss`
## on a press — because both ends go through `_finish`.
func hold(seconds: float) -> void:
	_tween = _node.create_tween()
	_tween.tween_interval(seconds)
	_tween.tween_callback(_finish)
	await finished


## Takes the card down now, cancelling any pending auto-hide.
func dismiss() -> void:
	_kill()
	_finish()


func _finish() -> void:
	_tween = null
	if not _card.visible:
		return
	_card.hide()
	finished.emit()


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
