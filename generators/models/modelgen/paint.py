"""The painted-miniature finish, as one Cycles node group every paint role wears.

The recipe is a tabletop painter's: a base coat, a zenithal light from above, a
dark wash pooled into the recesses, a dry-brushed highlight on the raised edges,
chips of bare metal at the edges and road dust up from the ground.

A role in the army's colour bakes as a grey value and a mask; the game's shader
maps that value onto the army's ramp, so one texture dresses every army and a
shadow on red stays red instead of going grey.
"""

from __future__ import annotations

from dataclasses import dataclass

import bpy

GROUP = "painted_miniature"
OUTPUT_MODE = "output_mode"
DUST = (0.46, 0.38, 0.27)
CHIP = (0.42, 0.42, 0.40)


@dataclass(frozen=True)
class Role:
    """One paint on the model. `team` roles carry a ramp value in `colour`'s grey."""

    colour: tuple[float, float, float]
    team: bool = False
    chip: float = 0.0
    dust: float = 0.6
    edge: float = 1.0
    wash: float = 1.0
    roughness: float = 0.7


def grey(value: float) -> tuple[float, float, float]:
    return (value, value, value)


ROLES: dict[str, Role] = {
    "team": Role(grey(0.50), team=True, chip=0.8),
    "team_light": Role(grey(0.74), team=True, chip=0.5),
    "team_dark": Role(grey(0.22), team=True, chip=0.3),
    "steel": Role((0.38, 0.41, 0.46), edge=1.2, dust=0.2, roughness=0.45),
    "gunmetal": Role((0.11, 0.12, 0.14), edge=1.3, dust=0.4, roughness=0.5),
    "rubber": Role((0.065, 0.065, 0.07), edge=1.0, dust=1.0, roughness=0.9),
    "wheel": Role((0.21, 0.22, 0.235), edge=1.1, dust=0.8, roughness=0.6),
    "canvas": Role((0.30, 0.26, 0.15), edge=0.7, dust=0.5, roughness=0.95),
    "leather": Role((0.17, 0.10, 0.055), edge=0.9, dust=0.5, roughness=0.8),
    "glass": Role((0.05, 0.11, 0.16), edge=0.5, wash=0.3, dust=0.1, roughness=0.15),
    "brass": Role((0.56, 0.40, 0.14), edge=1.4, dust=0.1, roughness=0.35),
    "bone": Role((0.71, 0.68, 0.58), edge=0.5, roughness=0.8),
    "plaster": Role((0.76, 0.72, 0.62), edge=0.5, dust=0.7, roughness=0.9),
    "stone": Role((0.27, 0.26, 0.24), edge=0.8, dust=0.8, roughness=0.9),
    "wood": Role((0.26, 0.16, 0.08), edge=0.8, dust=0.5, roughness=0.85),
}


