"""Bakes a model's high copy onto its low copy and writes what the game loads.

Three passes through Cycles: the paint, the army mask and the normals. The paint
and the mask are one RGBA PNG, RGB the paint and alpha the mask.
"""

from __future__ import annotations

import os
from dataclasses import dataclass

import bpy
import numpy as np

from . import paint


MASK_FLOOR = 0.25


@dataclass(frozen=True)
class BakeSettings:
    size: int = 512
    normal_size: int = 256
    samples: int = 48
    cage: float = 0.012
    reach: float = 0.03
    margin: int = 8


def _image(name: str, size: int, colorspace: str) -> bpy.types.Image:
    if name in bpy.data.images:
        bpy.data.images.remove(bpy.data.images[name])
    image = bpy.data.images.new(name, size, size, alpha=False, float_buffer=False)
    image.colorspace_settings.name = colorspace
    return image


def _bake_material(low: bpy.types.Object) -> bpy.types.Material:
    material = bpy.data.materials.new(f"{low.name}_target")
    material.use_nodes = True
    low.data.materials.clear()
    low.data.materials.append(material)
    for poly in low.data.polygons:
        poly.material_index = 0
    return material


def _pass(
    high: bpy.types.Object,
    low: bpy.types.Object,
    material: bpy.types.Material,
    image: bpy.types.Image,
    kind: str,
    settings: BakeSettings,
) -> None:
    nodes = material.node_tree.nodes
    target = nodes.get("target") or nodes.new("ShaderNodeTexImage")
    target.name = "target"
    target.image = image
    nodes.active = target
    view_layer = bpy.context.view_layer
    for obj in bpy.data.objects:
        obj.select_set(False)
    high.select_set(True)
    low.select_set(True)
    view_layer.objects.active = low
    bake = bpy.context.scene.render.bake
    bake.use_selected_to_active = True
    bake.cage_extrusion = settings.cage
    bake.max_ray_distance = settings.reach
    bake.margin = settings.margin
    bake.margin_type = "EXTEND"
    bake.use_clear = True
    bpy.ops.object.bake(type=kind)


def bake(high: bpy.types.Object, low: bpy.types.Object, out_dir: str, settings: BakeSettings) -> dict[str, str]:
    """Writes `<name>_paint.png` and `<name>_normal.png`; answers their paths."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "GPU"
    scene.cycles.samples = settings.samples
    scene.cycles.use_denoising = False
    material = _bake_material(low)
    name = low.name.removesuffix("_lo")
    os.makedirs(out_dir, exist_ok=True)

    paint.set_output(mask=False)
    colour = _image(f"{name}_colour", settings.size, "sRGB")
    _pass(high, low, material, colour, "EMIT", settings)

    paint.set_output(mask=True)
    mask = _image(f"{name}_mask", settings.size, "Non-Color")
    _pass(high, low, material, mask, "EMIT", settings)
    paint.set_output(mask=False)

    normal = _image(f"{name}_normal", settings.normal_size, "Non-Color")
    _pass(high, low, material, normal, "NORMAL", settings)

    paint_path = os.path.join(out_dir, f"{name}_paint.png")
    combined = bpy.data.images.new(f"{name}_paint", settings.size, settings.size, alpha=True)
    combined.colorspace_settings.name = "sRGB"
    pixels = np.empty(settings.size * settings.size * 4, dtype=np.float32)
    colour.pixels.foreach_get(pixels)
    mask_pixels = np.empty_like(pixels)
    mask.pixels.foreach_get(mask_pixels)
    # Never zero: an empty alpha lets an image pipeline throw that pixel's RGB away.
    pixels[3::4] = MASK_FLOOR + (1.0 - MASK_FLOOR) * mask_pixels[0::4]
    combined.pixels.foreach_set(pixels)
    combined.alpha_mode = "STRAIGHT"
    combined.filepath_raw = paint_path
    combined.file_format = "PNG"
    combined.save()

    normal_path = os.path.join(out_dir, f"{name}_normal.png")
    normal.filepath_raw = normal_path
    normal.file_format = "PNG"
    normal.save()
    return {"paint": paint_path, "normal": normal_path}
