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
