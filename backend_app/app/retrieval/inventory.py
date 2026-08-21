"""Tenant-filtered exact, keyword, and pgvector inventory search."""

from __future__ import annotations

import re
from dataclasses import dataclass
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Item
from app.db.tenant import TenantContext
from app.retrieval.embeddings import EmbeddingServiceError, VertexEmbeddingService


def _tokens(value: str) -> set[str]:
    return {part for part in re.sub(r"[^\w]+", " ", value.casefold()).split() if len(part) > 1}


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
        query_key, query_tokens = clean_query.casefold(), _tokens(clean_query)
        exact = [
            InventoryMatch(item, 1.0, "exact") for item in items
            if any(name.casefold() == query_key for name in item.names)
        ]
        if exact:
            return exact[:safe_limit]
        keyword_matches = []
        for item in items:
            item_tokens = _tokens(" ".join([*item.names, item.category, item.unit]))
            score = len(query_tokens & item_tokens) / max(1, len(query_tokens))
            if score >= 0.6:
                keyword_matches.append(InventoryMatch(item, score, "keyword"))
        keyword_matches.sort(key=lambda result: result.score, reverse=True)
        if keyword_matches:
            return keyword_matches[:safe_limit]
        # The slow/costed path happens only after deterministic matching fails.
        if self.embeddings is None:
            self.embeddings = VertexEmbeddingService()
        try:
            vector = await self.embeddings.embed_query(clean_query)
        except EmbeddingServiceError:
            return []
        statement = select(Item, Item.embedding.cosine_distance(vector).label("distance")).where(
            Item.owner_id == tenant.owner_id,
            Item.shop_category == tenant.shop_category,
            Item.embedding.is_not(None),
        ).order_by("distance").limit(safe_limit)
        rows = (await session.execute(statement)).all()
        return [InventoryMatch(item, max(0.0, 1.0 - float(distance)), "semantic") for item, distance in rows if distance is not None]


inventory_search_service = InventorySearchService()
