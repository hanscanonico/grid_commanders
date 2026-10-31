"""Ines Calder: a bun over a green eyeshade, glasses and the ledger."""

from .. import figure

TEXTURE = 768
LOOK = figure.look(
    "dark black bun glasses visor none mandarin mapcase ledger", woman=True, mood="smirk", iris="dark", jaw="soft"
)
ROLES = figure.looks_roles(LOOK)
rig = figure.rig_figure
build = figure.builder(LOOK)
