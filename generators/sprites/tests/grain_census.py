"""Dev instrument: how much of a terrain tile's grain each zoom rung draws.

Not a test, a readout. `tests/test_shadows.py::CastShadow` asks the question of
the units' cast shadow — the board keeps one source pixel in 4/z, so a picture
with 1px structure is a different picture at every rung — and answers it for
that one shape. Nobody had asked it of the ground the shadow falls on.

The subject is what the board paints, taken from the board's own authority.
`scenes/battle/terrain_autotiles.gd` routes road, river, bridge and shoal to
their autotile sheets, sea to the coast sheet or the sea sheet, and woods to the
woods sheet unless the cell is walled in by wood; only `reef` and an interior
wood keep a `terrain_atlas.png` column. So this reads every cell of every
autotile sheet and the two columns that survive as fallbacks — not the atlas
column of a terrain whose cells all draw from a sheet.

Per cell, per phase, this prints:

* the colour census and the lone-pixel count (a pixel no 4-neighbour shares a
  colour with) — how fine the tile's texture is authored;
* the grain density (the share of the tile that is not its base tone);
* that density again at every sampling phase of rungs 1, 2 and 4 (4:1, 2:1 and
  1:1), as a SHARE of the tile's own density, so 1.00 is "this rung draws the
  texture at the density it was authored at";
* the swing between the loosest and the densest phase.

Run: .venv/bin/python tests/grain_census.py [--source=both|fresh|installed]
                                            [--detail]
     make grain-census

`fresh` renders the sheets here, through `pipeline.SHEETS` — the same builders
`make tiles` writes with; `installed` reads the sheets the game loads under
`assets/tiles`. `both` runs the two and prints whether they agree — an installed
sheet that no longer matches the generator is a `make tiles` nobody ran, and
this readout would be describing art the game does not draw.
The committed reading is `docs/terrain_grain.md`.
"""

from __future__ import annotations

import argparse
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

# The package is not installed, and a file run by path puts its own directory
# on sys.path rather than the repo root, so put the root there ourselves.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from PIL import Image  # noqa: E402

from spritegen import autotile, pipeline, terrain  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]
ASSETS = REPO_ROOT / "assets" / "tiles"

# Source pixels per screen pixel at the rungs a match is played at, the same
# three `CastShadow` reads: 4:1 at rung 1, 2:1 at rung 2, 1:1 at rung 4.
RUNGS: tuple[tuple[int, int], ...] = ((1, 4), (2, 2), (4, 1))

# How far a phase's share of the grain may sit from the tile's own density
# before the tile is called a shimmer. `CastShadow`'s bar, so the two readings
# are on one scale.
TOLERANCE = 0.15


@dataclass(frozen=True)
class Sheet:
    """One generated contact sheet and how it is cut, mirroring
    `TerrainAutotiles.SHEET_PATHS` and the layout `autotile.sheet` lays down."""

    name: str
    rel: str
    cells: int
    cols: int
    key: str


# Every family the game draws a cell of, in `TerrainAutotiles.Family` order.
# `sea_b` is the sea's second time frame, which the board animates to.
SHEETS: tuple[Sheet, ...] = (
    Sheet("roads", "autotiles/roads.png", 16, 4, "mask"),
    Sheet("rivers", "autotiles/rivers.png", 16, 4, "mask"),
    Sheet("coast", "autotiles/coast.png", 16, 4, "mask"),
    Sheet("shoals", "autotiles/shoals.png", 16, 4, "mask"),
    Sheet("woods", "autotiles/woods.png", 16, 4, "mask"),
    Sheet("bridges", "autotiles/bridges.png", 2, 2, "deck"),
    Sheet("sea", "autotiles/sea.png", 3, 3, "phase"),
    Sheet("sea_b", "autotiles/sea_b.png", 3, 3, "phase"),
    Sheet("plains", "autotiles/plains.png", 8, 8, "phase"),
    Sheet("mountain", "autotiles/mountain.png", 3, 3, "phase"),
)

