"""Builds, bakes and exports models. Run by Blender, and only by Blender:

    blender --background --python generators/models/build_models.py -- tank city [--out DIR]

A model is a module under `modelgen/<folder>/`, and its folder is where its files
land under `assets/models/`. A module has `build(kit)` and may have `ROLES`,
`TEXTURE`, `NORMAL_TEXTURE`, `CAGE`, `REACH` and `rig(low)`. `ground` bakes the
terrain's tiles. A model that breaks `modelgen/contract.py` fails the run.
"""

import argparse
import importlib
import importlib.util
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

from modelgen import bake, contract, kit, paint  # noqa: E402
from modelgen.terrain import ground_textures  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
DEFAULT_OUT = os.path.join(REPO, "assets", "models")
FOLDERS = ("units", "buildings", "terrain", "generals")


def find(name: str):
    """The model's module and its folder."""
    for folder in FOLDERS:
        path = f"modelgen.{folder}.{name}"
        if importlib.util.find_spec(path) is not None:
            return importlib.import_module(path), folder
    raise SystemExit(f"no model named {name}")


def build(name: str, out: str, samples: int) -> list[str]:
    started = time.time()
    builder, folder = find(name)
    out_dir = os.path.join(out, folder)
    kit.clear_scene()
    roles = paint.role_materials(getattr(builder, "ROLES", None))
    low_kit = kit.Kit(name, "lo", roles)
    builder.build(low_kit)
    low = low_kit.join()
    errors = contract.check(name, low)
    high_kit = kit.Kit(name, "hi", roles)
    builder.build(high_kit)
    high = high_kit.join()
    settings = bake.BakeSettings(
        size=getattr(builder, "TEXTURE", bake.BakeSettings.size),
        normal_size=getattr(builder, "NORMAL_TEXTURE", bake.BakeSettings.normal_size),
        samples=samples,
        cage=getattr(builder, "CAGE", bake.BakeSettings.cage),
        reach=getattr(builder, "REACH", bake.BakeSettings.reach),
    )
    bake.bake(high, low, out_dir, settings)
    bpy.data.objects.remove(high, do_unlink=True)
    low.name = name
    low.data.materials.clear()
    for obj in bpy.data.objects:
        obj.select_set(False)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    rigged = hasattr(builder, "rig")
    if rigged:
        builder.rig(low)
    for marker, position in low_kit.markers.items():
        empty = bpy.data.objects.new(marker, None)
        empty.location = position
        bpy.context.scene.collection.objects.link(empty)
        empty.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(out_dir, f"{name}.glb"),
        export_format="GLB",
        use_selection=True,
        export_tangents=True,
        export_normals=True,
        export_materials="NONE",
        export_yup=True,
        export_skins=True,
        export_animations=False,
    )
    low.data.calc_loop_triangles()
    print(f"MODEL {name}: {len(low.data.loop_triangles)} tris, {time.time() - started:.0f} s")
    return errors


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("names", nargs="+")
    parser.add_argument("--out", default=DEFAULT_OUT)
    parser.add_argument("--samples", type=int, default=bake.BakeSettings.samples)
    args = parser.parse_args(argv)
    errors = []
    for name in args.names:
        if name == "ground":
            ground_textures.bake_tiles(os.path.join(args.out, "terrain"))
        else:
            errors += build(name, args.out, args.samples)
    for error in errors:
        print(f"CONTRACT BROKEN: {error}")
    if errors:
        sys.exit(1)


main()
