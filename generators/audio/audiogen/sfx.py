"""The nine authored sound effects — the game's Sfx.NAMES contract.

Each effect is a hand-authored recipe over the dsp toolkit, the way each
sprite in sprite_generator is a hand-authored voxel model: layered, seeded,
deterministic. The direction is 16-bit-era chiptune-plus — synthesis with
punchy envelopes and filtered noise, not raw beeps and not sample packs —
to sit beside the game's dimetric pixel art.

Category speaks loudness: UI sounds sit a step under COMBAT so a menu never
barks louder than a battle (the mix gate holds the bands apart).
"""

from __future__ import annotations

import numpy as np

from . import dsp

UI = "ui"
COMBAT = "combat"


def select() -> np.ndarray:
    """Cursor confirm: a bright two-step blip, up and gone."""
    a = dsp.square(660.0, 0.028, duty=0.4) * dsp.decay(0.028, 0.02)
    b = dsp.square(990.0, 0.045, duty=0.4) * dsp.decay(0.045, 0.018)
    out = dsp.mix(a * 0.8, np.concatenate([dsp.silence(0.022), b]))
    return dsp.highpass(out, 300.0)


def move() -> np.ndarray:
    """Order given: a soft downward whoosh with a low engine knock."""
    wind = dsp.noise(0.13, seed=11) * dsp.adsr(0.13, 0.015, 0.06, 0.4, 0.05)
    wind = dsp.lowpass(wind, dsp.sweep(2400.0, 500.0, 0.13))
    knock = dsp.sine(dsp.sweep(180.0, 110.0, 0.09), 0.09) * dsp.decay(0.09, 0.03)
    return dsp.mix(wind * 0.9, knock * 0.6)


def shot() -> np.ndarray:
    """Machine-gun crack: a hard noise transient over a falling snap."""
    crack = dsp.noise(0.09, seed=23) * dsp.decay(0.09, 0.012)
    crack = dsp.highpass(crack, 900.0)
    snap = dsp.square(dsp.sweep(420.0, 140.0, 0.07, curve=2.0), 0.07)
    snap *= dsp.decay(0.07, 0.02)
    return dsp.soft_clip(dsp.mix(crack * 1.1, snap * 0.7), drive=1.6)


def explosion() -> np.ndarray:
    """The kill frame: a deep drop under a rumble that breathes out."""
    boom = dsp.sine(dsp.sweep(150.0, 38.0, 0.42, curve=1.6), 0.42)
    boom *= dsp.decay(0.42, 0.09)
    rumble = dsp.noise(0.46, seed=37) * dsp.decay(0.46, 0.11)
    rumble = dsp.lowpass(rumble, dsp.sweep(3200.0, 220.0, 0.46))
    debris = dsp.noise(0.30, seed=38) * dsp.decay(0.30, 0.05)
    debris = dsp.bandpass(debris, 1200.0, 4200.0)
    late = np.concatenate([dsp.silence(0.05), debris * 0.35])
    return dsp.soft_clip(dsp.mix(boom * 1.0, rumble * 0.9, late), drive=1.8)


def capture() -> np.ndarray:
    """The flag comes down: three climbing plucks and a settle."""
    out = dsp.silence(0.26)
    for i, f in enumerate((392.0, 523.25, 659.25)):
        pluck = dsp.triangle(f, 0.11) * dsp.decay(0.11, 0.03)
        start = dsp.samples(0.065 * i)
        out[start : start + len(pluck)] += pluck * 0.8
    sparkle = dsp.noise(0.08, seed=51) * dsp.decay(0.08, 0.02)
    sparkle = dsp.highpass(sparkle, 5000.0)
    out[dsp.samples(0.13) : dsp.samples(0.13) + len(sparkle)] += sparkle * 0.25
    return out


