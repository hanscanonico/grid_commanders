"""Orin Flux: black spikes, a headset, a drone and a big grin."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "medium black spiky headset none none mandarin lanyard drone", age="young", mood="beam", iris="cyan", build=0.94
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
