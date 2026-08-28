"""The two authored marches — the game's Music.NAMES contract.

Composition lives here as hand-written data, the way each sprite is a
hand-written voxel model: melodies note by note, harmony as a bar chart of
(beats, bass root, stab voicing), rhythm as per-bar patterns plus authored
fills. Both are strictly original — this is a legal-clean project, so no
existing tune is quoted or interpolated.

parade  — the menu's face: a proud C-major march at 104 BPM, AABA over 32
          bars. Oom-pah tuba, afterbeat horns, parade snare with rolls into
          every strain, and a singable square lead; the bridge turns to the
          relative minor under a held counter-voice, and the last bar's
          G-B-D pickup lifts the loop back to its downbeat.
advance — the battle's pulse: an A-minor quickstep at 132 BPM, ABAC over 32
          bars. Driving eighth-note bass with octave pops, syncopated stabs,
          a thin urgent lead; the final strain crests at C6, the hats double
          to sixteenths, and a descending E7 run resolves across the seam
          onto the loop's opening A.
"""

from __future__ import annotations

import numpy as np

from . import sequencer

BARS = 32
BEATS = BARS * 4.0


# -- authoring helpers -------------------------------------------------------


def seq(steps, vel: float = 0.9) -> tuple:
    """A voice played through in sequence: (midi, beats[, velocity]) steps,
    midi None for a rest. Must span the whole song — a march has no slack."""
    notes = []
    at = 0.0
    for step in steps:
        midi, beats = step[0], step[1]
        if midi is not None:
            notes.append((at, midi, beats, step[2] if len(step) > 2 else vel))
        at += beats
    if at != BEATS:
        raise ValueError(f"melody spans {at} beats, the song is {BEATS}")
    return tuple(notes)


def _beat_chords(chart) -> list:
    """Per-beat (root, voicing) lookup expanded from the bar chart."""
    out = []
    for beats, root, chord in chart:
        out.extend([(root, chord)] * int(beats))
    if len(out) != int(BEATS):
        raise ValueError(f"chart spans {len(out)} beats, the song is {BEATS}")
    return out


def oompah(chart, vel: float = 1.0) -> tuple:
    """Root then fifth on the strong beats — the tuba half of the band
    (the afterbeat stabs are the other half)."""
    chords = _beat_chords(chart)
    notes = []
    for beat in range(0, len(chords), 2):
        root = chords[beat][0]
        on_the_one = beat % 4 == 0
        midi = root if on_the_one else root + 7
        notes.append((float(beat), midi, 1.0, vel if on_the_one else vel * 0.85))
    return tuple(notes)


def drive(chart, vel: float = 0.95) -> tuple:
    """Straight eighths with the octave popping off the backbeats' and."""
    chords = _beat_chords(chart)
    lift = (0, 0, 0, 12, 0, 0, 0, 12)
    notes = []
    for eighth in range(len(chords) * 2):
        beat = eighth / 2.0
        midi = chords[int(beat)][0] + lift[eighth % 8]
        accent = 1.0 if eighth % 8 == 0 else (0.85 if eighth % 2 == 0 else 0.72)
        notes.append((beat, midi, 0.5, vel * accent))
    return tuple(notes)


def afterbeats(chart, vel: float = 0.85) -> tuple:
    """Chord stabs on the weak beats — the pah of the oom-pah."""
    chords = _beat_chords(chart)
    notes = []
    for beat in range(1, len(chords), 2):
        for midi in chords[beat][1]:
            notes.append((float(beat), midi, 0.4, vel))
    return tuple(notes)


