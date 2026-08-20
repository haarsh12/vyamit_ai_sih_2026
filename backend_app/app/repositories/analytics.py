"""Tenant-safe bill, customer, and dashboard data operations."""

from __future__ import annotations

from datetime import UTC, datetime
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Bill, Customer, Item, SaleItem
from app.db.tenant import TenantContext


class AnalyticsRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def category_by_inventory_alias(self, tenant: TenantContext) -> dict[str, str]:
        items = (await self.session.scalars(select(Item).where(
            Item.owner_id == tenant.owner_id, Item.shop_category == tenant.shop_category
        ))).all()
        return {
            alias.strip().casefold(): item.category or "General"
            for item in items for alias in item.names if alias.strip()
        }

    async def upsert_customer_purchase(
        self, *, tenant: TenantContext, phone_number: str | None, name: str | None, amount: Decimal, purchased_at: datetime
    ) -> None:
        phone = (phone_number or "").strip()
        if not phone:
            return
        customer = await self.session.scalar(select(Customer).where(
            Customer.owner_id == tenant.owner_id,
            Customer.shop_category == tenant.shop_category,
            Customer.phone_number == phone,
        ).with_for_update())
        if customer is None:
            customer = Customer(
                owner_id=tenant.owner_id, shop_category=tenant.shop_category, phone_number=phone,
                name=(name or "").strip()[:120] or None,
                total_bills=1, total_spent=amount, last_purchase_date=purchased_at,
            )
            self.session.add(customer)
            return
        customer.total_bills += 1
        customer.total_spent += amount
        customer.last_purchase_date = purchased_at
        if name and name.strip():
            customer.name = name.strip()[:120]

    async def list_bills(self, tenant: TenantContext, *, limit: int, offset: int) -> list[Bill]:
        return (await self.session.scalars(
            select(Bill).where(
                Bill.owner_id == tenant.owner_id, Bill.shop_category == tenant.shop_category
            ).order_by(Bill.bill_date.desc()).offset(offset).limit(limit)
        )).all()
