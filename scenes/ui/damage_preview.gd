class_name DamagePreview
extends PanelContainer
## The attack forecast beside the cell under the cursor: what this shot deals,
## what comes back, and what the target is left standing on.
##
## Dressed as a chip rather than as a bar — the slate panel, ink outline and hard
## shadow ActionFeedback wears, because the two are the same species: transient
## paint floating over the board, where the docked bars are chrome outside it.
##
## It speaks HP out of 10, the unit every other HP display in the game speaks (UX
## recovery plan D4). Every number was handed over by the forecast: this formats
## and never computes, which is the cut-in's "replays, never decides" rule applied
## to text. Where it lands is BattleView's, which asks BoardCamera for the board's
## geometry.

const _PAD_X := 5
const _PAD_Y := 3

var _deal_label: Label
var _counter_label: Label
var _outcome_label: Label


func _ready() -> void:
	_build()


func _build() -> void:
	add_theme_stylebox_override("panel", UiTheme.dark_panel_box())

	var margin := UiKit.pad(null, _PAD_X, _PAD_Y)
	add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	margin.add_child(rows)

	_deal_label = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.WHITE)
	rows.add_child(_deal_label)
	# What comes back is the cost of the shot, so it reads as the secondary of the
	# two — the same split the bottom bar's name and stat lines take.
	_counter_label = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.PAPER_2)
	rows.add_child(_counter_label)
	_outcome_label = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.INK_3)
	rows.add_child(_outcome_label)


## Prints one forecast. Both damage lines are spans because luck can move where
## inside them a shot lands; the third states the target's own before and after so
## the player never subtracts, and carries the luck-free attack percentage as the
## secondary detail plan D4 allows it to be — a chip attack worth less than a
## displayed HP reads "Deal 0 HP" up top, and this is where it says it landed.
##
## The turnstile is `»` and not `→`: neither vendored face carries U+2192, so an
## arrow is the one mark on this panel the engine falls back to an OS font for.
func show_forecast(forecast: CombatSnapshot.Forecast) -> void:
	_deal_label.text = (
		"Deal %s HP"
		% _hp_span(
			forecast.defender_hp_before - forecast.defender_hp_after_max,
			forecast.defender_hp_before - forecast.defender_hp_after_min
		)
	)
	_counter_label.text = (
		(
			"Take %s HP"
			% _hp_span(
				forecast.attacker_hp_before - forecast.attacker_hp_after_max,
				forecast.attacker_hp_before - forecast.attacker_hp_after_min
			)
		)
		if forecast.counter_damage >= 0
		else "No counter"
	)
	_outcome_label.text = (
		"Target %d » %s HP · %d%% · luck included"
		% [
			forecast.defender_hp_before,
			_hp_span(forecast.defender_hp_after_min, forecast.defender_hp_after_max),
			forecast.attack_damage
		]
	)


## "5" for a certain outcome, "5–6" for one luck can move. Both bounds are the
## forecast's; this only chooses how to say them.
static func _hp_span(low: int, high: int) -> String:
	return str(low) if low == high else "%d–%d" % [low, high]
