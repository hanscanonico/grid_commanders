"""Nia Rowan: a brown braid, a headband and a monocle."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "tan brown braid headband none none v pouch monocle", woman=True, mood="smile", iris="green", boots="leather"
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
