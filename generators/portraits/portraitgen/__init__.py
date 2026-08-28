"""Deterministic portrait pipeline for grid_commanders' commander art.

`__all__` is the public surface: a run (`generate`, `install`, and the `OUTPUTS`
table they share) and the drawing surface every layer goes through. Everything
else is a module of this package's own — import it by name.
"""

from .canvas import Canvas
from .pipeline import OUTPUTS, Output, generate, install

__all__ = [
    "OUTPUTS",
    "Canvas",
    "Output",
    "generate",
    "install",
]
