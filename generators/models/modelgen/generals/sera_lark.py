"""Sera Lark: a bandana, a ponytail and a compass; the happiest of them."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "dark darkbrown ponytail bandana none none mandarin mapcase compass",
    woman=True,
    age="young",
    mood="beam",
    iris="brown",
    side=-1.0,
    boots="leather",
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
