"""
Analytics API - Business Insights and Bill Management
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session, select, func, and_
from typing import List, Dict, Any, Optional
from datetime import datetime, timedelta
import json
import logging
import re
from db.database import get_session
from core.shop_categories import stored_category
from db.models import Bill, SaleItem, Item, User, VerifiedCustomer
from db.schemas import BillCreate, VerifyCustomerBillRequest
from core.security import get_current_user
from pipeline.embedding_pipeline import EmbeddingServiceError, embedding_pipeline

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/bills", response_model=Dict[str, Any])
def create_bill(
    bill_data: BillCreate,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session)
):
    """Save a new bill and create sale items for analytics"""
    try:
        for item in bill_data.items:
            expected_line_total = round(item.quantity * item.price, 2)
            if abs(expected_line_total - item.total) > 0.01:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"total for '{item.name}' must equal quantity multiplied by price",
                )
        calculated_total = round(sum(item.total for item in bill_data.items), 2)
        if abs(calculated_total - bill_data.total_amount) > 0.01:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="total_amount must equal the sum of item totals",
            )
        logger.info("Creating bill for user=%s items=%s", user_id, len(bill_data.items))

        # Preserve category analytics for known inventory items instead of
        # assigning every sale to the catch-all General category.
        user = session.get(User, user_id)
        if user is None or not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Account is unavailable",
            )
        inventory_scope = stored_category(user.shop_category)
        category_by_name = {}
        for inventory_item in session.exec(
            select(Item).where(
                Item.owner_id == user_id,
                Item.shop_category == inventory_scope,
            )
        ).all():
            try:
                names = json.loads(inventory_item.names)
            except (TypeError, json.JSONDecodeError):
                names = [inventory_item.names]
            for name in names:
                category_by_name[str(name).strip().casefold()] = inventory_item.category or "General"
        
        # Create bill
        bill = Bill(
            owner_id=user_id,
            shop_category=inventory_scope,
            total_amount=calculated_total,
            total_items=len(bill_data.items),
            items_json=json.dumps([item.model_dump() for item in bill_data.items]),
            customer_phone=bill_data.customer_phone,
            customer_name=bill_data.customer_name,
            payment_method=bill_data.payment_method,
            bill_date=datetime.utcnow()
        )
        
        session.add(bill)
        session.flush()
        
        # Create sale items for analytics
        current_hour = datetime.utcnow().hour
        
        for item in bill_data.items:
            sale_item = SaleItem(
                owner_id=user_id,
                bill_id=bill.id,
                shop_category=inventory_scope,
                item_name=item.name,
                item_category=category_by_name.get(item.name.strip().casefold(), "General"),
                quantity=item.quantity,
                unit=item.unit,
                price_per_unit=item.price,
                total_price=item.total,
                sale_date=datetime.utcnow(),
                hour_of_day=current_hour
            )
            session.add(sale_item)

        session.commit()
        session.refresh(bill)
        
        logger.info(f"Bill {bill.id} created successfully")
        
        return {
            "success": True,
            "bill_id": bill.id,
            "message": "Bill saved successfully"
        }
        
    except HTTPException:
        session.rollback()
        raise
    except Exception as e:
        session.rollback()
        logger.error(f"Failed to create bill: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to save bill"
        )


def _normalise_customer_name(name: str) -> str:
    """Produce a deterministic, human-name key without changing display text."""
    return " ".join(name.split()).casefold()


def _serialise_bill(bill: Bill) -> Dict[str, Any]:
    """Keep ordinary history and verified-customer history on one wire shape."""
    return {
        "id": bill.id,
        "total_amount": bill.total_amount,
        "total_items": bill.total_items,
        "items": json.loads(bill.items_json),
        "customer_phone": bill.customer_phone,
        "customer_name": bill.customer_name,
        "payment_method": bill.payment_method,
        "bill_date": bill.bill_date.isoformat(),
        "created_at": bill.created_at.isoformat(),
    }


@router.post("/verified-customers/verify-bill", response_model=Dict[str, Any])
def verify_customer_for_bill(
    request: VerifyCustomerBillRequest,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Verify the printed bill's spoken name and link the immutable bill.

    This route is intentionally separate from bill creation: the client calls
    it only after the merchant accepts the post-print confirmation dialog.
    """
    bill = session.get(Bill, request.bill_id)
    if bill is None or bill.owner_id != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bill not found")

    display_name = " ".join((bill.customer_name or "").split())[:100]
    normalized_name = _normalise_customer_name(display_name)
    if not normalized_name or normalized_name in {"walk-in", "walk in", "walkin"}:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="A spoken customer name is required before it can be verified",
        )
    if not re.fullmatch(r"[A-Za-z][A-Za-z .'-]*", display_name):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Customer names may contain only Latin letters, spaces, apostrophes, hyphens, and periods",
        )

    try:
        customer = session.exec(
            select(VerifiedCustomer).where(
                VerifiedCustomer.owner_id == user_id,
                VerifiedCustomer.name_normalized == normalized_name,
            )
        ).first()
        created = customer is None
        if customer is None:
            # The name is the stored document. Query embeddings are generated
            # on each voice query and compared against this 768D vector.
            customer = VerifiedCustomer(
                owner_id=user_id,
                name=display_name,
                name_normalized=normalized_name,
                embedding=embedding_pipeline.generate_document_embedding(
                    f"Verified customer name: {display_name}"
                ),
            )
            session.add(customer)
            session.flush()

        bill.verified_customer_id = customer.id
        session.add(bill)
        session.commit()
        session.refresh(customer)
        return {
            "success": True,
            "created": created,
            "customer": {
                "id": customer.id,
                "name": customer.name,
                "verified_at": customer.verified_at.isoformat(),
            },
            "message": f"{customer.name} is in your verified customer list",
        }
    except EmbeddingServiceError as exc:
        session.rollback()
        logger.warning("Could not embed verified customer user=%s: %s", user_id, exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Customer verification is temporarily unavailable. Please try again.",
        ) from exc
    except HTTPException:
        session.rollback()
        raise
    except Exception as exc:
        session.rollback()
        logger.exception("Failed to verify customer for bill user=%s bill=%s", user_id, request.bill_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to verify this customer",
        ) from exc


