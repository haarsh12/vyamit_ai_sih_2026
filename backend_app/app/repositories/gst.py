"""GST queries; all functions are bound to a trusted owner context."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import GstConfiguration, GstInvoice, Item
from app.db.tenant import TenantContext


class GstRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def configuration(self, tenant: TenantContext, *, enabled_only: bool = False) -> GstConfiguration | None:
        statement = select(GstConfiguration).where(GstConfiguration.owner_id == tenant.owner_id)
        if enabled_only:
            statement = statement.where(GstConfiguration.is_enabled.is_(True))
        return await self.session.scalar(statement)

    async def inventory_by_alias(self, tenant: TenantContext) -> dict[str, Item]:
        items = (await self.session.scalars(
            select(Item).where(Item.owner_id == tenant.owner_id, Item.shop_category == tenant.shop_category)
        )).all()
        aliases: dict[str, Item] = {}
        for item in items:
            for name in item.names:
                aliases.setdefault(name.strip().casefold(), item)
        return aliases

    async def invoice(self, tenant: TenantContext, invoice_id: int) -> GstInvoice | None:
        return await self.session.scalar(
            select(GstInvoice).where(GstInvoice.id == invoice_id, GstInvoice.owner_id == tenant.owner_id)
        )
