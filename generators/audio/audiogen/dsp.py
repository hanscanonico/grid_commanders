"""Deterministic DSP toolkit: oscillators, envelopes, filters, mix bus.

Everything renders float64 mono in [-1, 1] at RATE and is a pure function of
its arguments. Noise comes from a per-sound seeded PCG64 generator — never a
global RNG — so every render of a sound reproduces the same bytes on every
platform (the same rule sprite_generator holds for its hash noise).
"""

from __future__ import annotations

import numpy as np

RATE = 44100


def seconds(n_samples: int) -> float:
    return n_samples / RATE


def samples(t: float) -> int:
    return int(round(t * RATE))


def silence(t: float) -> np.ndarray:
    return np.zeros(samples(t))


def _phase(freq: float | np.ndarray, n: int) -> np.ndarray:
    """Integrated phase supporting per-sample frequency curves (sweeps)."""
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    return 2.0 * np.pi * np.cumsum(f) / RATE


def sine(freq: float | np.ndarray, t: float) -> np.ndarray:
    return np.sin(_phase(freq, samples(t)))


def square(freq: float | np.ndarray, t: float, duty: float = 0.5) -> np.ndarray:
    """Zero-mean pulse wave: a duty other than 0.5 would otherwise carry DC
    (mean 2*duty - 1), which stacks when chords do."""
    ph = _phase(freq, samples(t)) / (2.0 * np.pi) % 1.0
    return np.where(ph < duty, 1.0, -1.0) - (2.0 * duty - 1.0)


def saw(freq: float | np.ndarray, t: float) -> np.ndarray:
    ph = _phase(freq, samples(t)) / (2.0 * np.pi) % 1.0
    return 2.0 * ph - 1.0


def triangle(freq: float | np.ndarray, t: float) -> np.ndarray:
    ph = _phase(freq, samples(t)) / (2.0 * np.pi) % 1.0
    return 4.0 * np.abs(ph - 0.5) - 1.0


def noise(t: float, seed: int) -> np.ndarray:
    return np.random.default_rng(seed).uniform(-1.0, 1.0, samples(t))


def sweep(start: float, end: float, t: float, curve: float = 1.0) -> np.ndarray:
    """A frequency (or any) curve from start to end; curve>1 falls faster early."""
    x = np.linspace(0.0, 1.0, samples(t)) ** curve
    return start + (end - start) * x


# -- envelopes --------------------------------------------------------------


def decay(t: float, half_life: float) -> np.ndarray:
    """Exponential decay from 1.0; half_life in seconds."""
    n = samples(t)
    return 0.5 ** (np.arange(n) / (half_life * RATE))


def adsr(t: float, a: float, d: float, s: float, r: float) -> np.ndarray:
    """Linear ADSR fitted into t seconds; sustain level s, release r seconds.

    The stages must fit: a note too short for its own envelope would be cut
    mid-release, which is the click the ramps exist to avoid.
    """
    n = samples(t)
    na, nd, nr = samples(a), samples(d), samples(r)
    if na + nd + nr > n:
        raise ValueError(f"ADSR {a}+{d}+{r}s does not fit in {t}s")
    return np.concatenate(
        [
            np.linspace(0.0, 1.0, na, endpoint=False),
            np.linspace(1.0, s, nd, endpoint=False),
            np.full(n - na - nd - nr, s),
            np.linspace(s, 0.0, nr),
        ]
    )


def edge_fade(x: np.ndarray, t: float = 0.004) -> np.ndarray:
    """Short raised-cosine fades so no sound starts or ends with a click."""
    n = min(samples(t), len(x) // 2)
    if n == 0:
        return x
    fade = 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, n))
    out = x.copy()
    out[:n] *= fade
    out[-n:] *= fade[::-1]
    return out


# -- filters ----------------------------------------------------------------


def lowpass(x: np.ndarray, cutoff: float | np.ndarray) -> np.ndarray:
    """One-pole lowpass; cutoff may be a per-sample curve (Hz)."""
    c = np.broadcast_to(np.asarray(cutoff, dtype=np.float64), (len(x),))
    a = np.exp(-2.0 * np.pi * np.clip(c, 10.0, RATE / 2.2) / RATE)
    out = np.empty_like(x)
    y = 0.0
    for i in range(len(x)):
        y = (1.0 - a[i]) * x[i] + a[i] * y
        out[i] = y
    return out


def highpass(x: np.ndarray, cutoff: float | np.ndarray) -> np.ndarray:
    return x - lowpass(x, cutoff)


def bandpass(x: np.ndarray, low: float, high: float) -> np.ndarray:
    return highpass(lowpass(x, high), low)


def ring(x: np.ndarray, freq: float) -> np.ndarray:
    """Ring modulation — the metallic voice."""
    return x * np.sin(2.0 * np.pi * freq * np.arange(len(x)) / RATE)


# -- bus --------------------------------------------------------------------


def mix(*layers: np.ndarray) -> np.ndarray:
    n = max(len(v) for v in layers)
    out = np.zeros(n)
    for v in layers:
        out[: len(v)] += v
    return out


def soft_clip(x: np.ndarray, drive: float = 1.0) -> np.ndarray:
    return np.tanh(x * drive)


def echo(x: np.ndarray, delay: float, gain: float, taps: int = 3) -> np.ndarray:
    n = len(x) + samples(delay) * taps
    out = np.zeros(n)
    out[: len(x)] = x
    for k in range(1, taps + 1):
        i = samples(delay) * k
        out[i : i + len(x)] += x * (gain**k)
    return out


def normalize(x: np.ndarray, peak_db: float = -1.5) -> np.ndarray:
    peak = np.max(np.abs(x))
    if peak == 0.0:
        return x
    return x * (10.0 ** (peak_db / 20.0) / peak)


def to_int16(x: np.ndarray) -> np.ndarray:
    return np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
