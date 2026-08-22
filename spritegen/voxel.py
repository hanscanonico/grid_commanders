"""A tiny dimetric voxel engine — the whole sheet's look lives here.

Projection matches the PixVoxel art the game shipped with: screen
x = (vx - vy) * 2, y = (vx + vy) - vz * 2, each voxel drawn as a 4x4 cube
sprite overlapping its neighbours by 2px, which is what produces the classic
2px-run stair edges. +x runs toward screen lower-right, +y toward screen
lower-left (units face +y), +z is up.

Two renderers share that geometry. `render_indexed` draws units: one flat
ramp slot per visible plane, ambient occlusion and the ground contact
charged as whole slot steps, 1px outlines read off the depth and normal
planes (dark away from the sun, LIGHT into it — see `_selective_outline` and
docs/outlines.md), and a material id emitted beside every pixel. `render` is
the older shading path — three computed face tones, fractional occlusion, a
two-tone dither on tops broad enough to carry one, and a contour in one
deliberate tone per material — and terrain and buildings still draw with it.
All of it is deterministic: no RNG anywhere.

Both renderers also have a `*_gbuffer` form that hands back the depth and
normal planes behind the picture as well as the picture — see
`spritegen/gbuffer.py`. `render` and `render_indexed` are those forms with the
extra planes dropped, so the colour they emit is unchanged to the byte.
"""

from __future__ import annotations

from dataclasses import dataclass

from PIL import Image

from .gbuffer import (
    DEPTH_EMPTY,
    N_LEFT,
    N_NONE,
    N_RIGHT,
    N_TOP,
    GBuffer,
    Plane,
    convex_edges,
    edge_mask,
    voxel_depth,
)
from .palette import (
    DITHERED,
    GLOSSY,
    IRON_SLOT_CEILING,
    MID_ACCENT,
    MID_CONTOUR,
    MID_EMPTY,
    MID_FACTION,
    MID_GUNMETAL,
    RGB,
    S_CONTOUR,
    S_RIM,
    S_TOP,
    S_UNDER,
    SLOTS,
    Faction,
    Ramp,
    darken,
    h01,
    lighten,
    luminance,
    material_slot,
    mix,
    ramp_for,
    resolve,
    shade,
)


class Model:
    """Sparse voxel set: (x, y, z) -> material name."""

    def __init__(self) -> None:
        self.vox: dict[tuple[int, int, int], str] = {}

    def set(self, x: int, y: int, z: int, m: str) -> None:
        self.vox[(x, y, z)] = m

    def unset(self, x: int, y: int, z: int) -> None:
        self.vox.pop((x, y, z), None)

    def box(self, x0: int, x1: int, y0: int, y1: int, z0: int, z1: int, m: str) -> None:
        """Filled box, inclusive bounds (order-insensitive)."""
        for x in range(min(x0, x1), max(x0, x1) + 1):
            for y in range(min(y0, y1), max(y0, y1) + 1):
                for z in range(min(z0, z1), max(z0, z1) + 1):
                    self.vox[(x, y, z)] = m

    def clear(self, x0: int, x1: int, y0: int, y1: int, z0: int, z1: int) -> None:
        for x in range(min(x0, x1), max(x0, x1) + 1):
            for y in range(min(y0, y1), max(y0, y1) + 1):
                for z in range(min(z0, z1), max(z0, z1) + 1):
                    self.vox.pop((x, y, z), None)

    def chamfer(self, x0: int, x1: int, y0: int, y1: int, z0: int, z1: int) -> None:
        """Knock the four corner columns off a box between z0..z1.

        Turns a slab into an octagonal mass — the cheap trick that keeps
        turrets, cabs and roofs from reading as pure cubes.
        """
        for z in range(min(z0, z1), max(z0, z1) + 1):
            for cx, cy in ((x0, y0), (x0, y1), (x1, y0), (x1, y1)):
                self.vox.pop((cx, cy, z), None)


def _face_pixels(sx: int, sy: int, k: int = 1) -> dict[str, list[tuple[int, int]]]:
    """The 4k x 4k cube sprite at screen anchor (sx, sy): top / left / right.

    `k` is the DENSITY: how many pixels one voxel edge is drawn at, over the
    shipped 4x4 cube. It is the only geometric knob in the engine, and it is
    what a 128px cell would be emitted through (k=2). It scales the drawing,
    not the model — see `tests/measure_128.py` and `docs/density_128.md` for
    what that distinction costs.

    The top face is the dimetric rhombus: 2k rows, row j spanning
    2k-1-j .. 2k+j, so it widens 2, 4, ... 4k. The two side faces are the
    2k x 2k blocks under it. At k=1 that is the shipped 4x4 cube exactly.
    """
    top: list[tuple[int, int]] = []
    for j in range(2 * k):
        top.extend((sx + i, sy + j) for i in range(2 * k - 1 - j, 2 * k + j + 1))
    left: list[tuple[int, int]] = []
    right: list[tuple[int, int]] = []
    for j in range(2 * k, 4 * k):
        left.extend((sx + i, sy + j) for i in range(2 * k))
        right.extend((sx + i, sy + j) for i in range(2 * k, 4 * k))
    return {"top": top, "left": left, "right": right}


