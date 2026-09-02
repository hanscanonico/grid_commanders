"""Deterministic sprite pipeline for grid_commanders.

Generates the game's two atlases — 18 units x 5 faction rows and 14 terrain
tiles x 5 rows — as curated isometric-voxel pixel art. There are no seeds and
no randomness: every sprite is an authored model, and every run reproduces
the same bytes.

`SHEETS` plus the two cell iterators are the one statement of what a run
produces. Each `Output` carries the directory of a game checkout it installs
into, so `install` derives its copy list from the same table `generate` writes
from rather than from a second list that has to be kept in step.

Outputs (under --out, default ./out):
  anim.json              the sheet contract — cell geometry, ambient clip,
                         column/row order, terrain phase counts
  units_atlas.png        1152x576 RGBA — drop-in for assets/tiles/units_atlas.png
  units_atlas_b.png      ambient animation frame B (every unit's second key pose)
  units_atlas_figures.png / units_atlas_figures_b.png
                          the same two frames with the tile's cast shadow left
                          off, for the cut-ins, which draw at 1:1 on their own
                          ground and idle on the ambient_figures clip
  units_atlas_figures_ko.png
                          one AUTHORED casualty frame per unit, shadowless
                          like the figure pair — the board never draws it, so
                          there is no board-sheet sibling — for the cut-ins'
                          death beat (the ko clip)
  units_atlas_figures_fire.png / units_atlas_figures_fire_b.png
                          one AUTHORED muzzle-lit frame per ARMED unit,
                          shadowless like the figure pair and a second key
                          for the three sustained weapon families — for the
                          cut-ins' fire beat (the fire clip)
  units_atlas_move.png / units_atlas_move_b.png
                          the same grid again, under way — one facing (the
                          art's own, screen-left); the consumer mirrors it
  terrain_atlas.png       896x384 RGBA — drop-in for assets/tiles/terrain_atlas.png
                          (the five property columns are transparent overlays)
  overlay.png / ui/cursor.png / icon/icon.png
                          the UI chrome — the range tile the scene modulates,
                          the board cursor, and the project icon
  units/<id>_<team>.png   one units-atlas cell each — the atlas's own art
                          exported cell by cell, for review; the game loads the
                          sheets, so these stay here and are installed nowhere
  iso_buildings/<id>_<team>.png  64x64 RGBA property buildings, for review too
  preview_units.png / preview_terrain.png / preview_map.png  review sheets
"""

from __future__ import annotations

import argparse
import shutil
import sys
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from functools import cache, partial
from pathlib import Path

from PIL import Image

from . import anim, atlas, autotile, chrome, terrain
from .palette import FACTIONS, Faction, faction_by_key
from .units import ATLAS_ORDER, Pose

# Where each kind of output lands in a grid_commanders checkout.
TILES_DIR = "assets/tiles"
AUTOTILES, AUTOTILES_DIR = "autotiles", "assets/tiles/autotiles"
# The two cell directories install nowhere: they are review exports of art the
# sheets already carry, so shipping them would ship the same pixels twice.
UNIT_CELLS = "units"
BUILDING_CELLS = "iso_buildings"
# The two chrome files that do not land beside the board sprites. Each output
# directory installs into exactly one place, so the icon — alone at the assets
# root in the game — gets a directory of its own here.
CURSOR_DIR, CURSOR_INSTALL_DIR = "ui", "assets/ui"
ICON_DIR, ICON_INSTALL_DIR = "icon", "assets"


@dataclass(frozen=True)
class Output:
    """One file a run produces: its path under --out, how it is built, and the
    directory `--install` copies it into — `None` for a review image, which is
    for a human to look at and no part of the game."""

    rel: str
    build: Callable[[], Image.Image]
    install_to: str | None = None


@cache
def _units_sheet(pose: Pose, shadow: bool) -> Image.Image:
    """The units atlas for one clip frame, kept because the previews are the
    same sheet zoomed rather than a second rendering of it."""
    return atlas.build_units_atlas(pose, shadow)


@cache
def _terrain_sheet() -> Image.Image:
    return atlas.build_terrain_atlas()


def _units(name: str, pose: Pose = Pose.A, shadow: bool = True) -> Output:
    return Output(name, partial(_units_sheet, pose, shadow), TILES_DIR)


