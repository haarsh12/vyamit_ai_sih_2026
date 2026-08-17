"""Inventory domain operations called by HTTP routes and future LiveKit tools."""

from __future__ import annotations

from fastapi import HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Item
from app.db.tenant import TenantContext
from app.repositories.inventory import InventoryRepository
from app.schemas.inventory import ItemCreate, ItemUpdate


class InventoryService:
    async def create(self, session: AsyncSession, tenant: TenantContext, payload: ItemCreate) -> Item:
        repository = InventoryRepository(session)
        existing = await repository.get(tenant, payload.id)
        if existing is not None:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Item already exists")
        item = await repository.create(
            tenant,
            master_id=payload.id,
            names=payload.names,
            price=payload.price,
            unit=payload.unit,
            category=payload.category,
            gst_rate_bps=int(payload.gst_rate * 100),
            hsn_code=payload.hsn_code,
            tax_category=payload.tax_category,
        )
        try:
            await session.commit()
        except IntegrityError as error:
            await session.rollback()
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Item already exists") from error
        await session.refresh(item)
        return item

    async def update(
        self, session: AsyncSession, tenant: TenantContext, master_id: str, payload: ItemUpdate
    ) -> Item:
        repository = InventoryRepository(session)
        item = await repository.get(tenant, master_id)
        if item is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")
        item.names = payload.names
        item.price = payload.price
        item.unit = payload.unit
        item.category = payload.category
        item.gst_rate_bps = int(payload.gst_rate * 100)
        item.hsn_code = payload.hsn_code
        item.tax_category = payload.tax_category
        await repository.enqueue_embedding(item)
        await session.commit()
        await session.refresh(item)
        return item

    async def delete(self, session: AsyncSession, tenant: TenantContext, master_id: str) -> None:
        repository = InventoryRepository(session)
        item = await repository.get(tenant, master_id)
        if item is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")
        await repository.delete(item)
        await session.commit()


inventory_service = InventoryService()
