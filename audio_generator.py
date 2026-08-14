#!/usr/bin/env python3
"""Deterministic sound pipeline for grid_commanders.

Renders the game's nine sound effects (autoload/sfx.gd's Sfx.NAMES contract)
as authored synthesis recipes: no RNG outside per-sound seeds, so every run
reproduces the same bytes.

Outputs (under --out, default ./out):
  sfx/<name>.wav     44100 Hz mono 16-bit — drop-ins for assets/sfx/
  soundboard.html    A/B audition page: the game's current sounds against
                     this run's, with the measurements beside each pair

--install requires an explicit game checkout path on purpose: a defaulted
destination once overwrote uncommitted work in the game repo (the
sprite_generator lesson, 2026-08-14).
"""

from __future__ import annotations

import argparse
import base64
import io
import sys
import wave
from pathlib import Path

from audiogen import measure, sfx
from audiogen.dsp import RATE, seconds, to_int16


def wav_bytes(x) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(to_int16(x).tobytes())
    return buf.getvalue()


def write_all(out: Path) -> dict[str, bytes]:
    rendered: dict[str, bytes] = {}
    (out / "sfx").mkdir(parents=True, exist_ok=True)
    for name in sfx.SFX:
        data = wav_bytes(sfx.render(name))
        (out / "sfx" / f"{name}.wav").write_bytes(data)
        rendered[name] = data
        print(f"  wrote {out / 'sfx' / (name + '.wav')}")
    return rendered


def soundboard(out: Path, rendered: dict[str, bytes], game: Path) -> None:
    rows = []
    for name in sfx.SFX:
        x = sfx.render(name)
        _b, category, _p = sfx.SFX[name]
        old_path = game / "assets/sfx" / f"{name}.wav"
        old_tag = "<em>missing</em>"
        if old_path.exists():
            old64 = base64.b64encode(old_path.read_bytes()).decode()
            old_tag = f'<audio controls preload="auto" src="data:audio/wav;base64,{old64}"></audio>'
        new64 = base64.b64encode(rendered[name]).decode()
        rows.append(
            f"<tr><td><b>{name}</b><br><small>{category}</small></td>"
            f"<td>{old_tag}</td>"
            f'<td><audio controls preload="auto" src="data:audio/wav;base64,{new64}"></audio></td>'
            f'<td class="num">{seconds(len(x)):.2f}s<br>peak {measure.peak_db(x):.1f} dB'
            f"<br>rms {measure.rms_db(x):.1f} dB<br>centroid {measure.centroid_hz(x):.0f} Hz</td></tr>"
        )
    html = (
        "<title>Soundboard</title><style>"
        "body{background:#14161a;color:#e9e7e1;font:15px ui-sans-serif,sans-serif;padding:32px}"
        "h1{font-size:22px}table{border-collapse:collapse}"
        "td{padding:10px 14px;border-bottom:1px solid #32363e;vertical-align:middle}"
        "th{text-align:left;padding:8px 14px;color:#9aa0a8;font-size:12px;"
        "text-transform:uppercase;letter-spacing:.1em}"
        ".num{font-variant-numeric:tabular-nums;color:#9aa0a8;font-size:12px}"
        "audio{width:240px}</style>"
        "<h1>Grid Commanders soundboard — current vs generated</h1>"
        "<table><tr><th>Sound</th><th>Current (in game)</th><th>Generated</th>"
        "<th>Measured</th></tr>" + "".join(rows) + "</table>"
    )
    (out / "soundboard.html").write_text(html)
    print(f"  wrote {out / 'soundboard.html'}")


def install(out: Path, dest: Path) -> None:
    sfx_dir = dest / "assets/sfx"
    if not sfx_dir.is_dir():
        sys.exit(
            f"{sfx_dir} is not a directory — is {dest} a grid_commanders checkout?"
        )
    for name in sfx.SFX:
        src = out / "sfx" / f"{name}.wav"
        if not src.exists():
            sys.exit(f"missing {src} — run a full generation first")
        (sfx_dir / f"{name}.wav").write_bytes(src.read_bytes())
    print(f"installed {len(sfx.SFX)} sounds into {sfx_dir}")


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("-o", "--out", type=Path, default=Path("out"))
    ap.add_argument(
        "--game",
        type=Path,
        default=Path("../grid_commanders"),
        help="game checkout the soundboard reads current sounds from (read-only)",
    )
    ap.add_argument(
        "--install",
        type=Path,
        metavar="GAME_DIR",
        help="copy the rendered sounds into a grid_commanders checkout "
        "(explicit path required — no default destination, deliberately)",
    )
    args = ap.parse_args()

    print(f"rendering {len(sfx.SFX)} sound effects")
    rendered = write_all(args.out)
    soundboard(args.out, rendered, args.game)
    if args.install is not None:
        install(args.out, args.install)


if __name__ == "__main__":
    main()
