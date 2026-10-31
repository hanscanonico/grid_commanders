"""Konrad Vale: steel parting, a scar and a mustache, helmet in hand."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "pale steel sidepart scar none mustache mandarin boards helm",
    mood="stern",
    iris="grey",
    jaw="square",
    gloves=True,
    side=-1.0,
    build=1.06,
    age="old",
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
