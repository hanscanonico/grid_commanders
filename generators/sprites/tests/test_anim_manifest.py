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
from spritegen import anim, atlas, terrain, units, voxel
from spritegen.palette import FACTIONS
from spritegen.units import ATLAS_ORDER, MOVES, UNITS, Pose


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

    def test_the_move_clip_plays_the_move_sheets_at_the_move_cadence(self):
        clip = anim.MANIFEST["clips"]["move"]
        self.assertEqual(clip["sheets"], list(anim.MOVE_SHEETS))
        self.assertEqual(clip["order"], list(range(len(anim.MOVE_SHEETS))))
        self.assertEqual(clip["ms_per_frame"], anim.MOVE_MS)
        self.assertEqual(clip["mode"], "loop")
        self.assertEqual(clip["fallback"], "ambient")

    def test_the_move_clip_ships_one_facing_and_says_which(self):
        """The sheets are the art's own facing and the consumer mirrors for
        the other one, so the manifest has to name both halves of that deal —
        a `facing` the game can compare a heading against, and the heading it
        must set `flip_h` for."""
        clip = anim.MANIFEST["clips"]["move"]
        self.assertIn(clip["facing"], ("left", "right"))
        other = "right" if clip["facing"] == "left" else "left"
        self.assertEqual(clip["flip_x_for"], [other])

    def test_only_the_mirrored_clip_carries_a_facing(self):
        """`facing`'s absence is a version-1 consumer's reading of "never
        mirror", which is what lets the schema grow without a version bump —
        so an existing clip may not sprout the key."""
        for name in ("ambient", "ambient_figures", "sea"):
            clip = anim.MANIFEST["clips"][name]
            self.assertNotIn("facing", clip, f"{name} must not claim a facing")
            self.assertNotIn("flip_x_for", clip)
            self.assertNotIn("fallback", clip)

    def test_the_move_cadence_is_quicker_than_the_idle_and_shares_no_tick(self):
        """A stride per cell crossed is faster than an idle beat, and the
        three cadences must not turn over together: if one divided another the
        whole board would step on the same tick."""
        self.assertLess(anim.MOVE_MS, anim.AMBIENT_MS)
        self.assertNotEqual(anim.AMBIENT_MS % anim.MOVE_MS, 0)
        self.assertNotEqual(anim.SEA_MS % anim.MOVE_MS, 0)

    def test_each_clip_owns_its_own_sheets(self):
        """A sheet in two clips is two cadences drawing one file."""
        tuples = (anim.AMBIENT_SHEETS, anim.FIGURE_SHEETS, anim.SEA_SHEETS)
        for sheets in tuples:
            self.assertTrue(
                set(anim.MOVE_SHEETS).isdisjoint(sheets),
                f"the move clip shares a sheet with {sheets}",
            )


