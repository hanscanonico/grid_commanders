"""Mara Voss: a tight black bun, a bandolier and a scowl."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "medium black bun none none none v bandolier baton",
    woman=True,
    mood="scowl",
    iris="dark",
    jaw="lean",
    gloves=True,
    build=0.94,
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
