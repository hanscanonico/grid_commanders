"""Sable Wren: the hood, a scarf and a dagger; nothing given away."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "pale black hood hood none none v scarf dagger",
    woman=True,
    age="young",
    mood="calm",
    iris="dark",
    jaw="heart",
    gloves=True,
    build=0.9,
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
