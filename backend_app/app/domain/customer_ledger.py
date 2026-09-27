"""Ledger operations with explicit confirmation and transaction-safe balances."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP
from typing import Literal
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import CustomerLedgerEntry, IdempotencyKey, WorkflowDraft
from app.db.tenant import TenantContext
from app.repositories.customer_ledger import CustomerLedgerRepository
from app.repositories.workflows import WorkflowDraftRepository
from app.schemas.ledger import (
    CustomerLedgerResponse,
    LedgerAdjustmentRequest,
    LedgerDraftResponse,
)


LedgerEntryType = Literal["udhaar", "payment"]
_MONEY_QUANTUM = Decimal("0.01")


class CustomerLedgerService:
    draft_ttl = timedelta(minutes=10)

    @staticmethod
    def _money(value: Decimal) -> Decimal:
        return Decimal(value).quantize(_MONEY_QUANTUM, rounding=ROUND_HALF_UP)

    @staticmethod
    def _entry_payload(entry: CustomerLedgerEntry) -> dict[str, object]:
        return {
            "id": entry.id,
            "bill_id": entry.bill_id,
            "entry_type": entry.entry_type,
            "amount": float(entry.amount),
            "balance_after": float(entry.balance_after),
            "source": entry.source,
            "note": entry.note,
            "occurred_at": entry.occurred_at,
            "created_at": entry.created_at,
        }

    async def get_statement(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        customer_id: int,
        *,
        limit: int = 100,
        offset: int = 0,
    ) -> CustomerLedgerResponse:
        repository = CustomerLedgerRepository(session)
        customer = await repository.get_customer_for_update(tenant, customer_id)
        if customer is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Verified customer not found")
        # This is a read-only request. The row lock is released with the request
        # transaction and makes the returned balance/statement internally
        # consistent under concurrent writes.
        safe_limit, safe_offset = min(max(limit, 1), 100), max(offset, 0)
        entries = await repository.list_entries(
            tenant, customer_id, limit=safe_limit, offset=safe_offset
        )
        return CustomerLedgerResponse(
            success=True,
            customer_id=customer.id,
            customer_name=customer.name,
            current_balance=float(customer.ledger_balance),
            entries=[self._entry_payload(entry) for entry in entries],
            total=await repository.count_entries(tenant, customer_id),
            limit=safe_limit,
            offset=safe_offset,
        )

    async def create_adjustment_draft(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        customer_id: int,
        payload: LedgerAdjustmentRequest,
    ) -> LedgerDraftResponse:
        repository = CustomerLedgerRepository(session)
        customer = await repository.get_customer_for_update(tenant, customer_id)
        if customer is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Verified customer not found")

        amount = self._money(payload.amount)
        current_balance = self._money(customer.ledger_balance)
        if payload.entry_type == "payment" and amount > current_balance:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Payment cannot exceed the outstanding ledger balance of ₹{current_balance:.2f}",
            )
        proposed_balance = self._money(
            current_balance + amount if payload.entry_type == "udhaar" else current_balance - amount
        )
        now = datetime.now(UTC)
        draft = WorkflowDraft(
            owner_id=tenant.owner_id,
            shop_category=tenant.shop_category,
            voice_session_id=tenant.session_id,
            kind="ledger_adjustment",
            state={
                "customer_id": customer.id,
                "customer_name": customer.name,
                "entry_type": payload.entry_type,
                "amount": str(amount),
                "current_balance": str(current_balance),
                "proposed_balance": str(proposed_balance),
                "note": payload.note,
                "source": payload.source,
            },
            confirmation_status="draft",
            expires_at=now + self.draft_ttl,
        )
        session.add(draft)
        await session.commit()
        await session.refresh(draft)
        return self._draft_response(draft)

    def _draft_response(self, draft: WorkflowDraft) -> LedgerDraftResponse:
        state = draft.state
        return LedgerDraftResponse(
            id=draft.id,
            version=draft.version,
            confirmation_status=draft.confirmation_status,
            expires_at=draft.expires_at,
            customer_id=int(state["customer_id"]),
            customer_name=str(state["customer_name"]),
            entry_type=str(state["entry_type"]),
            amount=float(Decimal(str(state["amount"]))),
            current_balance=float(Decimal(str(state["current_balance"]))),
            proposed_balance=float(Decimal(str(state["proposed_balance"]))),
            note=state.get("note"),
        )

    async def _append_entry(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        *,
        customer_id: int,
        entry_type: LedgerEntryType,
        amount: Decimal,
        source: str,
        occurred_at: datetime,
        bill_id: int | None = None,
        note: str | None = None,
    ) -> tuple[CustomerLedgerEntry, Decimal]:
        repository = CustomerLedgerRepository(session)
        customer = await repository.get_customer_for_update(tenant, customer_id)
        if customer is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Verified customer not found")

        safe_amount = self._money(amount)
        current_balance = self._money(customer.ledger_balance)
        if entry_type == "payment" and safe_amount > current_balance:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Payment cannot exceed the outstanding ledger balance of ₹{current_balance:.2f}",
            )
        balance_after = self._money(
            current_balance + safe_amount if entry_type == "udhaar" else current_balance - safe_amount
        )
        entry = CustomerLedgerEntry(
            owner_id=tenant.owner_id,
            shop_category=tenant.shop_category,
            verified_customer_id=customer.id,
            bill_id=bill_id,
            entry_type=entry_type,
            amount=safe_amount,
            balance_after=balance_after,
            source=source,
            note=note,
            occurred_at=occurred_at,
        )
        customer.ledger_balance = balance_after
        session.add(entry)
        await session.flush()
        return entry, balance_after

    async def record_bill_udhaar(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        *,
        customer_id: int,
        bill_id: int,
        amount: Decimal,
        occurred_at: datetime,
    ) -> CustomerLedgerEntry:
        entry, _ = await self._append_entry(
            session,
            tenant,
            customer_id=customer_id,
            entry_type="udhaar",
            amount=amount,
            source="bill",
            occurred_at=occurred_at,
            bill_id=bill_id,
            note=f"Udhaar bill #{bill_id}",
        )
        return entry

    async def record_gst_invoice_udhaar(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        *,
        customer_id: int,
        invoice_id: int,
        invoice_number: str,
        amount: Decimal,
        occurred_at: datetime,
    ) -> CustomerLedgerEntry:
        """Add a GST invoice credit charge in the same transaction as its invoice."""
        entry, _ = await self._append_entry(
            session,
            tenant,
            customer_id=customer_id,
            entry_type="udhaar",
            amount=amount,
            source="gst_invoice",
            occurred_at=occurred_at,
            note=f"GST invoice {invoice_number} (#{invoice_id})",
        )
        return entry

    async def confirm_adjustment_draft(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        draft_id: UUID,
        *,
        expected_version: int,
        idempotency_key: str,
    ) -> dict[str, object]:
        action = "customer_ledger.confirm"
        existing = await session.scalar(
            select(IdempotencyKey)
            .where(
                IdempotencyKey.owner_id == tenant.owner_id,
                IdempotencyKey.key == idempotency_key,
                IdempotencyKey.action == action,
            )
            .with_for_update()
        )
        if existing is not None:
            if existing.response is not None:
                return existing.response
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Ledger confirmation is still processing")

        request_key = IdempotencyKey(
            owner_id=tenant.owner_id,
            key=idempotency_key,
            action=action,
        )
        session.add(request_key)
        await session.flush()

        draft = await WorkflowDraftRepository(session).get(tenant, draft_id, lock=True)
        if draft is None or draft.kind != "ledger_adjustment":
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Ledger confirmation not found or expired")
        if draft.confirmation_status != "draft" or draft.version != expected_version:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Ledger confirmation was changed; review it again")

        state = draft.state
        entry, balance_after = await self._append_entry(
            session,
            tenant,
            customer_id=int(state["customer_id"]),
            entry_type=str(state["entry_type"]),
            amount=Decimal(str(state["amount"])),
            source=str(state.get("source") or "app"),
            occurred_at=datetime.now(UTC),
            note=state.get("note"),
        )
        draft.confirmation_status = "confirmed"
        draft.version += 1
        response = {
            "success": True,
            "customer_id": entry.verified_customer_id,
            "entry_id": entry.id,
            "entry_type": entry.entry_type,
            "amount": float(entry.amount),
            "current_balance": float(balance_after),
            "message": (
                f"₹{entry.amount:.2f} udhaar added"
                if entry.entry_type == "udhaar"
                else f"₹{entry.amount:.2f} payment recorded"
            ),
        }
        request_key.response = response
        request_key.status_code = status.HTTP_201_CREATED
        await session.commit()
        return response


customer_ledger_service = CustomerLedgerService()
