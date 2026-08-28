"""Deterministic sprite pipeline for grid_commanders' unit and terrain atlases.

`__all__` is the public surface: a run (`generate`, `install`, and the `SHEETS`
table they share), the two sheets and the two cells every consumer builds from,
the terrain tile, and the sheet manifest the game reads. Everything else is a
module of this package's own — import it by name.
"""

from .anim import MANIFEST, dump, dumps
from .atlas import build_terrain_atlas, build_units_atlas, building_cell, unit_cell
from .pipeline import SHEETS, Output, building_cells, generate, install, unit_cells
from .terrain import tile

__all__ = [
    "MANIFEST",
    "Output",
    "SHEETS",
    "build_terrain_atlas",
    "build_units_atlas",
    "building_cell",
    "building_cells",
    "dump",
    "dumps",
    "generate",
    "install",
    "tile",
    "unit_cell",
    "unit_cells",
]
