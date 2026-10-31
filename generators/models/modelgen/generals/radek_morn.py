"""Radek Morn: bald, a black beard, a bandolier and a hammer."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "medium darkbrown bald none none beard double bandolier hammer",
    mood="grin",
    iris="dark",
    jaw="square",
    build=1.14,
    gloves=True,
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
