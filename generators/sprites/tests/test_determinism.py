"""The README's headline promise, measured across two processes.

`test_atlas_contract.py` renders each sheet twice inside one interpreter, which
catches a seed but not the nondeterminism that only a second process has: a set
of strings iterated in hash order, a glob that came back in directory order, an
encoder carrying state from the sheet before it. So this runs the whole CLI
twice, in two subprocesses, under two different `PYTHONHASHSEED` values — the
one knob that makes string hashing differ between runs — and compares every
file it wrote, PNGs and `anim.json` alike, byte for byte.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ENTRY = Path(__file__).resolve().parents[1] / "sprite_generator.py"


def _launch(out: Path, hash_seed: str) -> subprocess.Popen:
    """The two runs go up together: a full render is ~40 s, and side by side
    they cost the suite one of them rather than two."""
    return subprocess.Popen(
        [sys.executable, str(ENTRY), "-o", str(out)],
        cwd=ENTRY.parent,
        env=dict(os.environ, PYTHONHASHSEED=hash_seed),
        stdout=subprocess.DEVNULL,
    )


def _read(out: Path) -> dict[str, bytes]:
    return {
        p.relative_to(out).as_posix(): p.read_bytes()
        for p in sorted(out.rglob("*"))
        if p.is_file()
    }


class TwoProcessesAreOneProcess(unittest.TestCase):
    def test_every_output_is_byte_identical(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            runs = [_launch(Path(a), "0"), _launch(Path(b), "1")]
            for run in runs:
                self.assertEqual(run.wait(), 0)
            first, second = _read(Path(a)), _read(Path(b))
        self.assertEqual(sorted(first), sorted(second))
        self.assertIn("anim.json", first)
        self.assertIn("units_atlas.png", first)
        for name, data in first.items():
            with self.subTest(output=name):
                self.assertEqual(data, second[name])


if __name__ == "__main__":
    unittest.main()