def stabs(chart, offsets=(1.5, 3.0), vel: float = 0.85) -> tuple:
    """Syncopated chord hits at fixed spots in every bar."""
    chords = _beat_chords(chart)
    notes = []
    for bar in range(len(chords) // 4):
        for off in offsets:
            beat = bar * 4 + off
            for midi in chords[int(beat)][1]:
                notes.append((beat, midi, 0.35, vel))
    return tuple(notes)


def kit(bars: int, pattern, start_bar: int = 0) -> tuple:
    """One drum voice's bar pattern repeated: (beat_in_bar, velocity) hits."""
    notes = []
    for bar in range(start_bar, start_bar + bars):
        for off, vel in pattern:
            notes.append((bar * 4.0 + off, 0, 0.25, vel))
    return tuple(notes)


def roll(bar: int, hits) -> tuple:
    """A snare roll at the end of a bar: (beat_in_bar, velocity) sixteenths."""
    return tuple((bar * 4.0 + off, 0, 0.25, vel) for off, vel in hits)


# -- parade ------------------------------------------------------------------
# C major, 104 BPM, AABA. The A strain shares bars 1-7; bar 8 differs per
# pass — settling the first time, turning minor into the bridge, and lifting
# a G-B-D pickup back to the loop's downbeat the last.
# The score stays hand-formatted: a line is a bar, which the formatter's
# one-note-a-line layout would destroy.
# fmt: off

_PARADE_A = [
    (72, 1.5), (74, 0.5), (76, 1.0), (79, 1.0),  # C: rising to the colours
    (76, 1.0), (72, 1.0), (67, 2.0),  # C: and easing down
    (74, 1.5), (76, 0.5), (77, 1.0), (74, 1.0),  # G
    (71, 1.0), (74, 1.0), (67, 2.0),  # G
    (72, 1.5), (74, 0.5), (76, 1.0), (79, 1.0),  # C
    (81, 1.0), (79, 1.0), (77, 1.0), (74, 1.0),  # F: the proud high step
    (76, 1.0), (79, 0.5), (76, 0.5), (74, 1.0), (71, 0.5), (74, 0.5),  # C G
]
_PARADE_A_END = [(72, 3.0), (None, 1.0)]  # C: at ease
_PARADE_A_TO_B = [(72, 2.0), (None, 1.0), (72, 0.5), (71, 0.5)]  # C: turning minor
_PARADE_A_LOOP = [(72, 2.0), (None, 0.5), (67, 0.5), (71, 0.5), (74, 0.5)]  # V pickup
_PARADE_B = [
    (69, 1.5), (71, 0.5), (72, 1.0), (76, 1.0),  # Am: the shaded answer
    (74, 1.0), (72, 1.0), (69, 2.0),  # Am
    (77, 1.5), (76, 0.5), (74, 1.0), (72, 1.0),  # F
    (71, 1.0), (72, 1.0), (74, 2.0),  # G
    (69, 1.5), (71, 0.5), (72, 1.0), (76, 1.0),  # Am
    (77, 1.0), (81, 1.0), (79, 2.0),  # F: reaching up
    (77, 1.0), (76, 1.0), (74, 1.0), (72, 1.0),  # G: stepping down
    (74, 1.0), (71, 1.0), (67, 1.0), (71, 1.0),  # G: re-forming for the reprise
]
PARADE_MELODY = (
    _PARADE_A + _PARADE_A_END
    + _PARADE_A + _PARADE_A_TO_B
    + _PARADE_B
    + _PARADE_A + _PARADE_A_LOOP
)

_C, _F, _G, _AM = (60, 64, 67), (60, 65, 69), (59, 62, 67), (60, 64, 69)
_PARADE_CHART_A = [
    (4, 48, _C), (4, 48, _C), (4, 43, _G), (4, 43, _G),
    (4, 48, _C), (4, 41, _F), (2, 48, _C), (2, 43, _G), (4, 48, _C),
]
_PARADE_CHART_B = [
    (4, 45, _AM), (4, 45, _AM), (4, 41, _F), (4, 43, _G),
    (4, 45, _AM), (4, 41, _F), (4, 43, _G), (4, 43, _G),
]
PARADE_CHART = _PARADE_CHART_A * 2 + _PARADE_CHART_B + _PARADE_CHART_A
# fmt: on

# Guide tones held under the bridge (bars 17-24), one whole note a bar.
_PARADE_COUNTER = tuple(
    (64.0 + 4.0 * bar, midi, 4.0, 0.8)
    for bar, midi in enumerate((64, 60, 57, 59, 60, 57, 59, 62))
)

_MARCH_KICK = ((0.0, 1.0), (2.0, 0.85))
_MARCH_SNARE = ((1.0, 0.85), (3.0, 0.92))
_MARCH_HAT = tuple((k * 0.5, 0.62 if k % 2 == 0 else 0.45) for k in range(8))
_STRAIN_ROLL = ((3.0, 0.5), (3.25, 0.6), (3.5, 0.7), (3.75, 0.85))


def parade() -> sequencer.Song:
    return sequencer.Song(
        bpm=104.0,
        beats=BEATS,
        tracks=(
            sequencer.Track("brass_lead", 0.34, seq(PARADE_MELODY)),
            sequencer.Track("stab", 0.12, afterbeats(PARADE_CHART)),
            sequencer.Track("tuba_bass", 0.30, oompah(PARADE_CHART)),
            sequencer.Track("pad", 0.15, _PARADE_COUNTER),
            sequencer.Track("kick", 0.50, kit(BARS, _MARCH_KICK)),
            sequencer.Track(
                "snare",
                0.34,
                kit(BARS, _MARCH_SNARE)
                + roll(7, _STRAIN_ROLL)
                + roll(15, _STRAIN_ROLL)
                + roll(23, _STRAIN_ROLL)
                + roll(31, _STRAIN_ROLL),  # the last one rolls into the loop
            ),
            sequencer.Track("hat", 0.32, kit(BARS, _MARCH_HAT)),
        ),
    )


# -- advance -----------------------------------------------------------------
# A minor, 132 BPM, ABAC. The A strain shares bars 1-7; bar 8 rises into the
# counter-charge the first pass and coils on the leading tone before the
# final strain the second. C crests at C6 and its last bar's descending E7
# run resolves across the seam onto the loop's opening A.
# fmt: off

_ADV_A = [
    (69, 1.0), (72, 0.5), (74, 0.5), (76, 1.0), (76, 0.5), (74, 0.5),  # Am: climb
    (72, 1.0), (69, 1.0), (76, 2.0),  # Am: held warning
    (77, 0.5), (76, 0.5), (77, 0.5), (79, 0.5), (81, 1.0), (79, 0.5), (77, 0.5),  # F
    (76, 1.0), (74, 1.0), (71, 2.0),  # G
    (69, 1.0), (72, 0.5), (74, 0.5), (76, 1.0), (76, 0.5), (74, 0.5),  # Am
    (72, 1.0), (69, 1.0), (79, 2.0),  # C
    (77, 0.5), (79, 0.5), (81, 1.0), (79, 0.5), (77, 0.5), (76, 1.0),  # F G: pressing
]
_ADV_A_TO_B = [(76, 1.0), (74, 0.5), (72, 0.5), (71, 1.0), (76, 1.0)]  # E: rising
_ADV_A_TO_C = [(76, 1.0), (74, 0.5), (72, 0.5), (71, 1.0), (68, 1.0)]  # E: coiling
_ADV_B = [
    (79, 1.5), (76, 0.5), (72, 1.0), (76, 1.0),  # C: the counter-charge
    (74, 1.5), (71, 0.5), (67, 1.0), (71, 1.0),  # G
    (69, 0.5), (71, 0.5), (72, 0.5), (74, 0.5), (76, 1.0), (72, 1.0),  # Am
    (71, 1.0), (68, 1.0), (64, 2.0),  # E: the dark answer
    (79, 1.5), (76, 0.5), (72, 1.0), (76, 1.0),  # C
    (74, 1.5), (71, 0.5), (67, 1.0), (74, 1.0),  # G
    (77, 0.5), (76, 0.5), (74, 0.5), (72, 0.5), (69, 1.0), (74, 1.0),  # F
    (76, 2.0), (74, 1.0), (71, 1.0),  # E: hanging on the dominant
]
_ADV_C = [
    (81, 1.5), (79, 0.5), (76, 1.0), (72, 1.0),  # Am: the summit
    (77, 1.5), (76, 0.5), (77, 1.0), (81, 1.0),  # F
    (79, 1.0), (76, 0.5), (72, 0.5), (79, 1.0), (84, 1.0),  # C: cresting at C6
    (83, 1.0), (81, 1.0), (79, 2.0),  # G
    (81, 1.5), (79, 0.5), (76, 1.0), (72, 1.0),  # Am
    (77, 1.0), (74, 1.0), (72, 1.0), (69, 1.0),  # F: falling back in ranks
    (71, 0.5), (72, 0.5), (71, 0.5), (69, 0.5), (68, 1.0), (71, 1.0),  # E
    (76, 2.0), (76, 0.5), (74, 0.5), (71, 0.5), (68, 0.5),  # E7 run into the loop
]
ADVANCE_MELODY = (
    _ADV_A + _ADV_A_TO_B
    + _ADV_B
    + _ADV_A + _ADV_A_TO_C
    + _ADV_C
)

_AMR, _FR, _GR, _CR, _E = (64, 69, 72), (65, 69, 72), (62, 67, 71), (64, 67, 72), (64, 68, 71)
_ADV_CHART_A = [
    (4, 45, _AMR), (4, 45, _AMR), (4, 41, _FR), (4, 43, _GR),
    (4, 45, _AMR), (4, 48, _CR), (2, 41, _FR), (2, 43, _GR), (4, 40, _E),
]
_ADV_CHART_B = [
    (4, 48, _CR), (4, 43, _GR), (4, 45, _AMR), (4, 40, _E),
    (4, 48, _CR), (4, 43, _GR), (4, 41, _FR), (4, 40, _E),
]
_ADV_CHART_C = [
    (4, 45, _AMR), (4, 41, _FR), (4, 48, _CR), (4, 43, _GR),
    (4, 45, _AMR), (4, 41, _FR), (4, 40, _E), (4, 40, _E),
]
ADVANCE_CHART = _ADV_CHART_A + _ADV_CHART_B + _ADV_CHART_A + _ADV_CHART_C
# fmt: on

_DRIVE_KICK = ((0.0, 1.0), (1.5, 0.7), (2.0, 0.9))
_DRIVE_SNARE = ((1.0, 0.85), (3.0, 0.92), (3.75, 0.5))
_DRIVE_HAT8 = tuple((k * 0.5, 0.42 if k % 2 == 0 else 0.55) for k in range(8))
_DRIVE_HAT16 = tuple((k * 0.25, 0.5 if k % 4 == 0 else 0.35) for k in range(16))
_PUSH_ROLL = ((3.5, 0.6), (3.75, 0.75))


def advance() -> sequencer.Song:
    return sequencer.Song(
        bpm=132.0,
        beats=BEATS,
        tracks=(
            sequencer.Track("edge_lead", 0.32, seq(ADVANCE_MELODY)),
            sequencer.Track("stab", 0.11, stabs(ADVANCE_CHART)),
            sequencer.Track("drive_bass", 0.26, drive(ADVANCE_CHART)),
            sequencer.Track("kick", 0.50, kit(BARS, _DRIVE_KICK)),
            sequencer.Track(
                "snare",
                0.34,
                kit(BARS, _DRIVE_SNARE)
                + roll(7, _PUSH_ROLL)
                + roll(15, _PUSH_ROLL)
                + roll(23, _PUSH_ROLL)
                + roll(31, _STRAIN_ROLL),  # the full roll launches the loop
            ),
            # The hats double to sixteenths under the final strain.
            sequencer.Track(
                "hat",
                0.30,
                kit(24, _DRIVE_HAT8) + kit(8, _DRIVE_HAT16, start_bar=24),
            ),
        ),
    )


# name -> (song builder, peak dBFS). Music sits under every combat SFX peak
# by contract — the Mix gate reads the margin off sfx.SFX and holds it.
MUSIC: dict[str, tuple] = {
    "parade": (parade, -7.0),
    "advance": (advance, -6.0),
}


def render(name: str) -> np.ndarray:
    """A finished loop: authored, sequenced, levelled to its authored peak."""
    builder, peak_db = MUSIC[name]
    return sequencer.render(builder(), peak_db)
