"""Viktor Draeg: bald, one eye, a grey mustache and a medal."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "light grey bald eyepatch none mustache v boards medal",
    age="old",
    mood="scowl",
    iris="ice",
    jaw="square",
    gloves=True,
    build=1.1,
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
