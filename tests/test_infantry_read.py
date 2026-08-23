"""The rifleman's read — the one unit whose subject is a PERSON.

Every other land unit is a machine, and a machine survives the board as a
mass: the board draws the 64px cell onto a 16px grid with nearest filtering,
so it keeps one source pixel in four and a tank is still a tank. A man is not
a mass. He is a head over shoulders, two legs with sky between them, and a
weapon held across him, and each of those is a feature small enough for the
4:1 sample to eat whole. The 2026-08-23 model measured 516 opaque pixels in a
28x29 box with a one-voxel leg gap and a rifle laid as a z-stair, which this
projection draws as a 45 degree line: at the board's sample that was a smudge
with two to four scattered grey dots on it.

These tests hold the parts of the figure that the halving is allowed to
thin but not to erase, and they are phrased against the sample itself rather
than against the source art — a leg gap that only exists at zoom is not a leg
gap. The offsets are all sixteen (dx, dy) the nearest filter can land on,
which is a superset of the four the fixed cell placement actually produces.

Run with `.venv/bin/python -m unittest discover tests`.
"""

from __future__ import annotations

import unittest

from spritegen.palette import MID_FACTION, FACTIONS, material_slot, ramp_for
from spritegen.units import Pose, build_model
from spritegen.voxel import render_indexed

SCALE = 4
PHASES = [(dx, dy) for dy in range(SCALE) for dx in range(SCALE)]


def _sprite(pose: Pose = Pose.A, faction=None):
    return render_indexed(build_model("infantry", pose), faction or FACTIONS[1]).image


def _solid(img) -> list[list[bool]]:
    px = img.convert("RGBA").load()
    return [[px[x, y][3] > 200 for x in range(img.width)] for y in range(img.height)]


def _sampled(img, dx: int, dy: int):
    """The sprite as the board draws it: colour per kept pixel, None for sky."""
    px = img.convert("RGBA").load()
    rows = []
    for y in range(dy, img.height, SCALE):
        row = []
        for x in range(dx, img.width, SCALE):
            c = px[x, y]
            row.append(c[:3] if c[3] > 200 else None)
        rows.append(row)
    return [row for row in rows if any(c is not None for c in row)]


def _longest_run(row, wanted) -> int:
    best = run = 0
    for c in row:
        run = run + 1 if c in wanted else 0
        best = max(best, run)
    return best


class InfantryMass(unittest.TestCase):
    """The rifleman may be the smallest unit on the sheet; he may not be a
    token. Measured 692 opaque pixels in a 32x37 box against the mech's 720,
    and 40-50 logical pixels once the board halves him twice."""

    MIN_PIXELS = 640
    MIN_HEIGHT = 34

    def test_the_rifleman_carries_a_land_unit_s_mass(self):
        for pose in Pose:
            with self.subTest(pose=pose):
                sprite = _sprite(pose)
                solid = _solid(sprite)
                count = sum(sum(row) for row in solid)
                rows = [y for y, row in enumerate(solid) if any(row)]
                self.assertGreaterEqual(count, self.MIN_PIXELS)
                self.assertGreaterEqual(rows[-1] - rows[0] + 1, self.MIN_HEIGHT)


class InfantryStride(unittest.TestCase):
    """Sky between the legs, at every offset the nearest filter can land on.

    Two legs are what tells a man from a bollard, and the tell is the hole
    between them, not the legs. The boots stand two voxels apart on BOTH axes
    for that reason: at one the gap closed at some offsets and the stride
    became a plinth. Measured 2-3 rows of interior sky per offset.
    """

    MIN_GAP_ROWS = 2
    FOOT_ROWS = 4

    def test_sky_survives_between_the_legs_at_every_board_offset(self):
        for dx, dy in PHASES:
            rows = _sampled(_sprite(), dx, dy)
            gapped = 0
            for row in rows[-self.FOOT_ROWS :]:
                xs = [x for x, c in enumerate(row) if c is not None]
                gapped += any(row[x] is None for x in range(xs[0], xs[-1]))
            with self.subTest(dx=dx, dy=dy):
                self.assertGreaterEqual(gapped, self.MIN_GAP_ROWS)


class InfantryRifle(unittest.TestCase):
    """The rifle has to read as a bar, which is why it is laid flat.

    A barrel that climbs in z draws a 45 degree screen stair, and a stair is
    exactly the shape the 4:1 sample turns into dots — the z-stair rifle this
    replaces left a longest run of ONE gunmetal logical pixel at most offsets
    and two at the rest. Along the (+x, -y) world diagonal the same weapon is
    a horizontal screen row, and the furniture hung a voxel under it gives the
    bar a second solid row so the sample cannot land on the dotted top face
    alone. Measured a longest run of 4 at all sixteen offsets.

    The gunmetal ramp is shared with `tire`, so the run is looked for above
    the figure's ankles only: the boots are on the same ramp and must not be
    able to stand in for the weapon.
    """

    MIN_RUN = 3
    BOOT_BAND = 0.70

    def test_the_rifle_is_a_contiguous_bar_at_every_board_offset(self):
        gun = set(ramp_for("gunmetal", FACTIONS[1]))
        for pose in Pose:
            for dx, dy in PHASES:
                rows = _sampled(_sprite(pose), dx, dy)
                upper = rows[: int(len(rows) * self.BOOT_BAND)]
                best = max(_longest_run(row, gun) for row in upper)
                with self.subTest(pose=pose, dx=dx, dy=dy):
                    self.assertGreaterEqual(best, self.MIN_RUN)

    def test_the_weapon_never_reaches_the_sheet_s_bright_gunmetal(self):
        # `steel` is the gunmetal ramp's top slot. A bright bar on this sprite
        # was refuted in the 2026-08-15 A/B panel: it became the widest and
        # lightest thing on the man and out-shouted the faction colour.
        for pose in Pose:
            with self.subTest(pose=pose):
                self.assertNotIn(
                    "steel", set(build_model("infantry", pose).vox.values())
                )


