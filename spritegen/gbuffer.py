"""Per-pixel geometry buffers beside the colour, and the pure passes over them.

The rasteriser in `voxel.py` bakes every edge into the 4x4 voxel stamp: an
outline is a per-part border pass, a rim is a slot bump on the voxel that owns
it. That is fine while an edge is a property of ONE voxel, and it is helpless
where an edge is a property of the PICTURE — a hull passing in front of another
hull, a ridge that should read as a highlight only where it is convex. The
pipelines this borrows from (Dead Cells' 3D-to-sprite bake, Broxxar's pixel-art
pipeline, David Holland's 3D pixel art) all solve that the same way: render at
the final resolution with no antialiasing, and emit DEPTH and NORMAL beside the
colour so outlines, selective outlining and lighting are a 2D post-pass on
those buffers.

This module is the buffer side of that: the containers, the depth convention,
and two pure passes (`edge_mask`, `convex_edges`). It imports nothing from the
renderer — the renderer imports it — and it draws nothing. Nothing in the
shipped art consumes these yet.

Depth is measured along the VIEW AXIS. The projection is
screen x = (vx - vy) * 2, y = (vx + vy) - vz * 2, so the only voxel offset that
lands on the same screen pixel is (1, 1, 1): that direction IS the camera ray,
and `voxel_depth` is the coordinate along it. Larger means nearer the camera,
which is also the painter's order the rasteriser draws in.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

from PIL import Image

# Face ids stored in the normal plane. NONE is background — and also every
# pixel a post-pass (the contour, the outline) painted outside the silhouette,
# since those pixels belong to no face.
N_NONE = 0
N_TOP = 1
N_LEFT = 2
N_RIGHT = 3

# The unit normal each face id stands for, in voxel space: the top face looks
# up +z, the screen-left face looks along +y (which the projection sends to the
# screen's lower left) and the screen-right face along +x.
FACE_NORMALS: dict[int, tuple[int, int, int]] = {
    N_TOP: (0, 0, 1),
    N_LEFT: (0, 1, 0),
    N_RIGHT: (1, 0, 0),
}

# Depth of a pixel no face wrote. Far below any model's real depth, so a
# 4-neighbour delta against it always clears any sane threshold and the
# silhouette falls out of the same test that finds self-overlap.
DEPTH_EMPTY = -1_000_000

# Up, left, right, down — same four steps the renderer measures its contour
# across, in the same order.
_NEIGHBOURS4 = ((0, -1), (-1, 0), (1, 0), (0, 1))

# The screen axis each pair of faces creases along, 0 horizontal and 1
# vertical. In this one projection a cube's top face sits ABOVE both of its
# camera-facing sides and those two sides sit BESIDE each other, so a boundary
# crossed along the other axis is two separate masses happening to touch on
# screen, not a crease on one surface — and asking a normal pair about a crease
# it cannot form is how a wall rising out of a deck reads as a ridge.
_CREASE_AXIS: dict[frozenset[int], int] = {
    frozenset((N_TOP, N_LEFT)): 1,
    frozenset((N_TOP, N_RIGHT)): 1,
    frozenset((N_LEFT, N_RIGHT)): 0,
}


def voxel_depth(x: int, y: int, z: int) -> int:
    """Depth of a voxel along the camera ray; larger is nearer the camera."""
    return x + y + z


def project(v: tuple[int, int, int]) -> tuple[int, int]:
    """The renderer's projection, applied to a direction rather than a point."""
    return ((v[0] - v[1]) * 2, (v[0] + v[1]) - v[2] * 2)


@dataclass(frozen=True)
class Plane:
    """A width x height scalar image in row-major order.

    Plain ints, no PIL: these are read by passes, not blitted. `values` may be
    a bytearray (ids, masks) or a list (depths, which go negative).
    """

    width: int
    height: int
    values: Sequence[int]

    def at(self, x: int, y: int) -> int:
        return self.values[y * self.width + x]


