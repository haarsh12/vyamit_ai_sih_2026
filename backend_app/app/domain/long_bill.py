"""Deterministic, tenant-scoped transcript-to-draft conversion for Long Bill.

Long Bill intentionally sends only the final device transcript to the API.  The
server never receives or persists microphone audio, never trusts a client price,
and returns an editable draft rather than creating a financial record.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP

from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Item
from app.db.tenant import TenantContext
from app.domain.workflows import workflow_service
from app.retrieval.inventory import inventory_search_service
from app.schemas.analytics import BillCreate
from app.schemas.long_bill import LongBillTranscriptResponse


_MAX_DRAFT_ITEMS = 30
_MAX_SEGMENTS_RETURNED = 12
_DEVANAGARI_DIGITS = str.maketrans("०१२३४५६७८९", "0123456789")
_NUMBER_WORDS: dict[str, Decimal] = {
    "one": Decimal("1"),
    "two": Decimal("2"),
    "three": Decimal("3"),
    "four": Decimal("4"),
    "five": Decimal("5"),
    "six": Decimal("6"),
    "seven": Decimal("7"),
    "eight": Decimal("8"),
    "nine": Decimal("9"),
    "ten": Decimal("10"),
    "half": Decimal("0.5"),
    "quarter": Decimal("0.25"),
    "aadha": Decimal("0.5"),
    "adha": Decimal("0.5"),
    "dedh": Decimal("1.5"),
    "derh": Decimal("1.5"),
    "ek": Decimal("1"),
    "do": Decimal("2"),
    "teen": Decimal("3"),
    "char": Decimal("4"),
    "paanch": Decimal("5"),
    "aadha": Decimal("0.5"),
    "आधा": Decimal("0.5"),
    "पाव": Decimal("0.25"),
    "डेढ़": Decimal("1.5"),
    "डेढ़": Decimal("1.5"),
    "एक": Decimal("1"),
    "दो": Decimal("2"),
    "तीन": Decimal("3"),
    "चार": Decimal("4"),
    "पांच": Decimal("5"),
    "पाँच": Decimal("5"),
}
_NUMBER_ALTERNATIVES = "|".join(sorted(map(re.escape, _NUMBER_WORDS), key=len, reverse=True))
_QUANTITY_PATTERN = re.compile(
    rf"(?<![\w.])(?P<amount>\d+(?:\.\d+)?|{_NUMBER_ALTERNATIVES})\s*"
    r"(?P<unit>kg|kilo(?:gram)?s?|किलो(?:ग्राम)?|g|gm|grams?|ग्राम|"
    r"l|lit(?:er|re)?s?|लीटर|piece(?:s)?|pcs?|packet(?:s)?|pack(?:s)?|"
    r"पीस|पैकेट)?(?![\w.])",
    re.IGNORECASE,
)


@dataclass(frozen=True, slots=True)
class _CatalogMention:
    item: Item
    start: int
    end: int


def _normalise_unit(value: str | None) -> str:
    key = (value or "").casefold().strip()
    if key in {"kg", "kilo", "kilogram", "kilograms", "किलो", "किलोग्राम"}:
        return "kg"
    if key in {"g", "gm", "gram", "grams", "ग्राम"}:
        return "g"
    if key in {"l", "lit", "liter", "litre", "liters", "litres", "लीटर"}:
        return "liter"
    if key in {"pc", "pcs", "piece", "pieces", "पीस"}:
        return "piece"
    if key in {"packet", "packets", "pack", "packs", "पैकेट"}:
        return "packet"
    return key or "unit"


def _convert_quantity(quantity: Decimal, spoken_unit: str | None, catalog_unit: str) -> Decimal:
    source = _normalise_unit(spoken_unit)
    target = _normalise_unit(catalog_unit)
    if source == target or not spoken_unit:
        return quantity
    if source == "g" and target == "kg":
        return quantity / Decimal("1000")
    if source == "kg" and target == "g":
        return quantity * Decimal("1000")
    return quantity


def printable_catalog_name(item: Item) -> str | None:
    """Use an existing Latin-script catalogue alias for receipt compatibility."""

    for name in item.names:
        clean = name.strip()
        if clean and re.search(r"[A-Za-z]", clean):
            return clean[:120]
    return None


def _find_catalog_mentions(transcript: str, catalog: list[Item]) -> list[_CatalogMention]:
    """Find non-overlapping catalogue aliases, preferring the longest alias."""

    candidates: list[_CatalogMention] = []
    for item in catalog:
        for alias in item.names:
            clean_alias = alias.strip()
            if len(clean_alias) < 2:
                continue
            for match in re.finditer(rf"(?<!\w){re.escape(clean_alias)}(?!\w)", transcript, re.IGNORECASE):
                candidates.append(_CatalogMention(item=item, start=match.start(), end=match.end()))

    candidates.sort(key=lambda match: (match.start, -(match.end - match.start)))
    selected: list[_CatalogMention] = []
    occupied_until = -1
    for candidate in candidates:
        if candidate.start < occupied_until:
            continue
        selected.append(candidate)
        occupied_until = candidate.end
    return selected[:_MAX_DRAFT_ITEMS]


def _quantity_for_mention(transcript: str, mention: _CatalogMention, next_start: int) -> Decimal:
    """Read a quantity immediately before or after one catalogue mention.

    A Long Bill often says either ``2 kg aata`` or ``aata 2 kg``.  We score
    explicit units first and keep the search inside this item's local segment,
    so a following item's quantity cannot become this item's quantity.
    """

    before_start = max(0, mention.start - 48)
    after_end = min(len(transcript), min(next_start, mention.end + 48))
    candidates: list[tuple[int, int, Decimal, str | None]] = []
    for context, absolute_start, is_before in (
        (transcript[before_start:mention.start], before_start, True),
        (transcript[mention.end:after_end], mention.end, False),
    ):
        for found in _QUANTITY_PATTERN.finditer(context.translate(_DEVANAGARI_DIGITS)):
            raw_amount = found.group("amount").casefold()
            try:
                amount = _NUMBER_WORDS.get(raw_amount)
                if amount is None:
                    amount = Decimal(raw_amount)
            except Exception:
                continue
            if amount <= 0 or amount > Decimal("100000"):
                continue
            absolute_edge = absolute_start + (found.end() if is_before else found.start())
            distance = (
                mention.start - absolute_edge if is_before else absolute_edge - mention.end
            )
            # Explicit units are less ambiguous than a bare number.
            candidates.append((0 if found.group("unit") else 1, distance, amount, found.group("unit")))
    if not candidates:
        return Decimal("1")
    _, _, amount, spoken_unit = min(candidates, key=lambda candidate: (candidate[0], candidate[1]))
    return _convert_quantity(amount, spoken_unit, mention.item.unit)


class LongBillService:
    """Build an editable draft from a final locally-recognized transcript."""

    async def create_draft(
        self, session: AsyncSession, tenant: TenantContext, transcript: str
    ) -> LongBillTranscriptResponse:
        from app.domain.token_saver import token_saver_service

        # First, process transcript via shared LLM billing service
        result = await token_saver_service.process(session, tenant, transcript)

        if result.type == "BILL" and result.draft is not None:
            return LongBillTranscriptResponse(
                status="draft",
                message=result.message or "Long Bill draft is ready to review.",
                draft=result.draft,
                resolved_item_count=len(result.draft.items),
                unresolved_segments=result.unresolved_items or [],
            )

        # Fallback to deterministic regex mentions if LLM did not return a draft bill
        catalog = await inventory_search_service.list_catalog(session, tenant)
        if catalog:
            mentions = _find_catalog_mentions(transcript, catalog)
            proposed_items: list[dict[str, object]] = []
            unresolved_segments: list[str] = list(result.unresolved_items or [])
            for index, mention in enumerate(mentions):
                bill_name = printable_catalog_name(mention.item)
                if bill_name is None:
                    unresolved_segments.append(mention.item.names[0][:120])
                    continue
                next_start = mentions[index + 1].start if index + 1 < len(mentions) else len(transcript)
                quantity = _quantity_for_mention(transcript, mention, next_start)
                price = Decimal(mention.item.price).quantize(Decimal("0.01"))
                total = (quantity * price).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
                proposed_items.append(
                    {
                        "name": bill_name,
                        "quantity": quantity,
                        "unit": _normalise_unit(mention.item.unit),
                        "price": price,
                        "total": total,
                    }
                )

            if proposed_items:
                total_amount = sum((item["total"] for item in proposed_items), Decimal("0.00"))
                payload = BillCreate.model_validate(
                    {
                        "items": proposed_items,
                        "total_amount": total_amount.quantize(Decimal("0.01")),
                        "payment_method": "cash",
                        "bill_type": "printed",
                        "billing_source": "voice",
                    }
                )
                draft = await workflow_service.create_bill_draft(session, tenant, payload)
                return LongBillTranscriptResponse(
                    status="draft",
                    message="Long Bill draft is ready to review.",
                    draft=draft,
                    resolved_item_count=len(proposed_items),
                    unresolved_segments=unresolved_segments[:_MAX_SEGMENTS_RETURNED],
                )

        return LongBillTranscriptResponse(
            status="needs_review",
            message=result.message or "No items were recognized. Review the transcript or speak item name, price, and quantity.",
            resolved_item_count=0,
            unresolved_segments=(result.unresolved_items or [])[:_MAX_SEGMENTS_RETURNED],
        )


long_bill_service = LongBillService()
