"""Versioned drafts keep agent proposals separate from financial writes."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import WorkflowDraft
from app.db.tenant import TenantContext
from app.domain.analytics import analytics_service
from app.repositories.workflows import WorkflowDraftRepository
from app.schemas.analytics import BillCreate
from app.schemas.workflows import BillDraftResponse


class WorkflowService:
    bill_draft_ttl = timedelta(minutes=30)

    @staticmethod
    def _response(draft: WorkflowDraft) -> BillDraftResponse:
        return BillDraftResponse(
            id=draft.id,
            kind=draft.kind,
            version=draft.version,
            confirmation_status=draft.confirmation_status,
            expires_at=draft.expires_at,
            state=BillCreate.model_validate(draft.state),
        )

    async def create_bill_draft(
        self, session: AsyncSession, tenant: TenantContext, payload: BillCreate
    ) -> BillDraftResponse:
        draft = WorkflowDraft(
            owner_id=tenant.owner_id,
            shop_category=tenant.shop_category,
            voice_session_id=tenant.session_id,
            kind="bill",
            state=payload.model_dump(mode="json"),
            confirmation_status="draft",
            expires_at=datetime.now(UTC) + self.bill_draft_ttl,
        )
        session.add(draft)
        await session.commit()
        await session.refresh(draft)
        return self._response(draft)

    async def get_bill_draft(
        self, session: AsyncSession, tenant: TenantContext, draft_id: UUID
    ) -> BillDraftResponse:
        draft = await WorkflowDraftRepository(session).get(tenant, draft_id)
        if draft is None or draft.kind != "bill":
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bill draft not found or expired")
        return self._response(draft)

    async def replace_bill_draft(
        self, session: AsyncSession, tenant: TenantContext, draft_id: UUID, *, expected_version: int, payload: BillCreate
    ) -> BillDraftResponse:
        draft = await WorkflowDraftRepository(session).get(tenant, draft_id, lock=True)
        if draft is None or draft.kind != "bill":
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bill draft not found or expired")
        if draft.confirmation_status != "draft" or draft.version != expected_version:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Bill draft was changed; refresh before saving")
        draft.state = payload.model_dump(mode="json")
        draft.version += 1
        await session.commit()
        await session.refresh(draft)
        return self._response(draft)

    async def confirm_bill_draft(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        draft_id: UUID,
        *,
        expected_version: int,
        idempotency_key: str,
    ) -> dict[str, object]:
        draft = await WorkflowDraftRepository(session).get(tenant, draft_id, lock=True)
        if draft is None or draft.kind != "bill":
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bill draft not found or expired")
        if draft.confirmation_status == "confirmed":
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Bill draft was already confirmed")
        if draft.confirmation_status != "draft" or draft.version != expected_version:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Bill draft was changed; refresh before confirming")
        # Validate again at the financial write boundary. Draft JSON is never
        # blindly trusted, even when it was produced by our own agent.
        result = await analytics_service.create_bill(
            session,
            tenant,
            BillCreate.model_validate(draft.state),
            idempotency_key=idempotency_key,
            commit=False,
        )
        draft.confirmation_status = "confirmed"
        draft.version += 1
        await session.commit()
        return {"bill": result, "draft_id": str(draft.id), "confirmation_status": "confirmed"}


workflow_service = WorkflowService()
