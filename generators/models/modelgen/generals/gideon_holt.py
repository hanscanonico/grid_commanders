"""Gideon Holt: an old grey beard behind square glasses, with his pipe."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "tan grey short glasses none beard double placket pipe",
    age="old",
    mood="kind",
    iris="brown",
    jaw="soft",
    build=1.08,
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
