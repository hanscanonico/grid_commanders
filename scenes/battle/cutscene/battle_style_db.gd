class_name BattleStyleDB
extends RefCounted
## Registry of BattleStyle resources, indexed by id. Same shape as TerrainDB and
## UnitDB — scan the directory, index by id — so adding a weapon signature is
## dropping a .tres in and naming it from a unit, with no code to change.
##
## `by_id` never returns null. A unit whose style is missing or misspelled stages
## as unarmed rather than crashing the cut-in mid-attack, the same graceful
## degradation Sfx gives a missing sound: the exchange still resolves, still ticks
## HP and still ends, it just has nothing leaving the barrel. The warning is
## pushed once per unknown id so a typo is visible in the log without filling it.

const STYLE_DIR := "res://data/battle_anim"

## The style anything unrecognised falls back to. Built in code rather than
## loaded, so the fallback cannot itself be the missing file. It overrides every
## `@export` default that assumes a weapon: a silent style flashes no muzzle and
## slams no hull back, so this and `unarmed.tres` stay one answer.
static var _unarmed: BattleStyle

var _by_id: Dictionary = {}
var _warned: Dictionary = {}


static func load_default() -> BattleStyleDB:
	var db := BattleStyleDB.new()
	var dir := DirAccess.open(STYLE_DIR)
	if dir == null:
		push_error("BattleStyleDB: cannot open %s" % STYLE_DIR)
		return db
	for file in dir.get_files():
		# Exported builds list .tres files as .tres.remap.
		var file_name := file.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var style: BattleStyle = load(STYLE_DIR.path_join(file_name))
		if style != null:
			db.register(style)
	return db


static func unarmed() -> BattleStyle:
	if _unarmed == null:
		_unarmed = BattleStyle.new()
		_unarmed.id = &"unarmed"
		_unarmed.projectile = BattleStyle.NONE
		_unarmed.muzzle = 0.0
		_unarmed.recoil = 0.0
	return _unarmed


func register(style: BattleStyle) -> void:
	if _by_id.has(style.id):
		push_error("BattleStyleDB: duplicate style id '%s'" % style.id)
		return
	if not BattleStyle.PROJECTILES.has(style.projectile):
		push_error(
			(
				"BattleStyleDB: style '%s' fires '%s', which is not a projectile kind %s"
				% [style.id, style.projectile, BattleStyle.PROJECTILES]
			)
		)
		return
	_by_id[style.id] = style


## The style a unit's primary weapon fires with. Never null — see above.
func for_unit(type: UnitType) -> BattleStyle:
	return by_id(type.battle_style)


## The style named by an already-resolved weapon slot. The slot is a replay
## fact; this maps it to presentation data and never asks the combat rules.
func for_weapon(type: UnitType, slot: StringName) -> BattleStyle:
	if slot == DamageChart.PRIMARY:
		return by_id(type.battle_style)
	if slot == DamageChart.SECONDARY:
		return by_id(type.secondary_battle_style)
	return unarmed()


func by_id(id: StringName) -> BattleStyle:
	var style: BattleStyle = _by_id.get(id)
	if style != null:
		return style
	if not _warned.has(id):
		_warned[id] = true
		push_warning("BattleStyleDB: no style '%s'; staging it unarmed" % id)
	return unarmed()


func has(id: StringName) -> bool:
	return _by_id.has(id)


## Every registered id, for a caller holding the whole shelf to one rule.
func ids() -> Array:
	return _by_id.keys()


func size() -> int:
	return _by_id.size()