@dataclass(frozen=True)
class GBuffer:
    """A render's colour plus the geometry behind every pixel.

    `depth` and `normal` describe the face that OWNS each pixel after
    overdraw — the last voxel the painter's algorithm wrote there. Pixels that
    a later 2D pass painted (the contour's halo, the outline) are geometry
    background: DEPTH_EMPTY and N_NONE. `material` is the same id plane
    `IndexedSprite.materials` carries; the plain `render` path leaves it empty.
    """

    rgba: Image.Image
    depth: Plane
    normal: Plane
    material: Plane

    @property
    def width(self) -> int:
        return self.rgba.width

    @property
    def height(self) -> int:
        return self.rgba.height


def edge_mask(depth: Plane, threshold: int = 2) -> Plane:
    """1px silhouette / self-overlap mask: pixels whose depth breaks a step.

    A written pixel is marked when any of its four neighbours is off the plane,
    empty, or deeper/nearer by MORE than `threshold`. The mask lies INSIDE the
    shape, one pixel thick, which is what a selective outline wants to draw
    from.

    `threshold` is tunable and its unit is one voxel of camera distance. The
    default of 2 is the smallest that survives a FLAT PLANE, which in this
    projection is a depth gradient, not a constant: stepping one pixel down the
    screen across a level deck crosses from one voxel to the (1, 1, 0) voxel
    beyond it, two steps further along the camera ray. So 2 is the steepest a
    continuous surface gets, and 3 — one voxel of relief — is the first real
    break. Measured on md_tank, dropping the threshold to 1 marks 716 interior
    pixels of 1646 drawn (the deck seams themselves); 2 marks 133.
    """
    w, h = depth.width, depth.height
    out = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            d = depth.at(x, y)
            if d == DEPTH_EMPTY:
                continue
            for dx, dy in _NEIGHBOURS4:
                nx, ny = x + dx, y + dy
                if not (0 <= nx < w and 0 <= ny < h):
                    out[y * w + x] = 1
                    break
                n = depth.at(nx, ny)
                if n == DEPTH_EMPTY or abs(n - d) > threshold:
                    out[y * w + x] = 1
                    break
    return Plane(w, h, out)


def convex_edges(normal: Plane, threshold: int = 0) -> Plane:
    """Mask of pixels sitting on a CONVEX crease between two faces.

    Holland's heuristic: at a boundary between two faces, the sign of the cross
    product of their normals against the direction of travel says whether the
    surface turns toward the viewer (convex ridge — a box's top edge, the near
    vertical corner) or away (concave gutter — where a wall meets the deck
    beside it). In this one fixed dimetric projection that test reduces to
    something cheaper and exactly equivalent: project both normals to screen
    with the renderer's own projection and ask whether they SPLAY APART along
    the step from one pixel to its neighbour.

    Only the axis a given pair of faces can actually crease along is asked —
    see `_CREASE_AXIS`. Both sides of a convex crease are marked; neither side
    of a concave one is.
    `threshold` raises the bar on that splay and is tunable: 0 keeps every
    crease the projection separates at all, which at three faces is all of
    them, and a higher value is the knob a lighting pass would turn if the
    engine ever grew more face directions.
    """
    w, h = normal.width, normal.height
    screen = {fid: project(n) for fid, n in FACE_NORMALS.items()}
    out = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            a = normal.at(x, y)
            if a == N_NONE:
                continue
            pax, pay = screen[a]
            for dx, dy in _NEIGHBOURS4:
                nx, ny = x + dx, y + dy
                if not (0 <= nx < w and 0 <= ny < h):
                    continue
                b = normal.at(nx, ny)
                if b == N_NONE or b == a:
                    continue
                if _CREASE_AXIS[frozenset((a, b))] != (1 if dy else 0):
                    continue
                pbx, pby = screen[b]
                if (pbx - pax) * dx + (pby - pay) * dy > threshold:
                    out[y * w + x] = 1
                    break
    return Plane(w, h, out)
