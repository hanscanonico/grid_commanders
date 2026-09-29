class_name CommanderLooks3D
extends RefCounted
## What each general looks like on the 3D board: the portrait generator's FACES
## columns a figure can show at board scale, read off the same table the busts
## are painted from so a general's 3D figure and their portrait agree.
##
## A mirror, not a source: `generators/portraits/portraitgen/roster.py` owns
## FACES, `head.py` the skin bases and `hair.py` the hair bases, and
## `generators/portraits/tests/test_actor_look_mirror.py` fails when this copy
## drifts from them. Each row is one string, columns in `COLUMNS` order.

const COLUMNS: Array[StringName] = [
	&"skin", &"hair", &"style", &"acc", &"acc2", &"facial", &"collar", &"chest", &"prop"
]

const LOOKS: Dictionary[StringName, String] = {
	&"alina_ward": "light auburn long none none none v sash sabre",
	&"gideon_holt": "tan grey short glasses none beard double placket pipe",
	&"rhea_sol": "tan black ponytail goggles none none mandarin loops wrench",
	&"cass_orlov": "light brown buzz scar none stubble v crossbelt cigar",
	&"mara_voss": "medium black bun none none none v bandolier baton",
	&"viktor_draeg": "light grey bald eyepatch none mustache v boards medal",
	&"cassian_rook": "tan blonde sidepart none none none mandarin lanyard card",
	&"lyra_quill": "pale platinum bob glasses none none mandarin placket book",
	&"orin_flux": "medium black spiky headset none none mandarin lanyard drone",
	&"nia_rowan": "tan brown braid headband none none v pouch monocle",
	&"sable_wren": "pale black hood hood none none v scarf dagger",
	&"tomas_reed": "dark black curly bandana none stubble v harness radio",
	&"ines_calder": "dark black bun glasses visor none mandarin mapcase ledger",
	&"konrad_vale": "pale steel sidepart scar none mustache mandarin boards helm",
	&"perrin_ash": "tan auburn short goggles none none v crossbelt plane",
	&"halden_marr": "tan grey curly none none beard double epaulette anchor",
	&"dane_ferrow": "dark black buzz fieldcap scar stubble mandarin plain coins",
	&"iris_colt": "light blonde ponytail headset none none v scarf whistle",
	&"sera_lark": "dark darkbrown ponytail bandana none none mandarin mapcase compass",
	&"iona_vance": "tan brown bob cap none none mandarin harness scales",
	&"ivar_thorne": "light darkbrown long scar none beard v sash axe",
	&"radek_morn": "medium darkbrown bald none none beard double bandolier hammer",
}

## The plain officer an unknown id and the empty seat stand as.
const NEUTRAL_LOOK := "medium brown short fieldcap none none v plain none"

## `portraitgen/head.py` SKIN_BASES, as 8-bit RGB.
const SKIN_BASES: Dictionary[StringName, Vector3i] = {
	&"dark": Vector3i(138, 90, 60),
	&"light": Vector3i(242, 201, 160),
	&"medium": Vector3i(217, 160, 102),
	&"pale": Vector3i(246, 220, 194),
	&"tan": Vector3i(198, 134, 66),
}

## `portraitgen/hair.py` HAIR_BASES, as 8-bit RGB.
const HAIR_BASES: Dictionary[StringName, Vector3i] = {
	&"auburn": Vector3i(140, 74, 47),
	&"black": Vector3i(38, 38, 38),
	&"blonde": Vector3i(224, 184, 76),
	&"brown": Vector3i(90, 60, 40),
	&"darkbrown": Vector3i(51, 37, 26),
	&"grey": Vector3i(189, 189, 189),
	&"platinum": Vector3i(231, 224, 204),
	&"steel": Vector3i(165, 165, 165),
}


static func has_look(id: StringName) -> bool:
	return LOOKS.has(id)


## The general's look: `skin_color` and `hair_color` as Colors, and every other
## column as a StringName. An id with no row, the empty seat's among them, is
## the neutral officer.
static func look_of(id: StringName) -> Dictionary:
	var row: PackedStringArray = LOOKS.get(id, NEUTRAL_LOOK).split(" ")
	var look := {}
	for i in COLUMNS.size():
		look[COLUMNS[i]] = StringName(row[i])
	look[&"skin_color"] = _rgb(SKIN_BASES[look[&"skin"]])
	look[&"hair_color"] = _rgb(HAIR_BASES[look[&"hair"]])
	return look


static func _rgb(bytes: Vector3i) -> Color:
	return Color8(bytes.x, bytes.y, bytes.z)
