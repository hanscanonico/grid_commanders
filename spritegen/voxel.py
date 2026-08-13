"""A tiny dimetric voxel engine — the whole sheet's look lives here.

Projection matches the PixVoxel art the game shipped with: screen
x = (vx - vy) * 2, y = (vx + vy) - vz * 2, each voxel drawn as a 4x4 cube
sprite overlapping its neighbours by 2px, which is what produces the classic
2px-run stair edges. +x runs toward screen lower-right, +y toward screen
lower-left (units face +y), +z is up.

On top of the flat three-tone faces the pack used, the renderer adds baked
ambient occlusion, front-edge rim light, a whisper of dither on broad tops,
and a per-part outline (each silhouette pixel outlines in a dark tint of the
part it borders, so red armour gets a red-black edge and gun steel a
grey-black one). All of it is deterministic: no RNG anywhere.
"""

from __future__ import annotations

from PIL import Image

from .palette import (
    DITHERED,
    GLOSSY,
    RGB,
    Faction,
    darken,
    h01,
    lighten,
    mix,
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


def _face_pixels(sx: int, sy: int) -> dict[str, list[tuple[int, int]]]:
    """The 4x4 cube sprite at screen anchor (sx, sy): top / left / right."""
    return {
        "top": [
            (sx + 1, sy),
            (sx + 2, sy),
            (sx, sy + 1),
            (sx + 1, sy + 1),
            (sx + 2, sy + 1),
            (sx + 3, sy + 1),
        ],
        "left": [(sx, sy + 2), (sx + 1, sy + 2), (sx, sy + 3), (sx + 1, sy + 3)],
        "right": [
            (sx + 2, sy + 2),
            (sx + 3, sy + 2),
            (sx + 2, sy + 3),
            (sx + 3, sy + 3),
        ],
    }


def render(model: Model, faction: Faction, outline: bool = True) -> Image.Image:
    """Render to a tightly-cropped RGBA image (1px border reserved for outline)."""
    if not model.vox:
        return Image.new("RGBA", (1, 1), (0, 0, 0, 0))

    anchors = {}
    for x, y, z in model.vox:
        anchors[(x, y, z)] = ((x - y) * 2, (x + y) - z * 2)
    minx = min(a[0] for a in anchors.values()) - 1
    miny = min(a[1] for a in anchors.values()) - 1
    w = max(a[0] for a in anchors.values()) + 4 + 2 - minx
    h = max(a[1] for a in anchors.values()) + 4 + 2 - miny

    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    vox = model.vox
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

        for face, pixels in faces.items():
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
            dither = mat in DITHERED and face == "top"
            for ix, iy in pixels:
                c = tone
                if dither:
                    n = (h01(ix, iy, 7) - 0.5) * 0.07
                    c = lighten(tone, n) if n > 0 else darken(tone, -n)
                px[ix, iy] = (c[0], c[1], c[2], 255)

    if outline:
        _outline(img)
    return img


def _outline(img: Image.Image) -> None:
    """1px per-part outline: each edge pixel is a dark tint of its neighbour."""
    px = img.load()
    w, h = img.size
    edges: list[tuple[int, int, RGB]] = []
    for yy in range(h):
        for xx in range(w):
            if px[xx, yy][3] != 0:
                continue
            neigh = []
            for nx, ny in ((xx - 1, yy), (xx + 1, yy), (xx, yy - 1), (xx, yy + 1)):
                if 0 <= nx < w and 0 <= ny < h:
                    c = px[nx, ny]
                    if c[3] == 255:
                        neigh.append(c)
            if neigh:
                r = sum(c[0] for c in neigh) // len(neigh)
                g = sum(c[1] for c in neigh) // len(neigh)
                b = sum(c[2] for c in neigh) // len(neigh)
                edges.append((xx, yy, darken((r, g, b), 0.68)))
    for xx, yy, c in edges:
        px[xx, yy] = (c[0], c[1], c[2], 255)


def compose_cell(
    sprite: Image.Image,
    kind: str = "land",
    cell: int = 64,
    bottom: int | None = None,
    dx: int = 0,
) -> Image.Image:
    """Center a rendered sprite on a transparent atlas cell with its shadow.

    kind: 'land' sits on the ground line with no shadow at all — a baked
    ellipse under ground units smears alpha over whatever terrain they stand
    on and erases the game's one instant airborne cue, which is that only
    air (and sea, as displacement) casts one (sprite review, 2026-08-13);
    'air' hovers with a gap and a small detached shadow, like the pack art;
    'sea' sits in the water on a displacement shadow with waterline foam.
    'prop' composes with no shadow (terrain tiles draw their own grounding).
    """
    out = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    w, h = sprite.size
    if kind == "air":
        bottom = bottom if bottom is not None else 44
        shadow_y = 56
        shadow_rx = max(5, int(w * 0.26))
    else:
        bottom = bottom if bottom is not None else 55
        shadow_y = bottom - 2
        shadow_rx = max(6, int(w * 0.42))
    x0 = (cell - w) // 2 + dx
    y0 = bottom - h

    if kind == "sea":
        # Ships sit IN the water: a flat displacement shading right under the
        # hull instead of a floating blob, then foam hugging the waterline.
        _shadow_ellipse(
            out, cell // 2 + dx, shadow_y + 1, shadow_rx, max(2, shadow_rx // 5), 52
        )
    elif kind == "air":
        _shadow_ellipse(
            out,
            cell // 2 + dx,
            shadow_y,
            shadow_rx,
            max(2, shadow_rx // 3),
            44,
        )
    place_in_cell(out, sprite, x0, y0)
    if kind == "sea":
        _waterline_foam(out)
    return out


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
    foam = (226, 240, 250)
    spans = []
    for yy in range(h):
        xs = [xx for xx in range(w) if px[xx, yy][3] == 255]
        if xs:
            spans.append((yy, min(xs), max(xs)))
    if not spans:
        return
    for i, (yy, lo, hi) in enumerate(reversed(spans[-FOAM_ROWS:])):
        n = 2 if i < 2 else 1
        for k in range(1, n + 1):
            if lo - k >= 0:
                px[lo - k, yy] = (*foam, 235 - 60 * k)
            if hi + k < w:
                px[hi + k, yy] = (*foam, 235 - 60 * k)


def _shadow_ellipse(
    img: Image.Image, cx: int, cy: int, rx: int, ry: int, alpha: int
) -> None:
    """Blend a soft dark ellipse over whatever is already in the image.

    Source-over, not a stamp: on the transparent unit cells this reduces to
    writing the shadow straight in, while on an opaque terrain tile the
    tree/prop shadow tints the ground instead of punching a near-black slab
    into it (the tile is later flattened to RGB, so the alpha would be lost).
    """
    px = img.load()
    w, h = img.size
    for yy in range(cy - ry, cy + ry + 1):
        for xx in range(cx - rx, cx + rx + 1):
            if not (0 <= xx < w and 0 <= yy < h):
                continue
            d = ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2
            if d > 1.0:
                continue
            a = alpha if d < 0.55 else int(alpha * 0.5)
            dr, dg, db, da = px[xx, yy]
            if da == 0:
                px[xx, yy] = (16, 18, 24, a)
                continue
            keep = da * (255 - a) // 255
            out_a = a + keep
            if out_a == 0:
                continue
            px[xx, yy] = (
                (16 * a + dr * keep) // out_a,
                (18 * a + dg * keep) // out_a,
                (24 * a + db * keep) // out_a,
                out_a,
            )
