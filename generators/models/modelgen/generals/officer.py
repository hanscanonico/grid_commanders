"""The plain officer an unknown id and the empty seat stand as."""

from .. import figure

TEXTURE = 768
LOOK = figure.look("medium brown short fieldcap none none v plain none", mood="calm", iris="brown", jaw="soft")
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
