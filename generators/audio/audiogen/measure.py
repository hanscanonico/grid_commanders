"""Measurements the gates assert over — the readouts, never the look.

Mirrors sprite_generator's tests/measure_livery.py role: every number a
test pins comes from here, so the tool and the suite can never disagree
about what "loud" or "distinct" means.
"""

from __future__ import annotations

import numpy as np

from .dsp import RATE


def peak_db(x: np.ndarray) -> float:
    p = float(np.max(np.abs(x)))
    return -120.0 if p == 0.0 else 20.0 * np.log10(p)


def rms_db(x: np.ndarray) -> float:
    r = float(np.sqrt(np.mean(x**2)))
    return -120.0 if r == 0.0 else 20.0 * np.log10(r)


def dc_offset(x: np.ndarray) -> float:
    return float(abs(np.mean(x)))


def edge_peak(x: np.ndarray, n: int = 16) -> float:
    """Loudest sample in the first/last n (~0.4ms) — a click detector.

    Deliberately shorter than the 4ms edge fade: the fade's shoulder is
    audible-by-design, the click is the discontinuity at the very edge.
    """
    return float(max(np.max(np.abs(x[:n])), np.max(np.abs(x[-n:]))))


def band_spectrum(x: np.ndarray, bands: int = 24) -> np.ndarray:
    """Log-band energy profile, normalised — the sound's tonal fingerprint."""
    spec = np.abs(np.fft.rfft(x)) ** 2
    freqs = np.fft.rfftfreq(len(x), 1.0 / RATE)
    edges = np.geomspace(40.0, RATE / 2.0, bands + 1)
    energy = np.array(
        [spec[(freqs >= lo) & (freqs < hi)].sum() for lo, hi in zip(edges, edges[1:])]
    )
    total = energy.sum()
    return energy / total if total > 0 else energy


def spectral_distance(a: np.ndarray, b: np.ndarray) -> float:
    """Cosine distance between band spectra: 0 identical, 1 orthogonal."""
    sa, sb = band_spectrum(a), band_spectrum(b)
    denom = float(np.linalg.norm(sa) * np.linalg.norm(sb))
    if denom == 0.0:
        return 1.0
    return 1.0 - float(np.dot(sa, sb)) / denom


def centroid_hz(x: np.ndarray) -> float:
    spec = np.abs(np.fft.rfft(x))
    freqs = np.fft.rfftfreq(len(x), 1.0 / RATE)
    total = spec.sum()
    return float((freqs * spec).sum() / total) if total > 0 else 0.0


# -- loop measurements -------------------------------------------------------
# A music track loops the whole file (the game's LOOP_FORWARD contract), so
# its one seam is last-sample -> first-sample. These read that seam the same
# way edge_peak reads a one-shot's edges.


def loop_step(x: np.ndarray) -> float:
    """Amplitude jump across the seam, as if x[-1] were followed by x[0]."""
    return float(abs(x[0] - x[-1]))


def loop_slope(x: np.ndarray) -> float:
    """Slope change across the seam — a kink clicks even when the step is 0."""
    return float(abs((x[1] - x[0]) - (x[-1] - x[-2])))


def typical_step(x: np.ndarray, percentile: float = 99.5) -> float:
    """The track's own sample-to-sample motion (a high percentile of |diff|):
    the yardstick a seam step must not exceed to stay inaudible in texture."""
    return float(np.percentile(np.abs(np.diff(x)), percentile))


def loop_rms_delta_db(x: np.ndarray, window: float = 0.25) -> float:
    """|head RMS - tail RMS| in dB: a loop must not dip out or thump in.

    The window is beat-scale on purpose: a pickup's last eighth is quieter
    than the downbeat it lifts into, and that is music, not a dropout.
    """
    n = int(window * RATE)
    return abs(rms_db(x[:n]) - rms_db(x[-n:]))


def tempo_bpm(x: np.ndarray, lo: float = 95.0, hi: float = 170.0) -> float:
    """Tempo read off the rendered audio: onset-strength autocorrelation.

    The search window is one octave-free band chosen so both marches' true
    tempos sit inside it while every half, double and dotted alias of either
    falls outside — the peak inside the band can only be the beat.
    """
    hop = int(RATE * 0.005)
    frames = len(x) // hop
    env = np.sqrt(np.mean(x[: frames * hop].reshape(frames, hop) ** 2, axis=1))
    onset = np.maximum(np.diff(env), 0.0)
    lag_lo = int(round(60.0 / hi / 0.005))
    lag_hi = int(round(60.0 / lo / 0.005))
    strength = [
        float(np.dot(onset[: len(onset) - lag], onset[lag:]))
        for lag in range(lag_lo, lag_hi + 1)
    ]
    return 60.0 / ((lag_lo + int(np.argmax(strength))) * 0.005)