# Which normal id each face of the cube sprite carries, so the rasteriser can
# stamp geometry beside colour without repeating the projection's conventions.
_FACE_NORMAL = {"top": N_TOP, "left": N_LEFT, "right": N_RIGHT}

Anchors = dict[tuple[int, int, int], tuple[int, int]]

# Up, left, down, right — the four edges an outline is measured across. Up and
# left are the lit ones; down and right face the ground the unit stands on.
UP, LEFT, DOWN, RIGHT = (0, -1), (-1, 0), (0, 1), (1, 0)

# Outlines are per PIXEL, off the G-buffer, not a band per part. The lit pair
# (up and left) is where the sun is, and it is the pair a SELECTIVE outline
# lightens instead of darkening — see `_selective_outline` and docs/outlines.md.
_LIT_STEPS = (UP, LEFT)

# How big a 4-neighbour depth step has to be before it is a real occlusion
# rather than the depth gradient a flat plane already carries in this
# projection. `gbuffer.edge_mask` documents why 2 is the floor; the unit path
# uses that default so the silhouette and the self-overlap fall out of one
# reading of one buffer.
EDGE_THRESHOLD = 2

# How far above the plane behind it a sel-out pixel is drawn, in ramp slots,
# before the material's own ceiling clamps it. Two steps is what makes a lit
# boundary read as a LINE on a side plane; on a top plane already at its
# ceiling it clamps to that plane's own slot, so the lit edge simply carries no
# line at all — which is the other half of what selective outlining means.
SEL_OUT_LIFT = 1


def _bounds(model: Model, k: int = 1) -> tuple[Anchors, int, int, int, int]:
    """Screen anchors per voxel plus the crop the sprite needs (2px margin, so
    a 1px outline and the passes after it always have a pixel to write), at
    density `k`."""
    anchors: Anchors = {}
    for x, y, z in model.vox:
        anchors[(x, y, z)] = ((x - y) * 2 * k, ((x + y) - z * 2) * k)
    minx = min(a[0] for a in anchors.values()) - k
    miny = min(a[1] for a in anchors.values()) - k
    w = max(a[0] for a in anchors.values()) + (4 + 2) * k - minx
    h = max(a[1] for a in anchors.values()) + (4 + 2) * k - miny
    return anchors, minx, miny, w, h


@dataclass
class IndexedSprite:
    """A rendered sprite plus the material id behind every pixel.

    The id is what makes a tint a lookup rather than a colour match: material
    1 is the faction's, and nothing else on the sprite moves when a row does.
    """

    image: Image.Image
    materials: bytearray

    def mid(self, x: int, y: int) -> int:
        return self.materials[y * self.image.width + x]


