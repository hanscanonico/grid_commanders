extends GutTest
## Resolves every id-shaped field in data/ against the database that answers for
## it. Nothing else in the project does, and every way one of them goes wrong is
## silent: a typo'd key in a terrain's move_costs makes that terrain impassable
## for the class (TerrainType.move_cost reads a missing key as IMPASSABLE), a
## typo'd id in a doctrine's list matches no unit, so the hook returns 0 and the
## general plays neutral — no error, no crash, nothing in the log. This is the
## data-side sibling of test_damage_chart.gd, which does the same job for the one
## file that already had it.
##
## The scan is by naming convention rather than by a list of field names, because
## a list of field names is itself a thing that rots — a doctrine that ships
## tomorrow with `bunker_ids` is covered here without anyone remembering this
## file exists. The convention is three suffixes and it is the whole rule:
##
##     *_ids        a unit id            (UnitDB)
##     *_class(es)  a movement class     (TerrainType's class constants)
##     *_terrain    a terrain id         (TerrainDB)
##
## The trade is stated rather than hidden: a field named *outside* the convention
## is **not** covered. The handful that predate it are named in BY_NAME below,
## and a new id-shaped field should take a conventional name instead of joining
## that list.
##
## Out of scope on purpose, each already linted where it belongs: the damage
## chart's rows and columns (test_damage_chart.gd), the cut-in's terrain keys
## (test_terrain_db.gd), the weapon signatures (test_battle_styles.gd), and
## whether every tier and every general writes its own numbers at all
## (test_ai_profile.gd, test_commander_hooks.gd).

const DATA_DIR := "res://data"

## What kind of thing an id-shaped field names, and so which database answers it.
enum Kind { NONE, UNIT, MOVE_CLASS, TERRAIN, DOMAIN }

## The convention, as a table. A field is id-shaped when its name ends with one
## of these.
const BY_SUFFIX := {
	"_ids": Kind.UNIT,
	"_class": Kind.MOVE_CLASS,
	"_classes": Kind.MOVE_CLASS,
	"_terrain": Kind.TERRAIN,
}

## The id-shaped fields whose names predate the convention. Kept short on
## purpose: this list is the part that rots, so anything added later should be
## named to the convention rather than listed here.
const BY_NAME := {
	"move_costs": Kind.MOVE_CLASS,  # TerrainType, keyed by class
	"builds": Kind.MOVE_CLASS,  # TerrainType
	"services": Kind.DOMAIN,  # TerrainType
	"domain": Kind.DOMAIN,  # UnitType
	"build_priority": Kind.UNIT,  # AIProfile
}

const LABEL := {
	Kind.UNIT: "a unit id",
	Kind.MOVE_CLASS: "a movement class",
	Kind.TERRAIN: "a terrain id",
	Kind.DOMAIN: "a unit domain",
}

## Spelled out rather than reflected off the script: these seven are the whole
## movement model, so a class added to TerrainType has to be added here too —
## and that failure is loud, which is the right way round for a lint.
const MOVE_CLASSES: Array[StringName] = [
	TerrainType.FOOT,
	TerrainType.BOOT,
	TerrainType.TIRES,
	TerrainType.TREADS,
	TerrainType.AIR,
	TerrainType.SHIP,
	TerrainType.LANDER,
]

const DOMAINS: Array[StringName] = [UnitType.LAND, UnitType.AIR, UnitType.SEA]

var unit_db: UnitDB
var terrain_db: TerrainDB


func before_each() -> void:
	unit_db = Fixture.unit_db()
	terrain_db = Fixture.terrain_db()


func test_every_resource_under_data_loads() -> void:
	var files := _data_files()
	assert_gt(files.size(), 0, "data/ should hold resources")
	for path in files:
		assert_not_null(load(path), "%s does not load" % path)


## The lint itself.
func test_every_id_shaped_field_names_something_that_exists() -> void:
	for entry in _scan():
		assert_true(
			_exists(entry["kind"], entry["id"]),
			(
				"%s: %s names '%s', which is not %s"
				% [entry["path"], entry["field"], entry["id"], LABEL[entry["kind"]]]
			)
		)


