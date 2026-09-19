"""Voice-to-inventory parsing with a Gemini implementation and safe fallback."""

from __future__ import annotations

import json
import logging
import os
import re
from typing import Any, Dict, Iterable, List


logger = logging.getLogger(__name__)

_UNIT_ALIASES = {
    "kg": "kg",
    "kilo": "kg",
    "kilos": "kg",
    "kilogram": "kg",
    "g": "g",
    "gm": "g",
    "gram": "g",
    "grams": "g",
    "l": "litre",
    "ltr": "litre",
    "litre": "litre",
    "liter": "litre",
    "ml": "ml",
    "piece": "piece",
    "pieces": "piece",
    "packet": "packet",
    "packets": "packet",
    "pkt": "packet",
    "plate": "plate",
}
_FALLBACK_ITEM_PATTERN = re.compile(
    r"(?P<name>[\w\s\-]+?)\s+(?P<price>\d+(?:\.\d+)?)\s*(?:₹|rs\.?|rupees?|/)?\s*(?P<unit>kg|kilo(?:s)?|g|gm|grams?|l|ltr|lit(?:re|er)s?|ml|pieces?|packets?|pkt|plates?)?\b",
    re.IGNORECASE,
)


class VoiceInventoryService:
    """Parse a transcription into the response shape used by the Flutter UI."""

    def __init__(self) -> None:
        self._api_key = os.getenv("GEMINI_API_KEY", "").strip()
        self._client = None
        self._types = None

    def _get_client(self) -> bool:
        if self._client is not None:
            return True
        if not self._api_key:
            return False
        try:
            from google import genai
            from google.genai import types

            self._client = genai.Client(api_key=self._api_key)
            self._types = types
            return True
        except Exception as exc:
            logger.warning("Voice inventory model is unavailable: %s", type(exc).__name__)
            return False

    @staticmethod
    def _normalise_category(name: Any, existing_categories: Iterable[str]) -> str:
        candidate = str(name or "Other").strip()[:60] or "Other"
        for existing in existing_categories:
            if str(existing).casefold() == candidate.casefold():
                return str(existing)
        return candidate.title()

    @staticmethod
    def _normalise_unit(unit: Any) -> str:
        value = str(unit or "piece").strip().lower()
        return _UNIT_ALIASES.get(value, value[:30] or "piece")

    @staticmethod
    def _existing_item(item: Dict[str, Any], existing_items: Iterable[Dict[str, Any]]) -> None:
        item_name = str(item.get("name") or "").strip().casefold()
        aliases = {item_name}
        aliases.update(str(alias).strip().casefold() for alias in item.get("aliases", []) if alias)
        for existing in existing_items:
            names = existing.get("names", [])
            if isinstance(names, str):
                try:
                    names = json.loads(names)
                except json.JSONDecodeError:
                    names = [names]
            if not isinstance(names, list):
                continue
            if aliases.intersection(str(name).strip().casefold() for name in names):
                item["is_existing"] = True
                item["old_price"] = float(existing.get("price") or 0)
                item["old_unit"] = str(existing.get("unit") or "piece")
                item["existing_id"] = str(existing.get("id") or existing.get("master_id") or "")
                return
        item["is_existing"] = False

    def _normalise_result(
        self, result: Any, raw_text: str, existing_items: List[Dict[str, Any]], existing_categories: List[str]
    ) -> Dict[str, Any]:
        categories: List[Dict[str, Any]] = []
        source_categories = result.get("categories", []) if isinstance(result, dict) else []
        if not isinstance(source_categories, list):
            source_categories = []

        for source_category in source_categories[:20]:
            if not isinstance(source_category, dict):
                continue
            items: List[Dict[str, Any]] = []
            for source_item in source_category.get("items", [])[:100]:
                if not isinstance(source_item, dict):
                    continue
                name = str(source_item.get("name") or "").strip()[:100]
                if not name:
                    continue
                try:
                    price = float(source_item.get("price", 0))
                except (TypeError, ValueError):
                    price = 0.0
                item = {
                    "name": name,
                    "price": max(price, 0.0),
                    "unit": self._normalise_unit(source_item.get("unit")),
                    "aliases": [str(alias)[:100] for alias in source_item.get("aliases", [])[:10] if alias],
                }
                self._existing_item(item, existing_items)
                items.append(item)
            if items:
                categories.append(
                    {"name": self._normalise_category(source_category.get("name"), existing_categories), "items": items}
                )
        return {"categories": categories, "raw_text": raw_text}

    def _parse_with_gemini(
        self, raw_text: str, existing_categories: List[str]
    ) -> Dict[str, Any] | None:
        if not self._get_client():
            return None
        prompt = f"""Extract retail inventory changes from this transcription: {json.dumps(raw_text, ensure_ascii=False)}

Existing categories: {json.dumps(existing_categories, ensure_ascii=False)}
Return JSON only: {{"categories":[{{"name":"category","items":[{{"name":"item","price":0,"unit":"kg|litre|piece","aliases":[]}}]}}]}}.
Use an existing category when it clearly matches. Never invent a price; use 0 when it is not spoken."""
        for model in ("gemini-2.5-flash-lite", "gemini-2.5-flash"):
            try:
                response = self._client.models.generate_content(
                    model=model,
                    contents=prompt,
                    config=self._types.GenerateContentConfig(
                        temperature=0,
                        max_output_tokens=2048,
                        response_mime_type="application/json",
                    ),
                )
                return json.loads(response.text)
            except Exception as exc:
                logger.info("Voice inventory model %s failed: %s", model, type(exc).__name__)
        return None

    def _fallback_parse(self, raw_text: str) -> Dict[str, Any]:
        """Provide useful, deterministic parsing when an AI provider is unavailable."""
        category = "Other"
        category_match = re.search(r"\bcategory\s+([\w\s-]+?)(?=\s+\w+\s+\d|[,;]|$)", raw_text, re.IGNORECASE)
        if category_match:
            category = category_match.group(1).strip()
        items = []
        for match in _FALLBACK_ITEM_PATTERN.finditer(raw_text):
            name = re.sub(r"\bcategory\b.*$", "", match.group("name"), flags=re.IGNORECASE).strip(" ,.-")
            if not name:
                continue
            items.append(
                {
                    "name": name.title(),
                    "price": float(match.group("price")),
                    "unit": self._normalise_unit(match.group("unit")),
                    "aliases": [],
                }
            )
        if not items and raw_text.strip():
            items.append({"name": raw_text.strip()[:100], "price": 0.0, "unit": "piece", "aliases": []})
        return {"categories": [{"name": category, "items": items}] if items else []}

    def parse(
        self, raw_text: str, existing_items: List[Dict[str, Any]], existing_categories: List[str]
    ) -> Dict[str, Any]:
        model_result = self._parse_with_gemini(raw_text, existing_categories)
        result = model_result if model_result is not None else self._fallback_parse(raw_text)
        return self._normalise_result(result, raw_text, existing_items, existing_categories)


voice_inventory_service = VoiceInventoryService()
