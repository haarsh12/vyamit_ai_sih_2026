"""Bill history and dashboard routes retained for Flutter compatibility."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user_id
from app.db.session import get_db_session
from app.domain.analytics import analytics_service
from app.repositories.tenants import get_tenant_context
from app.schemas.analytics import BillCreate


router = APIRouter(prefix="/analytics", tags=["analytics"])


@router.post("/bills", status_code=status.HTTP_201_CREATED)
async def create_bill(
    payload: BillCreate, idempotency_key: str | None = Header(default=None, alias="Idempotency-Key", max_length=128),
    user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session),
) -> dict:
    if not idempotency_key or not idempotency_key.strip():
        raise HTTPException(status_code=428, detail="Idempotency-Key header is required to save a bill")
    return await analytics_service.create_bill(session, await get_tenant_context(session, user_id), payload, idempotency_key=idempotency_key.strip())


@router.get("/bills")
async def get_bills(limit: int = 50, offset: int = 0, user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)) -> dict:
    return await analytics_service.list_bills(session, await get_tenant_context(session, user_id), limit=limit, offset=offset)


@router.get("/dashboard")
async def get_dashboard(days: int = 30, user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)) -> dict:
    return await analytics_service.dashboard(session, await get_tenant_context(session, user_id), days=days)


@router.get("/overview")
async def get_overview(days: int = 7, user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)) -> dict:
    return await analytics_service.overview(session, await get_tenant_context(session, user_id), days=days)