def render_indexed_gbuffer(
    model: Model, faction: Faction, outline: bool = True, k: int = 1
) -> GBuffer:
    """Render a unit out of the indexed ramps: one flat slot per visible plane.

    The old path shades every pixel by arithmetic, so one physical face lands
    on dozens of near-identical colours and no post-hoc quantiser can recover
    the plane structure that was never there. Here a face normal picks a SLOT
    — top, rim, body, shadow, under — and the ramp picks the colour, so a
    sprite costs tens of palette entries and a faction is a ramp swap.
    """
    if not model.vox:
        return _empty_gbuffer(bytearray([MID_EMPTY]))

    anchors, minx, miny, w, h = _bounds(model, k)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    mids = bytearray([MID_EMPTY]) * (w * h)
    ramps: list[Ramp | None] = [None] * (w * h)
    depth = [DEPTH_EMPTY] * (w * h)
    normal = bytearray(w * h)
    # The slot a sel-out pixel would be drawn at, kept per pixel because the
    # ceiling that clamps it is the painting voxel's, not the outline pass's.
    lit_slots = bytearray(w * h)
    # The floor the same voxel answered to, so a dark line cannot dig below
    # the material's own bottom step.
    dark_slots = bytearray(w * h)

    vox = model.vox
    zmin = min(v[2] for v in vox)
    # A lit plane stops at the top slot and the rim alone steps above it, so
    # a light livery material cannot carpet a deck in near-white — the
    # blotching the spec's own post-hoc quantiser produced. Iron stops one
    # lower still: see IRON_SLOT_CEILING.
    faction_cap = IRON_SLOT_CEILING if faction.key == "iron" else S_TOP
    for x, y, z in sorted(vox, key=lambda v: (v[0] + v[1], v[2])):
        mat = vox[(x, y, z)]
        spec = material_slot(mat)
        ramp = ramp_for(mat, faction)
        cap = faction_cap if spec.mid == MID_FACTION else SLOTS - 1
        # A fixed accent is a small part — a lamp, a canopy, a nose cone —
        # and five bands on twenty pixels is palette spent on nothing, so an
        # accent gets shadow / body / top and no rim or under.
        floor = spec.slot - 1 if spec.mid == MID_ACCENT else 0
        cap = min(cap, spec.slot + 1) if spec.mid == MID_ACCENT else cap
        sx, sy = anchors[(x, y, z)]
        sx -= minx
        sy -= miny

        # Ambient occlusion and the ground contact are whole slot steps: a
        # fractional darkening is exactly the per-pixel drift this rewrite
        # exists to delete.
        top_steps = 0
        if (x - 1, y, z + 1) in vox or (x, y - 1, z + 1) in vox:
            top_steps += 1
        if (x + 1, y, z + 1) in vox or (x, y + 1, z + 1) in vox:
            top_steps += 1
        # The rim is a lit plane's LEADING EDGE — the last voxel before the
        # top surface falls away toward the camera, on either camera-facing
        # side. The front corner alone (both sides open) is one voxel per
        # mass, which is why half the land group carried under 3% of its
        # pixels in the bright band the terrain ceiling reserves for units
        # (round-5 verdict): a low flat-topped hull has exactly one corner
        # and a tall one has none to spare. An edge is still an edge — an
        # interior top voxel is never rim, so this cannot bloom into
        # brightening the whole plane, and `_despeckle` folds away the lone
        # pixels a notch leaves.
        top_lit = top_steps == 0 and (x, y, z + 1) not in vox
        rim = top_lit and ((x + 1, y, z) not in vox or (x, y + 1, z) not in vox)
        under = 1 if z == zmin else 0
        left_steps = under + (1 if (x, y + 1, z + 1) in vox else 0)
        right_steps = under + (1 if (x + 1, y, z + 1) in vox else 0)

        offsets = {
            "top": 1 + (1 if rim else 0) - top_steps,
            "left": -left_steps,
            "right": -1 - right_steps,
        }
        vdepth = voxel_depth(x, y, z)
        for face, pixels in _face_pixels(sx, sy, k).items():
            # The rim is the one place a ceiling gives way, and it gives way
            # to the top of the ramp: it is an edge one voxel deep, and it is
            # where Iron's light-steel flash lives. Lifting Iron only to its
            # capped top plane's next step left the darkest faction with no
            # pixel at all in the band above L200 that the terrain ceiling
            # reserves for units.
            lifts_rim = rim and face == "top" and spec.mid == MID_FACTION
            ceiling = S_RIM if lifts_rim else cap
            slot = min(ceiling, max(floor, spec.slot + offsets[face]))
            slot = max(0, min(SLOTS - 1, slot))
            c = ramp[slot]
            nid = _FACE_NORMAL[face]
            lit = min(ceiling, SLOTS - 1, slot + SEL_OUT_LIFT)
            dark = max(0, min(SLOTS - 1, floor))
            for ix, iy in pixels:
                px[ix, iy] = (c[0], c[1], c[2], 255)
                idx = iy * w + ix
                mids[idx] = spec.mid
                ramps[idx] = ramp
                lit_slots[idx] = lit
                dark_slots[idx] = dark
                # Overdraw settles the geometry the same way it settles the
                # colour: the painter's last write owns the pixel.
                depth[idx] = vdepth
                normal[idx] = nid

    dplane = Plane(w, h, depth)
    nplane = Plane(w, h, normal)
    keep: bytearray | None = None
    if outline:
        keep = _selective_outline(
            img, mids, ramps, lit_slots, dark_slots, dplane, nplane
        )
    _despeckle(img, mids, keep)
    # The outline and the despeckle move colour, never geometry: every pixel
    # they touch already belonged to a face, and keeps that face's depth and
    # normal here.
    return GBuffer(img, dplane, nplane, Plane(w, h, mids))


def render_indexed(
    model: Model, faction: Faction, outline: bool = True, k: int = 1
) -> IndexedSprite:
    """`render_indexed_gbuffer` without the geometry planes."""
    g = render_indexed_gbuffer(model, faction, outline, k)
    return IndexedSprite(g.rgba, bytearray(g.material.values))


def _empty_gbuffer(mids: bytearray) -> GBuffer:
    """The 1x1 transparent buffer an empty model renders to."""
    img = Image.new("RGBA", (1, 1), (0, 0, 0, 0))
    return GBuffer(
        img,
        Plane(1, 1, [DEPTH_EMPTY]),
        Plane(1, 1, bytearray([N_NONE])),
        Plane(1, 1, mids),
    )


_NEIGHBOURS4 = ((0, -1), (-1, 0), (1, 0), (0, 1))


def _despeckle(
    img: Image.Image, mids: bytearray, keep: bytearray | None = None
) -> None:
    """Fold every lone pixel into the plane it is most like.

    A pixel sharing its colour with none of its four orthogonal neighbours
    is dirt at cut-in scale and shimmer at zoom-out (sprite fix spec, section
    2, rule 3). Stair corners and the outline's own diagonals leave a
    handful per sprite, so they are snapped to the neighbouring colour
    closest in value — the plane they were nearly part of already.

    In place and in scan order, not from a snapshot: a snapshot updates two
    lone neighbours at once and can strand each on the colour the other just
    left, so it needs a second pass to settle. Snapping against the live
    image settles in one, because a pixel that was snapped to a neighbour
    has given that neighbour a match and neither can move again.

    `keep` is the silhouette's own dark line, and it is exempt: a 1px outline
    down a stair edge is diagonal, so it is lone by this rule everywhere and
    folding it away is how an outline dots out. Every other pass answers for
    itself — an interior overlap line or a sel-out pixel with four unlike
    neighbours is dirt like any other, and goes.
    """
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            here = px[x, y]
            if here[3] != 255 or (keep is not None and keep[y * w + x]):
                continue
            neigh = []
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < w and 0 <= ny < h:
                    c = px[nx, ny]
                    if c[3] == 255:
                        neigh.append((c, ny * w + nx))
            if not neigh or any(c[:3] == here[:3] for c, _ in neigh):
                continue
            level = luminance(here[:3])
            best, src = min(neigh, key=lambda n: abs(luminance(n[0][:3]) - level))
            px[x, y] = best
            mids[y * w + x] = mids[src]


