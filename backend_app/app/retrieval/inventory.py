"""Tenant-filtered exact, keyword, transliterated, and pgvector inventory search."""

from __future__ import annotations

import asyncio
import re
from dataclasses import dataclass
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Item
from app.db.tenant import TenantContext
from app.retrieval.embeddings import EmbeddingServiceError, VertexEmbeddingService

TRANSLITERATION_MAP: dict[str, list[str]] = {
    "आटा": ["atta", "flour", "wheat"],
    "अट्टा": ["atta", "flour", "wheat"],
    "दूध": ["milk", "doodh"],
    "चावल": ["rice", "chawal"],
    "चीनी": ["sugar", "cheeni"],
    "शक्कर": ["sugar", "shakkar"],
    "तेल": ["oil", "tel"],
    "दाल": ["dal", "pulses", "lentils"],
    "नमक": ["salt", "namak"],
    "चाय": ["tea", "chai"],
    "बिस्कुट": ["biscuit", "biscuits"],
    "साबुन": ["soap", "sabun"],
    "मसाला": ["masala", "spices"],
    "घी": ["ghee"],
    "पनीर": ["paneer", "cheese"],
    "दही": ["curd", "dahi", "yogurt"],
    "ब्रेड": ["bread"],
    "अंडा": ["egg", "eggs", "anda"],
    "अंडे": ["egg", "eggs", "anda"],
    "आलू": ["potato", "aloo", "aaloo"],
    "प्याज": ["onion", "pyaaz"],
    "प्याज़": ["onion", "pyaaz"],
    "टमाटर": ["tomato", "tamatar"],
    "हल्दी": ["turmeric", "haldi"],
    "मिर्च": ["chilli", "chili", "mirch"],
    "धनिया": ["coriander", "dhaniya"],
    "जीरा": ["jeera", "cumin"],
}

STOP_WORDS = {
    "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
    "1kg", "1-kg", "1किलो", "किलो", "kg", "g", "gm", "gram", "grams",
    "liter", "lit", "litre", "l", "pack", "pkt", "packet",
    "चाहिए", "जोड़", "दो", "दूं", "दू", "चेक", "करो", "में", "का", "की", "के", "से", "है", "क्या", "बिल", "इन्वेंटरी", "हमारी"
}


def _tokens(value: str) -> set[str]:
    clean_parts = [part for part in re.sub(r"[^\w\u0900-\u097F]+", " ", value.casefold()).split() if len(part) >= 1]
    tokens = set(clean_parts)
    for part in clean_parts:
        if part in TRANSLITERATION_MAP:
            tokens.update(TRANSLITERATION_MAP[part])
    return tokens


@dataclass(frozen=True, slots=True)
class InventoryMatch:
    item: Item
    score: float
    source: str

    def to_tool_payload(self) -> dict[str, object]:
        return {
            "id": self.item.master_id,
            "names": self.item.names[:3],
            "category": self.item.category,
            "price": str(Decimal(self.item.price).quantize(Decimal("0.01"))),
            "unit": self.item.unit,
            "gst_rate": str(Decimal(self.item.gst_rate_bps) / Decimal("100")),
            "match_score": round(self.score, 3),
            "match_source": self.source,
        }


class InventorySearchService:
    """Avoids embeddings for exact alias/keyword matches and scopes every query internally."""

    def __init__(self, embeddings: VertexEmbeddingService | None = None) -> None:
        self.embeddings = embeddings

    async def list_catalog(self, session: AsyncSession, tenant: TenantContext) -> list[Item]:
        """Return the active tenant catalog for a non-mutating draft proposal."""

        return (await session.scalars(select(Item).where(
            Item.owner_id == tenant.owner_id, Item.shop_category == tenant.shop_category
        ))).all()

    async def search(
        self, session: AsyncSession, tenant: TenantContext, query: str, *, limit: int = 5
    ) -> list[InventoryMatch]:
        clean_query = query.strip()
        if not clean_query:
            return []
        safe_limit = min(max(limit, 1), 10)
        items = await self.list_catalog(session, tenant)
        if not items:
            return []

        query_key = clean_query.casefold()
        query_tokens = {t for t in _tokens(clean_query) if t not in STOP_WORDS}

        # 1. Exact Name / Alias Match
        exact = [
            InventoryMatch(item, 1.0, "exact") for item in items
            if any(name.casefold() == query_key for name in item.names)
        ]
        if exact:
            return exact[:safe_limit]

        # 2. Substring or Transliterated Match
        substring_matches = []
        for item in items:
            item_all_names = " ".join([*item.names, item.category or "", item.master_id or ""]).casefold()
            match_found = False
            for t in query_tokens:
                if t in item_all_names or any(t in name.casefold() or name.casefold() in t for name in item.names):
                    match_found = True
                    break
            if match_found:
                substring_matches.append(InventoryMatch(item, 0.9, "substring"))

        if substring_matches:
            return substring_matches[:safe_limit]

        # 3. Keyword Jaccard Match
        keyword_matches = []
        for item in items:
            item_tokens = _tokens(" ".join([*item.names, item.category or "", item.unit or ""]))
            intersection = query_tokens & item_tokens
            if intersection:
                score = len(intersection) / max(1, len(query_tokens))
                if score >= 0.3:
                    keyword_matches.append(InventoryMatch(item, score, "keyword"))
        keyword_matches.sort(key=lambda result: result.score, reverse=True)
        if keyword_matches:
            return keyword_matches[:safe_limit]

        # 4. Safe Semantic pgvector Fallback with Short Timeout
        if self.embeddings is None:
            self.embeddings = VertexEmbeddingService()
        try:
            vector = await asyncio.wait_for(self.embeddings.embed_query(clean_query), timeout=1.5)
            statement = select(Item, Item.embedding.cosine_distance(vector).label("distance")).where(
                Item.owner_id == tenant.owner_id,
                Item.shop_category == tenant.shop_category,
                Item.embedding.is_not(None),
            ).order_by("distance").limit(safe_limit)
            rows = (await session.execute(statement)).all()
            return [InventoryMatch(item, max(0.0, 1.0 - float(distance)), "semantic") for item, distance in rows if distance is not None]
        except Exception:
            return []


inventory_search_service = InventorySearchService()

