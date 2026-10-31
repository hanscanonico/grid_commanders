"""Perrin Ash: young, freckled, goggles up and a model plane."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "tan auburn short goggles none none v crossbelt plane",
    age="young",
    mood="grin",
    iris="brown",
    freckles=True,
    boots="leather",
    build=0.96,
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