def _autotiles(name: str, build: Callable[[], Image.Image]) -> Output:
    return Output(f"{AUTOTILES}/{name}.png", build, AUTOTILES_DIR)


_AMBIENT_A, _AMBIENT_B = anim.AMBIENT_SHEETS
_FIGURES_A, _FIGURES_B = anim.FIGURE_SHEETS
_FIRE_A, _FIRE_B = anim.FIRE_SHEETS
_MOVE_A, _MOVE_B = anim.MOVE_SHEETS

# Every sheet a full run writes, in the order it writes them. The sheet names
# come from `anim`, so the manifest's clips and the files on disk cannot
# disagree about what is called what.
SHEETS: tuple[Output, ...] = (
    _units(_AMBIENT_A),
    _units(_AMBIENT_B, Pose.B),
    _units(_FIGURES_A, shadow=False),
    _units(_FIGURES_B, Pose.B, shadow=False),
    _units(anim.KO_SHEET, Pose.KO, shadow=False),
    _units(_FIRE_A, Pose.FIRE_A, shadow=False),
    _units(_FIRE_B, Pose.FIRE_B, shadow=False),
    _units(_MOVE_A, Pose.MOVE_A),
    _units(_MOVE_B, Pose.MOVE_B),
    Output("terrain_atlas.png", _terrain_sheet, TILES_DIR),
    _autotiles("roads", partial(autotile.variant_sheet, autotile.road_tile)),
    _autotiles("rivers", partial(autotile.variant_sheet, autotile.river_tile)),
    _autotiles("coast", partial(autotile.variant_sheet, autotile.coast_tile)),
    _autotiles("shoals", partial(autotile.variant_sheet, autotile.shoal_tile)),
    _autotiles("woods", partial(autotile.variant_sheet, autotile.woods_tile)),
    _autotiles("bridges", autotile.bridge_sheet),
    # Both sea time frames, named by the clip that plays them so the manifest
    # and the files on disk cannot drift apart.
    *(
        Output(name, partial(autotile.sea_sheet, frame), AUTOTILES_DIR)
        for frame, name in enumerate(anim.SEA_SHEETS)
    ),
    _autotiles("plains", autotile.plains_sheet),
    _autotiles("mountain", autotile.mountain_sheet),
    Output("overlay.png", chrome.overlay, TILES_DIR),
    Output(f"{CURSOR_DIR}/cursor.png", chrome.cursor, CURSOR_INSTALL_DIR),
    Output(f"{ICON_DIR}/icon.png", chrome.icon, ICON_INSTALL_DIR),
    Output("preview_units.png", lambda: atlas.preview(_units_sheet(Pose.A, True), 2)),
    Output(
        "preview_terrain.png",
        lambda: atlas.preview(_terrain_sheet().convert("RGBA"), 2),
    ),
    Output("preview_map.png", atlas.build_demo),
)


def _sheet_cell(uid: str, fac: Faction) -> Image.Image:
    """One cell cut back out of the sheet the run already built."""
    return _units_sheet(Pose.A, True).crop(atlas.cell_box(uid, fac))


def unit_cells() -> Iterator[Output]:
    """One units-atlas cell per unit and faction.

    Review exports of art the atlas already carries, so they are written here
    and installed nowhere. `tests/check_snapshots.py` holds each to a cell of
    the run's own `units_atlas.png` — which cropping rather than re-rendering
    makes true by construction, and saves 90 renders a run.
    """
    for uid in ATLAS_ORDER:
        for fac in FACTIONS:
            yield Output(
                f"{UNIT_CELLS}/{uid}_{fac.team}.png", partial(_sheet_cell, uid, fac)
            )


def building_cells() -> Iterator[Output]:
    """One property building per property and faction, alone on its cell."""
    for bid in sorted(terrain.PROPERTY):
        for fac in FACTIONS:
            yield Output(
                f"{BUILDING_CELLS}/{bid}_{fac.team}.png",
                partial(atlas.building_cell, bid, fac),
            )


def generate(
    out: Path, *, cells: bool = True, log: Callable[[str], None] = print
) -> None:
    """Write every output under `out`, the manifest last."""
    log("building the sheets (18 units x 5 factions, 14 terrains, autotiles)")
    for output in SHEETS:
        _write(output, out, log)
    if cells:
        log("exporting unit and property-building cells")
        for output in (*unit_cells(), *building_cells()):
            _write(output, out, log)
    log("writing the sheet manifest")
    manifest = out / anim.MANIFEST_NAME
    anim.dump(manifest)
    log(f"  wrote {manifest}")


