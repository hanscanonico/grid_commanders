"""Lyra Quill: a platinum bob, round glasses and her book."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "pale platinum bob glasses none none mandarin placket book",
    woman=True,
    mood="calm",
    iris="grey",
    jaw="lean",
    build=0.92,
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
