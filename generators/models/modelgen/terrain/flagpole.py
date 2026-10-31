"""The pole a capture's flag flies from: a stone foot, a tall pole, a brass finial.

The game stretches it to clear each building's roof, so it stands one unit tall
and only its pole has height to give.
"""

from __future__ import annotations

from ..kit import Kit

TEXTURE = 256
NORMAL_TEXTURE = 128


def build(k: Kit) -> None:
    k.cull = False
    k.cyl((0, 0, 0.0), (0, 0, 0.03), 0.05, 0.042, "stone", 10, 0.006, "foot")
    k.cyl((0, 0, 0.03), (0, 0, 0.98), 0.012, 0.009, "wood", 8, 0.0, "pole")
    k.ellipsoid((0, 0, 1.0), (0.018, 0.018, 0.022), "brass", 5, 8, "finial")
