"""`anim.json` — the sheet contract the game reads instead of retyping it.

Every number the board needs to animate this art lives in one Python table
here: the cell's size and its ground line, each clip's sheets and cadence, the
column and row order of the units atlas, and how many phase variants each
terrain family ships. The game currently restates all of them by
hand (`unit_sprite.gd`, `terrain_autotiles.gd`), which is why a third ambient
sheet costs an edit on both sides; a manifest emitted next to the atlases costs
one.

So nothing here may be a literal that some other table already answers. The
sizes come from `atlas.CELL_W/CELL_H`, the columns from `units.ATLAS_ORDER`,
the rows from `palette.FACTIONS`, the phase counts from the terrain phase
tables, and `ground_px` is MEASURED off a rendered cell (see
`measure_ground_px`) rather than restated — a manifest that retypes a number is
just a third place to keep it in step. `AMBIENT_MS` is the one value with no
Python table behind it, because the cadence was only ever a game constant; the
manifest is now its source, and the comment carries the reasoning.

The JSON is deterministic like the rest of the pipeline: sorted keys, two-space
indent, trailing newline, so two runs are byte-identical.
"""

from __future__ import annotations

import json
from pathlib import Path

from . import atlas, terrain
from .palette import FACTIONS
from .units import ATLAS_ORDER, UNITS

# The manifest's own filename and the sheets the ambient clip plays, in frame
# order. `sprite_generator` writes its atlases under these names, so the clip
# and the files on disk cannot disagree.
MANIFEST_NAME = "anim.json"
AMBIENT_SHEETS: tuple[str, ...] = ("units_atlas.png", "units_atlas_b.png")
# Milliseconds per ambient frame. One cadence for the whole clip because the
# sheets encode one: frame B is the entire army a beat later, so a rotor and a
# swell cannot run at different rates without a third sheet. Half a second is
# the slowest rate a swept rotor still reads as turning, and the rotor is the
# faster of the two motions, so it sets the beat.
AMBIENT_MS = 500

# The sea's clip: the same three spatial phases in the same column order, once
# per time frame, written under the autotile directory the game installs them
# into (`sprite_generator._install`), so a path here is a path there. The
# frames themselves are `terrain.SEA_FRAMES`; a sheet name is the one thing
# only this table can answer, and the count is gated against that table.
SEA_SHEETS: tuple[str, ...] = ("autotiles/sea.png", "autotiles/sea_b.png")
# Milliseconds per sea frame. Nearly twice the ambient beat, and deliberately
# not a multiple of it: at 500 the two clips would turn over on the same tick
# every other frame and the whole board would blink at once, where 9:5 lets
# the water and the army drift out of step the way two unrelated motions do.
# The motion itself asks for slow — one glint crossing one board texel is a
# swell travelling, and a swell that crosses a texel twice a second is
# scintillation, which is the boil this clip exists to avoid. 900 ms puts the
# two-frame cycle at 1.8 s, about the period of the sea it is drawing.
SEA_MS = 900

# The terrain families that ship phase variants, and the table each counts.
# Named for the autotile sheet each family is drawn onto.
_PHASE_TABLES = {
    "sea": terrain.SEA_PHASES,
    "plains": terrain.PLAINS_PHASES,
    "mountain": terrain.MOUNTAIN_PHASES,
}

# Format version. Bump it when a consumer would have to read the file
# differently — adding a clip or a family is not that.
VERSION = 1


def measure_ground_px() -> int:
    """The cell's ground line, as a height above its BOTTOM edge, measured.

    The ground line is the row a land unit's contact shadow is centred on —
    the row its tracks or its feet rest on, and so the row a surface drawing
    the shadowless figure sheet has to put a contact ellipse of its own on.
    `voxel.GROUND_BOTTOM` is the sprite's own footing and the shadow sits
    `voxel.SHADOW_OFFSET` below it, so the answer is a subtraction between two
    constants — which is exactly why this measures instead: the manifest reads
    it off the art, the way the game's own test reads it off the shipped
    sheets.

    The method is that same subtraction: a composed cell minus the same cell
    with the tile shadow left off is the cast shadow alone, and an ellipse is
    widest on the row it is centred on. Every land column agrees on the answer,
    so the first one settles it.
    """
    uid = next(u for u in ATLAS_ORDER if UNITS[u][1] == "land")
    fac = FACTIONS[0]
    cell = atlas.unit_cell(uid, fac)
    lit = cell.load()
    bare = atlas.unit_cell(uid, fac, shadow=False).load()
    widest, ground = 0, -1
    for y in range(cell.height):
        span = sum(
            1 for x in range(cell.width) if lit[x, y][3] != 0 and bare[x, y][3] == 0
        )
        if span > widest:
            widest, ground = span, y
    if ground < 0:
        raise ValueError(f"no cast shadow under '{uid}' to measure the ground line on")
    return cell.height - 1 - ground


def build() -> dict:
    """The manifest, assembled from the live tables."""
    return {
        "version": VERSION,
        "cell": {
            "w": atlas.CELL_W,
            "h": atlas.CELL_H,
            "ground_px": measure_ground_px(),
            # What a cell taller than it is wide has over its footprint: the
            # sprite is scaled by its width, so this rides up over the row
            # above rather than shrinking the unit inside its tile.
            "overflow": atlas.CELL_H - atlas.CELL_W,
        },
        "clips": {
            "ambient": {
                "sheets": list(AMBIENT_SHEETS),
                "order": list(range(len(AMBIENT_SHEETS))),
                "ms_per_frame": AMBIENT_MS,
                "mode": "loop",
            },
            "sea": {
                "sheets": list(SEA_SHEETS),
                "order": list(range(len(SEA_SHEETS))),
                "ms_per_frame": SEA_MS,
                "mode": "loop",
            },
        },
        "columns": {uid: col for col, uid in enumerate(ATLAS_ORDER)},
        "rows": [{"key": fac.key, "team": fac.team} for fac in FACTIONS],
        "terrain_phases": {name: len(table) for name, table in _PHASE_TABLES.items()},
    }


MANIFEST: dict = build()


def dumps() -> str:
    """The manifest as the exact text `dump` writes."""
    return json.dumps(MANIFEST, sort_keys=True, indent=2) + "\n"


def dump(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(dumps(), encoding="utf-8")
