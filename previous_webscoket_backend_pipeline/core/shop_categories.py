"""Canonical shop-category contract shared by profile, inventory, and AI flows.

Inventory records are scoped using the canonical value returned by
``normalise_category``.  Keep aliases here so existing accounts created with
the old category names continue to work while all new writes use one value.
"""

from __future__ import annotations

import re
from typing import Final, Optional


SHOP_CATEGORIES: Final[tuple[str, ...]] = (
    "Kirana",
    "Stationery",
    "Pharmacy",
    "Doctor Prescription",
    "Dairy",
    "Hardware",
    "Fast Food",
    "General",
    "Clothing",
    "Other",
)

DEFAULT_CATEGORY: Final[str] = "General"


def _category_key(category: str) -> str:
    """Create a comparison key that is insensitive to case and punctuation."""
    return re.sub(r"[^a-z0-9]+", "", category.casefold())


_CATEGORY_BY_KEY: Final[dict[str, str]] = {
    _category_key(category): category for category in SHOP_CATEGORIES
}

# These are migration/compatibility aliases only.  API responses always use a
# canonical value above, which prevents the same scope from being represented
# by multiple spellings.
_CATEGORY_ALIASES: Final[dict[str, str]] = {
    "stationary": "Stationery",
    "staationary": "Stationery",
    "medical": "Pharmacy",
    "doctor": "Doctor Prescription",
    "prescription": "Doctor Prescription",
    "restaurant": "Fast Food",
    "fastfood": "Fast Food",
}


def normalise_category(category: str | None) -> Optional[str]:
    """Return a canonical category, or ``None`` when the input is unknown."""
    if not isinstance(category, str) or not category.strip():
        return None
    key = _category_key(category.strip())
    return _CATEGORY_BY_KEY.get(key) or _CATEGORY_ALIASES.get(key)


def validate_category(category: str | None) -> str:
    """Return the canonical category or raise instead of silently changing it.

    Silently converting an unknown category to ``General`` can put a shop in
    the wrong inventory scope.  Callers should surface the validation error to
    the client instead.
    """
    normalised = normalise_category(category)
    if normalised is None:
        allowed = ", ".join(SHOP_CATEGORIES)
        raise ValueError(f"Unsupported shop category. Choose one of: {allowed}")
    return normalised


def stored_category(category: str | None) -> str:
    """Safely read a legacy database value without failing an authenticated call."""
    return normalise_category(category) or DEFAULT_CATEGORY
