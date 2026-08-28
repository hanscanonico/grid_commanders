#!/usr/bin/env python3
"""The pipeline's entry point at the package root.

`python sprite_generator.py` is what the Makefile, CI and the README run, so
the name stays; everything it used to do lives in `spritegen.pipeline`, which
`python -m spritegen` reaches directly.
"""

from __future__ import annotations

from spritegen.pipeline import install, main

# tests/test_anim_manifest.py reaches the install step through this shim.
_install = install

if __name__ == "__main__":
    raise SystemExit(main())
