"""The snapshot gate CI runs: committed art vs a fresh generation.

Pixel comparison, not byte comparison: the committed PNGs may have been
encoded by a different Pillow/zlib than CI's, so identical art can still
differ in compression.

Nothing here is enumerated by hand. The pair list is derived from what the
generator actually emitted, and the check runs in both directions — a
generated file with no committed snapshot fails, and a committed snapshot the
generator no longer emits fails too. That is what keeps a new output (a new
autotile sheet, a new atlas) from landing compared against nothing.

The one output not compared file-for-file is `units/<id>_<team>.png`: those
cells are the units atlas's own cells, exported for the game's paste script.
Instead of committing 120 duplicates of art already snapshotted, each cell is
required to be, pixel for pixel, one of the cells of the committed
`units_atlas.png` — which pins the exporter to the atlas.

Run: .venv/bin/python tests/check_snapshots.py <generated-dir> [assets-dir]
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageChops

# Committed art that is not generator output and so is not a snapshot: the
# before/after/old reference shots kept for the write-ups, and the fonts.
REFERENCE_PREFIXES = ("before_", "after_", "old_")
# The cell directory covered through the atlas rather than file for file.
CELL_DIR = "units"
CELL_ATLAS = "units_atlas.png"


def _snapshots(assets: Path) -> set[Path]:
    """Committed files that claim to mirror generator output."""
    return {
        p.relative_to(assets)
        for p in assets.rglob("*.png")
        if not p.name.startswith(REFERENCE_PREFIXES)
    }


def _generated(gen: Path) -> set[Path]:
    return {p.relative_to(gen) for p in gen.rglob("*.png")}


def _differs(a_path: Path, b_path: Path) -> str | None:
    a = Image.open(a_path).convert("RGBA")
    b = Image.open(b_path).convert("RGBA")
    if a.size != b.size:
        return f"size mismatch: {b_path} {b.size} vs generated {a.size}"
    # alpha_only=False is required: on RGBA images getbbox() otherwise
    # inspects only the alpha band, so color-only drift would pass.
    if ImageChops.difference(a, b).getbbox(alpha_only=False) is not None:
        return f"pixel mismatch: {b_path}"
    return None


def _check_cells(gen: Path, assets: Path, cells: set[Path]) -> list[str]:
    """Every exported unit cell must be a cell of the committed atlas."""
    if not cells:
        return [f"generator emitted no {CELL_DIR}/ cells"]
    snap = assets / CELL_ATLAS
    if not snap.exists():
        return [f"missing snapshot: {snap}"]
    atlas = Image.open(snap).convert("RGBA")
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
    assets = Path(argv[2] if len(argv) > 2 else ".lavish/assets")
    generated = _generated(gen)
    cells = {p for p in generated if p.parent.name == CELL_DIR}
    pairs = sorted(generated - cells)
    committed = _snapshots(assets)

    bad = [
        f"generated file has no committed snapshot: {p}"
        for p in pairs
        if p not in committed
    ]
    bad += [
        f"committed snapshot the generator no longer emits: {p}"
        for p in sorted(committed - set(pairs))
    ]
    bad += _check_cells(gen, assets, cells)
    for p in pairs:
        if p in committed:
            note = _differs(gen / p, assets / p)
            if note:
                bad.append(note)
    if bad:
        print("\n".join(bad))
        return 1
    print(f"{len(pairs)} snapshots match generator output, {len(cells)} cells in-atlas")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
