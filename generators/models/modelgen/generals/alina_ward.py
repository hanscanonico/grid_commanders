"""Alina Ward: long auburn hair, a sash and a sabre."""

from .. import figure

TEXTURE = 768
ROLES = figure.looks_roles((242, 201, 160), (150, 72, 38))


def build(k):
    figure.build_figure(k, figure.CHIBI, 1.0)


def rig(low):
    figure.rig_figure(low, figure.CHIBI)
