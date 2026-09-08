"""A look at what a slice draws, for a reviewer rather than for a gate.

Not a test — `unittest discover` matches `test*.py`, so this file is never
collected. Each part renders one slice's layers over a stand-in of the ones it
does not own, at the pinned raster and again at four times nearest-neighbour,
because what a portrait does under decimation is the whole argument.

    .venv/bin/python tests/preview_sheet.py --part light_head -o /tmp/look

`light_head` is the bust `test_geometry.py` measures: a skull, a neck, a plain
shoulder block and a flat field — the least a bust can be and still show whether
the four bands, the rim, the occlusion band and the cast shadow are doing their
jobs. `uniform_props_backdrop` dresses that stand-in in every collar, chest
treatment, prop and window field. `features_hair` puts one cell on the sheet per
key of every vocabulary the face and the hair answer for. `sheet` is the whole
roster as the game will load it: all twenty-three busts at 110x134 over one row
per faction, and the face-chip strip under them, which is the diagnostic
image — a bust that cannot be told from its neighbour at chip size has not been
drawn yet. `board` is the reviewer's own question, "is this one style": every
bust beside a strip of the board's own art — 16px terrain cells and 64x96 unit
cells as the game draws them — at one shared zoom.

Run it from the package root, the way the suite is run, so `portraitgen` is on
the path.
"""

from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from PIL import Image  # noqa: E402

from portraitgen import bust as painter  # noqa: E402
from portraitgen import (  # noqa: E402
    backdrop,
    features,
    hair,
    head,
    light,
    props,
    roster,
    uniform,
)
from portraitgen.canvas import (  # noqa: E402
    BUST_SIZE,
    INK_FEATURE,
    Canvas,
)
from portraitgen.palette import (  # noqa: E402
    FACTIONS,
    INK,
    Faction,
    faction_by_key,
)

ZOOM = 4

# A skin base to build a ramp off, and the flat field the light part poses on.
# The skin is a stand-in: the roster's five skins arrive with slice D.
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

# The face the vocabulary sheet is drawn on, and how wide that sheet runs.
SKULL = head.Skull(*head.HEAD_DEFAULT)
COLUMNS = 10

# The stand-in skull for the dressed part, so a prop that reaches for a jaw has
# one to reach for.
HEAD = (54.0, 84.0, 166.0, 196.0)


def bust(
    skull: head.Skull, faction: str = "meridian", *, cast: bool = True
) -> Image.Image:
    """One stand-in bust on its field: backdrop, cast, uniform block, head.

    `cast=False` is the same bust with the hard offset shadow left off, which
    is how C1 is measured — the difference between the two is the shadow.
    """
    theme = faction_by_key(faction)
    cloth = light.faction_ramp(theme.key)
    skin = light.build_ramp(SKIN, rim_hue=cloth.rim)

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
            cell.resize((width * ZOOM, height * ZOOM), Image.Resampling.NEAREST),
            (x + width, 0),
        )
    return sheet


def _dressed(
    faction: Faction, collar: str, treatment: str, prop: str, kind: str
) -> Image.Image:
    ramp = light.faction_ramp(faction.key)
    canvas = Canvas()
    backdrop.draw(canvas, kind, faction)
    props.draw(canvas, prop, faction, ramp, layer="back")
    uniform.draw(canvas, faction, collar, ramp)
    canvas.ellipse(HEAD, (*ramp.base, 255))
    uniform.chest(canvas, treatment, faction, ramp)
    uniform.pip(canvas, ramp)
    props.draw(canvas, prop, faction, ramp, layer="front")
    return canvas.resolve()


def _row(busts: list[Image.Image]) -> Image.Image:
    width, height = BUST_SIZE
    sheet = Image.new("RGBA", (width * len(busts), height), (35, 39, 43, 255))
    for index, drawn in enumerate(busts):
        sheet.alpha_composite(drawn, (index * width, 0))
    return sheet


def _chip_strip(chips: list[Image.Image]) -> Image.Image:
    side = chips[0].height
    strip = Image.new("RGBA", (side * len(chips), side), (35, 39, 43, 255))
    for index, chip in enumerate(chips):
        strip.alpha_composite(chip, (index * side, 0))
    return strip.resize(
        (strip.width * ZOOM, strip.height * ZOOM), Image.Resampling.NEAREST
    )


