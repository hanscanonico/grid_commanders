"""A look at what the light model and the head module draw, for a human.

Not a test — `unittest discover` matches `test*.py`, so this file is never
collected. It renders the stand-in bust `test_geometry.py` measures over a row
of stand-in specs, at 1x and at 4x nearest-neighbour beside it, and writes one
PNG a reviewer can open.

The stand-in is deliberately not a general: the roster is slice D's and the
uniform, hair and features are slice C's. It is a skull, a neck, a plain
shoulder block and a flat field — the least a bust can be and still show
whether the four bands, the rim, the occlusion band and the cast shadow are
doing their jobs.

Run: .venv/bin/python tests/preview_sheet.py [-o OUT.png]
"""

from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from PIL import Image  # noqa: E402

from portraitgen import head, light  # noqa: E402
from portraitgen.canvas import INK_FEATURE, Canvas  # noqa: E402
from portraitgen.palette import INK, faction_by_key  # noqa: E402

# A skin base and a cloth base to build ramps off. Both are stand-ins: the
# roster's five skins and the faction cloth arrive with slices C and D.
SKIN: tuple[int, int, int] = (217, 160, 102)
FIELD: tuple[int, int, int] = (43, 47, 52)

# The shoulder mass the handoff draws, as a block, and the plane of it the key
# does not reach: the uniform module owns the real cut. It is here because the
# sheet's light test reads the shoulders and nothing else.
SHOULDER = (
    (12.0, 268.0),
    (12.0, 248.0),
    (64.0, 208.0),
    (156.0, 208.0),
    (208.0, 248.0),
    (208.0, 268.0),
)
SHOULDER_SHADE = ((156.0, 208.0), (208.0, 248.0), (208.0, 268.0), (140.0, 268.0))

# The stand-in row: one skull per jaw, and the two dials that pick a face-shade
# geometry, so a preview shows all three of them side by side.
ROW: tuple[tuple[str, head.Skull], ...] = (
    ("round", head.Skull(1.0, "round", 0.0, 1.0)),
    ("square-wide", head.Skull(1.14, "square", 0.0, 1.0)),
    ("tapered-lifted", head.Skull(0.9, "tapered", 3.0, 1.0)),
)


def bust(
    skull: head.Skull, faction: str = "meridian", *, cast: bool = True
) -> Image.Image:
    """One stand-in bust on its field: backdrop, cast, uniform block, head.

    `cast=False` is the same bust with the hard offset shadow left off, which
    is how C1 is measured — the difference between the two is the shadow.
    """
    theme = faction_by_key(faction)
    cloth = light.build_ramp(theme.body, rim_hue=theme.body_lt)
    skin = light.build_ramp(SKIN, rim_hue=theme.body_lt)

    figure = Canvas()
    figure.polygon(SHOULDER, cloth.base)
    figure.polygon(SHOULDER_SHADE, cloth.shade)
    figure.stroke(SHOULDER[1:-1], INK_FEATURE, (*INK, 255))
    head.draw(figure, skull, skin)

    sheet = Canvas()
    sheet.fill((*FIELD, 255))
    if cast:
        sheet.cast_shadow(figure)
    sheet.compose(figure)
    return sheet.resolve()


def contact_sheet() -> Image.Image:
    """Every stand-in at 1x, and again at 4x nearest-neighbour beside it."""
    cells = [bust(skull) for _, skull in ROW]
    width, height = cells[0].size
    sheet = Image.new("RGBA", (len(cells) * width * 5, height * 4), (0, 0, 0, 255))
    for index, cell in enumerate(cells):
        x = index * width * 5
        sheet.paste(cell, (x, 0))
        sheet.paste(
            cell.resize((width * 4, height * 4), Image.Resampling.NEAREST),
            (x + width, 0),
        )
    return sheet


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("-o", "--out", type=Path, default=None, help="where to write")
    args = ap.parse_args()
    out = args.out or Path(tempfile.gettempdir()) / "portrait_preview.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    contact_sheet().save(out)
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
