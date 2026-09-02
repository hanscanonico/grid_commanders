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
just a third place to keep it in step. The cadences (`AMBIENT_MS`, `SEA_MS`,
`MOVE_MS`) are the values with no Python table behind them, because a beat was
only ever a game constant; the manifest is now their source, and the comment
over each carries the reasoning.

The schema grows by ADDING, never by rewriting: `move` is the one clip carrying
`facing` and `flip_x_for`, `fallback` is the shared key of the clips a unit may
be left out of (`move` and `ko`), and `VERSION` stays 1 because the absence of
those keys is the reading a version-1 consumer already makes — never mirror, no
fallback. `mode` grew a VALUE rather than appearing: every clip has always
carried it, `loop` on all of them until `ko` shipped a single held frame.
`docs/move_clip.md` is the contract the game implements against; the README's
outputs table names the sheets.

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
# The same two frames with the tile's cast shadow left off, for the cut-ins,
# which draw at 1:1 on a ground plane of their own. Same art, same order, so
# the clip below is the ambient clip pointed at the other pair — a cut-in that
# idles shows exactly the beat the board shows.
FIGURE_SHEETS: tuple[str, ...] = (
    "units_atlas_figures.png",
    "units_atlas_figures_b.png",
)
# The casualty clip's one sheet: an authored KO frame per unit, composed the
# same shadowless way the figure pair is (the board never draws it, so there
# is no board-sheet sibling) — but it is AUTHORED art, not the figure pair's
# subtraction. `test_ko_pose.py`'s header says so for the pin that would
# otherwise assume every figure sheet is derived the same way.
KO_SHEET = "units_atlas_figures_ko.png"
# The fire clip's pair: an authored muzzle-lit frame per armed unit, composed
# the same shadowless way — no board-sheet sibling, since the board never
# draws a figure sheet either — and AUTHORED like the KO sheet, not the
# ambient pair's subtraction. Two sheets rather than KO's one because the three
# sustained weapon families need a second key for the stream to read as a
# blaze; every other armed unit draws the same model into both, which is the
# schema's existing single-frame-in-a-pair idiom (`units.pose.FIRE_PAIRS`)
# rather than a second clip shape.
FIRE_SHEETS: tuple[str, ...] = (
    "units_atlas_figures_fire.png",
    "units_atlas_figures_fire_b.png",
)
# Milliseconds per ambient frame. One cadence for the whole clip because the
# sheets encode one: frame B is the entire army a beat later, so a rotor and a
# swell cannot run at different rates without a third sheet. Half a second is
# the slowest rate a swept rotor still reads as turning, and the rotor is the
# faster of the two motions, so it sets the beat.
AMBIENT_MS = 500

# The move clip: the same 18x5 grid, the same cell rects, one frame per key of
# a unit under way. One facing only — the art faces +y, which the projection
# puts at screen lower-LEFT (`voxel` header: "+y toward screen lower-left,
# units face +y"), so these sheets are the LEFT-facing clip and the consumer
# mirrors them about the cell centre for a rightward move. Nothing in a move
# frame may encode screen-handedness; a mirrored rifleman leading with the
# other leg is correct.
MOVE_SHEETS: tuple[str, ...] = ("units_atlas_move.png", "units_atlas_move_b.png")
# Milliseconds per move frame. The board tweens one cell per 0.06 s x
# anim_scale — 0.18 s/cell at the normal tier, 0.12 s at quick — so 160 ms is
# about one stride per cell crossed, which is the whole reason a walk cycle
# reads instead of skating. It is also deliberately coprime-ish with the other
# two cadences: it neither divides nor multiplies 500 (ambient) or 900 (sea),
# so a moving unit, an idling one and the water never turn over on one tick.
MOVE_MS = 160

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
# differently — adding a clip or a family is not that, and neither is a clip
# carrying a key the older clips do not: `facing`/`flip_x_for`/`fallback`
# appear only on the clips that need them, and their ABSENCE is the reading a
# version-1 consumer already makes (never mirror, no fallback).
VERSION = 1


def _clip(
    sheets: tuple[str, ...],
    ms: int,
    mode: str = "loop",
    **extra: object,
) -> dict:
    """One clip entry: its sheets, their frame order, cadence and mode.

    `order` is derived from the sheet tuple rather than typed, so a clip and
    the files on disk cannot disagree about how many frames there are.
    """
    return {
        "sheets": list(sheets),
        "order": list(range(len(sheets))),
        "ms_per_frame": ms,
        "mode": mode,
        **extra,
    }


def _clips() -> dict[str, dict]:
    """The clip table, in the order a reader meets it. A new clip is one line
    here and nothing else."""
    return {
        "ambient": _clip(AMBIENT_SHEETS, AMBIENT_MS),
        "ambient_figures": _clip(FIGURE_SHEETS, AMBIENT_MS),
        # One frame, held rather than looped — the dead don't loop — and a
        # unit outside `units.KOS` draws its rest key here (see `_FALLBACK`),
        # so the sheet is a valid grid before every family has a wreck. `ms`
        # is 0: a hold never advances, so the cadence the other clips are
        # timed against says nothing about this one.
        "ko": _clip((KO_SHEET,), 0, mode="hold", fallback="ambient"),
        # Two sheets, looped at the ambient beat — the cadence-disjointness
        # lock (no new period may divide or multiply 500/160/900) is what
        # every OTHER new clip has to clear; reusing 500 outright is the
        # exemption the ninth animation slice already established for a
        # director-clock pair (`BoardBeat.frame_at` on `CutscenePlayback`'s
        # own `t`, never the wall clock — the cut-in idles on it exactly the
        # way `ambient_figures` does). `fallback` is "ambient" rather than
        # "ambient_figures" for the same reason `ko`'s is: both name the rest
        # POSE a unit outside the clip's own set draws, not a sheet family.
        "fire": _clip(FIRE_SHEETS, AMBIENT_MS, fallback="ambient"),
        "sea": _clip(SEA_SHEETS, SEA_MS),
        "move": _clip(
            MOVE_SHEETS,
            MOVE_MS,
            # The art's one facing, and the one the consumer flips for.
            facing="left",
            flip_x_for=["right"],
            # A unit with no authored move pose draws its ambient counterpart,
            # so a consumer that finds the move clip indistinguishable from
            # ambient for some column is seeing the intended art, not a
            # missing sheet.
            fallback="ambient",
        ),
    }


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
        "clips": _clips(),
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
