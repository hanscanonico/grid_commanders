#!/usr/bin/env python3
"""Deterministic sound pipeline for grid_commanders.

Renders the game's nine sound effects (autoload/sfx.gd's Sfx.NAMES contract)
and its two looping music tracks (autoload/music.gd's Music.NAMES) as
authored recipes and song data: no RNG outside per-sound seeds, so every run
reproduces the same bytes.

Outputs (under --out, default ./out):
  sfx/<name>.wav     44100 Hz mono 16-bit — drop-ins for assets/sfx/
  music/<name>.wav   44100 Hz mono 16-bit loops — drop-ins for assets/music/
  soundboard.html    A/B audition page: the game's current sounds against
                     this run's, with the measurements beside each pair
  musicboard.html    the same for the two marches; both players loop, so
                     the seam is auditioned by just letting them play

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

from audiogen import measure, music, sfx
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


def write_music(out: Path) -> dict:
    arrays = {name: music.render(name) for name in music.MUSIC}
    (out / "music").mkdir(parents=True, exist_ok=True)
    for name, x in arrays.items():
        (out / "music" / f"{name}.wav").write_bytes(wav_bytes(x))
        print(f"  wrote {out / 'music' / (name + '.wav')}")
    return arrays


_PAGE_STYLE = (
    "body{background:#14161a;color:#e9e7e1;font:15px ui-sans-serif,sans-serif;"
    "padding:32px}h1{font-size:22px}p{color:#9aa0a8;max-width:60em}"
    "table{border-collapse:collapse}"
    "td{padding:10px 14px;border-bottom:1px solid #32363e;vertical-align:middle}"
    "th{text-align:left;padding:8px 14px;color:#9aa0a8;font-size:12px;"
    "text-transform:uppercase;letter-spacing:.1em}"
    ".num{font-variant-numeric:tabular-nums;color:#9aa0a8;font-size:12px}"
    "audio{width:240px}"
)


def _audio_tag(data: bytes, loop: bool = False) -> str:
    b64 = base64.b64encode(data).decode()
    attrs = " loop" if loop else ""
    return (
        f'<audio controls preload="auto"{attrs} '
        f'src="data:audio/wav;base64,{b64}"></audio>'
    )


def soundboard(out: Path, rendered: dict[str, bytes], game: Path) -> None:
    rows = []
    for name in sfx.SFX:
        x = sfx.render(name)
        _b, category, _p = sfx.SFX[name]
        old_path = game / "assets/sfx" / f"{name}.wav"
        old_tag = "<em>missing</em>"
        if old_path.exists():
            old_tag = _audio_tag(old_path.read_bytes())
        rows.append(
            f"<tr><td><b>{name}</b><br><small>{category}</small></td>"
            f"<td>{old_tag}</td>"
            f"<td>{_audio_tag(rendered[name])}</td>"
            f'<td class="num">{seconds(len(x)):.2f}s<br>peak {measure.peak_db(x):.1f} dB'
            f"<br>rms {measure.rms_db(x):.1f} dB<br>centroid {measure.centroid_hz(x):.0f} Hz</td></tr>"
        )
    html = (
        f"<title>Soundboard</title><style>{_PAGE_STYLE}</style>"
        "<h1>Grid Commanders soundboard — current vs generated</h1>"
        "<table><tr><th>Sound</th><th>Current (in game)</th><th>Generated</th>"
        "<th>Measured</th></tr>" + "".join(rows) + "</table>"
    )
    (out / "soundboard.html").write_text(html)
    print(f"  wrote {out / 'soundboard.html'}")


def musicboard(out: Path, arrays: dict, game: Path) -> None:
    rows = []
    for name, x in arrays.items():
        builder, _peak = music.MUSIC[name]
        song = builder()
        old_path = game / "assets/music" / f"{name}.wav"
        old_tag = "<em>missing</em>"
        if old_path.exists():
            old_tag = _audio_tag(old_path.read_bytes(), loop=True)
        rows.append(
            f"<tr><td><b>{name}</b><br><small>{song.bpm:.0f} BPM</small></td>"
            f"<td>{old_tag}</td>"
            f"<td>{_audio_tag(wav_bytes(x), loop=True)}</td>"
            f'<td class="num">{seconds(len(x)):.1f}s'
            f"<br>peak {measure.peak_db(x):.1f} dB<br>rms {measure.rms_db(x):.1f} dB"
            f"<br>tempo {measure.tempo_bpm(x):.1f} BPM"
            f"<br>seam Δ {measure.loop_rms_delta_db(x):.1f} dB</td></tr>"
        )
    distance = measure.spectral_distance(arrays["parade"], arrays["advance"])
    html = (
        f"<title>Musicboard</title><style>{_PAGE_STYLE}</style>"
        "<h1>Grid Commanders musicboard — current vs composed</h1>"
        "<p>Both players loop, so let a track run past its end: the seam is "
        "the audition. Spectral distance between the two marches: "
        f"{distance:.3f}.</p>"
        "<table><tr><th>Track</th><th>Current (in game)</th><th>Composed</th>"
        "<th>Measured</th></tr>" + "".join(rows) + "</table>"
    )
    (out / "musicboard.html").write_text(html)
    print(f"  wrote {out / 'musicboard.html'}")


def install(out: Path, dest: Path) -> None:
    for sub, names in (("sfx", sfx.SFX), ("music", music.MUSIC)):
        target = dest / "assets" / sub
        if not target.is_dir():
            sys.exit(
                f"{target} is not a directory — is {dest} a grid_commanders checkout?"
            )
        for name in names:
            src = out / sub / f"{name}.wav"
            if not src.exists():
                sys.exit(f"missing {src} — run a full generation first")
            (target / f"{name}.wav").write_bytes(src.read_bytes())
        print(f"installed {len(names)} {sub} wavs into {target}")


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
    print(f"rendering {len(music.MUSIC)} music loops")
    arrays = write_music(args.out)
    musicboard(args.out, arrays, args.game)
    if args.install is not None:
        install(args.out, args.install)


if __name__ == "__main__":
    main()