def _selective_outline(
    img: Image.Image,
    mids: bytearray,
    ramps: list[Ramp | None],
    lit_slots: bytearray,
    dark_slots: bytearray,
    depth: Plane,
    normal: Plane,
) -> bytearray:
    """1px outlines read off the G-buffer, dark away from the sun and light into it.

    Every line here is one pixel wide and lies INSIDE the silhouette: the alpha
    never moves, and neither does the interior the model drew — which is what
    the old band cost. `edge_mask` finds the pixels in one reading of the depth
    plane, because in this projection a silhouette and a self-overlap are the
    same fact: a 4-neighbour whose depth breaks the step a continuous surface
    can carry (`EDGE_THRESHOLD`).

    What each of those pixels becomes is decided by WHERE the break is, in one
    fixed order, so a pixel is never both dark and light:

    - a break toward the ground (down or right) is the silhouette read against
      terrain, and takes the faction's own S0 — never a shared black;
    - a break against a NEARER surface is a self-overlap, and only the FAR side
      draws, at S1: the turret keeps its shape and the hull behind it takes the
      line, which is what stops one mass reading as two outlined stickers;
    - a break toward the sun (up or left) is the lit side, and it LIGHTENS
      instead: the pixel steps `SEL_OUT_LIFT` slots up its own ramp, clamped by
      the ceiling the painting voxel already answered to. That is selective
      outlining, and it is also why iron — capped at S3 — quietly draws no lit
      line rather than a bright one it has no business wearing.

    Convex creases (`convex_edges`) get the same lift where a lit face meets
    another face over a ridge, so a chamfered turret or a raised deck carries a
    1px highlight along its top edge. Concave gutters get nothing.

    One line here is not geometry at all: `_interior_contour`, S0 between two
    materials whose value step is too small to read. A barrel lying along a
    hull is one continuous surface — no depth break, nothing for `edge_mask`
    to find — and on a light Iron hull it disappears into it. Dropping that
    pass with the band took the sheet from 306 mushy faction/gunmetal contacts
    to 1,390, so it stays, and it stays last: the hull gives up the pixel, the
    fitting keeps every pixel it was drawn with.

    Nothing about the alpha, the depth or the normal moves here: this pass
    recolours pixels the rasteriser already drew, so the G-buffer behind the
    picture still describes the model rather than the outline.

    Returns the mask of the SILHOUETTE's dark pixels, which `_despeckle` then
    leaves alone. Along a stair edge that line runs diagonally, so its pixels
    can differ from all four orthogonal neighbours and the despeckle would
    fold half of them back into the plane — the dotted outline of round 9,
    rebuilt one pass later. They are the pixels spec item 10 exempts anyway:
    every one of them has a transparent neighbour.
    """
    px = img.load()
    w, h = img.size
    edges = edge_mask(depth, EDGE_THRESHOLD)
    convex = convex_edges(normal)
    paint: list[tuple[int, int, int]] = []
    silhouette = bytearray(w * h)

    for y in range(h):
        for x in range(w):
            i = y * w + x
            if ramps[i] is None:
                continue
            kind = _outline_kind(x, y, edges, convex, depth, normal)
            if kind is None:
                continue
            if kind == _LINE_LIT:
                slot = lit_slots[i]
            elif kind == _LINE_DARK:
                # The silhouette is S0's absolutely, whatever material meets
                # the ground there — round 9's precedence, kept.
                silhouette[i] = 1
                slot = S_CONTOUR
            else:
                # An INTERIOR line stops at the material's own floor instead:
                # an accent is a lamp or a canopy drawn on tens of pixels, and
                # a self-overlap inside one is a crease in the fitting, not a
                # hole punched through it.
                slot = max(dark_slots[i], S_UNDER)
            paint.append((x, y, slot))

    for x, y, slot in paint:
        i = y * w + x
        ramp = ramps[i]
        c = ramp[slot]
        px[x, y] = (c[0], c[1], c[2], 255)
        if slot <= S_UNDER:
            mids[i] = MID_CONTOUR

    for x, y in _interior_contour(px, mids, w, h):
        i = y * w + x
        c = ramps[i][S_CONTOUR]
        px[x, y] = (c[0], c[1], c[2], 255)
        mids[i] = MID_CONTOUR
    return silhouette


_INTERIOR_STEP = 36.0  # under ~2 ramp slots of value


def _interior_contour(px, mids: bytearray, w: int, h: int) -> list[tuple[int, int]]:
    """The faction pixels that meet a gunmetal fitting they cannot be told from.

    The hull gives up the pixel, never the feature: a gunmetal barrel on a
    light Iron hull gets its line out of the hull's own ramp, so the thing
    that identifies the unit keeps every pixel it was drawn with.
    """
    out: list[tuple[int, int]] = []
    for yy in range(h):
        for xx in range(w):
            if px[xx, yy][3] != 255 or mids[yy * w + xx] != MID_FACTION:
                continue
            here = luminance(px[xx, yy][:3])
            for nx, ny in ((xx + 1, yy), (xx, yy + 1), (xx - 1, yy), (xx, yy - 1)):
                if not (0 <= nx < w and 0 <= ny < h) or px[nx, ny][3] != 255:
                    continue
                if mids[ny * w + nx] != MID_GUNMETAL:
                    continue
                if abs(here - luminance(px[nx, ny][:3])) < _INTERIOR_STEP:
                    out.append((xx, yy))
                    break
    return out


