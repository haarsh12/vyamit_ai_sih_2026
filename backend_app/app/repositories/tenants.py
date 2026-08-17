"""Resolve authenticated owners into server-trusted repository context."""

from __future__ import annotations

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.categories import stored_category
from app.db.models import User
from app.db.tenant import TenantContext


async def get_tenant_context(session: AsyncSession, owner_id: int) -> TenantContext:
    user = await session.get(User, owner_id)
    if user is None or not user.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Account is unavailable")
    return TenantContext(owner_id=owner_id, shop_category=stored_category(user.shop_category))
