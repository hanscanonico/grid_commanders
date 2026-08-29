"""Deterministic sequencer: authored song data rendered into a looping track.

A song is hand-written note data — tracks of (start_beat, midi, beats,
velocity) over a tempo — the way each sprite_generator unit is a hand-written
voxel model. Instruments are recipes over the dsp toolkit; the notes carry
the taste, the sequencer only places them.

The game's Music autoload loops the whole file (LOOP_FORWARD, loop_end = file
length), so the last sample must lead into the first. Every tail that rings
past the song's end therefore wraps back to beat zero: the head of the file
already carries what was still sounding at the end, and the seam is silent by
construction. The loop gates in tests/ hold that promise.
"""

from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache

import numpy as np

from . import dsp


def midi_hz(midi: float) -> float:
    return 440.0 * 2.0 ** ((midi - 69.0) / 12.0)


@dataclass(frozen=True)
class Track:
    instrument: str
    gain: float
    notes: tuple  # of (start_beat, midi, beats, velocity)


@dataclass(frozen=True)
class Song:
    bpm: float
    beats: float
    tracks: tuple


# -- melodic instruments -----------------------------------------------------
# Signature (midi, t, vel) -> samples. Each shortens its slot a little — the
# articulation gap is what keeps a march stepping instead of smearing.


def brass_lead(midi: float, t: float, vel: float) -> np.ndarray:
    """The parade's singable front: wide pulse, slow vibrato, round release."""
    t = max(0.05, t * 0.95)
    freq = midi_hz(midi) * (1.0 + 0.004 * dsp.sine(5.5, t))
    return dsp.square(freq, t, duty=0.35) * dsp.adsr(t, 0.012, 0.06, 0.78, 0.05) * vel


def edge_lead(midi: float, t: float, vel: float) -> np.ndarray:
    """The advance's tenser voice: thin pulse, quick vibrato, hard attack."""
    t = max(0.04, t * 0.92)
    freq = midi_hz(midi) * (1.0 + 0.003 * dsp.sine(6.5, t))
    return dsp.square(freq, t, duty=0.25) * dsp.adsr(t, 0.005, 0.04, 0.7, 0.035) * vel


def tuba_bass(midi: float, t: float, vel: float) -> np.ndarray:
    """Oom-pah bottom: a triangle that breathes with the beat."""
    t = max(0.05, t * 0.9)
    return dsp.triangle(midi_hz(midi), t) * dsp.adsr(t, 0.008, 0.05, 0.85, 0.05) * vel


def drive_bass(midi: float, t: float, vel: float) -> np.ndarray:
    """The advance's engine: a narrow pulse that punches every eighth."""
    t = max(0.04, t * 0.85)
    env = dsp.adsr(t, 0.004, 0.05, 0.55, 0.03)
    return dsp.square(midi_hz(midi), t, duty=0.3) * env * vel


def stab(midi: float, t: float, vel: float) -> np.ndarray:
    """Afterbeat chord voice: short, bright, gone."""
    t = max(0.04, t * 0.8)
    env = dsp.adsr(t, 0.004, 0.05, 0.45, 0.03)
    return dsp.square(midi_hz(midi), t, duty=0.25) * env * vel


def pad(midi: float, t: float, vel: float) -> np.ndarray:
    """Held counter-voice: a triangle that swells in late."""
    return dsp.triangle(midi_hz(midi), t) * dsp.adsr(t, 0.06, 0.1, 0.8, 0.12) * vel


# -- percussion --------------------------------------------------------------
# Fixed-length hits (midi and duration ignored), built once and reused: the
# same crack at every backbeat is the chiptune read, and caching it keeps the
# only Python-loop filters out of the render path.


def _frozen(arr: np.ndarray) -> np.ndarray:
    """A cached hit is shared by every beat that plays it — make it read-only
    so an in-place edit raises instead of retuning the rest of the song."""
    arr.flags.writeable = False
    return arr


@lru_cache(maxsize=None)
def _kick_hit() -> np.ndarray:
    """A pitch-dropping thump with a soft beater tick on top."""
    body = dsp.sine(dsp.sweep(120.0, 44.0, 0.14, curve=1.5), 0.14)
    body *= dsp.decay(0.14, 0.05)
    tick = dsp.noise(0.02, seed=201) * dsp.decay(0.02, 0.004)
    return _frozen(dsp.mix(body, dsp.highpass(tick, 2000.0) * 0.25))


@lru_cache(maxsize=None)
def _snare_hit() -> np.ndarray:
    """Parade snare: a bright crack over a short drum body."""
    crack = dsp.noise(0.16, seed=202) * dsp.decay(0.16, 0.03)
    crack = dsp.bandpass(crack, 700.0, 7500.0)
    body = dsp.sine(dsp.sweep(220.0, 170.0, 0.08), 0.08) * dsp.decay(0.08, 0.02)
    return _frozen(dsp.mix(crack, body * 0.5))


@lru_cache(maxsize=None)
def _hat_hit() -> np.ndarray:
    """Closed hat: a tick of high metal."""
    tick = dsp.noise(0.05, seed=203) * dsp.decay(0.05, 0.012)
    return _frozen(dsp.highpass(tick, 6500.0))


def kick(_midi: float, _t: float, vel: float) -> np.ndarray:
    return _kick_hit() * vel


def snare(_midi: float, _t: float, vel: float) -> np.ndarray:
    return _snare_hit() * vel


def hat(_midi: float, _t: float, vel: float) -> np.ndarray:
    return _hat_hit() * vel


INSTRUMENTS = {
    "brass_lead": brass_lead,
    "edge_lead": edge_lead,
    "tuba_bass": tuba_bass,
    "drive_bass": drive_bass,
    "stab": stab,
    "pad": pad,
    "kick": kick,
    "snare": snare,
    "hat": hat,
}


# -- rendering ---------------------------------------------------------------


def add_wrapped(out: np.ndarray, x: np.ndarray, at: int) -> None:
    """Add x at sample `at`; whatever runs past the end wraps to the start.

    This is the loop seam: a decay still ringing at the file's last sample
    continues at its first, exactly what LOOP_FORWARD will play.
    """
    if len(x) > len(out):
        raise ValueError("a single note longer than the whole song")
    head = min(len(x), len(out) - at)
    out[at : at + head] += x[:head]
    if head < len(x):
        out[: len(x) - head] += x[head:]


def render(song: Song, peak_db: float) -> np.ndarray:
    """The finished loop: every track placed, tails wrapped, levelled.

    No edge fade — a fade would dent the loop seam. Click-freedom comes from
    every instrument's own attack and release ramps.
    """
    spb = 60.0 / song.bpm
    n = int(round(song.beats * spb * dsp.RATE))
    out = np.zeros(n)
    for track in song.tracks:
        instrument = INSTRUMENTS[track.instrument]
        for start, midi, beats, vel in track.notes:
            if not 0.0 <= start < song.beats:
                raise ValueError(f"note at beat {start} outside the song")
            x = instrument(midi, beats * spb, vel) * track.gain
            add_wrapped(out, x, int(round(start * spb * dsp.RATE)))
    return dsp.normalize(out, peak_db)