def _light_head(out: Path) -> list[Path]:
    """The bare bust the light model and the head module are read off."""
    return [_write(out / "light_head.png", contact_sheet())]


def _uniform_props_backdrop(out: Path) -> list[Path]:
    """One bust per faction over every backdrop, then a pass down the props."""
    kinds = sorted(backdrop.KINDS)
    collars = sorted(uniform.COLLAR_CUTS)
    treatments = sorted(uniform.CHEST_TREATMENTS)
    every = sorted(props.PROPS)
    written: list[Path] = []

    dressed = [
        _dressed(
            faction,
            collars[index % len(collars)],
            treatments[index % len(treatments)],
            every[index % len(every)],
            kinds[index % len(kinds)],
        )
        for index, faction in enumerate(FACTIONS)
    ]
    written.append(_write(out / "factions.png", _row(dressed)))

    meridian = faction_by_key("meridian")
    fields = [_dressed(meridian, "v", "plain", "book", kind) for kind in kinds]
    written.append(_write(out / "backdrops.png", _row(fields)))

    for start in range(0, len(every), 6):
        batch = every[start : start + 6]
        drawn = [
            _dressed(
                faction_by_key("iron"),
                collars[index % len(collars)],
                treatments[index % len(treatments)],
                prop,
                "grid",
            )
            for index, prop in enumerate(batch, start)
        ]
        written.append(_write(out / f"props_{start // 6}.png", _row(drawn)))
    return written


def _face(skin: light.Ramp) -> Canvas:
    """A cell: the field, and the head every feature is drawn onto."""
    cell = Canvas()
    cell.fill((*FIELD, 255))
    head.draw(cell, SKULL, skin)
    return cell


def _worn(skin: light.Ramp, mane: light.Ramp) -> list[Canvas]:
    """One cell per key of every vocabulary the two modules answer for."""
    cells: list[Canvas] = []
    for kind in sorted(features.EYE_KINDS):
        cell = _face(skin)
        features.eyes(cell, SKULL, kind, scale=features.EYE_DEFAULT)
        cells.append(cell)
    for kind in sorted(features.BROW_KINDS):
        cell = _face(skin)
        features.brow(cell, SKULL, kind, mane)
        cells.append(cell)
    for kind in sorted(features.NOSE_KINDS):
        cell = _face(skin)
        features.nose(cell, SKULL, kind, skin)
        cells.append(cell)
    for kind in sorted(features.MOUTH_KINDS):
        cell = _face(skin)
        features.mouth(cell, SKULL, kind)
        cells.append(cell)
    for kind in sorted(features.FACIAL_KINDS):
        cell = _face(skin)
        features.facial_hair(cell, SKULL, kind, mane)
        cells.append(cell)
    for kind in sorted(features.ACCESSORY_KINDS):
        cell = _face(skin)
        features.accessory(cell, SKULL, kind)
        cells.append(cell)
    for style in sorted(hair.STYLES):
        cell = _face(skin)
        hair.draw(cell, SKULL, style, mane, skin=skin)
        cells.append(cell)
    return cells


