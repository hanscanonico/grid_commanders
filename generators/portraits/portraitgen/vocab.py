"""How every vocabulary in this package answers an unknown key.

Each layer owns a dispatch table — the eye shapes, the collar cuts, the props,
the backdrop treatments — and the rule across all of them is the same: an
unknown key raises rather than falling through to a default, and the error names
what was asked for and what there is. Written out at each table that rule was
seventeen copies of one f-string, which is seventeen chances for one of them to
say `have {_EYES}` and dump a table of shapes at a caller.

`pick` is for a table whose value the caller wants; `known` for a vocabulary the
caller only has to be in, because what it reaches for afterwards is an attribute
or an index rather than an entry.
"""

from __future__ import annotations

from collections.abc import Collection, Mapping
from typing import TypeVar

T = TypeVar("T")


def pick(table: Mapping[str, T], key: str, what: str) -> T:
    """One entry out of a dispatch table. An unknown key raises."""
    if key not in table:
        raise KeyError(_unknown(key, table, what))
    return table[key]


def known(key: str, vocabulary: Collection[str], what: str) -> str:
    """`key` back, once the vocabulary is shown to hold it."""
    if key not in vocabulary:
        raise KeyError(_unknown(key, vocabulary, what))
    return key


def _unknown(key: str, vocabulary: Collection[str], what: str) -> str:
    return f"no {what} {key!r} (have {sorted(vocabulary)})"
