"""Inventory routes retained for the existing Flutter application."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user_id
from app.db.session import get_db_session
from app.domain.inventory import inventory_service
from app.repositories.inventory import InventoryRepository
from app.repositories.tenants import get_tenant_context
from app.schemas.inventory import ItemCreate, ItemResponse, ItemUpdate


router = APIRouter(prefix="/items", tags=["inventory"])


@router.get("/", response_model=list[ItemResponse])
async def list_items(
    user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)
) -> list[ItemResponse]:
    tenant = await get_tenant_context(session, user_id)
    items = await InventoryRepository(session).list(tenant)
    return [ItemResponse.from_entity(item) for item in items]


@router.post("/", response_model=ItemResponse, status_code=status.HTTP_201_CREATED)
async def create_item(
    payload: ItemCreate,
    user_id: int = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db_session),
) -> ItemResponse:
    item = await inventory_service.create(session, await get_tenant_context(session, user_id), payload)
    return ItemResponse.from_entity(item)


@router.put("/{item_id}/", response_model=ItemResponse)
@router.put("/{item_id}", response_model=ItemResponse, include_in_schema=False)
async def update_item(
    item_id: str,
    payload: ItemUpdate,
    user_id: int = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db_session),
) -> ItemResponse:
    item = await inventory_service.update(session, await get_tenant_context(session, user_id), item_id, payload)
    return ItemResponse.from_entity(item)


@router.delete("/{item_id}/", status_code=status.HTTP_204_NO_CONTENT)
@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT, include_in_schema=False)
async def delete_item(
    item_id: str,
    user_id: int = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db_session),
) -> Response:
    await inventory_service.delete(session, await get_tenant_context(session, user_id), item_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
