"""Compatibility endpoint for inventory dictation proposals."""

from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user_id
from app.db.session import get_db_session
from app.domain.voice_inventory import parse_inventory_dictation
from app.repositories.inventory import InventoryRepository
from app.repositories.tenants import get_tenant_context
from app.schemas.doctor import VoiceInventoryRequest


router = APIRouter(prefix="/inventory", tags=["inventory voice"])


@router.post("/voice-parse")
async def parse_voice_inventory(
    payload: VoiceInventoryRequest,
    user_id: int = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db_session),
) -> dict[str, object]:
    tenant = await get_tenant_context(session, user_id)
    items = await InventoryRepository(session).list(tenant)
    existing_items = [
        {"id": item.master_id, "names": item.names, "price": item.price, "unit": item.unit}
        for item in items
    ]
    categories = sorted({item.category for item in items if item.category})
    return parse_inventory_dictation(
        payload.raw_text, existing_items=existing_items, existing_categories=categories
    )