class InfantryFace(unittest.TestCase):
    """The one neutral patch on the man belongs on his head.

    Skin is the only hue on the sprite that is neither livery nor gunmetal, so
    wherever it lands is what the eye calls the face. The model this replaces
    put its skin box BELOW the helmet, on the chest, where it read as a sash;
    the face is on the skull's camera-facing plane now, and the only skin left
    below it is the two hands on the rifle. Measured 67% of the skin mass in
    the top 40% of the figure, against 18% before.
    """

    HEAD_BAND = 0.40
    MIN_HEAD_SHARE = 0.55

    def test_most_of_the_skin_is_on_the_head(self):
        for faction in FACTIONS:
            sprite = _sprite(faction=faction)
            px = sprite.convert("RGBA").load()
            skin = set(ramp_for("skin", faction))
            rows = [y for y, row in enumerate(_solid(sprite)) if any(row)]
            cut = rows[0] + self.HEAD_BAND * (rows[-1] - rows[0] + 1)
            found = [
                y
                for y in range(sprite.height)
                for x in range(sprite.width)
                if px[x, y][3] > 200 and px[x, y][:3] in skin
            ]
            with self.subTest(faction=faction.key):
                self.assertTrue(found, "the rifleman has no skin showing")
                share = sum(1 for y in found if y < cut) / len(found)
                self.assertGreaterEqual(share, self.MIN_HEAD_SHARE)


class InfantryNeck(unittest.TestCase):
    """A head is a head because it is NARROWER than the shoulders it sits on,
    over a dark step. The model this replaces put the helmet brim on exactly
    the torso's own slots, in the torso's own livery slot, so head and body
    were one unbroken red field and the man read as a barrel with a cap.

    Measured on the source model: the head is one voxel inside the shoulder
    line on each side in x, which this projection draws as four screen pixels
    on the near side and six on the far one, and the layer between them is
    shadow-slot livery only.
    """

    def _layers(self, pose: Pose) -> dict[int, dict[tuple[int, int], str]]:
        layers: dict[int, dict[tuple[int, int], str]] = {}
        for (x, y, z), mat in build_model("infantry", pose).vox.items():
            layers.setdefault(z, {})[(x, y)] = mat
        return layers

    def test_the_head_sits_inside_the_shoulder_line_over_a_dark_neck(self):
        for pose in Pose:
            layers = self._layers(pose)
            # The neck is the layer over the lit shoulder line. Pose B settles
            # the firing arm a voxel, so the widest LIVERY layer under that
            # neck is the shoulder line to measure against, not whichever one
            # carries the highlight in this pose.
            lit = [z for z, layer in layers.items() if "hull_lt" in layer.values()]
            self.assertTrue(lit, f"{pose}: the rifleman has no lit shoulder line")
            neck_z = max(lit) + 1
            livery = {
                z: [
                    s
                    for s, mat in layer.items()
                    if material_slot(mat).mid == MID_FACTION
                ]
                for z, layer in layers.items()
            }
            shoulder = max(
                (slots for z, slots in livery.items() if z < neck_z and slots),
                key=lambda slots: max(x for x, _ in slots) - min(x for x, _ in slots),
            )

            def on_the_man(layer, slots=shoulder):
                """The layer's voxels that stand on the man rather than out on
                the weapon he holds clear of himself."""
                xs = [x for x, _ in slots]
                ys = [y for _, y in slots]
                return {
                    (x, y): mat
                    for (x, y), mat in layer.items()
                    if min(xs) <= x <= max(xs) and min(ys) <= y <= max(ys)
                }

            neck = on_the_man(layers[neck_z])
            head = [
                slot
                for z, layer in layers.items()
                if z > neck_z
                for slot in on_the_man(layer)
            ]
            with self.subTest(pose=pose):
                self.assertTrue(head, "no head above the neck")
                # the neck is dark, and narrow enough to leave the shoulder
                # plane open around it
                self.assertEqual(set(neck.values()), {"hull_dk"})
                self.assertLessEqual(len(neck), len(shoulder) // 3)
                # and the head clears the shoulder line's outer slots
                self.assertGreater(min(x for x, _ in head), min(x for x, _ in shoulder))
                self.assertLess(max(x for x, _ in head), max(x for x, _ in shoulder))
