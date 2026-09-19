"""Customer purchase-summary maintenance for bill creation."""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlmodel import Session, select

from db.models import Customer


def record_customer_purchase(
    session: Session,
    *,
    owner_id: int,
    phone_number: Optional[str],
    name: Optional[str],
    amount: float,
    purchased_at: datetime,
) -> None:
    """Upsert only the authenticated shop's aggregate customer record."""
    phone = (phone_number or "").strip()
    if not phone:
        return
    customer = session.exec(
        select(Customer).where(Customer.owner_id == owner_id, Customer.phone_number == phone)
    ).first()
    if customer is None:
        customer = Customer(
            owner_id=owner_id,
            phone_number=phone,
            name=(name or "").strip()[:100] or None,
            total_bills=1,
            total_spent=amount,
            last_purchase_date=purchased_at,
        )
    else:
        customer.total_bills += 1
        customer.total_spent += amount
        customer.last_purchase_date = purchased_at
        if name and name.strip():
            customer.name = name.strip()[:100]
    session.add(customer)
