"""Compatibility-safe storage for the screen that created a bill."""

from __future__ import annotations

from typing import Any


VALID_BILLING_SOURCES = frozenset({"voice", "frequent"})


def billing_source_from_items(items: Any) -> str:
    """Read the optional source marker from the immutable bill-item JSON.

    Older deployed databases already have the ``bills`` table but cannot accept
    a new column until an operator runs a migration.  The source marker lives in
    the existing JSON document so a release can save bills safely during that
    transition.  Legacy item renderers ignore keys beginning with an underscore.
    """
    if isinstance(items, list) and items and isinstance(items[0], dict):
        source = items[0].get("_billing_source")
        if source in VALID_BILLING_SOURCES:
            return source
    return "voice"