@router.get("/verified-customers")
def get_verified_customers(
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Return the merchant's verified directory in alphabetical name order."""
    try:
        statement = (
            select(
                VerifiedCustomer,
                func.count(Bill.id).label("bill_count"),
                func.coalesce(func.sum(Bill.total_amount), 0).label("total_spent"),
                func.max(Bill.bill_date).label("last_purchase_date"),
            )
            .outerjoin(Bill, Bill.verified_customer_id == VerifiedCustomer.id)
            .where(VerifiedCustomer.owner_id == user_id)
            .group_by(VerifiedCustomer.id)
            .order_by(VerifiedCustomer.name_normalized.asc())
        )
        rows = session.exec(statement).all()
        customers = []
        for customer, bill_count, total_spent, last_purchase_date in rows:
            customers.append(
                {
                    "id": customer.id,
                    "name": customer.name,
                    "bill_count": int(bill_count or 0),
                    "total_spent": float(total_spent or 0),
                    "last_purchase_date": (
                        last_purchase_date.isoformat() if last_purchase_date else None
                    ),
                    "verified_at": customer.verified_at.isoformat(),
                }
            )
        return {"success": True, "customers": customers, "total": len(customers)}
    except Exception as exc:
        logger.exception("Failed to fetch verified customers user=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch verified customers",
        ) from exc


@router.get("/verified-customers/{customer_id}/bills")
def get_verified_customer_bills(
    customer_id: int,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Return one verified customer's linked bills, newest first."""
    customer = session.get(VerifiedCustomer, customer_id)
    if customer is None or customer.owner_id != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Verified customer not found")
    bills = session.exec(
        select(Bill)
        .where(
            Bill.owner_id == user_id,
            Bill.verified_customer_id == customer.id,
        )
        .order_by(Bill.bill_date.desc())
    ).all()
    return {
        "success": True,
        "customer": {"id": customer.id, "name": customer.name},
        "bills": [_serialise_bill(bill) for bill in bills],
        "total": len(bills),
    }


@router.get("/bills")
def get_bills(
    limit: int = 50,
    offset: int = 0,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session)
):
    """Get bill history"""
    try:
        statement = (
            select(Bill)
            .where(Bill.owner_id == user_id)
            .order_by(Bill.bill_date.desc())
            .offset(offset)
            .limit(limit)
        )
        
        bills = session.exec(statement).all()
        
        return {
            "success": True,
            "bills": [_serialise_bill(bill) for bill in bills],
            "total": len(bills),
            "limit": limit,
            "offset": offset
        }
        
    except Exception as e:
        logger.error(f"Failed to fetch bills: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch bills"
        )


@router.get("/dashboard")
def get_dashboard(
    days: int = 30,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session)
):
    """Get comprehensive dashboard analytics"""
    try:
        end_date = datetime.utcnow()
        start_date = end_date - timedelta(days=days)
        
        # Total revenue
        revenue_stmt = select(func.sum(Bill.total_amount)).where(
            and_(
                Bill.owner_id == user_id,
                Bill.bill_date >= start_date
            )
        )
        total_revenue = session.exec(revenue_stmt).first() or 0.0
        
        # Total bills
        bills_stmt = select(func.count(Bill.id)).where(
            and_(
                Bill.owner_id == user_id,
                Bill.bill_date >= start_date
            )
        )
        total_bills = session.exec(bills_stmt).first() or 0
        
        # Average bill value
        avg_bill_value = total_revenue / total_bills if total_bills > 0 else 0.0
        
        # Total inventory items
        inventory_stmt = select(func.count(Item.id)).where(Item.owner_id == user_id)
        total_inventory = session.exec(inventory_stmt).first() or 0
        
        # Top selling items
        top_items_stmt = (
            select(
                SaleItem.item_name,
                SaleItem.unit,
                func.sum(SaleItem.quantity).label('total_quantity'),
                func.sum(SaleItem.total_price).label('total_revenue'),
                func.count(SaleItem.id).label('times_sold')
            )
            .where(
                and_(
                    SaleItem.owner_id == user_id,
                    SaleItem.sale_date >= start_date
                )
            )
            .group_by(SaleItem.item_name, SaleItem.unit)
            .order_by(func.sum(SaleItem.total_price).desc())
            .limit(10)
        )
        
        top_items = session.exec(top_items_stmt).all()
        
        # Category breakdown
        category_stmt = (
            select(
                SaleItem.item_category,
                func.sum(SaleItem.total_price).label('total_sales'),
                func.sum(SaleItem.quantity).label('total_quantity')
            )
            .where(
                and_(
                    SaleItem.owner_id == user_id,
                    SaleItem.sale_date >= start_date
                )
            )
            .group_by(SaleItem.item_category)
            .order_by(func.sum(SaleItem.total_price).desc())
        )
        
        categories = session.exec(category_stmt).all()
        
        # Peak hours
        peak_hours_stmt = (
            select(
                SaleItem.hour_of_day,
                func.count(SaleItem.id).label('sales_count'),
                func.sum(SaleItem.total_price).label('total_sales')
            )
            .where(
                and_(
                    SaleItem.owner_id == user_id,
                    SaleItem.sale_date >= start_date
                )
            )
            .group_by(SaleItem.hour_of_day)
            .order_by(SaleItem.hour_of_day)
        )
        
        peak_hours = session.exec(peak_hours_stmt).all()
        
        # Peak day of week
        day_stmt = (
            select(
                func.extract('dow', Bill.bill_date).label('day_of_week'),
                func.count(Bill.id).label('bill_count'),
                func.sum(Bill.total_amount).label('total_sales')
            )
            .where(
                and_(
                    Bill.owner_id == user_id,
                    Bill.bill_date >= start_date
                )
            )
            .group_by('day_of_week')
            .order_by(func.sum(Bill.total_amount).desc())
        )
        
        days_data = session.exec(day_stmt).all()
        peak_day = days_data[0] if days_data else None
        
        day_names = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
        
        return {
            "success": True,
            "period_days": days,
            "summary": {
                "total_revenue": round(float(total_revenue), 2),
                "total_bills": total_bills,
                "average_bill_value": round(avg_bill_value, 2),
                "total_inventory_items": total_inventory
            },
            "top_selling_items": [
                {
                    "name": item[0],
                    "unit": item[1],
                    "quantity": float(item[2]),
                    "revenue": float(item[3]),
                    "times_sold": item[4]
                }
                for item in top_items
            ],
            "category_breakdown": [
                {
                    "category": cat[0],
                    "total_sales": float(cat[1]),
                    "quantity": float(cat[2]),
                    "percentage": round((float(cat[1]) / total_revenue * 100) if total_revenue > 0 else 0, 1)
                }
                for cat in categories
            ],
            "peak_hours": [
                {
                    "hour": int(hour[0]),
                    "sales_count": hour[1],
                    "total_sales": float(hour[2])
                }
                for hour in peak_hours
            ],
            "peak_day": {
                "day": day_names[int(peak_day[0])] if peak_day else "N/A",
                "bill_count": peak_day[1] if peak_day else 0,
                "total_sales": float(peak_day[2]) if peak_day else 0.0
            } if peak_day else None
        }
        
    except Exception as e:
        logger.error(f"Dashboard error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch dashboard data"
        )


@router.get("/overview")
def get_overview(
    days: int = 7,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session)
):
    """Quick overview for home screen"""
    try:
        end_date = datetime.utcnow()
        start_date = end_date - timedelta(days=days)
        
        # Revenue
        revenue = session.exec(
            select(func.sum(Bill.total_amount)).where(
                and_(Bill.owner_id == user_id, Bill.bill_date >= start_date)
            )
        ).first() or 0.0
        
        # Bill count
        bill_count = session.exec(
            select(func.count(Bill.id)).where(
                and_(Bill.owner_id == user_id, Bill.bill_date >= start_date)
            )
        ).first() or 0
        
        return {
            "success": True,
            "period_days": days,
            "total_revenue": round(float(revenue), 2),
            "total_bills": bill_count,
            "average_bill": round(float(revenue) / bill_count if bill_count > 0 else 0, 2)
        }
        
    except Exception as e:
        logger.error(f"Overview error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch overview"
        )
