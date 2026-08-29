"""Purity gates for the sequencer and its envelope.

The render must be a function of the song data alone, not of what the process
rendered before it: the percussion cache is a speed-up, never a state the
output can depend on. These hold that — a cold cache renders the same bytes as
a warm one, a cached hit cannot be edited in place, and an envelope too long
for its note is refused rather than truncated mid-release.

Run with `.venv/bin/python -m unittest discover tests`.
"""

from __future__ import annotations

import unittest

import numpy as np

from audiogen import music, sequencer
from audiogen.dsp import RATE, adsr

TRACKS = ("parade", "advance")
HIT_BUILDERS = (sequencer._kick_hit, sequencer._snare_hit, sequencer._hat_hit)


def _clear_hit_cache() -> None:
    for builder in HIT_BUILDERS:
        builder.cache_clear()


class ColdCache(unittest.TestCase):
    def test_a_cold_cache_renders_the_same_bytes_as_a_warm_one(self):
        warm = {name: music.render(name) for name in TRACKS}
        _clear_hit_cache()
        for name in TRACKS:
            with self.subTest(track=name):
                self.assertTrue(np.array_equal(music.render(name), warm[name]))

    def test_a_cached_hit_refuses_an_in_place_edit(self):
        for builder in HIT_BUILDERS:
            with self.subTest(hit=builder.__name__):
                with self.assertRaises(ValueError):
                    builder()[0] = 1.0

    def test_the_same_hit_object_is_handed_out_twice(self):
        for builder in HIT_BUILDERS:
            with self.subTest(hit=builder.__name__):
                self.assertIs(builder(), builder())


class Envelope(unittest.TestCase):
    def test_an_envelope_longer_than_its_note_is_refused(self):
        with self.assertRaises(ValueError):
            adsr(0.05, 0.02, 0.03, 0.8, 0.02)

    def test_a_note_envelope_fills_its_slot_and_starts_and_ends_silent(self):
        # The tightest note either song asks for: a stab at 0.127 s against
        # 0.084 s of ramps, so the guard above has 0.043 s of room today.
        env = adsr(0.127, 0.004, 0.05, 0.45, 0.03)
        self.assertEqual(len(env), int(round(0.127 * RATE)))
        self.assertEqual(env[0], 0.0)
        self.assertEqual(env[-1], 0.0)
        self.assertEqual(float(np.max(env)), 1.0)


class DrumPatterns(unittest.TestCase):
    def test_a_one_bar_pattern_lands_where_the_roll_helper_put_it(self):
        self.assertEqual(
            music.kit(1, ((3.0, 0.5), (3.5, 0.7)), start_bar=7),
            ((31.0, 0, 0.25, 0.5), (31.5, 0, 0.25, 0.7)),
        )


if __name__ == "__main__":
    unittest.main()
