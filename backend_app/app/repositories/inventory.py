"""Inventory persistence with mandatory owner/category filters."""

from __future__ import annotations

from datetime import UTC, datetime
from hashlib import sha256
from typing import Sequence

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import EmbeddingJob, Item
from app.db.tenant import TenantContext


def item_embedding_source_hash(item: Item) -> str:
    source = "|".join([*item.names, item.category, item.unit])
    return sha256(source.casefold().encode("utf-8")).hexdigest()


class InventoryRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def list(self, tenant: TenantContext) -> Sequence[Item]:
        result = await self.session.scalars(
            select(Item)
            .where(Item.owner_id == tenant.owner_id, Item.shop_category == tenant.shop_category)
            .order_by(Item.category, Item.master_id)
        )
        return result.all()

    async def get(self, tenant: TenantContext, master_id: str) -> Item | None:
        return await self.session.scalar(
            select(Item).where(
                Item.owner_id == tenant.owner_id,
                Item.shop_category == tenant.shop_category,
                Item.master_id == master_id,
            )
        )

    async def create(
        self,
        tenant: TenantContext,
        *,
        master_id: str,
        names: list[str],
        price: object,
        unit: str,
        category: str,
        gst_rate_bps: int,
        hsn_code: str | None,
        tax_category: str | None,
    ) -> Item:
        item = Item(
            owner_id=tenant.owner_id,
            shop_category=tenant.shop_category,
            master_id=master_id,
            names=names,
            price=price,
            unit=unit,
            category=category,
            gst_rate_bps=gst_rate_bps,
            hsn_code=hsn_code,
            tax_category=tax_category,
        )
        self.session.add(item)
        await self.session.flush()
        await self.enqueue_embedding(item)
        return item

    async def enqueue_embedding(self, item: Item) -> None:
        source_hash = item_embedding_source_hash(item)
        self.session.add(
            EmbeddingJob(
                entity_type="item",
                entity_id=item.id,
                owner_id=item.owner_id,
                operation="upsert",
                source_hash=source_hash,
                available_at=datetime.now(UTC),
            )
        )

    async def delete(self, item: Item) -> None:
        await self.session.delete(item)
