"""Rhea Sol: goggles up, a black ponytail, a wrench and a grin."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "tan black ponytail goggles none none mandarin loops wrench",
    woman=True,
    mood="grin",
    iris="amber",
    side=-1.0,
    boots="leather",
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
