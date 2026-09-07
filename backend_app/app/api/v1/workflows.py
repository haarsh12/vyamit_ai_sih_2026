"""Explicit UI confirmation endpoints for agent-created financial drafts."""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user_id
from app.db.session import get_db_session
from app.domain.workflows import workflow_service
from app.repositories.tenants import get_tenant_context
from app.schemas.analytics import BillCreate
from app.schemas.workflows import BillDraftReplace, BillDraftResponse, DraftConfirmation


router = APIRouter(prefix="/workflows", tags=["confirmed workflows"])


@router.post("/bill-drafts", response_model=BillDraftResponse, status_code=status.HTTP_201_CREATED)
async def create_bill_draft(
    payload: BillCreate, user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)
) -> BillDraftResponse:
    return await workflow_service.create_bill_draft(session, await get_tenant_context(session, user_id), payload)


@router.get("/bill-drafts/{draft_id}", response_model=BillDraftResponse)
async def get_bill_draft(
    draft_id: UUID, user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)
) -> BillDraftResponse:
    return await workflow_service.get_bill_draft(session, await get_tenant_context(session, user_id), draft_id)


@router.put("/bill-drafts/{draft_id}", response_model=BillDraftResponse)
async def replace_bill_draft(
    draft_id: UUID, payload: BillDraftReplace, user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)
) -> BillDraftResponse:
    bill = BillCreate.model_validate(payload.model_dump(exclude={"expected_version"}))
    return await workflow_service.replace_bill_draft(
        session, await get_tenant_context(session, user_id), draft_id, expected_version=payload.expected_version, payload=bill
    )


@router.post("/bill-drafts/{draft_id}/confirm")
async def confirm_bill_draft(
    draft_id: UUID,
    payload: DraftConfirmation,
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key", max_length=128),
    user_id: int = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db_session),
) -> dict[str, object]:
    if not idempotency_key or not idempotency_key.strip():
        raise HTTPException(status_code=status.HTTP_428_PRECONDITION_REQUIRED, detail="Idempotency-Key header is required to confirm a bill draft")
    return await workflow_service.confirm_bill_draft(
        session,
        await get_tenant_context(session, user_id),
        draft_id,
        expected_version=payload.expected_version,
        idempotency_key=idempotency_key.strip(),
        verified_customer_id=payload.verified_customer_id,
    )
