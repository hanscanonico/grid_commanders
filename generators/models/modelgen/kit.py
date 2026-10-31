"""Chunky hard-surface primitives for the painted miniatures.

Every model is written once against a `Kit` and built twice: `lod="hi"` carries
the rivets and round bevels the bake reads, `lod="lo"` the plain forms the game
draws. A cell is one Blender unit. Models face +X and stand on Z = 0; the game's
+Z (toward the lens) is Blender's -Y.
"""

from __future__ import annotations

import math
from collections.abc import Callable, Iterable, Sequence

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

BEVEL_SEGMENTS = {"hi": 3, "lo": 1}
# A bevel this wide is part of the silhouette, so the game's copy rounds it too.
ROUND_BEVEL = 0.018
CIRCLE_SIDES = {"hi": 2, "lo": 1}
UNDERSIDE = -0.7
CULL_BELOW = 0.3


def clear_scene() -> None:
    """Empties the file of every object and every mesh the last build left."""
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)


# How a part moves in the game's vertex shader. No skeleton and one draw call:
# the second UV layer says which motion a vertex follows and about which pivot.
STILL = 0
WHEEL = 1  # spins about its axle with `roll`
LEG_A = 2  # swings with `gait`
LEG_B = 3  # swings against `gait`
ARM_A = 4  # swings against `gait`, lifts with `aim`
ARM_B = 5  # swings with `gait`, lifts with `aim`
RECOIL = 6  # slides back along -X with `recoil`
TREAD = 7  # stays put; bands of paint crawl along it with `roll`


