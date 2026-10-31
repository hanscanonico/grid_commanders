"""Renders a built model as the game would show it, with no window and no Godot.

    blender --background --python generators/models/preview_models.py -- tank --out /abs/dir

Writes `<name>_close.png` (the model in two armies at the board camera's angle,
filling the frame) and `<name>_board.png` (the same, at the size it is played:
about fifty pixels a cell, which is the view that decides whether it works).
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MODELS = os.path.join(REPO, "assets", "models")
FOLDERS = ("units", "buildings", "terrain", "generals")
# `FactionRamp3D`'s tones: dark, base, light.
RAMPS = {
    "meridian": ("a93631", "db4a3b", "ee6757"),
    "aurora": ("2b4ea8", "3865d8", "4e7cea"),
    "verdant": ("1d6127", "2c8636", "349e40"),
    "gold": ("7e6d15", "a68f1d", "b3a04c"),
    "iron": ("2f363b", "4a5258", "5c666d"),
    "neutral": ("3c444a", "606a71", "737e86"),
}
PITCH = math.radians(52)
FOV = math.radians(30)
# The game's sun, as the direction its light travels.
SUN = Vector((0.606, -0.283, -0.743))
GROUND = (0.11, 0.22, 0.05)
WATER = (0.04, 0.26, 0.5)


def linear(hex_colour: str) -> tuple[float, float, float, float]:
    def one(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (int(hex_colour[i : i + 2], 16) / 255 for i in (0, 2, 4))
    return (one(r), one(g), one(b), 1.0)


def material_for(name: str, folder: str, army: str) -> bpy.types.Material:
    material = bpy.data.materials.new(f"{name}_{army}")
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    paint = nodes.new("ShaderNodeTexImage")
    paint.image = bpy.data.images.load(os.path.join(MODELS, folder, f"{name}_paint.png"), check_existing=True)
    paint.image.alpha_mode = "STRAIGHT"
    rgb = nodes.new("ShaderNodeSeparateColor")
    links.new(paint.outputs["Color"], rgb.inputs[0])
    ramp = nodes.new("ShaderNodeValToRGB")
    dark, base, light = RAMPS[army]
    band = ramp.color_ramp
    band.elements[0].position = 0.0
    d = linear(dark)
    band.elements[0].color = (d[0] * 0.5, d[1] * 0.5, d[2] * 0.5, 1.0)
    band.elements[1].position = 1.0
    band.elements[1].color = (0.8, 0.8, 0.8, 1.0)
    for position, colour in ((0.3, linear(dark)), (0.62, linear(base)), (0.95, linear(light))):
        element = band.elements.new(position)
        element.color = colour
    links.new(rgb.outputs[1], ramp.inputs[0])
    mask = nodes.new("ShaderNodeMapRange")
    links.new(paint.outputs["Alpha"], mask.inputs[0])
    mask.inputs[1].default_value = 0.25
    mask.inputs[2].default_value = 1.0
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    links.new(mask.outputs[0], mix.inputs[0])
    links.new(paint.outputs["Color"], mix.inputs[6])
    links.new(ramp.outputs[0], mix.inputs[7])
    normal_image = nodes.new("ShaderNodeTexImage")
    normal_image.image = bpy.data.images.load(os.path.join(MODELS, folder, f"{name}_normal.png"), check_existing=True)
    normal_image.image.colorspace_settings.name = "Non-Color"
    normal = nodes.new("ShaderNodeNormalMap")
    links.new(normal_image.outputs["Color"], normal.inputs["Color"])
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    links.new(normal.outputs[0], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.72
    bsdf.inputs["Specular IOR Level"].default_value = 0.3
    out = nodes.new("ShaderNodeOutputMaterial")
    links.new(bsdf.outputs[0], out.inputs[0])
    return material


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :]
    parser = argparse.ArgumentParser()
    parser.add_argument("name")
    parser.add_argument("--out", required=True)
    parser.add_argument("--armies", default="meridian,iron")
    parser.add_argument("--sea", action="store_true")
    parser.add_argument("--lift", type=float, default=0.0, help="raise the model, as an aircraft flies")
    parser.add_argument(
        "--yaw", type=float, default=0.0, help="turn the model, in degrees; a general faces the lens at 180"
    )
    args = parser.parse_args(argv)
    folder = next(f for f in FOLDERS if os.path.exists(os.path.join(MODELS, f, f"{args.name}.glb")))
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "GPU"
    scene.cycles.samples = 32
    scene.cycles.use_denoising = False
    scene.view_settings.view_transform = "Standard"
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("flat")
    world.use_nodes = True
    background = world.node_tree.nodes["Background"]
    background.inputs["Color"].default_value = (*(c for c in linear("c3cfe6")[:3]), 1.0)
    background.inputs["Strength"].default_value = 0.42
    scene.world = world
    bpy.ops.mesh.primitive_plane_add(size=60)
    ground = bpy.context.active_object
    ground_material = bpy.data.materials.new("ground")
    ground_material.use_nodes = True
    principled = next(n for n in ground_material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    principled.inputs["Base Color"].default_value = (*(WATER if args.sea else GROUND), 1.0)
    principled.inputs["Roughness"].default_value = 1.0
    ground.data.materials.append(ground_material)
    armies = args.armies.split(",")
    for i, army in enumerate(armies):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, folder, f"{args.name}.glb"))
        for obj in set(bpy.data.objects) - before:
            if obj.parent is None:
                obj.location = (i * 1.05, 0, args.lift)
                obj.rotation_mode = "XYZ"
                obj.rotation_euler = (0, 0, math.radians(args.yaw))
            if obj.type == "MESH":
                obj.data.materials.clear()
                obj.data.materials.append(material_for(args.name, folder, army))
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 0.95 * math.pi
    sun.data.angle = math.radians(1.5)
    scene.collection.objects.link(sun)
    sun.rotation_mode = "QUATERNION"
    sun.rotation_quaternion = (-SUN).to_track_quat("Z", "Y")
    camera = bpy.data.objects.new("lens", bpy.data.cameras.new("lens"))
    camera.data.angle = FOV
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.rotation_mode = "QUATERNION"
    look = Vector((-math.cos(PITCH) * 0.0, math.cos(PITCH), -math.sin(PITCH)))
    camera.rotation_quaternion = look.to_track_quat("-Z", "Y")
    centre = Vector(((len(armies) - 1) * 1.05 / 2, 0, 0.15 + args.lift))
    os.makedirs(args.out, exist_ok=True)
    for label, reach, width, height in (("close", 2.6 + 0.9 * (len(armies) - 1), 960, 540), ("board", 20.0, 1280, 720)):
        camera.location = centre - look * reach
        scene.render.resolution_x = width
        scene.render.resolution_y = height
        if label == "board":
            scene.render.use_border = True
            scene.render.use_crop_to_border = True
            scene.render.border_min_x, scene.render.border_max_x = 0.38, 0.62
            scene.render.border_min_y, scene.render.border_max_y = 0.38, 0.62
        else:
            scene.render.use_border = False
        scene.render.filepath = os.path.join(args.out, f"{args.name}_{label}.png")
        bpy.ops.render.render(write_still=True)
    print(f"PREVIEW {args.name}: {args.out}")


main()
