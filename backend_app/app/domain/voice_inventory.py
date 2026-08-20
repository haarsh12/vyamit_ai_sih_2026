"""Deterministic inventory-dictation proposal parser.

This is a compatibility bridge for the existing Flutter screen.  It performs
no writes and deliberately does not call an LLM from a request path.  The
LiveKit agent will use the same proposal semantics after realtime migration.
"""

from __future__ import annotations

import re
from typing import Any, Iterable


_UNIT_ALIASES = {
    "kg": "kg", "kilo": "kg", "kilos": "kg", "kilogram": "kg",
    "g": "g", "gm": "g", "gram": "g", "grams": "g",
    "l": "litre", "ltr": "litre", "litre": "litre", "liter": "litre",
    "ml": "ml", "piece": "piece", "pieces": "piece", "packet": "packet",
    "packets": "packet", "pkt": "packet", "plate": "plate", "plates": "plate",
}
_ITEM_PATTERN = re.compile(
    r"(?P<name>[\w\s\-]+?)\s+(?P<price>\d+(?:\.\d+)?)\s*(?:₹|rs\.?|rupees?|/)?\s*"
    r"(?P<unit>kg|kilo(?:s)?|g|gm|grams?|l|ltr|lit(?:re|er)s?|ml|pieces?|packets?|pkt|plates?)?\b",
    re.IGNORECASE,
)


def _unit(value: object) -> str:
    raw = str(value or "piece").strip().casefold()
    return _UNIT_ALIASES.get(raw, raw[:30] or "piece")


def _existing_item(item: dict[str, Any], existing_items: Iterable[dict[str, Any]]) -> None:
    names = {item["name"].casefold(), *(alias.casefold() for alias in item["aliases"])}
    for existing in existing_items:
        aliases = existing.get("names") or []
        if not isinstance(aliases, list):
            continue
        if names.intersection(str(alias).strip().casefold() for alias in aliases if alias):
            item.update({
                "is_existing": True,
                "old_price": float(existing.get("price") or 0),
                "old_unit": str(existing.get("unit") or "piece"),
                "existing_id": str(existing.get("id") or ""),
            })
            return
    item["is_existing"] = False


def parse_inventory_dictation(
    raw_text: str, *, existing_items: list[dict[str, Any]], existing_categories: list[str]
) -> dict[str, object]:
    """Return an editable proposal in the exact response shape Flutter expects."""

    category = "Other"
    category_match = re.search(r"\bcategory\s+([\w\s-]+?)(?=\s+\w+\s+\d|[,;]|$)", raw_text, re.IGNORECASE)
    if category_match:
        candidate = category_match.group(1).strip()
        category = next(
            (saved for saved in existing_categories if saved.casefold() == candidate.casefold()),
            candidate.title()[:60] or "Other",
        )
    parsed: list[dict[str, Any]] = []
    for match in _ITEM_PATTERN.finditer(raw_text):
        name = re.sub(r"\bcategory\b.*$", "", match.group("name"), flags=re.IGNORECASE).strip(" ,.-")
        if not name:
            continue
        item = {"name": name.title()[:100], "price": float(match.group("price")), "unit": _unit(match.group("unit")), "aliases": []}
        _existing_item(item, existing_items)
        parsed.append(item)
    if not parsed:
        item = {"name": raw_text[:100], "price": 0.0, "unit": "piece", "aliases": []}
        _existing_item(item, existing_items)
        parsed.append(item)
    return {"categories": [{"name": category, "items": parsed}], "raw_text": raw_text}
