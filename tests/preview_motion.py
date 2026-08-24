"""Dev instrument for the ambient animation — the picture behind the numbers.

`tests/measure_motion.py` counts what survives the board's sample; this draws
it. Every judgement about an idle so far has been made from those counts, and a
count cannot say whether a moving assembly reads as one aircraft turning its
rotor or as two aircraft alternating. So this writes, into a directory you name:

  motion_sheet.png   a contact sheet — every unit, pose A above pose B, once
                     per zoom rung, nearest-upscaled so both rungs occupy the
                     same 64x96 patch of your screen;
  motion_<uid>.gif   one loop per unit, rung 2, at the manifest's cadence.

Two things it does NOT do, on purpose. It is not part of `sprite_generator.py`'s
run and writes nothing into `out/`, so the determinism diff and the snapshot
gate never see it. And it invents no numbers: the frame list and the cadence are
read from `spritegen.anim` (`AMBIENT_SHEETS`, `AMBIENT_MS`), so a third sheet or
a new beat changes the preview without anyone editing it here.

What you are looking at is the board's own pipeline, in the board's own order:
the cell is composited over the terrain it stands on FIRST — plains for land and
air, sea for the hulls, at a fixed phase coordinate — and only then decimated
with nearest to (16, 24) or (32, 48) texels, because a unit sampled on its own
and a unit sampled against ground do not break the same way at the edges. The
upscale afterwards is viewing only; it adds no information and cannot hide the
decimation, which is the point of doing it with nearest too.

The GIFs share one quantised palette across their frames — both frames are
palettised together — so nothing flickers except what the art moves.

Run: .venv/bin/python tests/preview_motion.py OUTDIR [unit ...]
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

# The package is not installed, and a file run by path puts its own directory
# on sys.path rather than the repo root, so put the root there ourselves and
# `.venv/bin/python tests/preview_motion.py` works from a bare checkout.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from spritegen import atlas, terrain  # noqa: E402
from spritegen.anim import AMBIENT_MS, AMBIENT_SHEETS  # noqa: E402
from spritegen.palette import faction_by_key  # noqa: E402
from spritegen.units import ATLAS_ORDER, UNITS, Pose  # noqa: E402

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

# The clip's frames, as poses. The manifest names the sheets and `units.Pose`
# names the keys that draw them, so the two tables have to be the same length —
# if a third sheet ever ships without a third pose, say so here rather than
# quietly previewing two frames of a three-frame clip.
if len(AMBIENT_SHEETS) != len(Pose):
    raise SystemExit(
        f"anim.AMBIENT_SHEETS has {len(AMBIENT_SHEETS)} sheets but units.Pose has "
        f"{len(Pose)} keys — preview_motion cannot tell which draws which"
    )
_POSES = tuple(Pose)


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


def board_frame(uid: str, fac, pose: Pose, size: tuple[int, int]) -> Image.Image:
    """One unit, one pose, as the board hands it to the screen at `size`:
    composited over its ground, then decimated with nearest."""
    ground = backdrop(UNITS[uid][1])
    ground.alpha_composite(atlas.unit_cell(uid, fac, pose))
    return ground.resize(size, Image.NEAREST)


def zoom(img: Image.Image, factor: int) -> Image.Image:
    """The viewing upscale. Nearest, so it adds nothing and hides nothing:
    every pixel here is one whole texel the board would light."""
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def contact_sheet(uids: list[str], frames: dict) -> Image.Image:
    """Every unit across, every pose down, one band per rung."""
    cell_w, cell_h = atlas.CELL_W, atlas.CELL_H
    band_h = LABEL_H + len(_POSES) * (cell_h + GAP)
    sheet = Image.new(
        "RGBA",
        (GAP + len(uids) * (cell_w + GAP), GAP + len(RUNGS) * (LABEL_H + band_h)),
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
            x = GAP + col * (cell_w + GAP)
            draw.text((x, top), uid, fill=INK)
            for i, pose in enumerate(_POSES):
                sheet.paste(
                    zoom(frames[uid, rung, pose], VIEW // rung),
                    (x, top + LABEL_H + i * (cell_h + GAP)),
                )
        top += band_h
    return sheet


def gif(path: Path, frames: list[Image.Image]) -> None:
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
        duration=AMBIENT_MS,
        loop=0,
        disposal=1,
        optimize=False,
    )


def preview(uids: list[str], outdir: Path) -> None:
    fac = faction_by_key("red")
    outdir.mkdir(parents=True, exist_ok=True)
    frames = {
        (uid, rung, pose): board_frame(uid, fac, pose, size)
        for uid in uids
        for rung, size in RUNGS.items()
        for pose in _POSES
    }
    sheet = outdir / "motion_sheet.png"
    contact_sheet(uids, frames).save(sheet)
    print(f"{sheet}  ({len(uids)} units, rungs {', '.join(map(str, RUNGS))})")
    for uid in uids:
        path = outdir / f"motion_{uid}.gif"
        gif(path, [zoom(frames[uid, 2, pose], GIF_ZOOM) for pose in _POSES])
        print(f"{path}  ({len(_POSES)} frames @ {AMBIENT_MS} ms)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: preview_motion.py OUTDIR [unit ...]")
    wanted = sys.argv[2:] or list(ATLAS_ORDER)
    unknown = [uid for uid in wanted if uid not in ATLAS_ORDER]
    if unknown:
        sys.exit(f"unknown unit(s): {', '.join(unknown)}")
    preview(wanted, Path(sys.argv[1]))