# The `terrain_atlas.png` columns a board still paints as ground: reef has no
# family at all, and a wood walled in by wood keeps its column rather than
# drawing a tree line. Every other ground terrain draws from a sheet.
ATLAS_GROUND: tuple[str, ...] = ("reef", "woods")

ATLAS_REL = "terrain_atlas.png"

_BUILD = {out.rel: out.build for out in pipeline.SHEETS}


def sheet_image(rel: str, source: str, assets: Path) -> Image.Image:
    if source == "fresh":
        return _BUILD[rel]().convert("RGB")
    return Image.open(assets / rel).convert("RGB")


def sheet_tiles(spec: Sheet, source: str, assets: Path) -> list[Image.Image]:
    """Cut a contact sheet on `autotile.sheet`'s layout: a 2px outer margin,
    2px between cells, row-major."""
    img = sheet_image(spec.rel, source, assets)
    pitch = autotile.CELL + 2
    out = []
    for index in range(spec.cells):
        x = 2 + (index % spec.cols) * pitch
        y = 2 + (index // spec.cols) * pitch
        out.append(img.crop((x, y, x + autotile.CELL, y + autotile.CELL)))
    return out


def atlas_column(tid: str, source: str, assets: Path) -> Image.Image:
    img = sheet_image(ATLAS_REL, source, assets)
    col = terrain.TERRAIN_ORDER.index(tid)
    return img.crop((col * autotile.CELL, 0, (col + 1) * autotile.CELL, autotile.CELL))


def lone_pixels(img: Image.Image) -> int:
    """Pixels no 4-neighbour shares a colour with — the finest texture a tile
    carries, and the first thing a 4:1 downsample either keeps whole or drops
    whole."""
    px = img.load()
    w, h = img.size
    found = 0
    for y in range(h):
        for x in range(w):
            c = px[x, y]
            neighbours = [
                px[x + dx, y + dy]
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                if 0 <= x + dx < w and 0 <= y + dy < h
            ]
            if all(n != c for n in neighbours):
                found += 1
    return found


class Reading:
    """One drawn cell's census and its per-rung shares."""

    def __init__(self, name: str, sheet: str, img: Image.Image) -> None:
        px = img.load()
        w, h = img.size
        pixels = [(x, y, px[x, y]) for y in range(h) for x in range(w)]
        counts = Counter(c for _, _, c in pixels)
        base = counts.most_common(1)[0][0]

        self.name = name
        self.sheet = sheet
        self.pixels = img.tobytes()
        self.colours = len(counts)
        self.lone = lone_pixels(img)
        self.density = sum(1 for _, _, c in pixels if c != base) / len(pixels)
        self.shares: dict[int, list[float]] = {}
        for rung, ratio in RUNGS:
            row = []
            for phase_y in range(ratio):
                for phase_x in range(ratio):
                    kept = [
                        c
                        for x, y, c in pixels
                        if x % ratio == phase_x and y % ratio == phase_y
                    ]
                    drawn = sum(1 for c in kept if c != base) / len(kept)
                    row.append(drawn / self.density if self.density else 1.0)
            self.shares[rung] = row

    @property
    def worst(self) -> float:
        """The furthest any rung's any phase sits from the authored density."""
        return max(abs(s - 1.0) for row in self.shares.values() for s in row)

    @property
    def verdict(self) -> str:
        return "stable" if self.worst <= TOLERANCE else "shimmers"


def read(source: str, assets: Path) -> list[Reading]:
    out = []
    for spec in SHEETS:
        out.extend(
            Reading(f"{spec.name}/{index}", spec.rel, img)
            for index, img in enumerate(sheet_tiles(spec, source, assets))
        )
    out.extend(
        Reading(f"atlas {tid}", ATLAS_REL, atlas_column(tid, source, assets))
        for tid in ATLAS_GROUND
    )
    return out


def _span(row: list[float]) -> str:
    return f"{min(row):.2f}–{max(row):.2f}"


def _row(r: Reading) -> str:
    return (
        f"| `{r.name}` | `{r.sheet}` | {r.colours} | {r.lone} | "
        f"{r.density * 100:.1f}% | {_span(r.shares[1])} | {_span(r.shares[2])} | "
        f"{r.shares[4][0]:.2f} | {r.verdict} |"
    )


_HEAD = (
    "| cell | sheet | colours | lone px | grain | 4:1 share | 2:1 share |"
    " 1:1 | verdict |\n"
    "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |"
)


def _rng(values: list[float], scale: float = 1.0, suffix: str = "") -> str:
    lo, hi = min(values) * scale, max(values) * scale
    fmt = f"{lo:.1f}{suffix}" if lo == hi else f"{lo:.1f}–{hi:.1f}{suffix}"
    return fmt


def _ints(values: list[int]) -> str:
    lo, hi = min(values), max(values)
    return str(lo) if lo == hi else f"{lo}–{hi}"


def summary(readings: list[Reading]) -> None:
    print(
        "| family | sheet | cells | colours | lone px | grain | worst swing | verdict |"
    )
    print("| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |")
    for sheet in dict.fromkeys(r.sheet for r in readings):
        rows = [r for r in readings if r.sheet == sheet]
        bad = [r for r in rows if r.verdict != "stable"]
        worst = max(rows, key=lambda r: r.worst)
        verdict = "stable" if not bad else f"{len(bad)} shimmer"
        print(
            f"| {rows[0].name.split('/')[0] if '/' in rows[0].name else 'atlas'} "
            f"| `{sheet}` | {len(rows)} | {_ints([r.colours for r in rows])} "
            f"| {_ints([r.lone for r in rows])} "
            f"| {_rng([r.density for r in rows], 100.0, '%')} "
            f"| {worst.worst:.2f} | {verdict} |"
        )


def report(readings: list[Reading], detail: bool) -> None:
    if detail:
        print(_HEAD)
        for r in readings:
            print(_row(r))
        print()
    summary(readings)
    worst = max(readings, key=lambda r: r.worst)
    print()
    print(f"cells read: {len(readings)}")
    print(f"worst swing: {worst.name} at {worst.worst:.2f} (bar {TOLERANCE})")
    shimmering = [r for r in readings if r.verdict == "shimmers"]
    if shimmering:
        print(f"shimmers ({len(shimmering)}):")
        print(_HEAD)
        for r in shimmering:
            print(_row(r))
    else:
        print("shimmers: none")


def _fallback_checks(source: str, assets: Path) -> None:
    """The claims `TerrainAutotiles` is written against: an interior wood's
    atlas column is the woods sheet's mask 15, and phase 0 of each phase-keyed
    sheet is that terrain's atlas column."""
    for name, index in (("woods", 15), ("plains", 0), ("mountain", 0), ("sea", 0)):
        spec = next(s for s in SHEETS if s.name == name)
        cell = sheet_tiles(spec, source, assets)[index]
        same = cell.tobytes() == atlas_column(name, source, assets).tobytes()
        print(f"{name}/{index} == atlas {name}: {'yes' if same else 'NO'}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", choices=("both", "fresh", "installed"), default="both")
    ap.add_argument(
        "--detail", action="store_true", help="every cell, not just families"
    )
    ap.add_argument("--assets", type=Path, default=ASSETS)
    args = ap.parse_args(argv)

    if args.source != "installed":
        print("# fresh render\n")
        fresh = read("fresh", args.assets)
        report(fresh, args.detail)
    if args.source != "fresh":
        if args.source == "both":
            print()
        print("# installed assets\n")
        shipped = read("installed", args.assets)
        report(shipped, args.detail)
        print()
        _fallback_checks("installed", args.assets)
    if args.source == "both":
        agree = all(a.pixels == b.pixels for a, b in zip(fresh, shipped))
        print()
        print(f"installed matches fresh: {'yes' if agree else 'NO'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