# A dither is only a texture where there is a surface to spread it over. Under
# that area it is per-pixel noise: at the 4:1 board downsample a speckled 4px
# roof edge is a chewed edge, not a material (Gerstner's rule that uniform
# dither is harmful at sprite sizes). The threshold is measured in PAINTED TOP
# PIXELS of one contiguous same-material plane, not in voxels — a 12-voxel
# sawtooth ridge and a 12-voxel slab are the same voxel count and nothing like
# the same surface — and 96px is the roof plane of the airport hangar, the HQ
# fort and the city towers, the only three broad enough to read as texture.
DITHER_MIN_TOP_AREA = 96  # px of contiguous flat top, ~a 12x8 roof plane
DITHER_STEP = 0.06  # the one step under the face tone the dither drops to


def _broad_flat_tops(
    vox: dict[tuple[int, int, int], str], k: int = 1
) -> set[tuple[int, int, int]]:
    """The voxels whose exposed top belongs to a plane big enough to dither.

    A plane is a 4-connected run of same-material voxels at one z whose tops
    are all open to the sky; its area is the union of the top faces they paint.
    """
    tops = {v for v in vox if (v[0], v[1], v[2] + 1) not in vox and vox[v] in DITHERED}
    seen: set[tuple[int, int, int]] = set()
    broad: set[tuple[int, int, int]] = set()
    for start in sorted(tops):
        if start in seen:
            continue
        mat = vox[start]
        seen.add(start)
        stack = [start]
        plane = []
        while stack:
            x, y, z = stack.pop()
            plane.append((x, y, z))
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (x + dx, y + dy, z)
                if n in tops and n not in seen and vox[n] == mat:
                    seen.add(n)
                    stack.append(n)
        area: set[tuple[int, int]] = set()
        for x, y, z in plane:
            area.update(_face_pixels((x - y) * 2 * k, ((x + y) - z * 2) * k, k)["top"])
        if len(area) >= DITHER_MIN_TOP_AREA * k * k:
            broad.update(plane)
    return broad


# What a pixel's line is, before the material says which slot draws it.
_LINE_DARK, _LINE_OVERLAP, _LINE_LIT = 0, 1, 2


def _outline_kind(
    x: int,
    y: int,
    edges: Plane,
    convex: Plane,
    depth: Plane,
    normal: Plane,
) -> int | None:
    """Which line this pixel carries, or None if it carries none.

    Stated in one order and one order only, so no pixel is both dark and
    light: the ground-facing silhouette outranks a self-overlap, and a
    self-overlap outranks the lit side.
    """
    w, h = depth.width, depth.height
    if edges.at(x, y):
        d = depth.at(x, y)
        lit = False
        occluded = False
        for step in _NEIGHBOURS4:
            nx, ny = x + step[0], y + step[1]
            if not (0 <= nx < w and 0 <= ny < h) or depth.at(nx, ny) == DEPTH_EMPTY:
                if step in _LIT_STEPS:
                    lit = True
                else:
                    return _LINE_DARK
                continue
            # Only the FAR side of a self-overlap draws: the near mass keeps
            # its own shape, the one behind it takes the line.
            if depth.at(nx, ny) - d > EDGE_THRESHOLD:
                occluded = True
        if occluded:
            return _LINE_OVERLAP
        return _LINE_LIT if lit else None
    # A ridge the sun is on: the top face is the only one this light reaches
    # over a crease, so only it carries the 1px highlight.
    if convex.at(x, y) and normal.at(x, y) == N_TOP:
        return _LINE_LIT
    return None


