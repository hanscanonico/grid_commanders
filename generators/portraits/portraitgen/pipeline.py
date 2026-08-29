"""Deterministic portrait pipeline for grid_commanders.

Bakes the art `CommanderVisuals` loads: the five 64x64 faction emblems and the
twenty-three 220x268 commander busts. There are no seeds and no randomness —
every mark is authored, so every run reproduces the same bytes.

`OUTPUTS` is the one statement of what a run produces. Each `Output` carries
the directory of a game checkout it installs into, so `install` derives its copy
list from the same table `generate` writes from rather than from a second list
that has to be kept in step.

Outputs (under --out, default ./out):
  factions/<key>.png     64x64 RGBA emblem — drop-in for assets/portraits/factions
  commanders/<id>.png    220x268 RGBA bust — drop-in for assets/portraits/commanders
"""

from __future__ import annotations

import argparse
import shutil
import sys
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from functools import partial
from pathlib import Path

from PIL import Image

from .bust import busts as painted_busts
from .emblem import draw as draw_emblem
from .palette import EMBLEM_KEYS

# Where each kind of output lands in a grid_commanders checkout.
EMBLEMS, EMBLEMS_DIR = "factions", "assets/portraits/factions"
BUSTS, BUSTS_DIR = "commanders", "assets/portraits/commanders"


@dataclass(frozen=True)
class Output:
    """One file a run produces: its path under --out, how it is built, and the
    directory `--install` copies it into — `None` for a review image, which is
    for a human to look at and no part of the game."""

    rel: str
    build: Callable[[], Image.Image]
    install_to: str | None = None


def emblems() -> Iterator[Output]:
    """One emblem per army, in the order the game rows them."""
    for key in EMBLEM_KEYS:
        yield Output(f"{EMBLEMS}/{key}.png", partial(draw_emblem, key), EMBLEMS_DIR)


def busts() -> Iterator[Output]:
    """One bust per general, and the empty seat.

    The whole sheet is painted once here rather than per output: a bust is
    twenty-odd milliseconds, and building them together is what lets `Output`
    stay a plain "one file, one image" record.
    """
    for painted in painted_busts():
        yield Output(f"{BUSTS}/{painted.id}.png", lambda p=painted: p.image, BUSTS_DIR)


# Every file a full run writes, in the order it writes them.
OUTPUTS: tuple[Output, ...] = (*emblems(), *busts())


def generate(out: Path, *, log: Callable[[str], None] = print) -> None:
    """Write every output under `out`."""
    log(f"drawing {len(OUTPUTS)} portrait outputs")
    for output in OUTPUTS:
        path = out / output.rel
        path.parent.mkdir(parents=True, exist_ok=True)
        output.build().save(path)
        log(f"  wrote {path}")


def install(src: Path, dest: Path) -> int:
    """Copy a generated tree into a grid_commanders checkout; returns how many
    files landed."""
    pairs = [
        (src / o.rel, dest / o.install_to / Path(o.rel).name)
        for o in OUTPUTS
        if o.install_to is not None
    ]
    for source, target in pairs:
        if not source.exists():
            sys.exit(f"missing {source} — run a full generation first")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    print(f"installed {len(pairs)} files into {dest}")
    return len(pairs)


def _parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument(
        "-o", "--out", type=Path, default=Path("out"), help="output directory"
    )
    ap.add_argument(
        "--install",
        type=Path,
        metavar="GAME_DIR",
        help="copy the baked art into a grid_commanders checkout "
        "(explicit path required — no default destination, deliberately)",
    )
    return ap


def main() -> int:
    args = _parser().parse_args()
    generate(args.out)
    if args.install is not None:
        install(args.out, args.install)
    return 0
