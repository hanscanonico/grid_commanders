"""The snapshot gate CI runs: the game's installed audio vs a fresh render.

The baseline is what the game loads — `assets/sfx/**` and `assets/music/**` —
so a composition edit that forgot `make audio` fails here rather than shipping
silently. Generating twice and diffing the two runs, which is the other half of
CI, only proves the pipeline repeats itself; it says nothing about the files in
the repository.

Nothing here is enumerated by hand. The pair list is derived from what the
generator actually emitted, and the check runs in both directions — a generated
file with no installed home fails, and an installed file the generator no longer
emits fails too.

The effects are PCM, so they are compared byte for byte. The music is Ogg
Vorbis, whose bytes and even whose decoded samples belong to the libVorbis that
encoded them: a Linux decode of the committed macOS bytes is close to a fresh
Linux encode but not equal to it. So the marches are held to a portable
invariant instead — the decoded length exactly, which is what protects the loop
seam, and the samples to a measured tolerance far below any edit worth hearing.
A byte difference is reported as a note and never fails.

Run: .venv/bin/python tests/check_snapshots.py <generated-dir>
"""

from __future__ import annotations

import filecmp
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

# Run as a file rather than as part of the package, so the generator root has
# to be put on the path before its one encoder helper can be imported.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from audiogen.ogg import vendor_string  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]

# Where each generated subdirectory is installed in the game.
INSTALL_MAP = {"sfx": "assets/sfx", "music": "assets/music"}

_AUDIO_SUFFIXES = (".wav", ".ogg")


def _installed() -> dict[Path, Path]:
    """Generated relpath -> the file the game loads it as."""
    return {
        Path(rel_dir) / p.name: p
        for rel_dir, install_dir in INSTALL_MAP.items()
        for p in sorted((REPO_ROOT / install_dir).iterdir())
        if p.suffix in _AUDIO_SUFFIXES
    }


def _generated(gen: Path) -> set[Path]:
    return {
        (Path(rel_dir) / p.name)
        for rel_dir in INSTALL_MAP
        for p in (gen / rel_dir).glob("*")
        if p.is_file() and p.suffix in _AUDIO_SUFFIXES
    }


# The decode gap between platforms, measured on these two tracks: GitHub's
# ubuntu libVorbis against the committed macOS bytes reaches 0.023 peak and
# 0.00030 RMS in [-1, 1] units. The tolerances are those with slack — and RMS
# is the discriminating one, a whole march being averaged: raising one voice by
# 0.05 of gain measures 0.0041 and moving a single note 0.013, both far over.
PEAK_TOLERANCE = 0.07
RMS_TOLERANCE = 0.001


def _ogg_differs(generated: Path, installed: Path) -> str | None:
    a, rate_a = sf.read(generated, dtype="float64")
    b, rate_b = sf.read(installed, dtype="float64")
    if rate_a != rate_b:
        return f"sample rate mismatch: {installed} {rate_b} Hz vs generated {rate_a} Hz"
    if len(a) != len(b):
        return f"length mismatch: {installed} {len(b)} frames vs generated {len(a)}"
    delta = a - b
    peak = float(np.max(np.abs(delta)))
    rms = float(np.sqrt(np.mean(np.square(delta))))
    if peak > PEAK_TOLERANCE or rms > RMS_TOLERANCE:
        return (
            f"sample mismatch: {installed} differs by {peak:.5f} peak / "
            f"{rms:.5f} RMS, past the {PEAK_TOLERANCE} peak / {RMS_TOLERANCE} "
            f"RMS a re-encode may drift by"
        )
    return None


def _byte_note(generated: Path, installed: Path) -> str | None:
    """Not a failure: which encoder wrote the bytes, when they are not equal."""
    if filecmp.cmp(generated, installed, shallow=False):
        return None
    return (
        f"note: {installed} decodes the same but its bytes differ — encoded by "
        f"{vendor_string(installed.read_bytes())!r}, fresh render is "
        f"{vendor_string(generated.read_bytes())!r}"
    )


def _differs(generated: Path, installed: Path) -> str | None:
    if generated.suffix == ".ogg":
        return _ogg_differs(generated, installed)
    if not filecmp.cmp(generated, installed, shallow=False):
        return f"byte mismatch: {installed}"
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
    verdicts = {p: _differs(gen / p, baseline[p]) for p in pairs if p in baseline}
    bad += [note for note in verdicts.values() if note]
    # Only for a pair that agreed: on one that did not, the encoder is not the
    # story.
    for p, verdict in verdicts.items():
        if verdict is None and (gen / p).suffix == ".ogg":
            if note := _byte_note(gen / p, baseline[p]):
                print(note)
    if bad:
        print("\n".join(bad))
        return 1
    print(f"{len(pairs)} outputs match their baseline")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
