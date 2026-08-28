#!/usr/bin/env python3
"""The pipeline's entry point at the package root.

`python portrait_generator.py` is what the Makefile, CI and the README run, so
the name stays; everything it does lives in `portraitgen.pipeline`, which
`python -m portraitgen` reaches directly.
"""

from __future__ import annotations

from portraitgen.pipeline import install, main

__all__ = ["install", "main"]

if __name__ == "__main__":
    raise SystemExit(main())
