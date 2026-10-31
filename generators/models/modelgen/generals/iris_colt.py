"""Iris Colt: a blonde ponytail, a headset, a scarf and a whistle."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "light blonde ponytail headset none none v scarf whistle",
    woman=True,
    age="young",
    mood="smile",
    iris="green",
    jaw="heart",
    side=1.0,
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
