"""Cassian Rook: a blonde swept parting, a lanyard and a card up his sleeve."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "tan blonde sidepart none none none mandarin lanyard card",
    age="young",
    mood="smirk",
    iris="blue",
    jaw="lean",
    gloves=True,
    build=0.94,
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
