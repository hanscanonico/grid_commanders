"""Cass Orlov: buzzed and scarred, stubble and a cigar."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "light brown buzz scar none stubble v crossbelt cigar",
    mood="calm",
    iris="grey",
    jaw="square",
    scar_side=-1.0,
    build=1.04,
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
