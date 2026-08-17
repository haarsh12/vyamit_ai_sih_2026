"""Canonical shop-category contract shared by profile, inventory, and agents."""

from __future__ import annotations

import re
from typing import Final


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
    return re.sub(r"[^a-z0-9]+", "", category.casefold())


_CATEGORY_BY_KEY: Final[dict[str, str]] = {
    _category_key(category): category for category in SHOP_CATEGORIES
}
_CATEGORY_ALIASES: Final[dict[str, str]] = {
    "stationary": "Stationery",
    "staationary": "Stationery",
    "medical": "Pharmacy",
    "doctor": "Doctor Prescription",
    "prescription": "Doctor Prescription",
    "restaurant": "Fast Food",
    "fastfood": "Fast Food",
}


def normalise_category(category: str | None) -> str | None:
    if not isinstance(category, str) or not category.strip():
        return None
    key = _category_key(category.strip())
    return _CATEGORY_BY_KEY.get(key) or _CATEGORY_ALIASES.get(key)


def validate_category(category: str | None) -> str:
    normalised = normalise_category(category)
    if normalised is None:
        allowed = ", ".join(SHOP_CATEGORIES)
        raise ValueError(f"Unsupported shop category. Choose one of: {allowed}")
    return normalised


def stored_category(category: str | None) -> str:
    return normalise_category(category) or DEFAULT_CATEGORY
