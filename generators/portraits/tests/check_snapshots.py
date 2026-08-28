"""The snapshot gate CI runs: the game's installed art vs a fresh generation.

The baseline is what the game loads — `assets/portraits/**` — so a regeneration
that forgot `make portraits` fails here rather than shipping. A second copy of
the art beside the generator would only be a thing to keep in step with the
first.

Pixel comparison, not byte comparison: the installed PNGs may have been encoded
by a different Pillow/zlib than CI's, so identical art can still differ in
compression. Byte determinism is a separate claim, checked by generating twice
into two directories and diffing them.

Nothing here is enumerated by hand. The pair list is derived from what the
generator actually emitted, and the check runs in both directions — a generated
file with no installed home fails, and an installed file the generator no longer
emits fails too. That is what keeps a new output from landing compared against
nothing, and what catches a general who has left the roster.

Run: .venv/bin/python tests/check_snapshots.py <generated-dir>
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageChops

REPO_ROOT = Path(__file__).resolve().parents[3]

# Where each generated relpath directory is installed in the game. Restated
# rather than imported: this script is run as a file, not as part of the
# package, so it stands on Pillow alone.
INSTALL_MAP = {
    "commanders": "assets/portraits/commanders",
    "factions": "assets/portraits/factions",
}


def _installed() -> dict[Path, Path]:
    """Generated relpath -> the file the game loads it as."""
    return {
        Path(rel_dir) / p.name: p
        for rel_dir, install_dir in INSTALL_MAP.items()
        for p in sorted((REPO_ROOT / install_dir).glob("*.png"))
    }


def _generated(gen: Path) -> set[Path]:
    return {p.relative_to(gen) for p in gen.rglob("*.png") if p.is_file()}


def _differs(generated: Path, installed: Path) -> str | None:
    a = Image.open(generated).convert("RGBA")
    b = Image.open(installed).convert("RGBA")
    if a.size != b.size:
        return f"size mismatch: {installed} {b.size} vs generated {a.size}"
    # alpha_only=False is required: on RGBA images getbbox() otherwise inspects
    # only the alpha band, so colour-only drift would pass.
    if ImageChops.difference(a, b).getbbox(alpha_only=False) is not None:
        return f"pixel mismatch: {installed}"
    return None


def main(argv: list[str]) -> int:
    gen = Path(argv[1] if len(argv) > 1 else "/tmp/gen_a")
    pairs = sorted(_generated(gen))
    baseline = _installed()

    bad = [f"generated file has no baseline: {p}" for p in pairs if p not in baseline]
    bad += [
        f"baseline file the generator no longer emits: {baseline[p]}"
        for p in sorted(set(baseline) - set(pairs))
    ]
    bad += [
        note
        for p in pairs
        if p in baseline and (note := _differs(gen / p, baseline[p]))
    ]
    if bad:
        print("\n".join(bad))
        return 1
    print(f"{len(pairs)} outputs match their baseline")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
