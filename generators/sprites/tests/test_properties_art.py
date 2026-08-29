"""Contract tests for the property columns: neutral buildings under faction roofs.

The shaded path's outline, the building's palette slots, the transparent
ground a property is drawn on, and the five silhouettes.
"""

from __future__ import annotations

import unittest
from unittest import mock

from PIL import Image

from spritegen import atlas, buildings, palette, terrain
from spritegen.palette import (
    FACTIONS,
    MID_CONTOUR,
    MID_FACTION,
    OUTLINE_HEAVY,
    OUTLINE_RIM,
    RAMPS,
)
from spritegen.terrain import CELL
from spritegen import voxel
from spritegen.voxel import _broad_flat_tops, _prop_contour, render, render_indexed

from pixel_helpers import opaque_pixels


class PropOutline(unittest.TestCase):
    """The shaded path's edge and texture, held to one decision each.

    A neighbour-averaged contour spends one near-black per lit neighbourhood
    and a per-pixel dither spends one tone per amplitude, so a building came
    out of `voxel.render` carrying 200 colours no eye could name. The rules
    that replaced them are countable, and this is where they are counted —
    see docs/terrain_outlines.md.

    The buildings left this path in the properties pass (`PropertyPalette`
    below), so what is left on it is the reef rock: a small prop, whose
    contour is still one deliberate tone per material and whose tops are
    still too narrow to carry a texture. The dither's other half — that a
    plane broad enough DOES speckle — has no model left to state it on, and
    is stated by `DITHER_MIN_TOP_AREA` alone.
    """

    def _contour_ring(self, model, fac) -> set[tuple[int, int, int]]:
        """The pixels the outline pass adds, by difference."""
        lit = render(model, fac, outline=True).load()
        bare = render(model, fac, outline=False)
        bare_px = bare.load()
        return {
            lit[x, y][:3]
            for y in range(bare.height)
            for x in range(bare.width)
            if bare_px[x, y][3] == 0 and lit[x, y][3] == 255
        }

    def _props(self):
        for size in (2, 3, 4):
            yield f"reef rock {size}", buildings.rock_outcrop(size)

    def test_a_contour_pixel_is_a_materials_own_contour_tone(self):
        for name, model in self._props():
            for fac in FACTIONS:
                allowed = {_prop_contour(m, fac) for m in set(model.vox.values())}
                with self.subTest(prop=name, faction=fac.key):
                    self.assertTrue(self._contour_ring(model, fac))
                    self.assertLessEqual(self._contour_ring(model, fac), allowed)

    def test_the_contour_spends_no_more_tones_than_the_model_has_materials(self):
        for name, model in self._props():
            with self.subTest(prop=name):
                self.assertLessEqual(
                    len(self._contour_ring(model, FACTIONS[2])),
                    len(set(model.vox.values())),
                )

    def _undithered(self, model, fac):
        """The same render with the dither hash pinned above its threshold."""
        with mock.patch.object(voxel, "h01", lambda *_: 1.0):
            return opaque_pixels(render(model, fac, outline=False))

    def test_the_area_rule_reaches_the_picture_not_just_the_plane_finder(self):
        """A prop with no broad plane renders identically with the dither off.

        `_broad_flat_tops` agreeing with its own constant proves nothing if
        the renderer ignores it, so this compares pixels: pin the hash above
        the threshold, and a narrow-topped prop's picture must not move by a
        pixel.
        """
        fac = FACTIONS[2]
        for name, model in self._props():
            with self.subTest(prop=name):
                self.assertEqual(
                    opaque_pixels(render(model, fac, outline=False)),
                    self._undithered(model, fac),
                )

    def test_a_small_prop_carries_no_dither_at_all(self):
        for size in (2, 3):
            with self.subTest(size=size):
                self.assertEqual(
                    _broad_flat_tops(buildings.rock_outcrop(size).vox), set()
                )


