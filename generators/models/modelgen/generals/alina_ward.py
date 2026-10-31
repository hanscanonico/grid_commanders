"""Alina Ward: long auburn hair, a sash and a sabre."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "light auburn long none none none v sash sabre", woman=True, age="young", mood="smile", iris="blue", gloves=True
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