def fanfare() -> np.ndarray:
    """Victory sting: a stacked brass triad with vibrato, held then released."""
    t = 0.4
    vib = 1.0 + 0.006 * dsp.sine(6.0, t)
    chord = dsp.mix(
        dsp.square(261.63 * vib, t, duty=0.35),
        dsp.square(329.63 * vib, t, duty=0.35),
        dsp.square(392.00 * vib, t, duty=0.35),
    )
    chord = dsp.lowpass(chord, 3800.0) * dsp.adsr(t, 0.02, 0.08, 0.7, 0.14)
    lead = dsp.triangle(523.25 * vib, t) * dsp.adsr(t, 0.01, 0.1, 0.5, 0.12)
    return dsp.mix(chord * 0.5, lead * 0.5)


def flak() -> np.ndarray:
    """Airburst: a sharp pop that rings metal as the shrapnel spreads."""
    pop = dsp.noise(0.06, seed=67) * dsp.decay(0.06, 0.008)
    body = dsp.noise(0.3, seed=68) * dsp.decay(0.3, 0.05)
    shrapnel = dsp.ring(dsp.bandpass(body, 1800.0, 5200.0), 2350.0)
    thump = dsp.sine(dsp.sweep(240.0, 90.0, 0.12), 0.12) * dsp.decay(0.12, 0.03)
    return dsp.soft_clip(dsp.mix(pop * 1.2, shrapnel * 0.8, thump * 0.6), 1.5)


def rocket() -> np.ndarray:
    """Launch: igniter crack, then the motor tears away upward."""
    ign = dsp.noise(0.05, seed=83) * dsp.decay(0.05, 0.01)
    motor = dsp.noise(0.34, seed=84) * dsp.adsr(0.34, 0.02, 0.1, 0.8, 0.12)
    motor = dsp.lowpass(motor, dsp.sweep(1200.0, 5200.0, 0.34))
    whine = dsp.saw(dsp.sweep(300.0, 950.0, 0.34), 0.34)
    whine *= dsp.adsr(0.34, 0.05, 0.1, 0.5, 0.12)
    return dsp.soft_clip(dsp.mix(ign * 0.9, motor * 0.95, whine * 0.35), 1.4)


def torpedo() -> np.ndarray:
    """Underwater away: a muffled thunk, screw-wash, and a sonar answer."""
    thunk = dsp.sine(dsp.sweep(160.0, 70.0, 0.1), 0.1) * dsp.decay(0.1, 0.04)
    wash = dsp.noise(0.4, seed=97) * dsp.adsr(0.4, 0.03, 0.1, 0.7, 0.15)
    wash = dsp.lowpass(wash, 900.0 + 350.0 * dsp.sine(9.0, 0.4))
    # The sonar answer carries the identity: without it the wash collapses
    # into the explosion's rumble band (the Distinctness gate's finding).
    ping = dsp.mix(dsp.sine(820.0, 0.07), dsp.sine(1640.0, 0.07) * 0.4) * dsp.decay(
        0.07, 0.025
    )
    ping = dsp.echo(ping, 0.11, 0.5, taps=2)
    late = np.concatenate([dsp.silence(0.14), ping * 1.1])
    return dsp.mix(thunk * 0.8, wash * 0.55, late)


# name -> (builder, category, peak dBFS). UI sits a step under COMBAT.
SFX: dict[str, tuple] = {
    "select": (select, UI, -8.0),
    "move": (move, UI, -8.0),
    "shot": (shot, COMBAT, -3.0),
    "explosion": (explosion, COMBAT, -1.5),
    "capture": (capture, UI, -6.0),
    "fanfare": (fanfare, UI, -5.0),
    "flak": (flak, COMBAT, -3.0),
    "rocket": (rocket, COMBAT, -3.5),
    "torpedo": (torpedo, COMBAT, -4.0),
}


def render(name: str) -> np.ndarray:
    """A finished effect: built, levelled to its authored peak, click-free."""
    builder, _category, peak_db = SFX[name]
    # Fade first, level last: the fade would otherwise eat a peak that sits
    # near an edge, and the authored level is a contract the Mix gate holds.
    return dsp.normalize(dsp.edge_fade(builder()), peak_db)
