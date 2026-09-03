class_name SeaBeat
extends Node
## Puts an animated autotile family's sheet on the board's beat: on every
## `period_ms` tick it re-points that family's TileSetAtlasSource texture at
## the other frame. Frame B is the same variants in the same order — the sea's
## three phases, the rivers' and shoals' sixteen masks — so the source id, the
## cut, `sheet_cells`, `atlas_coords` and `variant` are all untouched and the
## beat costs one pointer.
##
## The sea was the first family on this beat, so the class keeps its name
## rather than one invented for a second user — renaming it would touch every
## comment and doc that already says "the sea's swell" for no behaviour
## change. `attach` generalised instead (S9, rivers and shoals): one instance
## per animated family, each carrying its own source and period, which is
## still the single tick-owner idiom — a sibling class per family would be
## three copies of the same eight lines with nothing left to tell apart.
##
## The whole board rides it for free: the backdrop and the property ground
## share `terrain_layer.tile_set`, so the out-of-bounds ring and any painted
## cell of that family swell with it, by construction rather than by a second
## code path.
##
## A Node because a beat needs a frame to arrive on and BattleView is
## RefCounted; it owns nothing but the pointer it was handed, in the
## dumb-drawer idiom CapturePips and MuzzleFlash are in. BattleView, the one
## owner of the TileSet and its sources, is what hands the source over —
## nothing here looks one up.

var _source: TileSetAtlasSource
var _family: int
var _period_ms: int
var _frame: int = 0


## Hangs a beat on `parent` for `source`, drawing `family`'s frames at
## `period_ms`, opening on whatever frame the rest of the board is on — a
## board loaded mid-beat would otherwise show frame A and snap a tick later.
static func attach(parent: Node, source: TileSetAtlasSource, family: int, period_ms: int) -> void:
	var beat := SeaBeat.new()
	beat._source = source
	beat._family = family
	beat._period_ms = period_ms
	beat._frame = BoardBeat.frame(period_ms)
	beat._point_at(beat._frame)
	parent.add_child(beat)


func _process(_delta: float) -> void:
	var frame := BoardBeat.frame(_period_ms)
	if frame == _frame:
		return
	_frame = frame
	_point_at(frame)


func _point_at(frame: int) -> void:
	_source.texture = load(TerrainAutotiles.sheet_path(_family, frame))
