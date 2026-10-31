"""The board's flocked ground as seamless tiles, painted by Cycles on a torus.

A tile repeats without a seam because every noise reads a point on a 4D torus,
so walking off one edge of the tile comes back in on the other.
"""

from __future__ import annotations

import math
import os

import bpy

TILES = {
    "grass": {
        "low": (0.075, 0.17, 0.04),
        "high": (0.15, 0.29, 0.06),
        "fleck": (0.30, 0.40, 0.09),
        "dark": (0.03, 0.08, 0.022),
        "fleck_amount": 0.55,
        "dark_amount": 0.55,
    },
    "floor": {
        "low": (0.085, 0.19, 0.04),
        "high": (0.16, 0.29, 0.05),
        "fleck": (0.30, 0.26, 0.08),
        "dark": (0.03, 0.07, 0.025),
        "fleck_amount": 0.6,
        "dark_amount": 0.8,
    },
    "road": {
        "low": (0.25, 0.18, 0.105),
        "high": (0.40, 0.30, 0.18),
        "fleck": (0.55, 0.47, 0.34),
        "dark": (0.12, 0.08, 0.05),
        "fleck_amount": 0.45,
        "dark_amount": 0.6,
    },
    "sand": {
        "low": (0.42, 0.31, 0.15),
        "high": (0.57, 0.44, 0.24),
        "fleck": (0.72, 0.62, 0.42),
        "dark": (0.26, 0.18, 0.09),
        "fleck_amount": 0.3,
        "dark_amount": 0.25,
    },
    "earth": {
        "low": (0.17, 0.11, 0.065),
        "high": (0.34, 0.24, 0.14),
        "fleck": (0.46, 0.38, 0.27),
        "dark": (0.06, 0.04, 0.03),
        "fleck_amount": 0.5,
        "dark_amount": 0.75,
    },
}


def _tile_material(spec: dict) -> bpy.types.Material:
    material = bpy.data.materials.new("tile")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    coords = nodes.new("ShaderNodeTexCoord")
    separate = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coords.outputs["UV"], separate.inputs[0])

    def op(kind, a, b=None):
        node = nodes.new("ShaderNodeMath")
        node.operation = kind
        for socket, value in zip(node.inputs, (a, b)):
            if value is None:
                continue
            if isinstance(value, (int, float)):
                socket.default_value = value
            else:
                links.new(value, socket)
        return node.outputs[0]

    two_pi = math.tau
    u = op("MULTIPLY", separate.outputs["X"], two_pi)
    v = op("MULTIPLY", separate.outputs["Y"], two_pi)
    combine = nodes.new("ShaderNodeCombineXYZ")
    links.new(op("COSINE", u), combine.inputs[0])
    links.new(op("SINE", u), combine.inputs[1])
    links.new(op("COSINE", v), combine.inputs[2])
    w = op("SINE", v)

    def fractal(scale: float, detail: float, seed: float = 0.0):
        node = nodes.new("ShaderNodeTexNoise")
        node.noise_dimensions = "4D"
        links.new(combine.outputs[0], node.inputs["Vector"])
        links.new(op("ADD", w, seed), node.inputs["W"])
        node.inputs["Scale"].default_value = scale
        node.inputs["Detail"].default_value = detail
        node.inputs["Roughness"].default_value = 0.55
        return node.outputs[0]

    def speck(scale: float, seed: float = 0.0):
        node = nodes.new("ShaderNodeTexVoronoi")
        node.voronoi_dimensions = "4D"
        node.feature = "F1"
        links.new(combine.outputs[0], node.inputs["Vector"])
        links.new(op("ADD", w, seed), node.inputs["W"])
        node.inputs["Scale"].default_value = scale
        node.inputs["Randomness"].default_value = 1.0
        return node

    def band(value, low, high):
        node = nodes.new("ShaderNodeMapRange")
        node.interpolation_type = "SMOOTHSTEP"
        links.new(value, node.inputs[0])
        node.inputs[1].default_value = low
        node.inputs[2].default_value = high
        return node.outputs[0]

    def mix(factor, a, b):
        node = nodes.new("ShaderNodeMix")
        node.data_type = "RGBA"
        node.clamp_factor = True
        links.new(factor, node.inputs[0])
        for socket, value in ((node.inputs[6], a), (node.inputs[7], b)):
            if isinstance(value, tuple):
                socket.default_value = (*value, 1.0)
            else:
                links.new(value, socket)
        return node.outputs[2]

    # Two scales of soft variation under everything: the static grass's clumps.
    broad = band(fractal(1.6, 4.0), 0.36, 0.64)
    clump = band(fractal(7.0, 5.0, 3.0), 0.3, 0.7)
    colour = mix(op("MULTIPLY", op("ADD", broad, clump), 0.5), spec["low"], spec["high"])

    # Dark gaps between the clumps, where the wash settles in the flock.
    fine = fractal(26.0, 6.0, 7.0)
    dark_mask = op("MULTIPLY", band(fine, 0.52, 0.34), spec["dark_amount"])
    colour = mix(dark_mask, colour, spec["dark"])

    # Bright flecks: single fibres and grains catching the light.
    fleck_voronoi = speck(34.0, 11.0)
    fleck = band(fleck_voronoi.outputs["Distance"], 0.2, 0.08)
    gate = band(fleck_voronoi.outputs["Color"], 0.35, 0.7)
    colour = mix(op("MULTIPLY", op("MULTIPLY", fleck, gate), spec["fleck_amount"]), colour, spec["fleck"])

    emission = nodes.new("ShaderNodeEmission")
    links.new(colour, emission.inputs["Color"])
    output = nodes.new("ShaderNodeOutputMaterial")
    links.new(emission.outputs[0], output.inputs[0])
    return material


def bake_tiles(out_dir: str, size: int = 512, samples: int = 8) -> None:
    os.makedirs(out_dir, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "GPU"
    scene.cycles.samples = samples
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.ops.mesh.primitive_plane_add(size=1.0)
    plane = bpy.context.active_object
    scene.render.bake.use_selected_to_active = False
    scene.render.bake.margin = 0
    for name, spec in TILES.items():
        material = _tile_material(spec)
        plane.data.materials.clear()
        plane.data.materials.append(material)
        image = bpy.data.images.new(f"ground_{name}", size, size, alpha=False)
        target = material.node_tree.nodes.new("ShaderNodeTexImage")
        target.image = image
        material.node_tree.nodes.active = target
        plane.select_set(True)
        bpy.context.view_layer.objects.active = plane
        bpy.ops.object.bake(type="EMIT")
        image.filepath_raw = os.path.join(out_dir, f"ground_{name}.png")
        image.file_format = "PNG"
        image.save()