def _install_directories() -> dict[str, str]:
    """Which generated subdirectory installs where, read off the outputs that
    live in one — the autotile sheets, today."""
    dirs: dict[str, str] = {}
    for output in SHEETS:
        parent = Path(output.rel).parent
        if output.install_to is not None and parent != Path("."):
            dirs[parent.as_posix()] = output.install_to
    return dirs


def install(src: Path, dest: Path) -> int:
    """Copy a generated tree into a grid_commanders checkout; returns how many
    files landed.

    The manifest travels with the sheets it describes: a checkout with new
    atlases and last run's anim.json would be the coupling `anim` exists to
    end. A sheet at the root is named and has to be there; a directory is
    copied as it stands. The per-cell exports are not copied at all — the game
    loads the sheets, and the cells are the same pixels a second time.
    """
    pairs = [
        (src / o.rel, dest / o.install_to / o.rel)
        for o in SHEETS
        if o.install_to is not None and Path(o.rel).parent == Path(".")
    ]
    pairs.append((src / anim.MANIFEST_NAME, dest / TILES_DIR / anim.MANIFEST_NAME))
    for sub, into in _install_directories().items():
        for f in sorted((src / sub).glob("*.png")):
            pairs.append((f, dest / into / f.name))
    for s, d in pairs:
        if not s.exists():
            sys.exit(f"missing {s} — run a full generation first")
        d.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(s, d)
    print(f"installed {len(pairs)} files into {dest}")
    return len(pairs)


def _write(output: Output, out: Path, log: Callable[[str], None]) -> None:
    _save(output.build(), out / output.rel, log)


def _save(img: Image.Image, path: Path, log: Callable[[str], None]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    log(f"  wrote {path}")


def _preview_only(ids: list[str], team: str, zoom: int, out: Path) -> None:
    """Fast iteration: render a hand-picked subset at high zoom."""
    fac = faction_by_key(team)
    cells = []
    for sid in ids:
        if sid in ATLAS_ORDER:
            cells.append(atlas.unit_cell(sid, fac))
        elif sid in terrain.TERRAIN_ORDER:
            cells.append(terrain.tile(sid, fac))
        else:
            sys.exit(
                f"unknown id '{sid}' (units: {', '.join(ATLAS_ORDER)}; "
                f"terrain: {', '.join(terrain.TERRAIN_ORDER)})"
            )
    pitch = max(c.width for c in cells) + 2
    tall = max(c.height for c in cells)
    sheet = Image.new("RGBA", (len(cells) * pitch + 2, tall + 4), (52, 52, 60, 255))
    for i, c in enumerate(cells):
        # Bottom-aligned: a unit cell and a terrain tile share a ground line.
        sheet.alpha_composite(c.convert("RGBA"), (i * pitch + 2, tall + 2 - c.height))
    sheet = sheet.resize((sheet.width * zoom, sheet.height * zoom), 0)
    _save(sheet, out / "preview_only.png", print)


def _parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument(
        "-o", "--out", type=Path, default=Path("out"), help="output directory"
    )
    ap.add_argument(
        "--only",
        metavar="IDS",
        help="comma list of unit/terrain ids: render only a zoomed "
        "preview_only.png of those (fast iteration)",
    )
    ap.add_argument(
        "--team",
        default="red",
        help="faction row for --only previews (neutral/red/blue/iron/verdant/gold)",
    )
    ap.add_argument(
        "--zoom", type=int, default=6, help="zoom factor for --only previews"
    )
    ap.add_argument(
        "--no-cells", action="store_true", help="skip the per-cell PNG exports"
    )
    ap.add_argument(
        "--install",
        type=Path,
        metavar="GAME_DIR",
        help="copy the atlases and the UI chrome into a grid_commanders checkout "
        "(explicit path required — no default destination, deliberately)",
    )
    return ap


def main() -> int:
    args = _parser().parse_args()
    if args.only:
        _preview_only(args.only.split(","), args.team, args.zoom, args.out)
        return 0
    generate(args.out, cells=not args.no_cells)
    if args.install is not None:
        install(args.out, args.install)
    return 0
