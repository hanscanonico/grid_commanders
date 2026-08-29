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


def _run(out: Path, hash_seed: str) -> dict[str, bytes]:
    env = dict(os.environ, PYTHONHASHSEED=hash_seed)
    subprocess.run(
        [sys.executable, str(ENTRY), "-o", str(out)],
        cwd=ENTRY.parent,
        env=env,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    return {
        p.relative_to(out).as_posix(): p.read_bytes()
        for p in sorted(out.rglob("*"))
        if p.is_file()
    }


class TwoProcessesAreOneProcess(unittest.TestCase):
    def test_every_output_is_byte_identical(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            first, second = _run(Path(a), "0"), _run(Path(b), "1")
        self.assertEqual(sorted(first), sorted(second))
        self.assertIn("anim.json", first)
        self.assertIn("units_atlas.png", first)
        for name, data in first.items():
            with self.subTest(output=name):
                self.assertEqual(data, second[name])


if __name__ == "__main__":
    unittest.main()
