"""Category-scoped inventory API.

The active scope is always read from the authenticated user's profile.  A
client can choose a product group (``Item.category``), but can never send a
shop category to read, overwrite, or delete another inventory namespace.
"""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal
import json
import logging
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session, select

from core.security import get_current_user
from core.shop_categories import stored_category
from db.database import get_session
from db.models import GstConfiguration, Item, User
from db.schemas import ItemCreate, ItemResponse, ItemUpdate
from gst.calculation import percent_to_basis_points


logger = logging.getLogger(__name__)
router = APIRouter()


def _active_inventory_scope(session: Session, user_id: int) -> str:
    """Return the profile-selected namespace for this authenticated user."""
    user = session.get(User, user_id)
    if user is None or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is unavailable",
        )
    return stored_category(user.shop_category)


def _to_response(item: Item) -> ItemResponse:
    try:
        names = json.loads(item.names) if item.names else []
    except (TypeError, json.JSONDecodeError) as exc:
        logger.warning("Skipping malformed inventory names for item=%s", item.id)
        raise ValueError("Stored inventory item has malformed names") from exc
    if not isinstance(names, list) or not names:
        raise ValueError("Stored inventory item has no names")
    return ItemResponse(
        id=item.master_id,
        names=names,
        price=item.price,
        unit=item.unit,
        category=item.category,
        gst_rate=item.gst_rate_bps / 100,
        hsn_code=item.hsn_code,
        tax_category=item.tax_category,
        owner_id=item.owner_id,
        master_id=item.master_id,
        shop_category=item.shop_category,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


def _find_item_in_scope(
    session: Session, user_id: int, inventory_scope: str, master_id: str
) -> Item | None:
    return session.exec(
        select(Item).where(
            Item.master_id == master_id,
            Item.owner_id == user_id,
            Item.shop_category == inventory_scope,
        )
    ).first()


def _validate_item_gst_access(
    session: Session, user_id: int, payload: ItemCreate | ItemUpdate
) -> int:
    """Only GST-configured shops can persist non-zero item tax metadata."""
    rate_bps = percent_to_basis_points(Decimal(str(payload.gst_rate)))
    configuration = session.exec(
        select(GstConfiguration).where(
            GstConfiguration.owner_id == user_id,
            GstConfiguration.is_enabled.is_(True),
        )
    ).first()
    if configuration is None:
        if rate_bps or payload.hsn_code or payload.tax_category:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Enable and validate GST Billing before adding GST details to inventory",
            )
        return 0
    try:
        allowed_rates = set(json.loads(configuration.allowed_gst_rates_json))
    except (TypeError, json.JSONDecodeError):
        allowed_rates = {0}
    if rate_bps not in allowed_rates:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="The selected GST rate is not enabled in the shop GST configuration",
        )
    return rate_bps


def _apply_item_changes(
    target: Item, payload: ItemCreate | ItemUpdate, gst_rate_bps: int
) -> None:
    """Apply only client-controlled product fields; scope and owner stay server-owned."""
    target.names = json.dumps(payload.names, ensure_ascii=False)
    target.price = payload.price
    target.unit = payload.unit
    target.category = payload.category
    target.gst_rate_bps = gst_rate_bps
    target.hsn_code = payload.hsn_code
    target.tax_category = payload.tax_category
    target.updated_at = datetime.utcnow()


