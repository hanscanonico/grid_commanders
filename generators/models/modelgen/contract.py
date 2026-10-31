"""The size contract the board places models by, checked on every build.

One cell is one Blender unit. A model faces +X and stands on Z = 0 (a ship's
origin is its waterline, an aircraft's its belly). These numbers mirror
`tests/unit/test_unit_models_3d.gd`, which holds the game to them too.
"""

from __future__ import annotations

from dataclasses import dataclass

TOLERANCE = 0.005


@dataclass(frozen=True)
class Limits:
    half: float
    floor: float
    top: float
    least_top: float = 0.0


LAND = Limits(0.42, 0.0, 0.42, 0.22)
AIR = Limits(0.42, 0.0, 0.32)
SEA = Limits(0.42, -0.06, 0.45)
PROPERTY = Limits(0.46, 0.0, 0.85)

LIMITS = {
    **{name: LAND for name in ("infantry", "mech", "recon", "tank", "md_tank", "apc", "anti_air", "rockets", "missiles")},
    "artillery": Limits(0.42, 0.0, 0.8, 0.22),
    "infantry_lone": Limits(0.42, 0.0, 0.6),
    "mech_lone": Limits(0.42, 0.0, 0.6),
    **{name: AIR for name in ("fighter", "bomber", "b_copter", "t_copter")},
    **{name: SEA for name in ("battleship", "cruiser", "lander")},
    "sub": Limits(0.42, -0.1, 0.45),
    **{name: PROPERTY for name in ("city", "base", "airport", "port", "hq")},
}


def check(name: str, obj) -> list[str]:
    """What a built model breaks, as lines to print; empty when it fits."""
    limits = LIMITS.get(name)
    world = [obj.matrix_world @ v.co for v in obj.data.vertices]
    xs, ys, zs = [p.x for p in world], [p.y for p in world], [p.z for p in world]
    print(
        f"BOUNDS {name}: x {min(xs):.3f}..{max(xs):.3f}  y {min(ys):.3f}..{max(ys):.3f}  "
        f"z {min(zs):.3f}..{max(zs):.3f}"
    )
    if limits is None:
        return []
    errors = []
    if max(abs(min(xs)), abs(max(xs)), abs(min(ys)), abs(max(ys))) > limits.half + TOLERANCE:
        errors.append(f"{name} reaches past its footprint of +-{limits.half}")
    if min(zs) < limits.floor - TOLERANCE:
        errors.append(f"{name} dips below {limits.floor}")
    if max(zs) > limits.top + TOLERANCE:
        errors.append(f"{name} stands above {limits.top}")
    if max(zs) < limits.least_top - TOLERANCE:
        errors.append(f"{name} stands below {limits.least_top}")
    return errors
