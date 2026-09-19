"""Authenticated Long Bill transcript endpoint."""

from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.rate_limit import SlidingWindowRateLimiter
from app.core.security import get_current_user_id
from app.db.session import get_db_session
from app.domain.long_bill import long_bill_service
from app.repositories.tenants import get_tenant_context
from app.schemas.long_bill import LongBillTranscriptRequest, LongBillTranscriptResponse


router = APIRouter(prefix="/voice/long-bill", tags=["long bill"])
_transcript_limiter = SlidingWindowRateLimiter(max_requests=20, window_seconds=60)


@router.post("/drafts", response_model=LongBillTranscriptResponse)
async def create_long_bill_draft(
    payload: LongBillTranscriptRequest,
    user_id: int = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db_session),
) -> LongBillTranscriptResponse:
    """Create a review-only draft from the locally recognized final transcript."""

    _transcript_limiter.check("long-bill", str(user_id))
    tenant = await get_tenant_context(session, user_id)
    return await long_bill_service.create_draft(session, tenant, payload.transcript)
