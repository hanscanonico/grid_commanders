"""The snapshot gate CI runs: the game's installed art vs a fresh generation.

The baseline is what the game loads — `assets/tiles/**` and `assets/ui/**` —
so a regeneration that forgets `make tiles` fails here rather than shipping. A
second copy of those sheets beside the generator would only be a thing to keep
in step with the first.

Pixel comparison, not byte comparison: the installed PNGs may have been
encoded by a different Pillow/zlib than CI's, so identical art can still
differ in compression. `anim.json` is compared byte for byte, being text.

Nothing here is enumerated by hand. The pair list is derived from what the
generator actually emitted, and the check runs in both directions — a
generated file with no installed home fails, and an installed file the
generator no longer emits fails too. That is what keeps a new output (a new
autotile sheet, a new atlas) from landing compared against nothing.

The per-cell exports are the outputs with no baseline to pair off: they are
review copies of art the sheets carry and the game never loads, so nothing
installs them. The unit cells are still held to the atlas — each must be,
pixel for pixel, one of the cells of the run's own `units_atlas.png`, which
pins the exporter to the sheet. That binds the art but not the cell's address
in the atlas, which nothing here can know.

A pixel mismatch also writes a before/after/diff contact sheet, because most
failures here are an art change somebody meant and the message alone gives a
reviewer nothing to look at.

Run: .venv/bin/python tests/check_snapshots.py <generated-dir> [assets-dir]
Naming an assets directory compares against that flat mirror instead, which is
how the review gallery's own copies are checked.
"""

from __future__ import annotations

import filecmp
import sys
from pathlib import Path

from diff_sheet import write_diff_sheet
from PIL import Image, ImageChops

GENERATOR_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(GENERATOR_ROOT))

from spritegen.pipeline import BUILDING_CELLS, SHEETS, UNIT_CELLS  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]
GALLERY_ASSETS = GENERATOR_ROOT / ".lavish" / "assets"


def _install_map() -> dict[str, str]:
    """Where each generated relpath is installed in the game, by its directory
    — read off the outputs themselves, so a new destination (the icon's, the
    cursor's) needs no second list here to be compared."""
    return {
        Path(o.rel).parent.as_posix(): o.install_to
        for o in SHEETS
        if o.install_to is not None
    }


INSTALL_MAP = _install_map()
# Emitted for the review gallery and installed nowhere: the previews are
# composed scenes rather than art the game loads, so they stay compared
# against the gallery's own copies.
NOT_INSTALLED = frozenset(
    {"preview_map.png", "preview_terrain.png", "preview_units.png"}
)
# The non-image output, compared byte for byte.
BYTE_COMPARED = frozenset({"anim.json"})

# Committed art that is not generator output and so is not a snapshot: the
# before/after/old reference shots kept for the write-ups, and the fonts.
REFERENCE_PREFIXES = ("before_", "after_", "old_")
# The two directories that install nowhere. The unit cells are covered through
# the atlas instead of file for file; the building cells are pinned to the
# terrain tiles by `tests/test_properties_art.py`.
CELL_DIRS = frozenset({UNIT_CELLS, BUILDING_CELLS})
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
            pairs[Path(rel_dir) / p.name] = p
    # A named baseline that is not on disk is left out of the pairs, so its
    # generated twin fails the "no baseline" direction rather than crashing.
    for name in BYTE_COMPARED:
        installed = REPO_ROOT / INSTALL_MAP["."] / name
        if installed.exists():
            pairs[Path(name)] = installed
    for name in NOT_INSTALLED:
        gallery = GALLERY_ASSETS / name
        if gallery.exists():
            pairs[Path(name)] = gallery
    return pairs


def _generated(gen: Path, suffixes: frozenset[str]) -> set[Path]:
    return {
        p.relative_to(gen)
        for p in gen.rglob("*")
        if p.suffix in suffixes and p.is_file()
    }


def _differs(a_path: Path, b_path: Path, rel: Path) -> str | None:
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
        return write_diff_sheet(a_path, b_path, rel).note(b_path)
    return None


def _check_cells(gen: Path, cells: set[Path]) -> list[str]:
    """Every exported unit cell must be a cell of the run's own atlas."""
    if not cells:
        return [f"generator emitted no {UNIT_CELLS}/ cells"]
    atlas_path = gen / CELL_ATLAS
    if not atlas_path.exists():
        return [f"missing {atlas_path}"]
    atlas = Image.open(atlas_path).convert("RGBA")
    sizes = {Image.open(gen / c).size for c in cells}
    if len(sizes) != 1:
        return [f"{UNIT_CELLS}/ cells are not one size: {sorted(sizes)}"]
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
    cells = {p for p in generated if p.parent.name in CELL_DIRS}
    pairs = sorted(generated - cells)
    baseline = _mirror(mirror) if mirror else _installed()

    bad = [f"generated file has no baseline: {p}" for p in pairs if p not in baseline]
    bad += [
        f"baseline file the generator no longer emits: {baseline[p]}"
        for p in sorted(set(baseline) - set(pairs))
    ]
    unit_cells = {p for p in cells if p.parent.name == UNIT_CELLS}
    bad += _check_cells(gen, unit_cells)
    for p in pairs:
        if p in baseline:
            note = _differs(gen / p, baseline[p], p)
            if note:
                bad.append(note)
    if bad:
        print("\n".join(bad))
        return 1
    print(
        f"{len(pairs)} outputs match their baseline, {len(unit_cells)} cells in-atlas"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
