"""Tomas Reed: curls under a bandana, a harness, a radio and a laugh."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "dark black curly bandana none stubble v harness radio",
    mood="beam",
    iris="hazel",
    jaw="soft",
    build=1.08,
    boots="leather",
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