def _new_group() -> bpy.types.NodeTree:
    tree = bpy.data.node_groups.new(GROUP, "ShaderNodeTree")
    sock = tree.interface.new_socket
    sock("Base", in_out="INPUT", socket_type="NodeSocketColor")
    for name in ("Team", "Chip", "Dust", "Edge", "Wash"):
        sock(name, in_out="INPUT", socket_type="NodeSocketFloat")
    sock("Shader", in_out="OUTPUT", socket_type="NodeSocketShader")
    nodes, links = tree.nodes, tree.links
    group_in = nodes.new("NodeGroupInput")
    group_out = nodes.new("NodeGroupOutput")

    def math(op: str, a, b=None, clamp: bool = False):
        node = nodes.new("ShaderNodeMath")
        node.operation = op
        node.use_clamp = clamp
        for socket, value in zip(node.inputs, (a, b)):
            if value is None:
                continue
            if isinstance(value, (int, float)):
                socket.default_value = value
            else:
                links.new(value, socket)
        return node.outputs[0]

    def mix(factor, a, b):
        node = nodes.new("ShaderNodeMix")
        node.data_type = "RGBA"
        node.clamp_factor = True
        for socket, value in ((node.inputs[0], factor), (node.inputs[6], a), (node.inputs[7], b)):
            if isinstance(value, (int, float)):
                socket.default_value = value
            elif isinstance(value, tuple):
                socket.default_value = (*value, 1.0)
            else:
                links.new(value, socket)
        return node.outputs[2]

    def ramp(value, low: float, high: float):
        node = nodes.new("ShaderNodeMapRange")
        node.interpolation_type = "SMOOTHSTEP"
        links.new(value, node.inputs[0])
        node.inputs[1].default_value = low
        node.inputs[2].default_value = high
        return node.outputs[0]

    def noise(scale: float, detail: float = 3.0, stretch: tuple[float, float, float] = (1, 1, 1)):
        node = nodes.new("ShaderNodeTexNoise")
        node.inputs["Scale"].default_value = scale
        node.inputs["Detail"].default_value = detail
        mapping = nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = stretch
        links.new(geometry.outputs["Position"], mapping.inputs["Vector"])
        links.new(mapping.outputs[0], node.inputs["Vector"])
        return node.outputs[0]

    geometry = nodes.new("ShaderNodeNewGeometry")
    separate_pos = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geometry.outputs["Position"], separate_pos.inputs[0])
    separate_nor = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geometry.outputs["Normal"], separate_nor.inputs[0])

    broad_ao = nodes.new("ShaderNodeAmbientOcclusion")
    broad_ao.inputs["Distance"].default_value = 0.34
    broad_ao.samples = 16
    wide_ao = nodes.new("ShaderNodeAmbientOcclusion")
    wide_ao.inputs["Distance"].default_value = 0.1
    wide_ao.samples = 16
    tight_ao = nodes.new("ShaderNodeAmbientOcclusion")
    tight_ao.inputs["Distance"].default_value = 0.03
    tight_ao.samples = 12
    marked = nodes.new("ShaderNodeAttribute")
    marked.attribute_type = "GEOMETRY"
    marked.attribute_name = "edge"
    edge = marked.outputs["Fac"]

    colour = group_in.outputs["Base"]

    # The base coat is never flat: long brush strokes and a little mottling.
    strokes = noise(46.0, 4.0, (0.28, 1.0, 1.6))
    mottle = noise(16.0, 3.0)
    variation = math("ADD", math("MULTIPLY", math("SUBTRACT", strokes, 0.5), 0.2), 1.0)
    variation = math("ADD", math("MULTIPLY", math("SUBTRACT", mottle, 0.5), 0.26), variation)
    colour = _scaled(nodes, links, colour, variation)

    # Zenithal: the undercoat sprayed from above lifts tops and sinks flanks.
    zenith = math("ADD", 0.66, math("MULTIPLY", math("ADD", separate_nor.outputs["Z"], 1.0), 0.27))
    colour = _scaled(nodes, links, colour, zenith)

    # A soft shade from the wide-open form down into the tucks of the model.
    shade = math("ADD", 0.5, math("MULTIPLY", broad_ao.outputs["AO"], 0.55))
    colour = _scaled(nodes, links, colour, shade)

    # The wash: tight in the crease, broad under the overhangs.
    wash_wide = math("ADD", 0.45, math("MULTIPLY", wide_ao.outputs["AO"], 0.55))
    wash_tight = math("ADD", 0.1, math("MULTIPLY", ramp(tight_ao.outputs["AO"], 0.25, 0.85), 0.9))
    wash = math("MULTIPLY", wash_wide, wash_tight)
    wash = math("ADD", math("MULTIPLY", math("SUBTRACT", wash, 1.0), group_in.outputs["Wash"]), 1.0, clamp=True)
    colour = _scaled(nodes, links, colour, wash)

    # The dry brush on every bevel, broken up as a real bristle catches.
    bristle = ramp(noise(90.0, 2.0), 0.3, 0.52)
    edge_paint = math("MULTIPLY", math("MULTIPLY", edge, bristle), group_in.outputs["Edge"], clamp=True)
    lifted = _scaled(nodes, links, _scaled(nodes, links, colour, 1.7), 1.0)
    colour = mix(math("MULTIPLY", edge_paint, 0.9), colour, lifted)

    # Chips to bare metal: at a bevel, where a coarse noise says the paint is gone.
    chip_noise = ramp(noise(30.0, 5.0), 0.6, 0.66)
    chip = math("MULTIPLY", math("MULTIPLY", edge, chip_noise), group_in.outputs["Chip"], clamp=True)
    chip = ramp(chip, 0.3, 0.45)
    colour = mix(chip, colour, CHIP)

    # Road dust: a fine stipple rising from the ground, thin at the top coat.
    height_fall = ramp(separate_pos.outputs["Z"], 0.17, 0.0)
    dust_noise = ramp(noise(70.0, 4.0), 0.36, 0.6)
    dust = math("MULTIPLY", math("MULTIPLY", height_fall, dust_noise), group_in.outputs["Dust"], clamp=True)
    dust = ramp(dust, 0.15, 0.6)
    colour = mix(math("MULTIPLY", dust, 0.7), colour, DUST)

    # What survives as the army's colour: the mask channel the game reads.
    kept = math("MULTIPLY", math("SUBTRACT", 1.0, chip), math("SUBTRACT", 1.0, math("MULTIPLY", dust, 0.7)))
    mask = math("MULTIPLY", group_in.outputs["Team"], kept)

    mode = nodes.new("ShaderNodeValue")
    mode.name = OUTPUT_MODE
    mode.outputs[0].default_value = 0.0
    mask_colour = nodes.new("ShaderNodeCombineColor")
    for i in range(3):
        links.new(mask, mask_colour.inputs[i])
    final = mix(mode.outputs[0], colour, mask_colour.outputs[0])

    emission = nodes.new("ShaderNodeEmission")
    links.new(final, emission.inputs["Color"])
    links.new(emission.outputs[0], group_out.inputs[0])
    return tree


