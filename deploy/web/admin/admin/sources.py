"""What a panel may read."""

from __future__ import annotations

from dataclasses import dataclass

from .posthog import PostHog
from .store import Store


@dataclass(frozen=True)
class Sources:
    store: Store
    posthog: PostHog
