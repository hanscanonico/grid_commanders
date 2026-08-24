#!/usr/bin/env python3
"""Deterministic sprite pipeline for grid_commanders.

Generates the game's two atlases — 18 units x 5 faction rows and 14 terrain
tiles x 5 rows — as curated isometric-voxel pixel art. There are no seeds and
no randomness: every sprite is an authored model, and every run reproduces
the same bytes.

Outputs (under --out, default ./out):
  anim.json              the sheet contract — cell geometry, ambient clip,
                         column/row order, terrain phase counts
  units_atlas.png        1152x480 RGBA — drop-in for assets/tiles/units_atlas.png
  units_atlas_b.png      ambient animation frame B (every unit's second key pose)
  units_atlas_figures.png / units_atlas_figures_b.png
                          the same two frames with the tile's cast shadow left
                          off, for the cut-ins, which draw at 1:1 on their own
                          ground and idle on the ambient_figures clip
  units_atlas_move.png / units_atlas_move_b.png
                          the same grid again, under way — one facing (the
                          art's own, screen-left); the consumer mirrors it
  terrain_atlas.png       896x320 RGBA — drop-in for assets/tiles/terrain_atlas.png
                          (the five property columns are transparent overlays)
  units/<id>_<team>.png   one units-atlas cell each, for paste_unit_sprites.gd
  iso_buildings/<id>_<team>.png  64x64 RGBA property buildings
  preview_units.png / preview_terrain.png / preview_map.png  review sheets
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from spritegen import anim, atlas, terrain
from spritegen.palette import FACTIONS, faction_by_key
from spritegen.units import ATLAS_ORDER, Pose


def _write(img, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print(f"  wrote {path}")


def _preview_only(ids: list[str], team: str, zoom: int, out: Path) -> None:
    """Fast iteration: render a hand-picked subset at high zoom."""
    from PIL import Image

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
    _write(sheet, out / "preview_only.png")


def _install(src: Path, dest: Path) -> None:
    import shutil

    # The manifest travels with the sheets it describes: a checkout with new
    # atlases and last run's anim.json would be the coupling this file exists
    # to end.
    sheets = [
        *anim.AMBIENT_SHEETS,
        *anim.FIGURE_SHEETS,
        *anim.MOVE_SHEETS,
        "terrain_atlas.png",
        anim.MANIFEST_NAME,
    ]
    atlases = [(src / name, dest / "assets/tiles" / name) for name in sheets]
    pairs = list(atlases)
    for cell in sorted((src / "units").glob("*.png")):
        pairs.append((cell, dest / "assets/sprites/units" / cell.name))
    for cell in sorted((src / "iso_buildings").glob("*.png")):
        pairs.append((cell, dest / "assets/sprites/iso_buildings" / cell.name))
    for sheet in sorted((src / "autotiles").glob("*.png")):
        pairs.append((sheet, dest / "assets/tiles/autotiles" / sheet.name))
    for s, d in pairs:
        if not s.exists():
            sys.exit(f"missing {s} — run a full generation first")
        d.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(s, d)
    print(f"installed atlases + {len(pairs) - len(atlases)} cells into {dest}")


def main() -> None:
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
        help="faction row for --only previews (neutral/red/blue/iron/verdant)",
    )
    ap.add_argument(
        "--zoom", type=int, default=6, help="zoom factor for --only previews"
    )
    ap.add_argument(
        "--no-cells", action="store_true", help="skip the per-cell PNG exports"
    )
    ap.add_argument(
        "--install",
        nargs="?",
        const=Path("../grid_commanders"),
        type=Path,
        metavar="GAME_DIR",
        help="copy atlases and cells into a grid_commanders "
        "checkout (default ../grid_commanders)",
    )
    args = ap.parse_args()

    if args.only:
        _preview_only(args.only.split(","), args.team, args.zoom, args.out)
        return

    frame_a, frame_b = anim.AMBIENT_SHEETS

    print("building units atlas (18 units x 5 factions)")
    units_atlas = atlas.build_units_atlas()
    _write(units_atlas, args.out / frame_a)

    print("building ambient frame B (every unit's second key pose)")
    _write(atlas.build_units_atlas(Pose.B), args.out / frame_b)

    figures_a, figures_b = anim.FIGURE_SHEETS

    print("building the figure sheets (no tile shadow, for the cut-ins)")
    _write(atlas.build_units_atlas(shadow=False), args.out / figures_a)
    _write(atlas.build_units_atlas(Pose.B, shadow=False), args.out / figures_b)

    move_a, move_b = anim.MOVE_SHEETS

    print(
        "building the move clip (one facing — the art's own, screen-left; "
        "the consumer mirrors it)"
    )
    _write(atlas.build_units_atlas(Pose.MOVE_A), args.out / move_a)
    _write(atlas.build_units_atlas(Pose.MOVE_B), args.out / move_b)

    print("building terrain atlas (14 terrains x 5 rows)")
    terrain_atlas = atlas.build_terrain_atlas()
    _write(terrain_atlas, args.out / "terrain_atlas.png")

    if not args.no_cells:
        print("exporting unit cells")
        for uid in ATLAS_ORDER:
            for fac in FACTIONS:
                _write(
                    atlas.unit_cell(uid, fac),
                    args.out / "units" / f"{uid}_{fac.team}.png",
                )
        print("exporting property-building cells")
        for bid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                _write(
                    atlas.building_cell(bid, fac),
                    args.out / "iso_buildings" / f"{bid}_{fac.team}.png",
                )

    print(
        "building autotile sheets (roads, rivers, coast, shoals, woods, bridges, sea)"
    )
    from spritegen import autotile

    _write(
        autotile.variant_sheet(autotile.road_tile), args.out / "autotiles" / "roads.png"
    )
    _write(
        autotile.variant_sheet(autotile.river_tile),
        args.out / "autotiles" / "rivers.png",
    )
    _write(
        autotile.variant_sheet(autotile.coast_tile),
        args.out / "autotiles" / "coast.png",
    )
    _write(
        autotile.variant_sheet(autotile.shoal_tile),
        args.out / "autotiles" / "shoals.png",
    )
    _write(
        autotile.variant_sheet(autotile.woods_tile),
        args.out / "autotiles" / "woods.png",
    )
    _write(autotile.bridge_sheet(), args.out / "autotiles" / "bridges.png")
    # Both sea time frames, named by the clip that plays them so the manifest
    # and the files on disk cannot drift apart.
    for frame, name in enumerate(anim.SEA_SHEETS):
        _write(autotile.sea_sheet(frame), args.out / name)
    _write(autotile.plains_sheet(), args.out / "autotiles" / "plains.png")
    _write(autotile.mountain_sheet(), args.out / "autotiles" / "mountain.png")

    print("writing the sheet manifest")
    manifest = args.out / anim.MANIFEST_NAME
    anim.dump(manifest)
    print(f"  wrote {manifest}")

    print("rendering previews")
    _write(atlas.preview(units_atlas, 2), args.out / "preview_units.png")
    _write(
        atlas.preview(terrain_atlas.convert("RGBA"), 2),
        args.out / "preview_terrain.png",
    )
    _write(atlas.build_demo(), args.out / "preview_map.png")

    if args.install is not None:
        _install(args.out, args.install)


if __name__ == "__main__":
    main()
