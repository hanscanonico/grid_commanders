"""What the shipped atlases cost, in bytes and in repeated cells.

A readout, not a gate: it reads the art installed under assets/tiles and
prints, per sheet, the PNG on disk, the RGBA it decodes to, how many cells it
holds, and how many of those cells are byte-for-byte copies of another cell in
the same sheet. The terrain atlas gets an extra column-by-column line, because
its faction rows are one tile repeated for every terrain that is not a
property.

The runtime block sums the sheets the battle scene actually loads, found by
scanning scenes/ for the paths rather than repeating a list that would rot.

Run: make sheet-census
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[3]
TILES = REPO / "assets" / "tiles"
SCENES = REPO / "scenes"

# The grid conventions the installed sheets use. The autotile sheets carry a
# bleed margin between cells (scenes/battle/terrain_autotiles.gd SHEET_MARGIN /
# SHEET_SEPARATION); the atlases are packed edge to edge, on a board tile
# (scenes/battle/battle_view.gd TERRAIN_PX) except for the unit sheets, whose
# taller cell is stated by the shipped contract below.
AUTOTILE_MARGIN = 2
AUTOTILE_SEPARATION = 2
TILE_CELL = 64
MANIFEST = TILES / "anim.json"

SHEET_PATH_RE = re.compile(r"res://(assets/tiles/[\w/]+\.png)")


def manifest() -> dict:
    """The contract shipped beside the art: the unit cell and which sheets are
    cut on it. Asking it is why a sheet gaining a faction row is not a guess
    between a 64x96 grid and a 64x64 one."""
    return json.loads(MANIFEST.read_text())


def unit_sheets(spec: dict) -> frozenset[str]:
    named = {
        sheet
        for clip in spec["clips"].values()
        for sheet in clip["sheets"]
        if "/" not in sheet
    }
    return frozenset(named)


@dataclass(frozen=True)
class Grid:
    """Where a sheet's cells sit: cell size, pitch, and the first cell's corner."""

    cell: tuple[int, int]
    pitch: tuple[int, int]
    origin: tuple[int, int]
    cols: int
    rows: int

    @property
    def count(self) -> int:
        return self.cols * self.rows

    def box(self, col: int, row: int) -> tuple[int, int, int, int]:
        x = self.origin[0] + col * self.pitch[0]
        y = self.origin[1] + row * self.pitch[1]
        return (x, y, x + self.cell[0], y + self.cell[1])


def grid_for(path: Path, size: tuple[int, int], spec: dict) -> Grid:
    w, h = size
    if path.parent.name == "autotiles":
        pitch = TILE_CELL + AUTOTILE_SEPARATION
        return Grid(
            cell=(TILE_CELL, TILE_CELL),
            pitch=(pitch, pitch),
            origin=(AUTOTILE_MARGIN, AUTOTILE_MARGIN),
            cols=(w - AUTOTILE_MARGIN) // pitch,
            rows=(h - AUTOTILE_MARGIN) // pitch,
        )
    if path.name in unit_sheets(spec):
        cw, ch = spec["cell"]["w"], spec["cell"]["h"]
    else:
        cw = ch = TILE_CELL
    if w % cw == 0 and h % ch == 0 and (w > cw or h > ch):
        return Grid((cw, ch), (cw, ch), (0, 0), w // cw, h // ch)
    return Grid((w, h), (w, h), (0, 0), 1, 1)


@dataclass(frozen=True)
class Census:
    path: Path
    size: tuple[int, int]
    png_bytes: int
    grid: Grid
    duplicate_cells: int
    loaders: tuple[str, ...]

    @property
    def rgba_bytes(self) -> int:
        return self.size[0] * self.size[1] * 4

    @property
    def duplicate_share(self) -> float:
        return self.duplicate_cells / max(1, self.grid.count)

    @property
    def duplicate_bytes(self) -> int:
        cell_px = self.grid.cell[0] * self.grid.cell[1]
        return self.duplicate_cells * cell_px * 4


def cell_bytes(img: Image.Image, grid: Grid) -> list[bytes]:
    rgba = img.convert("RGBA")
    return [
        rgba.crop(grid.box(col, row)).tobytes()
        for row in range(grid.rows)
        for col in range(grid.cols)
    ]


def loaders_by_sheet() -> dict[str, tuple[str, ...]]:
    """Which scene scripts name each sheet, so the runtime total is read off
    the game rather than off a list kept by hand."""
    found: dict[str, list[str]] = {}
    for script in sorted(SCENES.rglob("*.gd")):
        rel = script.relative_to(REPO).as_posix()
        for sheet in SHEET_PATH_RE.findall(script.read_text()):
            names = found.setdefault(sheet, [])
            if rel not in names:
                names.append(rel)
    return {sheet: tuple(names) for sheet, names in found.items()}


def sheets() -> list[Path]:
    return sorted(TILES.glob("*.png")) + sorted((TILES / "autotiles").glob("*.png"))


def census(path: Path, loaders: dict[str, tuple[str, ...]], spec: dict) -> Census:
    img = Image.open(path)
    grid = grid_for(path, img.size, spec)
    cells = cell_bytes(img, grid)
    rel = path.relative_to(REPO).as_posix()
    return Census(
        path=path,
        size=img.size,
        png_bytes=path.stat().st_size,
        grid=grid,
        duplicate_cells=len(cells) - len(set(cells)),
        loaders=loaders.get(rel, ()),
    )


def terrain_column_report(path: Path, spec: dict) -> list[str]:
    """Per column of the terrain atlas, how many of the faction rows are
    byte-identical to row 0."""
    img = Image.open(path)
    grid = grid_for(path, img.size, spec)
    rgba = img.convert("RGBA")
    lines = []
    for col in range(grid.cols):
        first = rgba.crop(grid.box(col, 0)).tobytes()
        same = sum(
            1
            for row in range(1, grid.rows)
            if rgba.crop(grid.box(col, row)).tobytes() == first
        )
        lines.append(f"  col {col:2d}: {same}/{grid.rows - 1} rows identical to row 0")
    return lines


def kib(n: int) -> str:
    return f"{n / 1024:8.1f} KiB"


def report() -> list[str]:
    loaders = loaders_by_sheet()
    spec = manifest()
    rows = [census(p, loaders, spec) for p in sheets()]
    out = [
        f"{'sheet':38s} {'PNG':>12s} {'RGBA':>12s} "
        f"{'cells':>6s} {'dup':>6s} {'dup%':>6s} {'loaded':>7s}",
    ]
    for c in rows:
        out.append(
            f"{c.path.relative_to(TILES).as_posix():38s} "
            f"{kib(c.png_bytes)} {kib(c.rgba_bytes)} "
            f"{c.grid.count:6d} {c.duplicate_cells:6d} "
            f"{100 * c.duplicate_share:5.0f}% "
            f"{'yes' if c.loaders else 'no':>7s}"
        )
    live = [c for c in rows if c.loaders]
    out += [
        "",
        f"all sheets:     {kib(sum(c.png_bytes for c in rows))} PNG, "
        f"{kib(sum(c.rgba_bytes for c in rows))} RGBA",
        f"loaded at once: {kib(sum(c.png_bytes for c in live))} PNG, "
        f"{kib(sum(c.rgba_bytes for c in live))} RGBA "
        f"over {len(live)} sheets",
        f"duplicate cells in the loaded set: "
        f"{sum(c.duplicate_cells for c in live)} cells, "
        f"{kib(sum(c.duplicate_bytes for c in live))} RGBA",
        "",
        f"terrain_atlas.png, {len(spec['rows'])} faction rows per column:",
    ]
    out += terrain_column_report(TILES / "terrain_atlas.png", spec)
    out += ["", "loaded by:"]
    for c in live:
        out.append(
            f"  {c.path.relative_to(TILES).as_posix():38s} {', '.join(c.loaders)}"
        )
    return out


def main() -> int:
    if not TILES.is_dir():
        print(f"no installed art at {TILES}", file=sys.stderr)
        return 1
    print("\n".join(report()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
