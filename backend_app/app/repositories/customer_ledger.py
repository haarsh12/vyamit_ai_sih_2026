"""Tenant-scoped persistence helpers for immutable customer ledger entries."""

from __future__ import annotations

from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import CustomerLedgerEntry, VerifiedCustomer
from app.db.tenant import TenantContext


class CustomerLedgerRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_customer_for_update(
        self, tenant: TenantContext, customer_id: int
    ) -> VerifiedCustomer | None:
        """Lock the balance row so simultaneous entries cannot overwrite it."""

        return await self.session.scalar(
            select(VerifiedCustomer)
            .where(
                VerifiedCustomer.id == customer_id,
                VerifiedCustomer.owner_id == tenant.owner_id,
                VerifiedCustomer.shop_category == tenant.shop_category,
            )
            .with_for_update()
        )

    async def list_entries(
        self,
        tenant: TenantContext,
        customer_id: int,
        *,
        limit: int,
        offset: int,
    ) -> list[CustomerLedgerEntry]:
        entries = await self.session.scalars(
            select(CustomerLedgerEntry)
            .where(
                CustomerLedgerEntry.owner_id == tenant.owner_id,
                CustomerLedgerEntry.shop_category == tenant.shop_category,
                CustomerLedgerEntry.verified_customer_id == customer_id,
            )
            .order_by(CustomerLedgerEntry.occurred_at.desc(), CustomerLedgerEntry.id.desc())
            .limit(limit)
            .offset(offset)
        )
        return list(entries.all())

    async def count_entries(self, tenant: TenantContext, customer_id: int) -> int:
        result = await self.session.scalar(
            select(func.count(CustomerLedgerEntry.id)).where(
                CustomerLedgerEntry.owner_id == tenant.owner_id,
                CustomerLedgerEntry.shop_category == tenant.shop_category,
                CustomerLedgerEntry.verified_customer_id == customer_id,
            )
        )
        return int(result or 0)

    async def total_outstanding(self, tenant: TenantContext) -> Decimal:
        value = await self.session.scalar(
            select(func.coalesce(func.sum(VerifiedCustomer.ledger_balance), Decimal("0"))).where(
                VerifiedCustomer.owner_id == tenant.owner_id,
                VerifiedCustomer.shop_category == tenant.shop_category,
            )
        )
        return Decimal(value or 0)

    async def has_entries(self, tenant: TenantContext, customer_id: int) -> bool:
        return (
            await self.session.scalar(
                select(CustomerLedgerEntry.id)
                .where(
                    CustomerLedgerEntry.owner_id == tenant.owner_id,
                    CustomerLedgerEntry.shop_category == tenant.shop_category,
                    CustomerLedgerEntry.verified_customer_id == customer_id,
                )
                .limit(1)
            )
        ) is not None
