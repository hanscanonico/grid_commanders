"""`anim.json` says what the tables say, and says it the same way twice.

The manifest exists so the game stops retyping this pipeline's numbers, which
only helps if the manifest is not retyping them either. These tests hold every
field against the table it is supposed to come from — column order against
`ATLAS_ORDER`, rows against `FACTIONS`, phase counts against the terrain phase
tables, the cell against `atlas`, and `ground_px` against a cell actually
rendered — plus the determinism the rest of the pipeline promises and the
install step that has to carry the file to the game beside its sheets.

Run with `.venv/bin/python -m unittest discover tests`.
"""

from __future__ import annotations

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

import sprite_generator
from spritegen import anim, atlas, terrain, voxel
from spritegen.palette import FACTIONS
from spritegen.units import ATLAS_ORDER, UNITS


class Columns(unittest.TestCase):
    def test_the_columns_are_the_atlas_order(self):
        cols = anim.MANIFEST["columns"]
        self.assertEqual(len(cols), len(ATLAS_ORDER))
        for want, uid in enumerate(ATLAS_ORDER):
            self.assertEqual(cols[uid], want, f"{uid} is not column {want}")

    def test_the_rows_are_the_faction_order(self):
        self.assertEqual(
            anim.MANIFEST["rows"],
            [{"key": f.key, "team": f.team} for f in FACTIONS],
        )


class Phases(unittest.TestCase):
    def test_the_phase_counts_are_the_phase_tables(self):
        self.assertEqual(
            anim.MANIFEST["terrain_phases"],
            {
                "sea": len(terrain.SEA_PHASES),
                "plains": len(terrain.PLAINS_PHASES),
                "mountain": len(terrain.MOUNTAIN_PHASES),
            },
        )


class Cell(unittest.TestCase):
    def test_the_cell_is_the_atlas_cell(self):
        cell = anim.MANIFEST["cell"]
        self.assertEqual((cell["w"], cell["h"]), (atlas.CELL_W, atlas.CELL_H))
        self.assertEqual(cell["overflow"], atlas.CELL_H - atlas.CELL_W)

    def test_ground_px_is_where_every_land_cell_puts_its_shadow(self):
        """The measured row is not one column's accident: the contact ellipse
        is centred on the same row under every land unit on the sheet."""
        ground = anim.MANIFEST["cell"]["ground_px"]
        fac = FACTIONS[1]
        for uid in ATLAS_ORDER:
            if UNITS[uid][1] != "land":
                continue
            cell = atlas.unit_cell(uid, fac)
            lit = cell.load()
            bare = atlas.unit_cell(uid, fac, shadow=False).load()
            spans = [
                sum(
                    1
                    for x in range(cell.width)
                    if lit[x, y][3] != 0 and bare[x, y][3] == 0
                )
                for y in range(cell.height)
            ]
            widest = max(range(len(spans)), key=lambda y: spans[y])
            self.assertEqual(
                cell.height - 1 - widest, ground, f"{uid}'s shadow is centred elsewhere"
            )

    def test_ground_px_is_the_composer_s_own_arithmetic(self):
        """A second, independent derivation, so the two readings cannot share
        an off-by-one: `compose_cell` centres a land unit's ellipse on
        `bottom - 1 + SHADOW_OFFSET.y` with `bottom = h - GROUND_BOTTOM`, so
        the height of that row above the bottom edge is a subtraction of two
        voxel constants. If the pixel scan drifts a row, this disagrees."""
        self.assertEqual(
            anim.MANIFEST["cell"]["ground_px"],
            voxel.GROUND_BOTTOM - voxel.SHADOW_OFFSET[1],
        )


class Clip(unittest.TestCase):
    def test_the_ambient_clip_plays_the_sheets_the_generator_writes(self):
        clip = anim.MANIFEST["clips"]["ambient"]
        self.assertEqual(clip["sheets"], list(anim.AMBIENT_SHEETS))
        self.assertEqual(clip["order"], list(range(len(anim.AMBIENT_SHEETS))))
        self.assertEqual(clip["ms_per_frame"], anim.AMBIENT_MS)
        self.assertEqual(clip["mode"], "loop")

    def test_the_figure_clip_is_the_ambient_clip_on_the_figure_sheets(self):
        """The cut-in idles on the same beat the board does — the figure pair
        is the ambient pair minus the tile shadow, so a second cadence here
        would be the two surfaces disagreeing about one motion."""
        clip = anim.MANIFEST["clips"]["ambient_figures"]
        self.assertEqual(clip["sheets"], list(anim.FIGURE_SHEETS))
        self.assertEqual(len(anim.FIGURE_SHEETS), len(anim.AMBIENT_SHEETS))
        ambient = anim.MANIFEST["clips"]["ambient"]
        self.assertEqual(clip["order"], ambient["order"])
        self.assertEqual(clip["ms_per_frame"], ambient["ms_per_frame"])
        self.assertEqual(clip["mode"], ambient["mode"])


class Install(unittest.TestCase):
    def test_the_install_step_ships_the_manifest_with_the_sheets(self):
        """The manifest is only a contract where the game can read it: a
        game install that took the new atlases and left last run's anim.json
        behind is the drift this file exists to end."""
        with tempfile.TemporaryDirectory() as tmp:
            src, dest = Path(tmp) / "out", Path(tmp) / "game"
            for sub in ("units", "iso_buildings", "autotiles"):
                (src / sub).mkdir(parents=True)
            for name in (*anim.AMBIENT_SHEETS, *anim.FIGURE_SHEETS):
                (src / name).write_bytes(b"")
            (src / "terrain_atlas.png").write_bytes(b"")
            anim.dump(src / anim.MANIFEST_NAME)
            with contextlib.redirect_stdout(io.StringIO()):
                sprite_generator._install(src, dest)
            shipped = dest / "assets/tiles" / anim.MANIFEST_NAME
            self.assertTrue(shipped.exists(), "the install left the manifest behind")
            self.assertEqual(shipped.read_text(encoding="utf-8"), anim.dumps())


class Determinism(unittest.TestCase):
    def test_two_dumps_are_byte_identical(self):
        with tempfile.TemporaryDirectory() as tmp:
            a, b = Path(tmp) / "a" / "anim.json", Path(tmp) / "b" / "anim.json"
            anim.dump(a)
            anim.dump(b)
            self.assertEqual(a.read_bytes(), b.read_bytes())
            self.assertTrue(a.read_text().endswith("}\n"))
            self.assertEqual(json.loads(a.read_text()), anim.MANIFEST)


if __name__ == "__main__":
    unittest.main()