def render_gbuffer(model: Model, faction: Faction, outline: bool = True) -> GBuffer:
    """`render`, with the depth and normal planes behind the picture kept.

    The shaded path has no material ids, so `material` comes back empty.
    """
    if not model.vox:
        return _empty_gbuffer(bytearray([MID_EMPTY]))

    anchors, minx, miny, w, h = _bounds(model)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    depths = [DEPTH_EMPTY] * (w * h)
    normals = bytearray(w * h)
    vox = model.vox
    # Which material painted each pixel, for the contour below. The painter's
    # last write owns it, exactly as it owns the colour.
    mats: list[str | None] = [None] * (w * h)
    broad = _broad_flat_tops(vox)
    zmin = min(v[2] for v in vox)
    zmax = max(v[2] for v in vox)
    zspan = max(1, zmax - zmin)
    order = sorted(vox, key=lambda v: (v[0] + v[1], v[2]))
    for x, y, z in order:
        mat = vox[(x, y, z)]
        base = resolve(mat, faction)
        gloss = mat in GLOSSY
        sx, sy = anchors[(x, y, z)]
        sx -= minx
        sy -= miny
        faces = _face_pixels(sx, sy)

        # -- ambient occlusion ------------------------------------------------
        # Top face: shadowed by walls behind it and overhangs beside it.
        ao_top = 1.0
        if (x - 1, y, z + 1) in vox or (x, y - 1, z + 1) in vox:
            ao_top *= 0.80
        if (x + 1, y, z + 1) in vox or (x, y + 1, z + 1) in vox:
            ao_top *= 0.86
        if (x - 1, y - 1, z + 1) in vox:
            ao_top *= 0.93
        # Rim light on unshadowed front-corner tops — the crisp bright edge
        # facing the camera.
        rim = (
            ao_top == 1.0
            and (x + 1, y, z) not in vox
            and (x, y + 1, z) not in vox
            and (x, y, z + 1) not in vox
        )
        # Side faces: darkened under an overhang one up and one out.
        ao_right = 0.78 if (x + 1, y, z + 1) in vox else 1.0
        ao_left = 0.82 if (x, y + 1, z + 1) in vox else 1.0
        # Contact occlusion where the model meets the ground, and a soft
        # vertical gradient so tall masses darken toward their base — the
        # extra value step that keeps big flat sides from reading flat.
        depth = (zmax - z) / zspan
        grad_left = depth * 0.10 + (0.08 if z == zmin else 0.0)
        grad_right = depth * 0.12 + (0.08 if z == zmin else 0.0)

        vdepth = voxel_depth(x, y, z)
        for face, pixels in faces.items():
            nid = _FACE_NORMAL[face]
            tone = shade(base, face, gloss)
            if face == "top":
                tone = mix(tone, (12, 16, 28), 1 - ao_top) if ao_top < 1.0 else tone
                if rim:
                    tone = lighten(tone, 0.13)
            elif face == "left":
                shade_amt = (1 - ao_left) + grad_left
                if shade_amt > 0:
                    tone = mix(tone, (12, 16, 28), min(0.5, shade_amt))
            elif face == "right":
                shade_amt = (1 - ao_right) + grad_right
                if shade_amt > 0:
                    tone = mix(tone, (12, 16, 28), min(0.55, shade_amt))
            # A dither, not a noise field: one step under the face tone, on
            # half the pixels, and only where the plane is broad enough to
            # read as texture. The old per-pixel jitter spent a colour per
            # amplitude on every top in the model — 203 colours on the aurora
            # airport, most of them one another's neighbours.
            dither = face == "top" and (x, y, z) in broad
            low = darken(tone, DITHER_STEP) if dither else tone
            for ix, iy in pixels:
                c = low if dither and h01(ix, iy, 7) < 0.5 else tone
                px[ix, iy] = (c[0], c[1], c[2], 255)
                idx = iy * w + ix
                depths[idx] = vdepth
                normals[idx] = nid
                mats[idx] = mat

    if outline:
        _prop_outline(img, mats, faction)
    # The outline sits outside the silhouette, so it owns no face and leaves
    # the geometry planes as background there.
    mids = bytearray([MID_EMPTY]) * (w * h)
    return GBuffer(img, Plane(w, h, depths), Plane(w, h, normals), Plane(w, h, mids))


def render(model: Model, faction: Faction, outline: bool = True) -> Image.Image:
    """Render to a tightly-cropped RGBA image (1px border reserved for outline)."""
    return render_gbuffer(model, faction, outline).rgba


# The contour a terrain prop or a building is read against. It is a PARTIAL
# grade — one deliberate tone per material, drawn only where the silhouette
# meets transparency — against the units' heavier per-faction S0 band: a
# building is what an army is read AGAINST, so its edge states the shape
# without keying like a unit's.
#
# 0.55 of the material's own colour puts it a clear step under that material's
# darkest face (the right face is 0.60 of it), so the line reads on every side
# of the mass. The tone is taken from the MATERIAL, not from the shaded pixel
# it borders: averaging the neighbours spent one near-black per lit
# neighbourhood — 30-40 colours a building, none of them separable from the
# next — where one tone per material spends five.
PROP_CONTOUR_DARKEN = 0.55


def _prop_contour(mat: str, faction: Faction) -> RGB:
    return darken(resolve(mat, faction), PROP_CONTOUR_DARKEN)


def _prop_outline(img: Image.Image, mats: list[str | None], faction: Faction) -> None:
    """1px silhouette contour, one deliberate tone per material.

    Where two materials meet along the same edge the darker of their contours
    wins, so the line around a mass is one line rather than a dotted seam of
    two — the same reason the indexed path claims the outer boundary whole.
    """
    px = img.load()
    w, h = img.size
    tones: dict[str, RGB] = {}
    edges: list[tuple[int, int, RGB]] = []
    for yy in range(h):
        for xx in range(w):
            if px[xx, yy][3] != 0:
                continue
            best: RGB | None = None
            for nx, ny in ((xx - 1, yy), (xx + 1, yy), (xx, yy - 1), (xx, yy + 1)):
                if not (0 <= nx < w and 0 <= ny < h) or px[nx, ny][3] != 255:
                    continue
                mat = mats[ny * w + nx]
                if mat is None:
                    continue
                if mat not in tones:
                    tones[mat] = _prop_contour(mat, faction)
                c = tones[mat]
                if best is None or (luminance(c), c) < (luminance(best), best):
                    best = c
            if best is not None:
                edges.append((xx, yy, best))
    for xx, yy, c in edges:
        px[xx, yy] = (c[0], c[1], c[2], 255)