@router.post("/", response_model=ItemResponse)
def create_item(
    item: ItemCreate,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Create or update an item inside the user's currently selected category."""
    try:
        inventory_scope = _active_inventory_scope(session, user_id)
        gst_rate_bps = _validate_item_gst_access(session, user_id, item)
        existing_item = _find_item_in_scope(session, user_id, inventory_scope, item.id)

        if existing_item:
            _apply_item_changes(existing_item, item, gst_rate_bps)
            session.add(existing_item)
            session.commit()
            session.refresh(existing_item)
            logger.info("Updated item=%s user=%s scope=%s", item.id, user_id, inventory_scope)
            return _to_response(existing_item)

        new_item = Item(
            master_id=item.id,
            names=json.dumps(item.names, ensure_ascii=False),
            category=item.category,
            shop_category=inventory_scope,
            price=item.price,
            unit=item.unit,
            owner_id=user_id,
            gst_rate_bps=gst_rate_bps,
            hsn_code=item.hsn_code,
            tax_category=item.tax_category,
        )
        session.add(new_item)
        session.commit()
        session.refresh(new_item)

        logger.info("Created item=%s user=%s scope=%s", item.id, user_id, inventory_scope)
        return _to_response(new_item)
    except HTTPException:
        raise
    except Exception:
        session.rollback()
        logger.exception("Failed to create/update item user=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to save item",
        )


@router.get("/", response_model=List[ItemResponse])
def get_items(
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """List only the inventory owned by the active profile category."""
    inventory_scope = _active_inventory_scope(session, user_id)
    try:
        items = session.exec(
            select(Item).where(
                Item.owner_id == user_id,
                Item.shop_category == inventory_scope,
            )
        ).all()
        response_items: List[ItemResponse] = []
        for stored_item in items:
            try:
                response_items.append(_to_response(stored_item))
            except ValueError:
                continue
        logger.info(
            "Fetched items=%s user=%s scope=%s",
            len(response_items),
            user_id,
            inventory_scope,
        )
        return response_items
    except HTTPException:
        raise
    except Exception:
        logger.exception("Failed to fetch inventory user=%s scope=%s", user_id, inventory_scope)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch inventory",
        )


@router.put("/{item_id}", response_model=ItemResponse)
@router.put("/{item_id}/", response_model=ItemResponse, include_in_schema=False)
def update_item(
    item_id: str,
    item: ItemUpdate,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Update an item only when it belongs to the active category namespace."""
    try:
        inventory_scope = _active_inventory_scope(session, user_id)
        existing_item = _find_item_in_scope(session, user_id, inventory_scope, item_id)
        if not existing_item:
            # Do not disclose whether this id exists in a different category.
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")

        gst_rate_bps = _validate_item_gst_access(session, user_id, item)
        _apply_item_changes(existing_item, item, gst_rate_bps)
        session.add(existing_item)
        session.commit()
        session.refresh(existing_item)
        logger.info("Updated item=%s user=%s scope=%s", item_id, user_id, inventory_scope)
        return _to_response(existing_item)
    except HTTPException:
        raise
    except Exception:
        session.rollback()
        logger.exception("Failed to update item=%s user=%s", item_id, user_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update item",
        )


@router.delete("/{item_id}")
@router.delete("/{item_id}/", include_in_schema=False)
def delete_item(
    item_id: str,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Delete an item only from the currently selected category namespace."""
    try:
        inventory_scope = _active_inventory_scope(session, user_id)
        existing_item = _find_item_in_scope(session, user_id, inventory_scope, item_id)
        if not existing_item:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")

        session.delete(existing_item)
        session.commit()
        logger.info("Deleted item=%s user=%s scope=%s", item_id, user_id, inventory_scope)
        return {"success": True, "message": "Item deleted successfully"}
    except HTTPException:
        raise
    except Exception:
        session.rollback()
        logger.exception("Failed to delete item=%s user=%s", item_id, user_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete item",
        )


@router.post("/bulk-embed")
async def bulk_embed_items(
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Generate embeddings only for the inventory in the active category scope."""
    try:
        from pipeline.embedding_pipeline import embedding_pipeline

        inventory_scope = _active_inventory_scope(session, user_id)
        items = session.exec(
            select(Item).where(
                Item.owner_id == user_id,
                Item.shop_category == inventory_scope,
            )
        ).all()
        if not items:
            return {
                "success": True,
                "message": "No items to embed in this category",
                "scope": inventory_scope,
                "total": 0,
                "updated": 0,
            }

        texts: list[str] = []
        items_to_update: list[Item] = []
        for stored_item in items:
            try:
                names = json.loads(stored_item.names)
                if not isinstance(names, list) or not names:
                    continue
                # The item's own product metadata is embedded; retrieval is
                # still constrained by shop_category in SQL.
                texts.append(" ".join(map(str, names)) + f" {stored_item.category}")
                items_to_update.append(stored_item)
            except (TypeError, json.JSONDecodeError):
                logger.warning("Cannot embed malformed item=%s", stored_item.id)

        embeddings = embedding_pipeline.generate_embeddings_batch(texts)
        for stored_item, embedding in zip(items_to_update, embeddings):
            stored_item.embedding = embedding
            stored_item.updated_at = datetime.utcnow()
            session.add(stored_item)
        session.commit()

        logger.info(
            "Generated embeddings=%s user=%s scope=%s",
            len(items_to_update),
            user_id,
            inventory_scope,
        )
        return {
            "success": True,
            "message": f"Generated embeddings for {len(items_to_update)} items",
            "scope": inventory_scope,
            "total": len(items),
            "updated": len(items_to_update),
        }
    except HTTPException:
        raise
    except Exception:
        session.rollback()
        logger.exception("Bulk embedding failed user=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to generate embeddings",
        )