class PropertyPalette(unittest.TestCase):
    """A building is drawn the way a unit is: slots, not shading arithmetic.

    The properties pass (2026-08-22) took the five buildings off `voxel.render`
    and onto `render_indexed`, out of the masonry / concrete / machinery ramps
    (`palette.PROPERTY_MATERIALS`), one band under the units
    (`voxel.BUILDING_TOP_SLOT`). What that bought is measured here: the two
    numbers a building was an outlier on, held to what a unit is held to.
    """

    # The unit cap, `IndexedPalette.test_no_sprite_spends_more_than_24_colours`,
    # now reached rather than approached: the shading path spent 61-74 colours
    # a building (204 before the contour and dither rules), and the widest
    # sprite on the sheet — the aurora airport, five ramps and four accents —
    # spends 23.
    SPRITE_CEILING = 24
    # The share of a sprite's own silhouette boundary drawn as the contour,
    # per outline grade, measured over all 18 units both poses:
    #
    #   light grade  units 0.579-0.696   buildings 0.650-0.743
    #   heavy grade  units 0.791-0.941   buildings 0.821-0.985
    #
    # The rim grade shares the light grade's band, and on a BUILDING it shares
    # its pixels outright: a property stops at `BUILDING_TOP_SLOT`, so the rim
    # the grade lifts into is not a rung a wall may reach and the lift never
    # fires (`voxel._selective_outline`). A roof is what an army is read
    # against; it does not get to answer the ground the same way.
    #
    # Buildings sit a little over the units of their grade because a lot is a
    # flat plate — its whole sunward edge is one ground-facing step — and that
    # is the gap these bands allow. What they do not allow is the shading
    # path's figure, which was 1.000 on eleven of the twenty-five sprites: an
    # unconditional keyline, drawn as hard on the side the sun is on as on the
    # side it is not.
    BOUNDARY_DARK = {
        palette.OUTLINE_LIGHT: (0.50, 0.75),
        OUTLINE_RIM: (0.50, 0.75),
        OUTLINE_HEAVY: (0.75, 0.99),
    }

    def _sprite(self, bid, fac):
        return render_indexed(
            buildings.model_for(bid, fac), fac, top_slot=voxel.BUILDING_TOP_SLOT
        )

    def test_every_building_is_drawn_by_the_indexed_renderer(self):
        for bid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                with self.subTest(building=bid, faction=fac.key):
                    model = buildings.model_for(bid, fac)
                    self.assertTrue(model.indexed)
                    # ...and what terrain composes is that renderer's picture
                    self.assertEqual(
                        opaque_pixels(render(model, fac)),
                        opaque_pixels(self._sprite(bid, fac).image),
                    )
        # the nature props are the shaded path's, and stay on it
        self.assertFalse(buildings.rock_outcrop(2).indexed)

    def test_no_building_spends_more_than_a_unit_does(self):
        for bid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                with self.subTest(building=bid, faction=fac.key):
                    colours = len(set(opaque_pixels(self._sprite(bid, fac).image)))
                    self.assertLessEqual(colours, self.SPRITE_CEILING)

    def test_the_boundary_is_a_break_rather_than_a_keyline(self):
        for bid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                sprite = self._sprite(bid, fac)
                img = sprite.image
                px = img.load()
                w, h = img.size
                edge = [
                    (x, y)
                    for y in range(h)
                    for x in range(w)
                    if px[x, y][3] == 255
                    and not all(
                        0 <= x + dx < w
                        and 0 <= y + dy < h
                        and px[x + dx, y + dy][3] == 255
                        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                    )
                ]
                dark = sum(1 for x, y in edge if sprite.mid(x, y) == MID_CONTOUR)
                lo, hi = self.BOUNDARY_DARK[fac.outline]
                with self.subTest(building=bid, faction=fac.key):
                    self.assertGreaterEqual(dark / len(edge), lo)
                    self.assertLessEqual(dark / len(edge), hi)

    def test_the_owner_reads_out_of_the_factions_own_ramp(self):
        for bid in sorted(terrain.PROPERTY):
            for fac in FACTIONS[1:]:  # the unowned row wears no faction pixel
                sprite = self._sprite(bid, fac)
                px = sprite.image.load()
                worn = [
                    px[x, y][:3]
                    for y in range(sprite.image.height)
                    for x in range(sprite.image.width)
                    if sprite.mid(x, y) == MID_FACTION
                ]
                with self.subTest(building=bid, faction=fac.key):
                    self.assertGreater(len(worn), 40)
                    self.assertEqual(set(worn) - set(RAMPS[fac.key]), set())

    def test_two_owners_of_the_same_building_are_tellable_apart(self):
        """The 1x reading, kept beside the board-scale one above.

        `RowSeparation` holds the armies apart but says nothing about the
        board's flags, and the pair that costs the most is the same one it
        costs on the units: the unowned row against Iron, two greys, which
        meet at 45.0 here (the widest pair, meridian against aurora on the
        base, is 176.2). Measured over the pixels that actually DIFFER
        between two rows of one building, which is a different question from
        the one the 4:1 gate asks — this bounds how far apart the changed
        pixels are, that one bounds how much of the cell changed at all. The
        faction-read pass moved both: the unowned row swapped families, so
        far more pixels differ and each of them by less.
        """
        for bid in sorted(terrain.PROPERTY):
            rows = {f.key: self._sprite(bid, f).image for f in FACTIONS}
            for i, a in enumerate(FACTIONS):
                for b in FACTIONS[i + 1 :]:
                    pa, pb = rows[a.key].load(), rows[b.key].load()
                    w, h = rows[a.key].size
                    seen = [
                        (pa[x, y], pb[x, y])
                        for y in range(h)
                        for x in range(w)
                        if pa[x, y] != pb[x, y]
                    ]
                    apart = sum(
                        sum((c[k] - d[k]) ** 2 for k in range(3)) ** 0.5
                        for c, d in seen
                    ) / len(seen)
                    with self.subTest(building=bid, pair=(a.key, b.key)):
                        self.assertGreater(apart, 40.0)

    # The board draws a 64px tile into a 16px cell — 4:1, NEAREST — and an
    # owner is read there, not in the atlas. The measure is the mean RGB
    # distance between two rows of ONE property over that downsample, taken
    # over every pixel either row draws (the shared transparent surround is
    # not evidence of anything). The units answer the same measure at 34-95,
    # so a property is allowed to say less than an army does and no less than
    # this.
    #
    # The properties pass left the faction read at 12-27 here, and the pair it
    # left worst is the pair whose colours are both greys: the unowned row and
    # Iron, 12.4 on the airport. Owned rows now differ by more than which
    # dark roof they wear — the paint comes down the front of the building
    # (`buildings.ROOF_TRIM`) — and the unowned row is built out of cool
    # concrete against the owned rows' warm masonry, which is the one thing
    # Iron's own grey cannot be told from by value.
    #
    # This measure is phase-sensitive: 4:1 NEAREST keeps one row in four, so
    # moving a building up or down the cell changes which of its rows the
    # board ever draws. Standing the airport and the port on the shared
    # ground line (`terrain.PROPERTY_ANCHOR`) moved them 15 and 9 rows and
    # cost them a phase's worth of read — port neutral/Iron 29.0 -> 23.0,
    # airport Iron/verdant 32.6 -> 27.1, the two thinnest margins on the
    # board today. Recolouring work should aim at those two pairs first.
    BOARD_ZOOM = 4
    OWNERS_APART = 25.0
    # Neutral against Iron is a grey against a grey and buys its margin with
    # hue alone, so it is held to a floor of its own rather than to the bar
    # every coloured pair clears.
    NEUTRAL_IRON_APART = 20.0
    # Gold against the two rows it sits BETWEEN. The bar above was set by four
    # hues spread around the wheel; a fifth one lands between red and green by
    # construction, and there is nowhere on a property for it to buy the
    # distance back — a property shows an owner in ~27 of the 109 pixels the
    # board samples, so the pair distance is the roof rungs' own and no
    # ladder can move it far. Measured over the whole hue and ladder space
    # the row's other gates leave open, gold's worst pair peaks at 23.2; the
    # shipped hue reads 23.8 / 20.5 (hq, against meridian and verdant),
    # 31.6 / 20.8 (city), 32.9 / 24.7 (base), and clears the full bar on the
    # airport and the port. Against the three rows it is NOT between —
    # aurora, iron, neutral — it clears by 27.1 to 63.1 and is held to the
    # bar. So this is the same shape as the neutral/Iron floor: a pair whose
    # margin cannot be bought where the others buy theirs.
    GOLD_NEIGHBOURS_APART = 20.0
    GOLD_NEIGHBOURS = ({"gold", "meridian"}, {"gold", "verdant"})

    def _board_cell(self, tid: str, fac):
        """One property tile as the board samples it: 4:1, nearest."""
        tile = terrain.tile(tid, fac).convert("RGBA")
        size = (tile.width // self.BOARD_ZOOM, tile.height // self.BOARD_ZOOM)
        return tile.resize(size, Image.NEAREST)

    def test_two_owners_are_tellable_apart_at_the_boards_own_scale(self):
        for tid in sorted(terrain.PROPERTY):
            rows = {f.key: self._board_cell(tid, f) for f in FACTIONS}
            for i, a in enumerate(FACTIONS):
                for b in FACTIONS[i + 1 :]:
                    pa, pb = rows[a.key].load(), rows[b.key].load()
                    w, h = rows[a.key].size
                    drawn = [
                        (pa[x, y], pb[x, y])
                        for y in range(h)
                        for x in range(w)
                        if pa[x, y][3] or pb[x, y][3]
                    ]
                    apart = sum(
                        sum((c[k] - d[k]) ** 2 for k in range(3)) ** 0.5
                        for c, d in drawn
                    ) / len(drawn)
                    pair = {a.key, b.key}
                    bar = self.OWNERS_APART
                    if pair == {"neutral", "iron"}:
                        bar = self.NEUTRAL_IRON_APART
                    elif pair in self.GOLD_NEIGHBOURS:
                        bar = self.GOLD_NEIGHBOURS_APART
                    with self.subTest(property=tid, pair=(a.key, b.key)):
                        self.assertGreater(apart, bar)

    def test_a_property_never_takes_the_rim_step_a_unit_keys_off(self):
        """`BUILDING_TOP_SLOT`: the band over the top plane is the army's."""
        rim = {ramp[-1] for ramp in RAMPS.values()}
        rim |= {
            palette.MASONRY_RAMP[-1],
            palette.CONCRETE_RAMP[-1],
            palette.MACHINE_RAMP[-1],
        }
        for bid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                with self.subTest(building=bid, faction=fac.key):
                    drawn = set(opaque_pixels(self._sprite(bid, fac).image))
                    self.assertEqual(drawn & rim, set())


class PropertyOverlays(unittest.TestCase):
    """A property is a building on transparent ground, not a tile of grass.

    Design review rounds 4 and 5: the five property columns baked the plains
    green into their cells, so a city on road or beach wore a green square.
    They now carry the building, its base plate and its solid shadow, and
    nothing else; the board paints the ground under them.
    """

    def _cell(self, tid: str, fac) -> Image.Image:
        return terrain.tile(tid, fac).convert("RGBA")

    def test_only_the_property_columns_carry_transparency(self):
        img = atlas.build_terrain_atlas()
        px = img.load()
        for col, tid in enumerate(terrain.TERRAIN_ORDER):
            clear = sum(
                1
                for y in range(img.height)
                for x in range(col * CELL, col * CELL + CELL)
                if px[x, y][3] == 0
            )
            with self.subTest(tile=tid):
                if tid in terrain.PROPERTY:
                    self.assertGreater(clear, 0)
                else:
                    self.assertEqual(clear, 0)

    def test_a_property_leaves_its_corners_to_the_ground(self):
        # The corners are the ground plate's, wherever the building stands.
        for tid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                px = self._cell(tid, fac).load()
                for corner in (
                    (0, 0),
                    (CELL - 1, 0),
                    (0, CELL - 1),
                    (CELL - 1, CELL - 1),
                ):
                    with self.subTest(tile=tid, faction=fac.key, corner=corner):
                        self.assertEqual(px[corner][3], 0)

    def test_property_cells_carry_no_semi_transparent_pixel(self):
        # The units' rule, held for the terrain sheet's buildings too: a soft
        # alpha edge is a halo on the board and a grey stain in the cut-in.
        for tid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                with self.subTest(tile=tid, faction=fac.key):
                    cell = self._cell(tid, fac)
                    raw = cell.tobytes()
                    self.assertEqual({raw[i] for i in range(3, len(raw), 4)}, {0, 255})

    def _shadow(self, tid: str, fac) -> list[tuple[int, int]]:
        px = self._cell(tid, fac).load()
        return [
            (x, y)
            for y in range(CELL)
            for x in range(CELL)
            if px[x, y] == (*terrain.SHADOW, 255)
        ]

    def test_the_shadow_is_opaque_and_solid(self):
        # Both parities, so it cannot go back to a 1px checkerboard unnoticed
        # — see CastShadow for the measurement that retired that shape.
        for tid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                with self.subTest(tile=tid, faction=fac.key):
                    shadow = self._shadow(tid, fac)
                    self.assertGreater(len(shadow), 0)
                    self.assertEqual({(x + y) % 2 for x, y in shadow}, {0, 1})

    # CastShadow's tolerance is 0.15 over a whole army; a building's shadow is
    # a ~130px band two pixels wide, so at 4:1 the sampling grid still lands on
    # more of one diagonal than another and solid comes in at 0.69-1.38. That
    # residual is the band's SHAPE. The checkerboard's was structure: 0.00-2.76
    # at 4:1 and 0.00-2.00 at 2:1, where a phase draws none of the shadow at
    # all. Solid measures 0.97-1.06 at 2:1 and exactly 1.0 at 1:1.
    RUNG_TOLERANCE = 0.45

    def test_every_rung_draws_the_same_share_of_the_shadow(self):
        for tid in sorted(terrain.PROPERTY):
            shadow = self._shadow(tid, FACTIONS[1])
            for ratio in (4, 2, 1):
                for phase_y in range(ratio):
                    for phase_x in range(ratio):
                        drawn = sum(
                            1
                            for x, y in shadow
                            if x % ratio == phase_x and y % ratio == phase_y
                        )
                        share = drawn * ratio * ratio / len(shadow)
                        with self.subTest(
                            tile=tid, ratio=ratio, phase=(phase_x, phase_y)
                        ):
                            self.assertAlmostEqual(
                                share, 1.0, delta=self.RUNG_TOLERANCE
                            )

    def test_every_property_stands_on_one_ground_line(self):
        # Five buildings on one board share one grid, so they have to share
        # the row they stand on. The airport used to bottom out at 45 and the
        # port at 51 against the other three's 60, which read as two of the
        # five hovering over the tile the other three sit on. The row is
        # pinned, not merely agreed: a shared line that drifts up the cell
        # would still pass a five-way equality.
        lines = {}
        for tid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                px = self._cell(tid, fac).load()
                rows = [y for y in range(CELL) for x in range(CELL) if px[x, y][3] != 0]
                lines[(tid, fac.key)] = max(rows)
        self.assertEqual(set(lines.values()), {60}, lines)

    def test_the_tile_and_the_exported_cell_place_one_building(self):
        # The atlas tile is the exported iso_buildings cell plus a shadow, so
        # the two surfaces cannot drift into placing the same building twice.
        for tid in sorted(terrain.PROPERTY):
            for fac in FACTIONS:
                tile_px = self._cell(tid, fac).load()
                cell_px = atlas.building_cell(tid, fac).convert("RGBA").load()
                with self.subTest(tile=tid, faction=fac.key):
                    for y in range(CELL):
                        for x in range(CELL):
                            if cell_px[x, y][3] == 0:
                                continue
                            self.assertEqual(tile_px[x, y], cell_px[x, y])


class PropertySilhouette(unittest.TestCase):
    """`Silhouette`'s reading, asked of the five properties.

    A property is picked off a full map by its MASS, exactly as a unit is,
    and until 2026-08-24 nothing measured it: read at rung 1 (4:1, the rung a
    match is played at) the three land properties were one shape wearing
    three labels — city/hq 0.729, base/hq 0.713, city/base 0.671 — and the
    hq, the tile a match is won on, topped out THREE SOURCE ROWS over a city,
    which is under one board texel at 4:1 and so no step at all. The hq/city
    remass answers both — 0.591, 0.585 and 0.536, in that order — and puts
    the hq's top row six source rows over the city's and twenty-two over the
    base's.

    Two readings, on the building alone: the cast shadow is the same
    silhouette offset down-right, so counting it in doubles every shape's
    area with a copy of itself and washes the comparison out.
    """

    RUNG_1 = 4  # source pixels per screen pixel at the board's own zoom
    IOU_BAR = 0.62
    # One board texel at rung 1, in source rows: the hq does not merely edge
    # the others out, it stands a whole texel of the sampled cell above them.
    HQ_LEAD = RUNG_1
    # Named debt, not tolerance, in `Silhouette.KNOWN_CLONES`'s style: a pair
    # listed here fails the bar and is asserted to keep failing, so paying one
    # off is a visible diff. These three are the water/air group — airport
    # 0.781 against the base and 0.862 against the port, base/port 0.689 —
    # which the hq/city pass did not touch: the three of them are one low
    # shed apiece and the next remass owes them a mass each. Every pair
    # either of the two this pass DID touch is in clears the bar; the worst
    # of those is airport/city at 0.611.
    KNOWN_CLONES: frozenset[frozenset[str]] = frozenset(
        {
            frozenset(("airport", "base")),
            frozenset(("airport", "port")),
            frozenset(("base", "port")),
        }
    )

    def _drawn(self, tid: str) -> Image.Image:
        """One property cell with its cast shadow knocked out."""
        cell = terrain.tile(tid, FACTIONS[0]).convert("RGBA")
        px = cell.load()
        for y in range(CELL):
            for x in range(CELL):
                if px[x, y][:3] == terrain.SHADOW:
                    px[x, y] = (0, 0, 0, 0)
        return cell

    def _silhouette(self, tid: str) -> set[tuple[int, int]]:
        small = self._drawn(tid).resize(
            (CELL // self.RUNG_1, CELL // self.RUNG_1), Image.NEAREST
        )
        px, n = small.load(), CELL // self.RUNG_1
        return {(x, y) for y in range(n) for x in range(n) if px[x, y][3] > 200}

    def _top_row(self, tid: str) -> int:
        px = self._drawn(tid).load()
        return min(y for y in range(CELL) for x in range(CELL) if px[x, y][3] > 200)

    def test_no_two_properties_share_a_silhouette_on_the_board(self):
        order = sorted(terrain.PROPERTY)
        shapes = {tid: self._silhouette(tid) for tid in order}
        for i, a in enumerate(order):
            for b in order[i + 1 :]:
                iou = len(shapes[a] & shapes[b]) / len(shapes[a] | shapes[b])
                with self.subTest(pair=(a, b)):
                    if frozenset((a, b)) in self.KNOWN_CLONES:
                        self.assertGreater(iou, self.IOU_BAR)  # debt still real
                    else:
                        self.assertLessEqual(iou, self.IOU_BAR)

    def test_the_hq_stands_a_board_texel_over_every_other_property(self):
        hq_top = self._top_row("hq")
        for tid in sorted(terrain.PROPERTY - {"hq"}):
            with self.subTest(property=tid):
                self.assertGreaterEqual(self._top_row(tid) - hq_top, self.HQ_LEAD)


if __name__ == "__main__":
    unittest.main()
