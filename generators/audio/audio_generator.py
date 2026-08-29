#!/usr/bin/env python3
"""Deterministic sound pipeline for grid_commanders.

Renders the game's nine sound effects (autoload/sfx.gd's Sfx.NAMES contract)
and its two looping music tracks (autoload/music.gd's Music.NAMES) as
authored recipes and song data: no RNG outside per-sound seeds, so every run
reproduces the same bytes.

Outputs (under --out, default ./out):
  sfx/<name>.wav     44100 Hz mono 16-bit — drop-ins for assets/sfx/
  music/<name>.ogg   44100 Hz mono Ogg Vorbis loops — drop-ins for
                     assets/music/, an eighth of the PCM they replace
  soundboard.html    A/B audition page: the game's current sounds against
                     this run's, with the measurements beside each pair
  musicboard.html    the same for the two marches; both players loop, so
                     the seam is auditioned by just letting them play

--only NAME [NAME ...] narrows a run to the named effects and tracks (and
refuses --install, which would leave the rest of assets/ from an older
render); --no-boards skips the two HTML pages.

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

import numpy as np

from audiogen import measure, music, sfx
from audiogen.dsp import RATE, seconds, to_int16
from audiogen.ogg import ogg_bytes

# This generator lives at generators/audio/ inside the game repository, so the
# checkout the soundboard reads from is two levels up — resolved from __file__
# rather than from the working directory, which a `make` target may set anywhere.
GAME_ROOT = Path(__file__).resolve().parents[2]


def wav_bytes(x: np.ndarray) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(to_int16(x).tobytes())
    return buf.getvalue()


def write_all(out: Path, names: list[str]) -> dict[str, np.ndarray]:
    rendered = {name: sfx.render(name) for name in names}
    (out / "sfx").mkdir(parents=True, exist_ok=True)
    for name, x in rendered.items():
        (out / "sfx" / f"{name}.wav").write_bytes(wav_bytes(x))
        print(f"  wrote {out / 'sfx' / (name + '.wav')}")
    return rendered


def write_music(
    out: Path, names: list[str]
) -> tuple[dict[str, np.ndarray], dict[str, bytes]]:
    arrays = {name: music.render(name) for name in names}
    encoded = {name: ogg_bytes(x) for name, x in arrays.items()}
    (out / "music").mkdir(parents=True, exist_ok=True)
    for name, data in encoded.items():
        (out / "music" / f"{name}.ogg").write_bytes(data)
        print(f"  wrote {out / 'music' / (name + '.ogg')}")
    return arrays, encoded


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


def _audio_tag(data: bytes, loop: bool = False, mime: str = "audio/wav") -> str:
    b64 = base64.b64encode(data).decode()
    attrs = " loop" if loop else ""
    return (
        f'<audio controls preload="auto"{attrs} src="data:{mime};base64,{b64}"></audio>'
    )


def soundboard(out: Path, rendered: dict[str, np.ndarray], game: Path) -> None:
    rows = []
    for name, x in rendered.items():
        _b, category, _p = sfx.SFX[name]
        old_path = game / "assets/sfx" / f"{name}.wav"
        old_tag = "<em>missing</em>"
        if old_path.exists():
            old_tag = _audio_tag(old_path.read_bytes())
        rows.append(
            f"<tr><td><b>{name}</b><br><small>{category}</small></td>"
            f"<td>{old_tag}</td>"
            f"<td>{_audio_tag(wav_bytes(x))}</td>"
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


def musicboard(
    out: Path, arrays: dict[str, np.ndarray], encoded: dict[str, bytes], game: Path
) -> None:
    rows = []
    for name, x in arrays.items():
        builder, _peak = music.MUSIC[name]
        song = builder()
        old_tag = "<em>missing</em>"
        for suffix, mime in ((".ogg", "audio/ogg"), (".wav", "audio/wav")):
            old_path = game / "assets/music" / f"{name}{suffix}"
            if old_path.exists():
                old_tag = _audio_tag(old_path.read_bytes(), loop=True, mime=mime)
                break
        rows.append(
            f"<tr><td><b>{name}</b><br><small>{song.bpm:.0f} BPM</small></td>"
            f"<td>{old_tag}</td>"
            f"<td>{_audio_tag(encoded[name], loop=True, mime='audio/ogg')}</td>"
            f'<td class="num">{seconds(len(x)):.1f}s'
            f"<br>peak {measure.peak_db(x):.1f} dB<br>rms {measure.rms_db(x):.1f} dB"
            f"<br>tempo {measure.tempo_bpm(x):.1f} BPM"
            f"<br>seam Δ {measure.loop_rms_delta_db(x):.1f} dB</td></tr>"
        )
    intro = (
        "<p>Both players loop, so let a track run past its end: the seam is "
        "the audition."
    )
    if len(arrays) == len(music.MUSIC):
        distance = measure.spectral_distance(arrays["parade"], arrays["advance"])
        intro += f" Spectral distance between the two marches: {distance:.3f}."
    html = (
        f"<title>Musicboard</title><style>{_PAGE_STYLE}</style>"
        "<h1>Grid Commanders musicboard — current vs composed</h1>"
        f"{intro}</p>"
        "<table><tr><th>Track</th><th>Current (in game)</th><th>Composed</th>"
        "<th>Measured</th></tr>" + "".join(rows) + "</table>"
    )
    (out / "musicboard.html").write_text(html)
    print(f"  wrote {out / 'musicboard.html'}")


def plan(only: list[str] | None, install: Path | None) -> tuple[list[str], list[str]]:
    """Which effects and tracks a run covers. Raises ValueError on a bad request."""
    if not only:
        return list(sfx.SFX), list(music.MUSIC)
    known = list(sfx.SFX) + list(music.MUSIC)
    unknown = [name for name in only if name not in known]
    if unknown:
        raise ValueError(
            f"no such sound/track: {', '.join(unknown)}; "
            f"known names are {', '.join(known)}"
        )
    if install is not None:
        raise ValueError(
            "--only cannot be installed: a partial run leaves the rest of "
            "assets/ from an older render — drop --only to install"
        )
    return (
        [name for name in sfx.SFX if name in only],
        [name for name in music.MUSIC if name in only],
    )


def install(out: Path, dest: Path) -> None:
    for sub, names, suffix in (
        ("sfx", sfx.SFX, ".wav"),
        ("music", music.MUSIC, ".ogg"),
    ):
        target = dest / "assets" / sub
        if not target.is_dir():
            sys.exit(
                f"{target} is not a directory — is {dest} a grid_commanders checkout?"
            )
        for name in names:
            src = out / sub / f"{name}{suffix}"
            if not src.exists():
                sys.exit(f"missing {src} — run a full generation first")
            (target / f"{name}{suffix}").write_bytes(src.read_bytes())
            kept = {f"{name}{suffix}", f"{name}{suffix}.import"}
            for stale in target.glob(f"{name}.*"):
                # A file left behind in a format we stopped shipping ships
                # anyway — the game imports everything under assets/.
                if stale.name not in kept:
                    stale.unlink()
                    print(f"  removed stale {stale}")
        print(f"installed {len(names)} {sub} {suffix.lstrip('.')} files into {target}")


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("-o", "--out", type=Path, default=Path("out"))
    ap.add_argument(
        "--game",
        type=Path,
        default=GAME_ROOT,
        help="game checkout the soundboard reads current sounds from (read-only)",
    )
    ap.add_argument(
        "--install",
        type=Path,
        metavar="GAME_DIR",
        help="copy the rendered sounds into a grid_commanders checkout "
        "(explicit path required — no default destination, deliberately)",
    )
    ap.add_argument(
        "--only",
        nargs="+",
        metavar="NAME",
        help="render just these sounds or tracks (cannot be installed)",
    )
    ap.add_argument(
        "--no-boards", action="store_true", help="skip the HTML audition boards"
    )
    args = ap.parse_args()

    try:
        sfx_names, music_names = plan(args.only, args.install)
    except ValueError as error:
        sys.exit(str(error))

    if sfx_names:
        print(f"rendering {len(sfx_names)} sound effects")
        rendered = write_all(args.out, sfx_names)
        if not args.no_boards:
            soundboard(args.out, rendered, args.game)
    if music_names:
        print(f"rendering {len(music_names)} music loops")
        arrays, encoded = write_music(args.out, music_names)
        if not args.no_boards:
            musicboard(args.out, arrays, encoded, args.game)
    if args.install is not None:
        install(args.out, args.install)


if __name__ == "__main__":
    main()
