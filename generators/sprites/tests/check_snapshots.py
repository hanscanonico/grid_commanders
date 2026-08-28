"""The snapshot gate CI runs: the game's installed art vs a fresh generation.

The baseline is what the game loads — `assets/tiles/**` and
`assets/sprites/**` — so a regeneration that forgets `make tiles` fails here
rather than shipping. A second copy of those sheets beside the generator would
only be a thing to keep in step with the first.

Pixel comparison, not byte comparison: the installed PNGs may have been
encoded by a different Pillow/zlib than CI's, so identical art can still
differ in compression. `anim.json` is compared byte for byte, being text.

Nothing here is enumerated by hand. The pair list is derived from what the
generator actually emitted, and the check runs in both directions — a
generated file with no installed home fails, and an installed file the
generator no longer emits fails too. That is what keeps a new output (a new
autotile sheet, a new atlas) from landing compared against nothing.

The one output not compared file-for-file is `units/<id>_<team>.png`: those
cells are the units atlas's own cells, exported for the game's paste script.
Each cell is required to be, pixel for pixel, one of the cells of the
installed `units_atlas.png` — which pins the exporter to the atlas. That binds
the art but not the cell's address in the atlas, which nothing here can know.

Run: .venv/bin/python tests/check_snapshots.py <generated-dir> [assets-dir]
Naming an assets directory compares against that flat mirror instead, which is
how the review gallery's own copies are checked.
"""

from __future__ import annotations

import filecmp
import sys
from pathlib import Path

from PIL import Image, ImageChops

REPO_ROOT = Path(__file__).resolve().parents[3]
GALLERY_ASSETS = Path(__file__).resolve().parents[1] / ".lavish" / "assets"

# Where each generated relpath is installed in the game, by its directory.
INSTALL_MAP = {
    ".": "assets/tiles",
    "autotiles": "assets/tiles/autotiles",
    "iso_buildings": "assets/sprites/iso_buildings",
}
# Emitted for the review gallery and installed nowhere: the previews are
# composed scenes rather than art the game loads, so they stay compared
# against the gallery's own copies.
NOT_INSTALLED = frozenset(
    {"preview_map.png", "preview_terrain.png", "preview_units.png"}
)
# Installed beside the generated art but drawn by `make ui-art`, not here.
NOT_GENERATED = frozenset({"overlay.png"})
# The non-image output, compared byte for byte.
BYTE_COMPARED = frozenset({"anim.json"})

# Committed art that is not generator output and so is not a snapshot: the
# before/after/old reference shots kept for the write-ups, and the fonts.
REFERENCE_PREFIXES = ("before_", "after_", "old_")
# The cell directory covered through the atlas rather than file for file.
CELL_DIR = "units"
CELL_ATLAS = "units_atlas.png"


def _mirror(assets: Path) -> dict[Path, Path]:
    """A flat assets directory: every file claims to mirror one output."""
    return {
        p.relative_to(assets): p
        for p in assets.rglob("*.png")
        if not p.name.startswith(REFERENCE_PREFIXES)
    }


def _installed() -> dict[Path, Path]:
    """Generated relpath -> the file the game loads it as."""
    pairs: dict[Path, Path] = {}
    for rel_dir, install_dir in INSTALL_MAP.items():
        for p in (REPO_ROOT / install_dir).glob("*.png"):
            if p.name not in NOT_GENERATED:
                pairs[Path(rel_dir) / p.name] = p
    for name in BYTE_COMPARED:
        pairs[Path(name)] = REPO_ROOT / INSTALL_MAP["."] / name
    for name in NOT_INSTALLED:
        pairs[Path(name)] = GALLERY_ASSETS / name
    return pairs


def _generated(gen: Path, suffixes: frozenset[str]) -> set[Path]:
    return {
        p.relative_to(gen)
        for p in gen.rglob("*")
        if p.suffix in suffixes and p.is_file()
    }


def _differs(a_path: Path, b_path: Path) -> str | None:
    if b_path.name in BYTE_COMPARED:
        if not filecmp.cmp(a_path, b_path, shallow=False):
            return f"byte mismatch: {b_path}"
        return None
    a = Image.open(a_path).convert("RGBA")
    b = Image.open(b_path).convert("RGBA")
    if a.size != b.size:
        return f"size mismatch: {b_path} {b.size} vs generated {a.size}"
    # alpha_only=False is required: on RGBA images getbbox() otherwise
    # inspects only the alpha band, so color-only drift would pass.
    if ImageChops.difference(a, b).getbbox(alpha_only=False) is not None:
        return f"pixel mismatch: {b_path}"
    return None


def _check_cells(gen: Path, atlas_path: Path | None, cells: set[Path]) -> list[str]:
    """Every exported unit cell must be a cell of the installed atlas."""
    if not cells:
        return [f"generator emitted no {CELL_DIR}/ cells"]
    if atlas_path is None or not atlas_path.exists():
        return [f"missing baseline: {atlas_path or CELL_ATLAS}"]
    atlas = Image.open(atlas_path).convert("RGBA")
    sizes = {Image.open(gen / c).size for c in cells}
    if len(sizes) != 1:
        return [f"{CELL_DIR}/ cells are not one size: {sorted(sizes)}"]
    cw, ch = sizes.pop()
    if atlas.width % cw or atlas.height % ch:
        return [f"{CELL_ATLAS} {atlas.size} is not a grid of {cw}x{ch} cells"]
    tiles = {
        atlas.crop((x, y, x + cw, y + ch)).tobytes()
        for y in range(0, atlas.height, ch)
        for x in range(0, atlas.width, cw)
    }
    return [
        f"exported cell is in no cell of {CELL_ATLAS}: {c}"
        for c in sorted(cells)
        if Image.open(gen / c).convert("RGBA").tobytes() not in tiles
    ]


def main(argv: list[str]) -> int:
    gen = Path(argv[1] if len(argv) > 1 else "/tmp/gen_a")
    mirror = Path(argv[2]) if len(argv) > 2 else None
    suffixes = frozenset({".png"} if mirror else {".png", ".json"})
    generated = _generated(gen, suffixes)
    cells = {p for p in generated if p.parent.name == CELL_DIR}
    pairs = sorted(generated - cells)
    baseline = _mirror(mirror) if mirror else _installed()

    bad = [f"generated file has no baseline: {p}" for p in pairs if p not in baseline]
    bad += [
        f"baseline file the generator no longer emits: {baseline[p]}"
        for p in sorted(set(baseline) - set(pairs))
    ]
    bad += _check_cells(gen, baseline.get(Path(CELL_ATLAS)), cells)
    for p in pairs:
        if p in baseline:
            note = _differs(gen / p, baseline[p])
            if note:
                bad.append(note)
    if bad:
        print("\n".join(bad))
        return 1
    print(f"{len(pairs)} outputs match their baseline, {len(cells)} cells in-atlas")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