def _grid(cells: list[Canvas]) -> Image.Image:
    width, height = BUST_SIZE
    rows = -(-len(cells) // COLUMNS)
    page = Image.new("RGBA", (width * COLUMNS, height * rows), (0, 0, 0, 255))
    for index, cell in enumerate(cells):
        spot = (index % COLUMNS * width, index // COLUMNS * height)
        page.paste(cell.resolve(), spot)
    return page


def _sheet(out: Path) -> list[Path]:
    """The roster itself: one row per faction, and the chip strip under it."""
    rows = [
        [roster.FACES[key] for key in sorted(roster.FACES) if _army(key) == army]
        for army in ("meridian", "iron", "aurora", "verdant")
    ]
    painted = [[painter.paint(face) for face in row] for row in rows]
    painted.append([painter.paint(roster.NEUTRAL)])
    width, height = BUST_SIZE
    page = Image.new(
        "RGBA",
        (width * max(map(len, painted)), height * len(painted)),
        (35, 39, 43, 255),
    )
    for index, row in enumerate(painted):
        page.alpha_composite(_row(row), (0, index * height))
    chips = [painter.chip(face) for row in rows for face in row]
    chips.append(painter.chip(roster.NEUTRAL))
    return [
        _write(out / "contact_sheet.png", page),
        _write(out / "face_crops.png", _chip_strip(chips)),
    ]


def _army(key: str) -> str:
    return painter.FACTION_OF[key]


def _features_hair(out: Path) -> list[Path]:
    """Every eye, brow, nose, mouth, beard, accessory and hairstyle, once."""
    skin = light.build_ramp(SKIN)
    mane = hair.ramp_for("brown")
    return [_write(out / "features_hair.png", _grid(_worn(skin, mane)))]


# The board's own art, and the scale the game draws it at: a terrain cell is
# baked at 64 and laid on a 16px world grid, a unit cell at 64x96 on the same
# grid. Both are `assets/tiles`, so this part reads the game's shipped sheets
# rather than drawing a stand-in of them.
GAME = Path(__file__).resolve().parents[3]
TILE = 16
TERRAIN_PX = 64
UNIT_W, UNIT_H = 64, 96
BOARD_COLUMNS = 7


def _cells(sheet: Image.Image, size: tuple[int, int], wanted: int) -> list[Image.Image]:
    """The first `wanted` cells of an atlas that have anything drawn in them."""
    width, height = size
    found: list[Image.Image] = []
    for top in range(0, sheet.height - height + 1, height):
        for left in range(0, sheet.width - width + 1, width):
            cell = sheet.crop((left, top, left + width, top + height))
            if cell.getbbox() is not None and len(found) < wanted:
                found.append(cell)
    return found


def _board_strip() -> Image.Image:
    """A run of the board as the game lays it out: terrain cells on the world
    grid with a rank of units standing on them, all at the game's own scale."""
    terrain = Image.open(GAME / "assets/tiles/terrain_atlas.png").convert("RGBA")
    units = Image.open(GAME / "assets/tiles/units_atlas.png").convert("RGBA")
    unit_h = UNIT_H * TILE // UNIT_W
    strip = Image.new("RGBA", (BOARD_COLUMNS * TILE, TILE * 2 + unit_h), (0, 0, 0, 0))
    for index, cell in enumerate(
        _cells(terrain, (TERRAIN_PX, TERRAIN_PX), BOARD_COLUMNS * 2)
    ):
        spot = (
            index % BOARD_COLUMNS * TILE,
            unit_h - TILE + index // BOARD_COLUMNS * TILE,
        )
        strip.alpha_composite(cell.resize((TILE, TILE), Image.Resampling.BOX), spot)
    for index, cell in enumerate(_cells(units, (UNIT_W, UNIT_H), BOARD_COLUMNS)):
        strip.alpha_composite(
            cell.resize((TILE, unit_h), Image.Resampling.BOX), (index * TILE, 0)
        )
    return strip


def _board(out: Path) -> list[Path]:
    """Every bust next to the board, at one scale — the "is this one style?"
    read, which is a question about the two sheets side by side and not about
    either of them alone."""
    busts = [painter.paint(roster.FACES[key]) for key in sorted(roster.FACES)]
    busts.append(painter.paint(roster.NEUTRAL))
    width, height = BUST_SIZE
    columns = 8
    rows = -(-len(busts) // columns)
    strip = _board_strip()
    page = Image.new(
        "RGBA",
        (width * columns, height * rows + strip.height + TILE),
        (35, 39, 43, 255),
    )
    for index, drawn in enumerate(busts):
        page.alpha_composite(
            drawn, (index % columns * width, index // columns * height)
        )
    for column in range(0, page.width, strip.width):
        page.alpha_composite(strip, (column, height * rows + TILE // 2))
    return [
        _write(
            out / "board_and_busts.png",
            page.resize(
                (page.width * ZOOM, page.height * ZOOM), Image.Resampling.NEAREST
            ),
        )
    ]


def _write(path: Path, image: Image.Image) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    return path


PARTS = {
    "light_head": _light_head,
    "uniform_props_backdrop": _uniform_props_backdrop,
    "features_hair": _features_hair,
    "sheet": _sheet,
    "board": _board,
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--part", default="uniform_props_backdrop", choices=sorted(PARTS)
    )
    parser.add_argument(
        "-o", "--out", default=None, help="where to write (default: a temp dir)"
    )
    args = parser.parse_args()
    out = (
        Path(args.out)
        if args.out
        else Path(tempfile.mkdtemp(prefix="portrait-preview-"))
    )
    for path in PARTS[args.part](out):
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
