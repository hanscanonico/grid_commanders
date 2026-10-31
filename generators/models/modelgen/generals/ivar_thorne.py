"""Ivar Thorne: long hair, a beard, a scar and an axe."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "light darkbrown long scar none beard v sash axe",
    mood="scowl",
    iris="brown",
    jaw="square",
    build=1.1,
    boots="leather",
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
