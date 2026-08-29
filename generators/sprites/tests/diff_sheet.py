"""The picture the snapshot gate owes a reviewer when a sheet has changed.

Most snapshot failures are an art change somebody meant, so the gate's job is
not only to say a sheet moved but to show how: one PNG per differing sheet,
installed art beside the fresh generation beside a map of the pixels that
moved, cropped to the cells that changed and scaled up so a one-pixel outline
shift is visible without a loupe.

The sheets go to a gitignored reports directory, being a reading of one run
rather than an output anything else consumes.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageChops

REPORT_DIR = Path(__file__).resolve().parents[3] / "reports" / "sprite_snapshot_diffs"

BACKDROP = (24, 24, 28, 255)
GUTTER = (90, 90, 100, 255)
HIGHLIGHT = (255, 0, 200, 255)
GUTTER_PX = 2
PAD_PX = 2
SCALE = 8
# Tried in order against a sheet's dimensions: the tall unit cell, then the
# square terrain and autotile cell.
CELL_GUESSES = ((64, 96), (64, 64))
# Scale up until the sheet is about this wide; a crop already wider than it
# is shown at 1:1 rather than shrunk.
SCALE_TO_WIDTH = 2048


@dataclass(frozen=True)
class DiffReport:
    """What one differing sheet cost, and where to look at it."""

    path: Path
    pixels: int
    cells: int

    def note(self, baseline: Path) -> str:
        counted = f"{self.pixels} pixels"
        if self.cells:
            counted += f" in {self.cells} cells"
        return f"pixel mismatch: {baseline} ({counted}) — see {self.path}"


def cell_grid(size: tuple[int, int]) -> tuple[int, int] | None:
    """The cell size a sheet is a grid of, or None if it is one picture.

    Guessed from the sheet's own dimensions rather than read off the
    generator, which this gate deliberately does not import: the grid only
    decides where the picture is cropped, so a guess that misses costs a
    wider crop and nothing else.
    """
    for grid in CELL_GUESSES:
        w, h = size
        if not (w % grid[0] or h % grid[1] or (w, h) == grid):
            return grid
    return None


def _mask(before: Image.Image, after: Image.Image) -> Image.Image:
    bands = ImageChops.difference(before, after).split()
    lit = bands[0]
    for band in bands[1:]:
        lit = ImageChops.lighter(lit, band)
    return lit.point(lambda v: 255 if v else 0)


def _region(
    mask: Image.Image, grid: tuple[int, int] | None
) -> tuple[int, int, int, int]:
    left, top, right, bottom = mask.getbbox()
    if grid is None:
        return (
            max(0, left - PAD_PX),
            max(0, top - PAD_PX),
            min(mask.width, right + PAD_PX),
            min(mask.height, bottom + PAD_PX),
        )
    cw, ch = grid
    return (
        left // cw * cw,
        top // ch * ch,
        min(mask.width, -(-right // cw) * cw),
        min(mask.height, -(-bottom // ch) * ch),
    )


def _changed_cells(mask: Image.Image, grid: tuple[int, int] | None) -> int:
    if grid is None:
        return 0
    cw, ch = grid
    return sum(
        mask.crop((x, y, x + cw, y + ch)).getbbox() is not None
        for y in range(0, mask.height, ch)
        for x in range(0, mask.width, cw)
    )


def _on_backdrop(panel: Image.Image) -> Image.Image:
    plate = Image.new("RGBA", panel.size, BACKDROP)
    plate.alpha_composite(panel)
    return plate


def _diff_panel(after: Image.Image, mask: Image.Image) -> Image.Image:
    faded = Image.blend(
        _on_backdrop(after), Image.new("RGBA", after.size, BACKDROP), 0.75
    )
    faded.paste(Image.new("RGBA", after.size, HIGHLIGHT), mask=mask)
    return faded


def build_sheet(
    before: Image.Image, after: Image.Image, grid: tuple[int, int] | None
) -> tuple[Image.Image, int, int]:
    """installed | generated | what moved, cropped and scaled up.

    Returns the sheet, the count of differing pixels and of differing cells
    (0 when the sheet is not a grid).
    """
    before = before.convert("RGBA")
    after = after.convert("RGBA")
    mask = _mask(before, after)
    pixels = mask.histogram()[255]
    if not pixels:
        raise ValueError("no pixels differ")
    cells = _changed_cells(mask, grid)
    box = _region(mask, grid)
    panels = [
        _on_backdrop(before.crop(box)),
        _on_backdrop(after.crop(box)),
        _diff_panel(after.crop(box), mask.crop(box)),
    ]
    w, h = panels[0].size
    scale = max(1, min(SCALE, (SCALE_TO_WIDTH - 2 * GUTTER_PX) // (3 * w)))
    w, h = w * scale, h * scale
    sheet = Image.new("RGBA", (3 * w + 2 * GUTTER_PX, h), GUTTER)
    for i, panel in enumerate(panels):
        sheet.paste(panel.resize((w, h), Image.NEAREST), (i * (w + GUTTER_PX), 0))
    return sheet, pixels, cells


def write_diff_sheet(
    generated: Path, baseline: Path, relpath: Path, out_dir: Path = REPORT_DIR
) -> DiffReport:
    before = Image.open(baseline)
    after = Image.open(generated)
    sheet, pixels, cells = build_sheet(before, after, cell_grid(before.size))
    out_dir.mkdir(parents=True, exist_ok=True)
    stem = relpath.with_suffix("").as_posix().replace("/", "_")
    path = out_dir / f"{stem}_diff.png"
    sheet.save(path)
    return DiffReport(path, pixels, cells)
