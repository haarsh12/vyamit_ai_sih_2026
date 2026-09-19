"""Dedicated GST voice extraction prompt and response normalizer."""

from __future__ import annotations

import json
import logging
from decimal import Decimal
from typing import Any, Dict, Iterable, List

from pipeline.llm_pipeline import LLMPipeline, llm_pipeline

from .validation import validate_gstin


logger = logging.getLogger(__name__)
_MAX_CONTEXT_ITEMS = 50


class GstVoiceService:
    """Extract GST invoice facts only; it never calculates money or tax."""

    def __init__(self, pipeline: LLMPipeline | None = None) -> None:
        self._pipeline = pipeline or llm_pipeline

    @staticmethod
    def _names(item: Dict[str, Any]) -> list[str]:
        names = item.get("names", [])
        if isinstance(names, str):
            try:
                names = json.loads(names)
            except json.JSONDecodeError:
                names = [names]
        return [str(name).strip()[:100] for name in names if str(name).strip()]

    @classmethod
    def _inventory_context(cls, inventory: Iterable[Dict[str, Any]]) -> List[Dict[str, Any]]:
        context: List[Dict[str, Any]] = []
        for item in inventory:
            if len(context) >= _MAX_CONTEXT_ITEMS:
                break
            names = cls._names(item)
            if not names:
                continue
            context.append(
                {
                    "name": names[0],
                    "aliases": names,
                    "rate": item.get("price", 0),
                    "unit": str(item.get("unit") or "unit")[:30],
                    "gst_rate": Decimal(str(item.get("gst_rate_bps", 0))) / Decimal("100"),
                    "hsn_code": item.get("hsn_code"),
                }
            )
        return context

    @classmethod
    def _build_prompt(
        cls, text: str, inventory: Iterable[Dict[str, Any]], shop_category: str
    ) -> str:
        return f"""You are Vyamit AI's GST invoice fact extractor for a {str(shop_category)[:60]} shop.

The customer said: {json.dumps(text, ensure_ascii=False)}
Trusted inventory context: {json.dumps(cls._inventory_context(inventory), ensure_ascii=False, default=str)}

Return JSON only with this exact shape:
{{
  "type": "BILL" | "QUERY" | "ERROR",
  "customer": {{"name": "Latin script name", "gstin": "optional GSTIN", "state_code": "optional two digit GST state code"}},
  "items": [{{"name": "Latin script only", "qty": number, "unit": "kg/litre/piece", "rate": number, "gst_rate": number, "hsn_code": "optional"}}],
  "msg": "short reply in the customer's language",
  "should_stop": false
}}

Rules:
1. Support English, Hindi, Marathi, Hinglish, and the shop category; return item/customer invoice fields in Latin script for thermal printing.
2. Extract facts only. Never calculate taxable values, CGST, SGST, IGST, tax totals, or grand totals.
3. Prefer the trusted inventory rate, GST rate, and HSN/SAC when an item matches. For an unknown item, include it only when quantity and rate are stated.
4. GSTIN and state are optional for the customer. Never invent either.
5. If GST is not stated for an unknown item, return gst_rate 0. Do not guess a tax rate.
6. Reject negative amounts, quantities, malformed requests, markdown, and extra keys."""

    @staticmethod
    def _decimal(value: Any, default: Decimal = Decimal("0")) -> Decimal:
        try:
            result = Decimal(str(value))
            return result if result >= 0 else default
        except Exception:
            return default

    @classmethod
    def _normalise_item(cls, raw: Any) -> dict[str, Any] | None:
        if not isinstance(raw, dict):
            return None
        name = str(raw.get("name") or raw.get("item_name") or "").strip()[:120]
        quantity = cls._decimal(raw.get("qty", raw.get("quantity", 1)), Decimal("1"))
        rate = cls._decimal(raw.get("rate", raw.get("price", 0)))
        gst_rate = cls._decimal(raw.get("gst_rate", 0))
        if not name or quantity <= 0 or rate < 0 or gst_rate > 40:
            return None
        return {
            "name": name,
            "qty": format(quantity, "f"),
            "qty_display": f"{format(quantity, 'f')}{str(raw.get('unit') or 'unit').strip()[:30]}",
            "unit": str(raw.get("unit") or "unit").strip()[:30],
            "rate": format(rate, "f"),
            "gst_rate": format(gst_rate, "f"),
            "hsn_code": str(raw.get("hsn_code") or "").strip().upper()[:16] or None,
        }

    @classmethod
    def normalise_response(cls, raw: Any) -> dict[str, Any]:
        if not isinstance(raw, dict):
            raw = {}
        response_type = str(raw.get("type") or "ERROR").upper()
        if response_type not in {"BILL", "QUERY", "ERROR"}:
            response_type = "ERROR"
        customer_raw = raw.get("customer") if isinstance(raw.get("customer"), dict) else {}
        customer_gstin = str(customer_raw.get("gstin") or "").strip()
        try:
            customer_gstin = validate_gstin(customer_gstin) if customer_gstin else None
        except ValueError:
            customer_gstin = None
        state_code = str(customer_raw.get("state_code") or "").strip().zfill(2)
        if customer_gstin:
            state_code = customer_gstin[:2]
        items = [
            item
            for item in (cls._normalise_item(candidate) for candidate in raw.get("items", []))
            if item is not None
        ]
        if response_type == "BILL" and not items:
            response_type = "ERROR"
        customer = {
            "name": str(customer_raw.get("name") or "Walk-in customer").strip()[:120],
            "gstin": customer_gstin,
            "state_code": state_code if state_code.isdigit() and len(state_code) == 2 else None,
        }
        return {
            "type": response_type,
            "customer": customer,
            "customer_name": customer["name"],
            "items": items if response_type == "BILL" else [],
            "msg": str(raw.get("msg") or "Please try again.").strip()[:500],
            "should_stop": bool(raw.get("should_stop", False)),
        }

    def process(self, text: str, inventory: Iterable[Dict[str, Any]], shop_category: str) -> dict[str, Any]:
        response, duration, model = self._pipeline.invoke(
            self._build_prompt(text, inventory, shop_category)
        )
        result = self.normalise_response(response)
        result["metadata"] = {"model_used": model, "duration_ms": round(duration * 1000, 2), "pipeline": "gst"}
        logger.info("GST voice request completed type=%s model=%s", result["type"], model)
        return result


gst_voice_service = GstVoiceService()

