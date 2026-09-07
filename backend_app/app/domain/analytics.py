"""Billing writes and dashboard aggregation kept independent from the HTTP/UI layer."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from decimal import Decimal
from typing import Any

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import AuditEvent, Bill, IdempotencyKey, Item, SaleItem
from app.db.tenant import TenantContext
from app.domain.billing_source import billing_source_from_items
from app.domain.customers import customer_service
from app.repositories.analytics import AnalyticsRepository
from app.repositories.verified_customers import VerifiedCustomerRepository
from app.schemas.analytics import BillCreate


class AnalyticsService:
    async def create_bill(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        payload: BillCreate,
        *,
        idempotency_key: str,
        commit: bool = True,
        verified_customer_id: int | None = None,
    ) -> dict[str, Any]:
        action = "bill.create"
        existing = await session.scalar(select(IdempotencyKey).where(
            IdempotencyKey.owner_id == tenant.owner_id, IdempotencyKey.key == idempotency_key, IdempotencyKey.action == action
        ).with_for_update())
        if existing is not None:
            if existing.response is not None:
                return existing.response
            raise HTTPException(status_code=409, detail="A bill with this idempotency key is still processing")
        request_key = IdempotencyKey(owner_id=tenant.owner_id, key=idempotency_key, action=action)
        session.add(request_key)
        await session.flush()
        repository = AnalyticsRepository(session)
        now = datetime.now(UTC)
        categories = await repository.category_by_inventory_alias(tenant)
        items = [
            {
                "name": item.name.strip(),
                "quantity": str(item.quantity),
                "unit": item.unit.strip(),
                "price": str(item.price),
                "total": str(item.total),
                "_billing_source": payload.billing_source,
            }
            for item in payload.items
        ]
        
        # Link to verified customer if provided
        final_verified_customer_id = verified_customer_id

        if final_verified_customer_id is not None:
            if await VerifiedCustomerRepository(session).get_by_id(
                tenant,
                final_verified_customer_id,
            ) is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Verified customer not found",
                )

        # A same-name record is not sufficient to identify a person.  Linking a
        # printed bill is always an explicit owner choice made in the post-print
        # verification dialog (or an explicit workflow confirmation).
        
        bill = Bill(
            owner_id=tenant.owner_id, shop_category=tenant.shop_category, total_amount=payload.total_amount,
            total_items=len(payload.items), items=items, customer_phone=payload.customer_phone,
            customer_name=payload.customer_name, verified_customer_id=final_verified_customer_id,
            payment_method=payload.payment_method.strip(), bill_type=payload.bill_type,
            bill_date=now,
        )
        session.add(bill)
        await session.flush()
        for item in payload.items:
            session.add(SaleItem(
                owner_id=tenant.owner_id, bill_id=bill.id, shop_category=tenant.shop_category,
                item_name=item.name.strip(), item_category=categories.get(item.name.strip().casefold(), "General"),
                quantity=item.quantity, unit=item.unit.strip(), price_per_unit=item.price,
                total_price=item.total, sale_date=now, hour_of_day=now.hour,
            ))
        
        # Update existing Customer aggregate (for phone-based tracking)
        await repository.upsert_customer_purchase(
            tenant=tenant, phone_number=payload.customer_phone, name=payload.customer_name,
            amount=payload.total_amount, purchased_at=now,
        )
        
        # Update VerifiedCustomer stats if linked
        if final_verified_customer_id:
            await customer_service.update_customer_stats_after_bill(
                session,
                tenant,
                final_verified_customer_id,
                amount=payload.total_amount,
                bill_date=now,
            )
        
        result = {"success": True, "bill_id": bill.id, "message": "Bill saved successfully"}
        request_key.response, request_key.status_code = result, status.HTTP_201_CREATED
        session.add(AuditEvent(
            created_at=now, owner_id=tenant.owner_id, session_id=tenant.session_id,
            action=action, outcome="success", metadata_={"bill_id": bill.id, "verified_customer_id": final_verified_customer_id},
        ))
        # Workflow confirmation adds its draft state to this same transaction.
        # Ordinary compatibility endpoints retain the existing commit behaviour.
        if commit:
            await session.commit()
        else:
            await session.flush()
        return result

    async def list_bills(self, session: AsyncSession, tenant: TenantContext, *, limit: int, offset: int) -> dict[str, Any]:
        safe_limit, safe_offset = min(max(limit, 1), 100), max(offset, 0)
        bills = await AnalyticsRepository(session).list_bills(tenant, limit=safe_limit, offset=safe_offset)
        return {
            "success": True, "bills": [{
                "id": bill.id, "total_amount": float(bill.total_amount), "total_items": bill.total_items,
                "items": bill.items, "customer_phone": bill.customer_phone, "customer_name": bill.customer_name,
                "payment_method": bill.payment_method, "bill_type": bill.bill_type,
                "billing_source": billing_source_from_items(bill.items),
                "bill_date": bill.bill_date.isoformat(),
                "created_at": bill.created_at.isoformat(),
            } for bill in bills], "total": len(bills), "limit": safe_limit, "offset": safe_offset,
        }

    async def dashboard(self, session: AsyncSession, tenant: TenantContext, *, days: int) -> dict[str, Any]:
        safe_days = min(max(days, 1), 3650)
        since = datetime.now(UTC) - timedelta(days=safe_days)
        owner = tenant.owner_id
        total_revenue, total_bills = (await session.execute(select(
            func.coalesce(func.sum(Bill.total_amount), Decimal("0")), func.count(Bill.id)
        ).where(
            Bill.owner_id == owner, Bill.shop_category == tenant.shop_category, Bill.bill_date >= since
        ))).one()
        inventory_count = await session.scalar(select(func.count(Item.id)).where(
            Item.owner_id == owner, Item.shop_category == tenant.shop_category
        )) or 0
        top_items = (await session.execute(select(
            SaleItem.item_name, SaleItem.unit, func.sum(SaleItem.quantity), func.sum(SaleItem.total_price), func.count(SaleItem.id)
        ).where(
            SaleItem.owner_id == owner, SaleItem.shop_category == tenant.shop_category, SaleItem.sale_date >= since
        ).group_by(
            SaleItem.item_name, SaleItem.unit
        ).order_by(func.sum(SaleItem.total_price).desc()).limit(10))).all()
        categories = (await session.execute(select(
            SaleItem.item_category, func.sum(SaleItem.total_price), func.sum(SaleItem.quantity)
        ).where(
            SaleItem.owner_id == owner, SaleItem.shop_category == tenant.shop_category, SaleItem.sale_date >= since
        ).group_by(
            SaleItem.item_category
        ).order_by(func.sum(SaleItem.total_price).desc()))).all()
        peak_hours = (await session.execute(select(
            SaleItem.hour_of_day, func.count(SaleItem.id), func.sum(SaleItem.total_price)
        ).where(
            SaleItem.owner_id == owner, SaleItem.shop_category == tenant.shop_category, SaleItem.sale_date >= since
        ).group_by(
            SaleItem.hour_of_day
        ).order_by(SaleItem.hour_of_day))).all()
        peak_day = (await session.execute(select(
            func.extract("dow", Bill.bill_date), func.count(Bill.id), func.sum(Bill.total_amount)
        ).where(
            Bill.owner_id == owner, Bill.shop_category == tenant.shop_category, Bill.bill_date >= since
        ).group_by(
            func.extract("dow", Bill.bill_date)
        ).order_by(func.sum(Bill.total_amount).desc()).limit(1))).first()
        total_revenue = Decimal(total_revenue)
        total_bills = int(total_bills)
        return {
            "success": True, "period_days": safe_days,
            "summary": {"total_revenue": float(total_revenue), "total_bills": total_bills,
                        "average_bill_value": float(total_revenue / total_bills) if total_bills else 0.0,
                        "total_inventory_items": int(inventory_count)},
            "top_selling_items": [{"name": row[0], "unit": row[1], "quantity": float(row[2]), "revenue": float(row[3]), "times_sold": int(row[4])} for row in top_items],
            "category_breakdown": [{"category": row[0], "total_sales": float(row[1]), "quantity": float(row[2]), "percentage": round(float(Decimal(row[1]) / total_revenue * 100), 1) if total_revenue else 0.0} for row in categories],
            "peak_hours": [{"hour": int(row[0]), "sales_count": int(row[1]), "total_sales": float(row[2])} for row in peak_hours],
            "peak_day": None if peak_day is None else {"day": ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][int(peak_day[0])], "bill_count": int(peak_day[1]), "total_sales": float(peak_day[2])},
        }

    async def overview(self, session: AsyncSession, tenant: TenantContext, *, days: int) -> dict[str, Any]:
        safe_days = min(max(days, 1), 3650)
        since = datetime.now(UTC) - timedelta(days=safe_days)
        revenue, count = (await session.execute(select(
            func.coalesce(func.sum(Bill.total_amount), Decimal("0")), func.count(Bill.id)
        ).where(
            Bill.owner_id == tenant.owner_id,
            Bill.shop_category == tenant.shop_category,
            Bill.bill_date >= since,
        ))).one()
        revenue, count = Decimal(revenue), int(count)
        return {"success": True, "period_days": safe_days, "total_revenue": float(revenue), "total_bills": count, "average_bill": float(revenue / count) if count else 0.0}


analytics_service = AnalyticsService()
