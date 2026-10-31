"""Dane Ferrow: a field cap, a scar, stubble and a purse of coins."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "dark black buzz fieldcap scar stubble mandarin plain coins",
    mood="scowl",
    iris="dark",
    jaw="square",
    build=1.1,
    scar_side=-1.0,
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
