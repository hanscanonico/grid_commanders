class_name BattleCommandReceipt
extends RefCounted
## Typed facts returned by BattleCommandPipeline after one committed-command
## attempt. Interaction flow reads these facts; the pipeline never chooses the
## next player state or AI plan.

var command: Command
var validation_error := ""
var applied := false
var ambushed := false
var watched := false
var turn_changed := false
var team_before := 0
var team_after := 0
var day_before := 0
var day_after := 0
var winner := 0


func _init(p_command: Command) -> void:
	command = p_command


func rejected() -> bool:
	return not validation_error.is_empty()
