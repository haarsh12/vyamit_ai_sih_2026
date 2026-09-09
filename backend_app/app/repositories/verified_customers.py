"""Repository for verified customer data access operations."""

from __future__ import annotations

from datetime import UTC, datetime
from decimal import Decimal

from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Bill, VerifiedCustomer
from app.db.tenant import TenantContext


class VerifiedCustomerRepository:
    """Data access layer for verified customers with tenant-scoped queries."""

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def create(
        self,
        tenant: TenantContext,
        *,
        name: str,
        phone_number: str | None = None,
    ) -> VerifiedCustomer:
        """Create a new verified customer for the authenticated tenant.

        The original verified-customer migration predates database timestamp
        defaults.  Set both timestamps here so this write works on existing
        deployments as well as freshly-created databases.
        """
        now = datetime.now(UTC)
        customer = VerifiedCustomer(
            owner_id=tenant.owner_id,
            shop_category=tenant.shop_category,
            name=name.strip(),
            phone_number=phone_number.strip() if phone_number else None,
            total_bills=0,
            total_spent=Decimal("0"),
            created_at=now,
            updated_at=now,
        )
        self.session.add(customer)
        await self.session.flush()
        return customer

    async def get_by_id(self, tenant: TenantContext, customer_id: int) -> VerifiedCustomer | None:
        """Get a verified customer by ID within tenant boundary."""
        return await self.session.scalar(
            select(VerifiedCustomer).where(
                VerifiedCustomer.id == customer_id,
                VerifiedCustomer.owner_id == tenant.owner_id,
                VerifiedCustomer.shop_category == tenant.shop_category,
            )
        )

    async def find_by_exact_name(
        self, tenant: TenantContext, name: str
    ) -> VerifiedCustomer | None:
        """Find a verified customer by exact name match (case-insensitive)."""
        clean_name = name.strip()
        if not clean_name:
            return None
        
        return await self.session.scalar(
            select(VerifiedCustomer).where(
                VerifiedCustomer.owner_id == tenant.owner_id,
                VerifiedCustomer.shop_category == tenant.shop_category,
                func.lower(VerifiedCustomer.name) == clean_name.lower(),
            )
        )

    async def find_by_name_pattern(
        self, tenant: TenantContext, name_pattern: str, limit: int = 10
    ) -> list[VerifiedCustomer]:
        """Find verified customers by name pattern (case-insensitive substring match)."""
        clean_pattern = name_pattern.strip()
        if not clean_pattern:
            return []
        
        results = await self.session.scalars(
            select(VerifiedCustomer)
            .where(
                VerifiedCustomer.owner_id == tenant.owner_id,
                VerifiedCustomer.shop_category == tenant.shop_category,
                func.lower(VerifiedCustomer.name).contains(clean_pattern.lower()),
            )
            .order_by(func.lower(VerifiedCustomer.name), VerifiedCustomer.name)
            .limit(limit)
        )
        return list(results.all())

    async def find_by_phone(
        self, tenant: TenantContext, phone_number: str
    ) -> VerifiedCustomer | None:
        """Find a verified customer by phone number."""
        clean_phone = phone_number.strip()
        if not clean_phone:
            return None
        
        return await self.session.scalar(
            select(VerifiedCustomer).where(
                VerifiedCustomer.owner_id == tenant.owner_id,
                VerifiedCustomer.shop_category == tenant.shop_category,
                VerifiedCustomer.phone_number == clean_phone,
            )
        )

    async def list_all(
        self,
        tenant: TenantContext,
        *,
        limit: int = 100,
        offset: int = 0,
        order_by: str = "name",
    ) -> list[VerifiedCustomer]:
        """List all verified customers for a tenant with pagination."""
        query = select(VerifiedCustomer).where(
            VerifiedCustomer.owner_id == tenant.owner_id,
            VerifiedCustomer.shop_category == tenant.shop_category,
        )
        
        # Apply ordering
        if order_by == "recent":
            query = query.order_by(VerifiedCustomer.last_purchase_date.desc().nulls_last())
        elif order_by == "total_spent":
            query = query.order_by(VerifiedCustomer.total_spent.desc())
        else:  # default: alphabetical by name
            query = query.order_by(
                func.lower(VerifiedCustomer.name),
                VerifiedCustomer.name,
            )
        
        query = query.limit(limit).offset(offset)
        
        results = await self.session.scalars(query)
        return list(results.all())

    async def count_all(self, tenant: TenantContext) -> int:
        """Count total verified customers for a tenant."""
        count = await self.session.scalar(
            select(func.count(VerifiedCustomer.id)).where(
                VerifiedCustomer.owner_id == tenant.owner_id,
                VerifiedCustomer.shop_category == tenant.shop_category,
            )
        )
        return count or 0

    async def update_purchase_stats(
        self,
        customer: VerifiedCustomer,
        *,
        amount: Decimal,
        purchased_at: datetime,
    ) -> None:
        """Update customer's purchase statistics after a bill is confirmed."""
        customer.total_bills += 1
        customer.total_spent += amount
        
        # Update last_purchase_date if this is more recent
        if customer.last_purchase_date is None or purchased_at > customer.last_purchase_date:
            customer.last_purchase_date = purchased_at

    async def get_bill_history(
        self,
        tenant: TenantContext,
        customer_id: int,
        *,
        limit: int = 50,
        offset: int = 0,
    ) -> list[Bill]:
        """Get bill history for a verified customer, ordered by most recent first."""
        results = await self.session.scalars(
            select(Bill)
            .where(
                Bill.owner_id == tenant.owner_id,
                Bill.shop_category == tenant.shop_category,
                Bill.verified_customer_id == customer_id,
            )
            .order_by(Bill.bill_date.desc())
            .limit(limit)
            .offset(offset)
        )
        return list(results.all())

    async def count_bills(self, tenant: TenantContext, customer_id: int) -> int:
        """Count total bills for a verified customer."""
        count = await self.session.scalar(
            select(func.count(Bill.id)).where(
                Bill.owner_id == tenant.owner_id,
                Bill.shop_category == tenant.shop_category,
                Bill.verified_customer_id == customer_id,
            )
        )
        return count or 0

    async def get_bill_for_linking(
        self,
        tenant: TenantContext,
        bill_id: int,
    ) -> Bill | None:
        """Lock one tenant-owned bill before it is linked to a verified customer."""
        return await self.session.scalar(
            select(Bill)
            .where(
                Bill.id == bill_id,
                Bill.owner_id == tenant.owner_id,
                Bill.shop_category == tenant.shop_category,
            )
            .with_for_update()
        )

    async def search_by_embedding(
        self,
        tenant: TenantContext,
        query_embedding: list[float],
        *,
        limit: int = 5,
        min_score: float = 0.6,
    ) -> list[tuple[VerifiedCustomer, float]]:
        """Search verified customers by name embedding with cosine similarity."""
        statement = (
            select(
                VerifiedCustomer,
                VerifiedCustomer.name_embedding.cosine_distance(query_embedding).label("distance"),
            )
            .where(
                VerifiedCustomer.owner_id == tenant.owner_id,
                VerifiedCustomer.shop_category == tenant.shop_category,
                VerifiedCustomer.name_embedding.is_not(None),
            )
            .order_by("distance")
            .limit(limit)
        )
        
        rows = (await self.session.execute(statement)).all()
        
        # Convert distance to similarity score (1 - distance) and filter by min_score
        results = [
            (customer, max(0.0, 1.0 - float(distance)))
            for customer, distance in rows
            if distance is not None
        ]
        
        return [(customer, score) for customer, score in results if score >= min_score]

    async def delete(self, customer: VerifiedCustomer) -> None:
        """Delete a verified customer (soft delete by removing from verified list)."""
        await self.session.delete(customer)
        await self.session.flush()