# The cell's vertical landmarks, each stated as a height ABOVE its bottom
# edge: the ground line a land or sea unit stands on, the higher line an
# aircraft hovers at, and the ground its shadow falls on.
GROUND_BOTTOM = 9
AIR_BOTTOM = 20
AIR_SHADOW_BOTTOM = 6


def compose_cell(
    sprite: Image.Image,
    kind: str = "land",
    cell: tuple[int, int] = (64, 64),
    bottom: int | None = None,
    dx: int = 0,
    wake: bool = False,
    shadow: bool = True,
) -> Image.Image:
    """Center a rendered sprite on a transparent atlas cell with its shadow.

    `cell` is (width, height), and every vertical landmark is measured up
    from the cell's BOTTOM edge — the ground line is the bottom of the tile
    the unit occupies. A taller cell therefore adds sky above the sprite and
    moves nothing, which is what lets a silhouette overflow its tile upward.

    Shadow policy (sprite review round 3): land units get a tight hard
    CONTACT shadow — without one they float over the tile — and the airborne
    cue is the shadow's offset and the sky between unit and shadow, not its
    presence: 'air' hovers over a larger ellipse displaced down-right.
    'sea' sits in the water on a displacement shadow with waterline foam;
    `wake` adds the running foam a hull that is mostly under water needs to
    separate from open sea at all (see `_wake`).
    'prop' composes with no shadow (terrain tiles draw their own grounding).

    Altitude is read off the shadow's SIZE and OFFSET, never off its density
    (the round-3 quarter-tone/half-tone pair is superseded — see
    `_shadow_ellipse`): a land unit's hugs the hull, an airborne one is
    larger and displaced down-right with ground showing between. Nothing
    here is semi-transparent — the shadow and every fleck of foam are opaque,
    because partial alpha is a blurred halo at cut-in scale.

    `shadow=False` leaves that cast shadow off, for a surface that draws its
    own ground and its own shadow rather than standing the cell on a tile.

    It SUBTRACTS rather than skips, so the cell is the tile's cell with those
    pixels taken back out and can never be a second opinion on the art. The
    waterline foam is why that matters: it is placed against the composed
    cell's own spans, so a shadow that was never drawn would move the foam.
    """
    cell_w, cell_h = cell
    out = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
    w, h = sprite.size
    if bottom is None:
        bottom = cell_h - (AIR_BOTTOM if kind == "air" else GROUND_BOTTOM)
    x0 = (cell_w - w) // 2 + dx
    y0 = bottom - h

    cast: list[tuple[int, int]] = []
    if kind == "sea":
        # Ships sit IN the water: a flat displacement shading right under
        # the hull instead of a floating blob, then foam at the waterline.
        rx = max(6, int(w * 0.42))
        cast = _shadow_ellipse(out, cell_w // 2 + dx, bottom - 1, rx, max(2, rx // 5))
    elif kind == "air":
        rx = max(6, int(w * 0.30))
        cast = _shadow_ellipse(
            out, cell_w // 2 + dx + 4, cell_h - AIR_SHADOW_BOTTOM, rx, max(2, rx // 3)
        )
    elif kind == "land":
        rx = max(4, int(w * 0.34))
        cast = _shadow_ellipse(out, cell_w // 2 + dx, bottom - 1, rx, max(2, rx // 4))
    place_in_cell(out, sprite, x0, y0)
    if kind == "sea":
        if wake:
            _wake(out, sprite, x0, y0)
        _waterline_foam(out)
    if not shadow:
        _erase_shadow(out, cast)
    return out


def _erase_shadow(img: Image.Image, cast: list[tuple[int, int]]) -> None:
    """Clear the shadow the cell was composed with, leaving all else alone.

    A cast pixel the sprite, the wake or the foam has since painted over is
    no longer shadow and is kept: what comes out is only what is still the
    tone the ellipse wrote there.
    """
    px = img.load()
    for xx, yy in cast:
        if px[xx, yy] == CAST:
            px[xx, yy] = EMPTY


def place_in_cell(cell_img: Image.Image, sprite: Image.Image, x0: int, y0: int) -> None:
    """Composite a sprite into a fixed-size cell, refusing to crop it.

    Pillow clips a paste at the destination edge without complaining, which
    turns a sprite that outgrew its cell into a silently trimmed barrel or
    roof. Overflow is an authoring error, so it stops the build instead.
    """
    cw, ch = cell_img.size
    sw, sh = sprite.size
    if x0 < 0 or y0 < 0 or x0 + sw > cw or y0 + sh > ch:
        raise ValueError(
            f"sprite {sw}x{sh} placed at ({x0}, {y0}) does not fit the "
            f"{cw}x{ch} cell — shorten the model or move it inward"
        )
    cell_img.alpha_composite(sprite, (x0, y0))


FOAM_ROWS = 4
FOAM: RGB = (226, 240, 250)
SHADOW: RGB = (16, 18, 24)
# What a composed shadow pixel and an untouched one look like. One statement,
# because three passes ask: the ellipse writes CAST, the wake may take a CAST
# pixel back, and `_erase_shadow` turns whatever is still CAST into EMPTY.
CAST = (*SHADOW, 255)
EMPTY = (0, 0, 0, 0)
# How far the wake runs on past the stern, in cell columns.
WAKE_TRAIL = 6


def _wake(img: Image.Image, sprite: Image.Image, x0: int, y0: int) -> None:
    """Running foam along an awash hull's whole length, trailing off the stern.

    A ship reads against open sea by its freeboard; a submarine has none, so
    the round-4 legibility measure put the sub last on the sheet. The foam is
    what the water does about the hull it is breaking over, so it follows the
    hull's own underside — the bottom-most sprite pixel of every column —
    rather than a fixed row, and then keeps going up-right past the stern
    along the dimetric hull axis (2 columns per row).

    Opaque, never partial alpha, and drawn ON the water rather than beside it:
    it takes empty pixels and shadow pixels alike, because the foam is what
    the surface does over the displacement shading, not a stipple interleaved
    with it. It ran on the shadow's own parity while the shadow was a 1px
    checkerboard; a solid shadow (see `_shadow_ellipse`) would otherwise have
    swallowed the whole length of it and left the hull nothing but its stern
    trail. `_erase_shadow` keeps a shadow pixel the wake has taken, so the
    figure sheet is unmoved by this.
    """
    px = img.load()
    sp = sprite.load()
    w, h = img.size
    sw, sh = sprite.size

    def fleck(x: int, y: int) -> None:
        if 0 <= x < w and 0 <= y < h and px[x, y] in (EMPTY, CAST):
            px[x, y] = (*FOAM, 255)

    keel = []
    for sx in range(sw):
        column = [sy for sy in range(sh) if sp[sx, sy][3] == 255]
        if column:
            keel.append((x0 + sx, y0 + max(column)))
    if not keel:
        return
    for i, (x, y) in enumerate(keel):
        fleck(x, y + 1)
        if i % 2 == 0:
            fleck(x, y + 2)
    stern_x, stern_y = keel[-1]
    for k in range(1, WAKE_TRAIL + 1):
        y = stern_y - (k + 1) // 2
        fleck(stern_x + k, y)
        fleck(stern_x + k, y + 1)


def _waterline_foam(img: Image.Image) -> None:
    """Foam flecks just outside the hull along its real waterline rows.

    The waterline is wherever the hull actually bottoms out, so the rows come
    from the composed pixels rather than from the ground line the sprite was
    placed against: `render` reserves a trailing empty row, and the dimetric
    hull tapers to a narrow tip, so a fixed offset misses the wide part of
    the wake. Flecks trail outward along the hull's last few rows, widest at
    the bottom.
    """
    px = img.load()
    w, h = img.size
    foam = FOAM
    spans = []
    for yy in range(h):
        xs = [xx for xx in range(w) if px[xx, yy][3] == 255]
        if xs:
            spans.append((yy, min(xs), max(xs)))
    if not spans:
        return
    # The outer fleck used to fade on alpha; it now thins out as a dither
    # instead, because a semi-transparent pixel is a halo at cut-in scale.
    for i, (yy, lo, hi) in enumerate(reversed(spans[-FOAM_ROWS:])):
        n = 2 if i < 2 else 1
        for k in range(1, n + 1):
            if k > 1 and yy % 2:
                continue
            if lo - k >= 0:
                px[lo - k, yy] = (*foam, 255)
            if hi + k < w:
                px[hi + k, yy] = (*foam, 255)


def _shadow_ellipse(
    img: Image.Image, cx: int, cy: int, rx: int, ry: int
) -> list[tuple[int, int]]:
    """A hard SOLID shadow: opaque dark pixels, filled, no partial alpha.

    It used to be a 1px checkerboard, on the argument that the gaps let the
    terrain through so the shadow tinted without smearing. That argument only
    ever held at one sampling ratio. The board draws this 64px cell onto a
    16px grid with nearest filtering at whole zoom rungs 1..5, so it keeps one
    source pixel in 4/z — and a 1px parity read differently at every rung it
    was sampled at: solid at rung 1 (the kept phase is the shadow's own),
    nearly absent at rung 2 for the land grid and simultaneously solid for the
    air one, and at rung 4, where the art is 1:1, individual black dots. Two
    players reported those dots on the board. A filled ellipse is the one
    shape whose read cannot move with the ratio — it is the same shadow at
    every rung, which is what "one logical pixel" buys the contour, bought
    here by having no sub-pixel structure to lose at all.

    A logical-pixel checker (4px blocks) and a solid core with a dithered
    fringe were both rendered against this at rungs 1, 2 and 4: the checker
    reads as a chequered flag under an aircraft at 1:1 and as a dashed line at
    rung 2, and the fringe reads as debris. Solid was the only one that read
    as shade at all three.

    Returns the pixels it wrote, so a caller composing a shadowless cell can
    take exactly those back out again — see compose_cell's `shadow`.
    """
    px = img.load()
    w, h = img.size
    written = []
    for yy in range(cy - ry, cy + ry + 1):
        for xx in range(cx - rx, cx + rx + 1):
            if not (0 <= xx < w and 0 <= yy < h):
                continue
            if ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2 > 1.0:
                continue
            if px[xx, yy][3] == 0:
                px[xx, yy] = CAST
                written.append((xx, yy))
    return written
