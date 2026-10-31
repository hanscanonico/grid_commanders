"""Halden Marr: an old sailor's grey curls and beard, epaulettes and an anchor."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "tan grey curly none none beard double epaulette anchor",
    age="old",
    mood="calm",
    iris="blue",
    jaw="soft",
    build=1.12,
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