class Kit:
    """Collects a model's parts, each one mesh in one paint role."""

    def __init__(self, name: str, lod: str, roles: dict[str, bpy.types.Material]) -> None:
        self.name = name
        self.lod = lod
        self.roles = roles
        self.parts: list[bpy.types.Object] = []
        self.markers: dict[str, Vector] = {}
        self.round_parts: dict[str, tuple[Vector, Vector, Vector, Vector]] = {}
        self.binders: dict[str, Callable[[Vector], dict[str, float]]] = {}
        self.boosts: dict[str, float] = {}
        self.motions: dict[str, tuple[int, float, float]] = {}
        self.cull = True
        self.smooth_angle = 40.0

    @property
    def hi(self) -> bool:
        return self.lod == "hi"

    def marker(self, name: str, at: Sequence[float]) -> None:
        self.markers[name] = Vector(at)

    def _finish(self, bm: bmesh.types.BMesh, role: str, bevel: float, label: str) -> bpy.types.Object:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mesh = bpy.data.meshes.new(f"{self.name}_{label}")
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(mesh.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        # The second slot's only job is to mark which faces the bevel made.
        mesh.materials.append(self.roles[role])
        mesh.materials.append(self.roles[role])
        if bevel > 0.0:
            mod = obj.modifiers.new("bevel", "BEVEL")
            mod.width = bevel
            mod.segments = BEVEL_SEGMENTS[self.lod] + (1 if bevel >= ROUND_BEVEL else 0)
            mod.material = 1
            mod.limit_method = "ANGLE"
            mod.angle_limit = math.radians(35)
            mod.harden_normals = False
            mod.profile = 0.5
        self.parts.append(obj)
        return obj

    def loft(
        self,
        sections: Sequence[tuple[float, Sequence[tuple[float, float]]]],
        role: str,
        bevel: float = 0.012,
        at: Sequence[float] = (0, 0, 0),
        label: str = "loft",
    ) -> bpy.types.Object:
        """Skins closed XY outlines stacked up Z, every outline the same length."""
        bm = bmesh.new()
        rings = []
        for z, outline in sections:
            rings.append([bm.verts.new((x + at[0], y + at[1], z + at[2])) for x, y in outline])
        for low, high in zip(rings, rings[1:]):
            n = len(low)
            for i in range(n):
                bm.faces.new((low[i], low[(i + 1) % n], high[(i + 1) % n], high[i]))
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
        return self._finish(bm, role, bevel, label)

    def box(
        self,
        centre: Sequence[float],
        size: Sequence[float],
        role: str,
        bevel: float = 0.008,
        taper: float = 1.0,
        tilt: float = 0.0,
        label: str = "box",
    ) -> bpy.types.Object:
        """A box round `centre`; `taper` scales its top, `tilt` pitches it nose up about Y."""
        sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2
        low = [(-sx, -sy), (sx, -sy), (sx, sy), (-sx, sy)]
        high = [(x * taper, y * taper) for x, y in low]
        obj = self.loft([(-sz, low), (sz, high)], role, bevel, label=label)
        obj.matrix_world = Matrix.Translation(centre) @ Matrix.Rotation(-tilt, 4, "Y")
        return obj

    def side_profile(
        self,
        outline: Sequence[tuple[float, float]],
        y0: float,
        y1: float,
        role: str,
        bevel: float = 0.01,
        label: str = "profile",
    ) -> bpy.types.Object:
        """Extrudes an XZ outline across Y, as a track run or a wedge hull is cut."""
        bm = bmesh.new()
        near = [bm.verts.new((x, y0, z)) for x, z in outline]
        far = [bm.verts.new((x, y1, z)) for x, z in outline]
        n = len(outline)
        for i in range(n):
            bm.faces.new((near[i], near[(i + 1) % n], far[(i + 1) % n], far[i]))
        bm.faces.new(near)
        bm.faces.new(list(reversed(far)))
        return self._finish(bm, role, bevel, label)

    def cyl(
        self,
        p0: Sequence[float],
        p1: Sequence[float],
        r0: float,
        r1: float | None = None,
        role: str = "steel",
        sides: int = 10,
        bevel: float = 0.004,
        label: str = "cyl",
    ) -> bpy.types.Object:
        """A capped cylinder or cone from `p0` to `p1`; the bake's copy is twice as round."""
        r1 = r0 if r1 is None else r1
        sides *= CIRCLE_SIDES[self.lod]
        a, b = Vector(p0), Vector(p1)
        axis = (b - a).normalized()
        u = axis.orthogonal().normalized()
        v = axis.cross(u).normalized()
        bm = bmesh.new()
        low, high = [], []
        for i in range(sides):
            t = math.tau * i / sides
            d = u * math.cos(t) + v * math.sin(t)
            low.append(bm.verts.new(a + d * r0))
            high.append(bm.verts.new(b + d * r1))
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((low[i], low[j], high[j], high[i]))
        bm.faces.new(list(reversed(low)))
        bm.faces.new(high)
        obj = self._finish(bm, role, bevel, label)
        self.round_parts[obj.name] = (a.copy(), axis, u, v)
        return obj

    def ellipsoid(
        self,
        centre: Sequence[float],
        radii: Sequence[float],
        role: str,
        rings: int = 8,
        sides: int = 12,
        label: str = "ball",
    ) -> bpy.types.Object:
        """A smooth egg; the bake's copy is twice as fine."""
        rings *= CIRCLE_SIDES[self.lod]
        sides *= CIRCLE_SIDES[self.lod]
        bm = bmesh.new()
        c = Vector(centre)
        south = bm.verts.new(c - Vector((0, 0, radii[2])))
        north = bm.verts.new(c + Vector((0, 0, radii[2])))
        layers = []
        for i in range(1, rings):
            phi = math.pi * i / rings - math.pi / 2
            layer = []
            for j in range(sides):
                t = math.tau * j / sides
                layer.append(
                    bm.verts.new(
                        c
                        + Vector(
                            (
                                radii[0] * math.cos(phi) * math.cos(t),
                                radii[1] * math.cos(phi) * math.sin(t),
                                radii[2] * math.sin(phi),
                            )
                        )
                    )
                )
            layers.append(layer)
        for j in range(sides):
            k = (j + 1) % sides
            bm.faces.new((south, layers[0][k], layers[0][j]))
            bm.faces.new((north, layers[-1][j], layers[-1][k]))
            for low, high in zip(layers, layers[1:]):
                bm.faces.new((low[j], low[k], high[k], high[j]))
        return self._finish(bm, role, 0.0, label)

    def tube(
        self,
        path: Sequence[tuple[Sequence[float], float, float]],
        role: str,
        sides: int = 8,
        label: str = "tube",
    ) -> bpy.types.Object:
        """A limb: rings of (centre, radius across, radius forward) skinned along a path."""
        sides *= CIRCLE_SIDES[self.lod]
        bm = bmesh.new()
        centres = [Vector(p[0]) for p in path]
        rings = []
        for i, (_, across, forward) in enumerate(path):
            before = centres[max(i - 1, 0)]
            after = centres[min(i + 1, len(path) - 1)]
            tangent = (after - before).normalized()
            x_axis = Vector((0, 1, 0)).cross(tangent).normalized()
            y_axis = tangent.cross(x_axis).normalized()
            rings.append(
                [
                    bm.verts.new(
                        centres[i]
                        + x_axis * across * math.cos(math.tau * j / sides)
                        + y_axis * forward * math.sin(math.tau * j / sides)
                    )
                    for j in range(sides)
                ]
            )
        for low, high in zip(rings, rings[1:]):
            for j in range(sides):
                k = (j + 1) % sides
                bm.faces.new((low[j], low[k], high[k], high[j]))
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
        return self._finish(bm, role, 0.0, label)

    def rock(
        self,
        centre: Sequence[float],
        radii: Sequence[float],
        role: str,
        seed: float,
        rough: float = 0.28,
        rings: int = 6,
        sides: int = 9,
        keep_above: float | None = None,
        label: str = "rock",
    ) -> bpy.types.Object:
        """A craggy egg, the same crags on both copies; the bake's has finer ones too.

        `keep_above` shaves off everything lower, as a snow cap sits on a peak.
        """
        rings *= 3 if self.hi else 1
        sides *= 3 if self.hi else 1
        bm = bmesh.new()
        c = Vector(centre)

        def surface(phi: float, t: float) -> Vector:
            d = Vector((math.cos(phi) * math.cos(t), math.cos(phi) * math.sin(t), math.sin(phi)))
            big = noise.noise(d * 1.7 + Vector((seed, seed * 0.7, 0)))
            small = noise.noise(d * 6.0 + Vector((seed, 0, seed))) if self.hi else 0.0
            grit = noise.noise(d * 19.0 + Vector((0, seed, seed))) if self.hi else 0.0
            bump = 1.0 + rough * big + rough * 0.42 * small + rough * 0.14 * grit
            return c + Vector((radii[0] * d.x * bump, radii[1] * d.y * bump, radii[2] * d.z * bump))

        south = bm.verts.new(surface(-math.pi / 2, 0))
        north = bm.verts.new(surface(math.pi / 2, 0))
        layers = []
        for i in range(1, rings):
            phi = math.pi * i / rings - math.pi / 2
            layers.append([bm.verts.new(surface(phi, math.tau * j / sides)) for j in range(sides)])
        for j in range(sides):
            k = (j + 1) % sides
            bm.faces.new((south, layers[0][k], layers[0][j]))
            bm.faces.new((north, layers[-1][j], layers[-1][k]))
            for low, high in zip(layers, layers[1:]):
                bm.faces.new((low[j], low[k], high[k], high[j]))
        if keep_above is not None:
            doomed = [v for v in bm.verts if v.co.z < keep_above]
            bmesh.ops.delete(bm, geom=doomed, context="VERTS")
        bm.normal_update()
        return self._finish(bm, role, 0.0, label)

    def crag(
        self,
        x: float,
        y: float,
        rx: float,
        ry: float,
        top: float,
        role: str,
        seed: float,
        rough: float = 0.3,
        snow_above: float | None = None,
        lift: float = 0.0,
        label: str = "crag",
    ) -> bpy.types.Object:
        """A peak: a rough cone from the ground up; `snow_above` keeps only what is higher."""
        rows = 9 * (3 if self.hi else 1)
        sides = 9 * (3 if self.hi else 1)
        bm = bmesh.new()

        def point(t: float, a: float) -> Vector:
            d = Vector((math.cos(a), math.sin(a), t * 2.0))
            big = noise.noise(d * 1.5 + Vector((seed, seed * 0.7, 0)))
            mid = noise.noise(d * 3.6 + Vector((seed, 0, seed)))
            fine = noise.noise(d * 9.0 + Vector((0, seed, seed))) if self.hi else 0.0
            grit = noise.noise(d * 23.0 + Vector((seed, seed, 0))) if self.hi else 0.0
            taper = (1.0 - t) ** 0.85
            bump = 1.0 + rough * (big + 0.75 * mid + 0.35 * fine + 0.14 * grit)
            shear = rough * 0.5 * t * noise.noise(Vector((seed, a * 0.2, t)))
            return Vector(
                (
                    x + rx * taper * bump * math.cos(a) + shear * rx,
                    y + ry * taper * bump * math.sin(a),
                    top * t * (1.0 + 0.12 * rough * mid) + lift,
                )
            )

        layers = []
        for i in range(rows):
            t = i / rows
            layers.append([bm.verts.new(point(t, math.tau * j / sides)) for j in range(sides)])
        tip = bm.verts.new(Vector((x + rough * 0.12 * rx, y, top + lift)))
        for j in range(sides):
            k = (j + 1) % sides
            for low, high in zip(layers, layers[1:]):
                bm.faces.new((low[j], low[k], high[k], high[j]))
            bm.faces.new((layers[-1][j], layers[-1][k], tip))
        if snow_above is not None:
            doomed = []
            for vert in bm.verts:
                jag = 0.09 * top * noise.noise(Vector((vert.co.x * 16.0, vert.co.y * 16.0, seed)))
                if vert.co.z < snow_above + jag:
                    doomed.append(vert)
            bmesh.ops.delete(bm, geom=doomed, context="VERTS")
            for vert in bm.verts:
                vert.co.x += (vert.co.x - x) * 0.04
                vert.co.y += (vert.co.y - y) * 0.04
                vert.co.z += 0.004
        return self._finish(bm, role, 0.0, label)

    def moves(self, obj: bpy.types.Object, kind: int, pivot: Sequence[float] = (0.0, 0.0)) -> bpy.types.Object:
        """Says how a part moves in the game. `pivot` is its (x, z) in the model."""
        self.motions[obj.name] = (kind, pivot[0], pivot[1])
        return obj

    def bind(self, obj: bpy.types.Object, weigh: Callable[[Vector], dict[str, float]]) -> bpy.types.Object:
        """Skins a part: `weigh` answers each vertex's bones. Asked once the part is in place."""
        self.binders[obj.name] = weigh
        return obj

    def boost(self, obj: bpy.types.Object, factor: float) -> bpy.types.Object:
        """Spends more of the texture on a part: a face, say."""
        self.boosts[obj.name] = factor
        return obj

    def rivets(self, points: Iterable[Sequence[float]], normal: Sequence[float], r: float = 0.009) -> None:
        """Rivet heads only the bake sees: they arrive in the game as paint and normals."""
        if not self.hi:
            return
        n = Vector(normal).normalized()
        for p in points:
            base = Vector(p) - n * 0.002
            self.cyl(base, base + n * r * 0.75, r, r * 0.55, "team", sides=6, bevel=0.0, label="rivet")

    def seam(self, centre: Sequence[float], size: Sequence[float], role: str = "team_dark") -> None:
        """A panel line, standing proud on the bake's copy so the wash pools along it."""
        if self.hi:
            self.box(centre, size, role, bevel=0.0, label="seam")

    def join(self) -> bpy.types.Object:
        """Applies every part's bevel and merges them into one mesh, smooth with hard flats."""
        view_layer = bpy.context.view_layer
        for obj in bpy.data.objects:
            obj.select_set(False)
        for obj in self.parts:
            obj.select_set(True)
        view_layer.objects.active = self.parts[0]
        bpy.ops.object.convert(target="MESH")
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        if self.hi:
            for obj in self.parts:
                _mark_edges(obj.data)
        else:
            if self.cull:
                self._cull_undersides()
            self._unwrap_parts()
            self._write_motion()
            self._apply_binders()
            self._mark_boosts()
        for obj in self.parts:
            obj.select_set(True)
        view_layer.objects.active = self.parts[0]
        bpy.ops.object.join()
        joined = view_layer.objects.active
        joined.name = f"{self.name}_{self.lod}"
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        mesh = joined.data
        mesh.name = joined.name
        bpy.ops.object.shade_smooth()
        bpy.ops.object.shade_auto_smooth(angle=math.radians(self.smooth_angle))
        # Flats stay flat under a soft bevel: the normals lean on the big faces.
        weighted = joined.modifiers.new("weighted", "WEIGHTED_NORMAL")
        weighted.keep_sharp = True
        weighted.weight = 100
        bpy.ops.object.modifier_apply(modifier=weighted.name)
        if not self.hi:
            self._pack()
        return joined

    def _cull_undersides(self) -> None:
        """The lens never looks up: faces turned to the ground would only eat texels."""
        for obj in self.parts:
            bm = bmesh.new()
            bm.from_mesh(obj.data)
            under = [f for f in bm.faces if f.normal.z < UNDERSIDE and f.calc_center_median().z < CULL_BELOW]
            if len(under) < len(bm.faces):
                bmesh.ops.delete(bm, geom=under, context="FACES")
            bm.to_mesh(obj.data)
            bm.free()

    def _unwrap_parts(self) -> None:
        """A round part unrolls into one strip and two caps; the rest project by facing."""
        view_layer = bpy.context.view_layer
        flat = [obj for obj in self.parts if obj.name not in self.round_parts]
        for obj in self.parts:
            obj.select_set(obj in flat)
        view_layer.objects.active = flat[0]
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(62), island_margin=0.0, scale_to_bounds=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        for obj in self.parts:
            if obj.name in self.round_parts:
                _unroll(obj.data, *self.round_parts[obj.name])

    def _write_motion(self) -> None:
        for obj in self.parts:
            mesh = obj.data
            render_layer = mesh.uv_layers["UVMap"]
            layer = mesh.uv_layers.new(name="motion")
            kind, px, pz = self.motions.get(obj.name, (STILL, 0.0, 0.0))
            value = (kind * 10.0 + 5.0 + px, pz)
            for loop in layer.data:
                loop.uv = value
            mesh.uv_layers.active = render_layer
            render_layer.active_render = True

    def _apply_binders(self) -> None:
        for obj in self.parts:
            weigh = self.binders.get(obj.name)
            if weigh is None:
                continue
            for vert in obj.data.vertices:
                for bone, weight in weigh(obj.matrix_world @ vert.co).items():
                    group = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
                    group.add([vert.index], weight, "REPLACE")

    def _mark_boosts(self) -> None:
        for obj in self.parts:
            attribute = obj.data.attributes.new("uv_boost", "FLOAT", "FACE")
            factor = self.boosts.get(obj.name, 1.0)
            attribute.data.foreach_set("value", [factor] * len(obj.data.polygons))

    def _pack(self) -> None:
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.select_all(action="SELECT")
        bpy.ops.uv.average_islands_scale()
        bpy.ops.object.mode_set(mode="OBJECT")
        mesh = bpy.context.view_layer.objects.active.data
        boosts = mesh.attributes["uv_boost"].data
        mesh.uv_layers.active = mesh.uv_layers["UVMap"]
        uv_data = mesh.uv_layers.active.data
        for poly in mesh.polygons:
            factor = boosts[poly.index].value
            if factor != 1.0:
                for loop in poly.loop_indices:
                    uv_data[loop].uv = uv_data[loop].uv * factor
        mesh.attributes.remove(mesh.attributes["uv_boost"])
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.uv.pack_islands(rotate=True, scale=True, margin_method="FRACTION", margin=0.012, shape_method="CONCAVE")
        bpy.ops.object.mode_set(mode="OBJECT")


def _mark_edges(mesh: bpy.types.Mesh) -> None:
    """Writes which faces the bevel made, where the dry brush will catch."""
    attribute = mesh.attributes.new("edge", "FLOAT", "FACE")
    attribute.data.foreach_set("value", [1.0 if p.material_index == 1 else 0.0 for p in mesh.polygons])


def _unroll(mesh: bpy.types.Mesh, a: Vector, axis: Vector, u: Vector, v: Vector) -> None:
    """Writes UVs for a cylinder: true lengths along its side, its caps planar."""
    mesh.uv_layers.new(name="UVMap")
    bm = bmesh.new()
    bm.from_mesh(mesh)
    uv = bm.loops.layers.uv.active
    heights = [(vert.co - a).dot(axis) for vert in bm.verts]
    middle = (min(heights) + max(heights)) / 2
    radius = max((vert.co - a - axis * (vert.co - a).dot(axis)).length for vert in bm.verts)

    def radial(co: Vector) -> Vector:
        rel = co - a
        return rel - axis * rel.dot(axis)

    for face in bm.faces:
        if abs(face.normal.dot(axis)) > 0.85:
            offset = 4.0 if face.normal.dot(axis) > 0 else 8.0
            for loop in face.loops:
                rel = loop.vert.co - a
                loop[uv].uv = (rel.dot(u) + offset, rel.dot(v))
            continue
        angles = [math.atan2(radial(loop.vert.co).dot(v), radial(loop.vert.co).dot(u)) for loop in face.loops]
        if max(angles) - min(angles) > math.pi:
            angles = [t + math.tau if t < 0 else t for t in angles]
        for loop, angle in zip(face.loops, angles):
            height = (loop.vert.co - a).dot(axis)
            inward = radius - radial(loop.vert.co).length
            height += inward if height > middle else -inward
            loop[uv].uv = (angle * radius, height)
    bm.to_mesh(mesh)
    bm.free()