## A convention-driven walk fails open: rename every field out of the convention
## and the lint above passes over an empty scan reporting nothing. This is what
## says it is still looking at something, per kind — the four numbers are floors,
## not counts, so ordinary data edits do not touch them.
func test_the_scan_reaches_every_kind_it_answers_for() -> void:
	var found: Dictionary = {}
	for entry in _scan():
		found[entry["kind"]] = int(found.get(entry["kind"], 0)) + 1
	assert_gt(int(found.get(Kind.UNIT, 0)), 20, "unit ids: the doctrine lists and build_priority")
	assert_gt(int(found.get(Kind.MOVE_CLASS, 0)), 40, "movement classes: every move_costs table")
	assert_gt(int(found.get(Kind.TERRAIN, 0)), 5, "terrain ids: the shore, cover and unload lists")
	assert_gt(
		int(found.get(Kind.DOMAIN, 0)), 15, "domains: every unit and every servicing property"
	)


## A power's expiry is an enum with exactly two points, and a .tres stores it as
## a plain integer — so a third value is storable, reads as neither expiry, and
## PowerCommand would carry the power past both.
func test_every_power_expires_at_one_of_the_two_points() -> void:
	var expiries: Array[int] = [CommanderType.Duration.OWNER_TURN, CommanderType.Duration.ROUND]
	for co in Fixture.commander_db().all():
		assert_has(expiries, int(co.power_duration), "%s's power expires at no known point" % co.id)


# --- the walk ----------------------------------------------------------------


## Every id-shaped value in data/, as {path, field, kind, id}. Deterministic:
## files sorted, directories after them, ids in declaration order.
func _scan() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for path in _data_files():
		var resource: Resource = load(path)
		if resource == null:
			continue
		for field in _stored_fields(resource):
			var kind: Kind = _kind_of(field)
			if kind == Kind.NONE:
				continue
			for id in _ids_in(resource.get(field)):
				found.append({"path": path, "field": field, "kind": kind, "id": id})
	return found


func _kind_of(field: String) -> Kind:
	for suffix: String in BY_SUFFIX:
		if field.ends_with(suffix):
			return BY_SUFFIX[suffix]
	return BY_NAME.get(field, Kind.NONE)


## The ids a field holds: one for a scalar, each element of a list, each key of a
## table — move_costs is keyed by movement class, and the key is the id-shaped
## half of it.
func _ids_in(value: Variant) -> Array[StringName]:
	var ids: Array[StringName] = []
	match typeof(value):
		TYPE_STRING_NAME, TYPE_STRING:
			ids.append(StringName(value))
		TYPE_ARRAY:
			for element: Variant in value:
				ids.append(StringName(element))
		TYPE_DICTIONARY:
			for key: Variant in value:
				ids.append(StringName(key))
	return ids


## An empty id counts as a miss rather than as "unset": a doctrine reading one
## matches nothing, which is exactly as silent as the typo this file is for.
func _exists(kind: Kind, id: StringName) -> bool:
	match kind:
		Kind.UNIT:
			return unit_db.by_id(id) != null
		Kind.TERRAIN:
			return terrain_db.by_id(id) != null
		Kind.MOVE_CLASS:
			return id in MOVE_CLASSES
		Kind.DOMAIN:
			return id in DOMAINS
	return false


func _data_files(dir_path: String = DATA_DIR) -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return paths
	var files := dir.get_files()
	files.sort()
	for file in files:
		# Exported builds list resources with a .remap suffix.
		var resource_file := file.trim_suffix(".remap")
		if resource_file.ends_with(".tres"):
			paths.append(dir_path.path_join(resource_file))
	var dirs := dir.get_directories()
	dirs.sort()
	for sub_dir in dirs:
		paths.append_array(_data_files(dir_path.path_join(sub_dir)))
	return paths


## The fields a .tres can actually store: an @export carries STORAGE, a plain
## script var does not.
static func _stored_fields(resource: Resource) -> Array[String]:
	var fields: Array[String] = []
	for property in resource.get_property_list():
		var usage := int(property.usage)
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) and (usage & PROPERTY_USAGE_STORAGE):
			fields.append(property.name)
	return fields