class MoveFallback(unittest.TestCase):
    def test_an_unauthored_unit_moves_as_it_idles(self):
        """The move clip is valid before a single stride is authored: every
        uid outside `units.MOVES` renders its ambient counterpart, cell for
        cell. That is the contract the sheets ship on, so it is measured on
        the assembled sheets — placement included — rather than trusted from
        `build_model`."""
        for move, ambient in ((Pose.MOVE_A, Pose.A), (Pose.MOVE_B, Pose.B)):
            moved = atlas.build_units_atlas(move)
            idle = atlas.build_units_atlas(ambient)
            for col, uid in enumerate(ATLAS_ORDER):
                if uid in MOVES:
                    continue
                for row in range(len(FACTIONS)):
                    box = (
                        col * atlas.CELL_W,
                        row * atlas.CELL_H,
                        (col + 1) * atlas.CELL_W,
                        (row + 1) * atlas.CELL_H,
                    )
                    with self.subTest(unit=uid, row=row, pose=move.name):
                        self.assertEqual(
                            moved.crop(box).tobytes(), idle.crop(box).tobytes()
                        )

    def test_a_frame_ticking_branch_reads_the_beat_not_the_pose(self):
        """`build_model`'s fallback hides this, so it is asked of the builders
        directly: a branch that ticks with the FRAME — the rotor phase — must
        give MOVE_A the A art and MOVE_B the B art. Written as
        `X if pose is Pose.A else Y` it would hand MOVE_A the off-beat blade,
        and the first authored copter stride would inherit the bug.

        It is asked of the DISC alone. When it was written the copters had no
        move art and the whole model answered it; now that they rake under
        way, the airframe legitimately differs from its ambient key and only
        the disc — the part that ticks with the frame rather than with the
        clip — has to match frame for frame. `b_copter`'s tail rotor is rotor
        material too, and it is bolted to a boom that comes up in the rake, so
        reading every rotor voxel would take the boom's attitude for a blade
        phase."""
        for uid in ("b_copter", "t_copter"):
            builder = UNITS[uid][0]
            for move, ambient in ((Pose.MOVE_A, Pose.A), (Pose.MOVE_B, Pose.B)):
                with self.subTest(unit=uid, pose=move.name):
                    disc = self._disc(builder(move))
                    # Named, so a `_disc` that stopped finding the blades
                    # cannot answer this test with two empty sets: four arms
                    # of five voxels on `b_copter`, two discs of them on the
                    # tandem, in every pose.
                    self.assertEqual(len(disc), 20 if uid == "b_copter" else 32)
                    self.assertEqual(disc, self._disc(builder(ambient)))

    # Both copters paint every main disc at one height (`units._rotor(m, ...,
    # 9, ...)`), and a disc is the one rotor that sweeps HORIZONTALLY: each
    # arm is a run of voxels side by side in that plane. A tail rotor stands
    # on edge, so whatever of it crosses the plane crosses it alone.
    DISC_Z = 9

    @classmethod
    def _disc(cls, model) -> set:
        plane = {
            v for v, mat in model.vox.items() if mat == "rotor" and v[2] == cls.DISC_Z
        }
        return {
            (x, y, z)
            for x, y, z in plane
            if {(x - 1, y, z), (x + 1, y, z), (x, y - 1, z), (x, y + 1, z)} & plane
        }

    def test_a_unit_that_opts_into_the_move_clip_authors_a_move_pose(self):
        """`MOVES` is what takes a unit out of the fallback above, so a uid
        listed there with no move art of its own would ship a move clip that
        is its idle under a new name and no test would notice: the fallback
        test skips it and the sheets still build.

        The claim is asked of the PAIR, not of either frame. Written as
        "MOVE_A's voxels differ from A's" it fails units that author their
        stride honestly: the tracked family holds the travel-lock, so its
        MOVE_A IS pose A and everything the clip says is in MOVE_B. So what
        is asked is that the move pair differs from the ambient pair — one
        frame may reuse its ambient key, not both.

        This is the cheap voxel-level half of the rule and it is kept for
        that: it fails in the builder's own terms, before anything is
        composed. The other half — that the two move frames differ from each
        OTHER — cannot be asked here, because a frame may differ only in
        composition: the fixed-wing pair holds one attitude in the model and
        takes its beat from the air bob. `MoveFrames.
        test_the_move_pair_is_not_the_ambient_pair` asks both halves of the
        composed cells, which is where that one is answerable.
        """
        for uid in MOVES:
            builder = UNITS[uid][0]
            vox = {pose: builder(pose).vox for pose in Pose}
            with self.subTest(unit=uid):
                self.assertNotEqual(
                    (vox[Pose.MOVE_A], vox[Pose.MOVE_B]),
                    (vox[Pose.A], vox[Pose.B]),
                )

    def test_the_aircraft_under_way_hold_a_texel_of_nose_down(self):
        """What the air family's move clip says, in the only terms a sheet
        that may never translate the hull has: attitude. The forward-most
        course of the airframe sits at least one whole board texel lower
        under way (`dz = -2`, the texel rule in `units._shift`) while the
        aftmost two courses — nozzles, tail turret, tail rotor, ramp — never
        go DOWN with it, so the screen line ROTATES about the wings or the
        mast rather than the whole aircraft sinking.

        The fixed wings hold their tails exactly; the two copters lift theirs,
        because a rotorcraft with no wing carries the whole of that reading in
        the fuselage line and a nose-down on its own measured 17 and 14
        changed rung-1 texels against the parked pose — the smallest
        parked-vs-moving deltas in the fleet. Raking the airframe about the
        mast, tail up as the nose goes down, is the same rotation read from
        both ends: 30 and 29. Which is why this reads the aft courses'
        FLOOR and not their voxels."""
        for uid in MOVES:
            if UNITS[uid][1] != "air":
                continue
            builder = UNITS[uid][0]
            idle, moved = builder(Pose.A).vox, builder(Pose.MOVE_A).vox
            ys = [y for _, y, _ in idle]
            with self.subTest(unit=uid, reading="nose"):
                nose = max(ys)
                self.assertLessEqual(
                    min(z for _, y, z in moved if y == nose),
                    min(z for _, y, z in idle if y == nose) - 2,
                )
            with self.subTest(unit=uid, reading="tail"):
                tail = min(ys) + 1
                self.assertGreaterEqual(
                    min(z for _, y, z in moved if y <= tail),
                    min(z for _, y, z in idle if y <= tail),
                )

    def test_the_clip_table_names_the_clips_the_manifest_publishes(self):
        """`units.CLIP_POSES` is what a family task reads to know which poses
        it owes a clip; a name or a frame count that drifts from the manifest
        would author strides for a clip no consumer plays."""
        for name, poses in units.CLIP_POSES.items():
            clip = anim.MANIFEST["clips"].get(name)
            self.assertIsNotNone(
                clip, f"CLIP_POSES names {name}, the manifest does not"
            )
            self.assertEqual(len(poses), len(clip["sheets"]))


# Every units sheet the install has to carry, in one place, so seeding the
# fake output directory and asserting what landed cannot drift apart.
_SHEETS: tuple[str, ...] = (
    *anim.AMBIENT_SHEETS,
    *anim.FIGURE_SHEETS,
    *anim.MOVE_SHEETS,
)


class Install(unittest.TestCase):
    def test_the_install_step_ships_the_manifest_with_the_sheets(self):
        """The manifest is only a contract where the game can read it: a
        game install that took the new atlases and left last run's anim.json
        behind is the drift this file exists to end."""
        with tempfile.TemporaryDirectory() as tmp:
            src, dest = Path(tmp) / "out", Path(tmp) / "game"
            for sub in ("units", "iso_buildings", "autotiles"):
                (src / sub).mkdir(parents=True)
            for name in _SHEETS:
                (src / name).write_bytes(b"")
            (src / "terrain_atlas.png").write_bytes(b"")
            anim.dump(src / anim.MANIFEST_NAME)
            with contextlib.redirect_stdout(io.StringIO()):
                sprite_generator._install(src, dest)
            tiles = dest / "assets/tiles"
            shipped = tiles / anim.MANIFEST_NAME
            self.assertTrue(shipped.exists(), "the install left the manifest behind")
            self.assertEqual(shipped.read_text(encoding="utf-8"), anim.dumps())
            # A clip the manifest names but the install does not ship is the
            # same drift one step later, so every sheet has to land too.
            for name in _SHEETS:
                self.assertTrue((tiles / name).exists(), f"the install left {name}")


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