def _scaled(nodes, links, colour, factor):
    node = nodes.new("ShaderNodeVectorMath")
    node.operation = "SCALE"
    links.new(colour, node.inputs[0])
    if isinstance(factor, (int, float)):
        node.inputs["Scale"].default_value = factor
    else:
        links.new(factor, node.inputs["Scale"])
    return node.outputs[0]


def role_materials(extra: dict[str, Role] | None = None) -> dict[str, bpy.types.Material]:
    """Fresh bake materials, one per role, all wearing one rebuilt finish."""
    for material in list(bpy.data.materials):
        if material.name.startswith("role_"):
            bpy.data.materials.remove(material)
    if GROUP in bpy.data.node_groups:
        bpy.data.node_groups.remove(bpy.data.node_groups[GROUP])
    tree = _new_group()
    materials = {}
    for name, role in {**ROLES, **(extra or {})}.items():
        material = bpy.data.materials.new(f"role_{name}")
        material.use_nodes = True
        nodes = material.node_tree.nodes
        nodes.clear()
        group = nodes.new("ShaderNodeGroup")
        group.node_tree = tree
        group.inputs["Base"].default_value = (*role.colour, 1.0)
        group.inputs["Team"].default_value = 1.0 if role.team else 0.0
        group.inputs["Chip"].default_value = role.chip
        group.inputs["Dust"].default_value = role.dust
        group.inputs["Edge"].default_value = role.edge
        group.inputs["Wash"].default_value = role.wash
        out = nodes.new("ShaderNodeOutputMaterial")
        material.node_tree.links.new(group.outputs[0], out.inputs[0])
        materials[name] = material
    return materials


def set_output(mask: bool) -> None:
    """Sends the finish to the colour pass or the army-mask pass."""
    node = bpy.data.node_groups[GROUP].nodes[OUTPUT_MODE]
    node.outputs[0].default_value = 1.0 if mask else 0.0
