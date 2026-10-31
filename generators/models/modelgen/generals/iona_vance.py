"""Iona Vance: a brown bob under a peaked cap, a harness and the scales."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "tan brown bob cap none none mandarin harness scales", woman=True, mood="stern", iris="hazel", jaw="soft"
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
