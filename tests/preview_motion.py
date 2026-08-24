"""Dev instrument for the unit animation clips — the picture behind the numbers.

`tests/measure_motion.py` counts what survives the board's sample; this draws
it. Every judgement about an idle so far has been made from those counts, and a
count cannot say whether a moving assembly reads as one aircraft turning its
rotor or as two aircraft alternating. `--clip {ambient,move}` picks which clip
is drawn (default ambient), and it writes, into a directory you name:

  motion_sheet_<clip>.png  a contact sheet — every unit, one row per pose of
                           the clip, once per zoom rung, nearest-upscaled so
                           both rungs occupy the same 64x96 patch of your
                           screen;
  motion_<clip>_<uid>.gif  one loop per unit, rung 2, at that clip's cadence.

The move clip is drawn FLIPPED as well by default (`--no-flip` turns it off,
`--flip` forces it on for any clip): the sheets are the left-facing art and the
game mirrors them about the cell centre for a rightward move, so the contact
sheet puts each unit's frames next to their `FLIP_LEFT_RIGHT` mirror. Nothing
in a move frame may encode screen-handedness, and the mirror is the only place
that shows.

Two things it does NOT do, on purpose. It is not part of `sprite_generator.py`'s
run and writes nothing into `out/`, so the determinism diff and the snapshot
gate never see it. And it invents no numbers: the frame list and the cadence are
read from `spritegen.units` (`CLIP_POSES`) and `spritegen.anim` (the clip's
sheet tuple and its `*_MS`), so a third sheet or a new beat changes the preview
without anyone editing it here.

What you are looking at is the board's own pipeline, in the board's own order:
the cell is composited over the terrain it stands on FIRST — plains for land and
air, sea for the hulls, at a fixed phase coordinate — and only then decimated
with nearest to (16, 24) or (32, 48) texels, because a unit sampled on its own
and a unit sampled against ground do not break the same way at the edges. The
upscale afterwards is viewing only; it adds no information and cannot hide the
decimation, which is the point of doing it with nearest too.

The GIFs share one quantised palette across their frames — both frames are
palettised together — so nothing flickers except what the art moves.

Run: .venv/bin/python tests/preview_motion.py OUTDIR [--clip {ambient,move}]
     [--flip | --no-flip] [unit ...]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw

# The package is not installed, and a file run by path puts its own directory
# on sys.path rather than the repo root, so put the root there ourselves and
# `.venv/bin/python tests/preview_motion.py` works from a bare checkout.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from spritegen import atlas, terrain  # noqa: E402
from spritegen.anim import (  # noqa: E402
    AMBIENT_MS,
    AMBIENT_SHEETS,
    MOVE_MS,
    MOVE_SHEETS,
)
from spritegen.palette import faction_by_key  # noqa: E402
from spritegen.units import ATLAS_ORDER, CLIP_POSES, UNITS, Pose  # noqa: E402

# The rungs `measure_motion` reads, and how far each is upscaled to land back
# on a 64x96 patch: rung r samples the cell to (16r, 24r), so 4 // r restores
# it. Keeping the two rungs the same size on screen is what makes the sheet
# comparable down a column.
RUNGS = {1: (16, 24), 2: (32, 48)}
VIEW = 4
# The GIF's own viewing scale, on top of its rung-2 sample. The sheet is where
# scale is fixed, because it is read side by side; a loop is watched on its
# own, and a 32x48 sample at 1:1 is too small to watch. Also nearest.
GIF_ZOOM = 4
# The board coordinate the backdrop is drawn at. Plains and sea both ship phase
# variants, so a preview has to pick a cell; this one is fixed rather than
# hashed per unit, so every column stands on the same ground.
BACKDROP_XY = (0, 1)
# Sheet furniture.
GAP = 6
LABEL_H = 12
INK = (232, 232, 232, 255)
PAPER = (24, 24, 28, 255)

# Each previewable clip, as the two tables that have to agree about it: the
# sheets `anim` publishes and the cadence they play at. The poses come from
# `units.CLIP_POSES` under the same key, so a clip is named once.
CLIP_SHEETS = {
    "ambient": (AMBIENT_SHEETS, AMBIENT_MS),
    "move": (MOVE_SHEETS, MOVE_MS),
}


def clip_poses(clip: str) -> tuple[Pose, ...]:
    """The clip's frames, as poses, gated against its sheet count.

    The manifest names a clip's sheets and `units.CLIP_POSES` names the keys
    that draw them, so the two tables have to be the same length — if a third
    sheet ever ships without a third pose, say so here rather than quietly
    previewing two frames of a three-frame clip.
    """
    sheets, _ = CLIP_SHEETS[clip]
    poses = CLIP_POSES[clip]
    if len(sheets) != len(poses):
        raise SystemExit(
            f"the {clip} clip has {len(sheets)} sheets but "
            f"units.CLIP_POSES[{clip!r}] has {len(poses)} keys — preview_motion "
            "cannot tell which draws which"
        )
    return poses


def backdrop(kind: str) -> Image.Image:
    """The ground under a cell, as the board stacks it.

    A cell is CELL_H tall over a CELL_W tile, so it stands on its own tile and
    hangs `CELL_H - CELL_W` px over the tile behind — the same overflow the
    manifest publishes. Both tiles are here, so the part of the sprite that
    rides up over the row above is judged against the ground it rides over.
    """
    tid = "sea" if kind == "sea" else "plains"
    x, y = BACKDROP_XY
    img = Image.new("RGBA", (atlas.CELL_W, atlas.CELL_H), PAPER)
    img.paste(
        atlas.phased_tile(tid, x, y - 1).convert("RGBA"),
        (0, atlas.CELL_H - 2 * terrain.CELL),
    )
    img.paste(
        atlas.phased_tile(tid, x, y).convert("RGBA"),
        (0, atlas.CELL_H - terrain.CELL),
    )
    return img


def board_frame(
    uid: str, fac, pose: Pose, size: tuple[int, int], flip: bool = False
) -> Image.Image:
    """One unit, one pose, as the board hands it to the screen at `size`:
    composited over its ground, then decimated with nearest.

    `flip` mirrors the CELL and not the ground, because that is what the
    consumer does: `Sprite2D.flip_h` about the cell centre, over terrain that
    never mirrors. Mirroring the composite instead would flip the ground's own
    lighting and make the sprite look wrong for the ground's reason.
    """
    ground = backdrop(UNITS[uid][1])
    cell = atlas.unit_cell(uid, fac, pose)
    if flip:
        cell = cell.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    ground.alpha_composite(cell)
    return ground.resize(size, Image.NEAREST)


def zoom(img: Image.Image, factor: int) -> Image.Image:
    """The viewing upscale. Nearest, so it adds nothing and hides nothing:
    every pixel here is one whole texel the board would light."""
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def contact_sheet(
    uids: list[str], frames: dict, poses: tuple[Pose, ...], flip: bool
) -> Image.Image:
    """Every unit across, every pose down, one band per rung.

    With `flip`, a unit occupies two adjacent columns — its frames as authored
    and the same frames mirrored — so the pair is read side by side, which is
    the only way to see that a stride does not encode screen-handedness.
    """
    cell_w, cell_h = atlas.CELL_W, atlas.CELL_H
    sides = (False, True) if flip else (False,)
    unit_w = len(sides) * (cell_w + GAP)
    band_h = LABEL_H + len(poses) * (cell_h + GAP)
    sheet = Image.new(
        "RGBA",
        (GAP + len(uids) * unit_w, GAP + len(RUNGS) * (LABEL_H + band_h)),
        PAPER,
    )
    draw = ImageDraw.Draw(sheet)
    top = GAP
    for rung, size in RUNGS.items():
        draw.text(
            (GAP, top),
            # ASCII only: the drawn label uses Pillow's bitmap default font,
            # which has no glyph for an em dash and would draw a box.
            f"rung {rung} - {size[0]}x{size[1]} texels, shown {VIEW // rung}x",
            fill=INK,
        )
        top += LABEL_H
        for col, uid in enumerate(uids):
            x0 = GAP + col * unit_w
            for s, mirrored in enumerate(sides):
                x = x0 + s * (cell_w + GAP)
                draw.text((x, top), f"{uid} flip" if mirrored else uid, fill=INK)
                for i, pose in enumerate(poses):
                    sheet.paste(
                        zoom(frames[uid, rung, pose, mirrored], VIEW // rung),
                        (x, top + LABEL_H + i * (cell_h + GAP)),
                    )
        top += band_h
    return sheet


def gif(path: Path, frames: list[Image.Image], ms: int) -> None:
    """Write the loop, with ONE palette for the whole clip.

    Quantising each frame on its own gives each its own 256 colours, and the
    two then disagree about pixels the art never touched — the loop flickers
    where it should hold still. So the frames are palettised as a single strip
    and cut back apart, and dithering is off for the same reason: an error
    diffusion is a second animation.
    """
    w, h = frames[0].size
    strip = Image.new("RGB", (w * len(frames), h))
    for i, frame in enumerate(frames):
        strip.paste(frame.convert("RGB"), (i * w, 0))
    strip = strip.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=0)
    cut = [strip.crop((i * w, 0, (i + 1) * w, h)) for i in range(len(frames))]
    cut[0].save(
        path,
        save_all=True,
        append_images=cut[1:],
        duration=ms,
        loop=0,
        disposal=1,
        optimize=False,
    )


def preview(
    uids: list[str], outdir: Path, clip: str = "ambient", flip: bool | None = None
) -> None:
    """Draw one clip. `flip` defaults to on for the move clip, off otherwise —
    move is the only clip the consumer mirrors."""
    poses = clip_poses(clip)
    ms = CLIP_SHEETS[clip][1]
    if flip is None:
        flip = clip == "move"
    fac = faction_by_key("red")
    outdir.mkdir(parents=True, exist_ok=True)
    frames = {
        (uid, rung, pose, mirrored): board_frame(uid, fac, pose, size, mirrored)
        for uid in uids
        for rung, size in RUNGS.items()
        for pose in poses
        for mirrored in ((False, True) if flip else (False,))
    }
    sheet = outdir / f"motion_sheet_{clip}.png"
    contact_sheet(uids, frames, poses, flip).save(sheet)
    print(f"{sheet}  ({len(uids)} units, rungs {', '.join(map(str, RUNGS))})")
    for uid in uids:
        path = outdir / f"motion_{clip}_{uid}.gif"
        gif(path, [zoom(frames[uid, 2, pose, False], GIF_ZOOM) for pose in poses], ms)
        print(f"{path}  ({len(poses)} frames @ {ms} ms)")


def main(argv: list[str]) -> None:
    parser = argparse.ArgumentParser(
        description="Draw a clip's frames the way the board samples them.",
    )
    parser.add_argument("outdir", metavar="OUTDIR", help="where the files are written")
    parser.add_argument(
        "--clip",
        choices=sorted(CLIP_SHEETS),
        default="ambient",
        help="which clip to draw (default: ambient)",
    )
    parser.add_argument(
        "--flip",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="show each unit beside its mirror (default: on for the move clip)",
    )
    parser.add_argument(
        "unit",
        nargs="*",
        help="uids to draw (default: the whole atlas, in column order)",
    )
    args = parser.parse_args(argv)
    wanted = args.unit or list(ATLAS_ORDER)
    unknown = [uid for uid in wanted if uid not in ATLAS_ORDER]
    if unknown:
        sys.exit(f"unknown unit(s): {', '.join(unknown)}")
    preview(wanted, Path(args.outdir), args.clip, args.flip)


if __name__ == "__main__":
    main(sys.argv[1:])
