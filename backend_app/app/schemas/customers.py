"""Pydantic schemas for verified customer operations."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class CustomerVerificationSuggestionResponse(BaseModel):
    """The safe confirmation message for a post-bill customer name."""
    should_verify: bool
    customer_name: str | None = None
    existing_customer_id: int | None = None
    existing_customer_name: str | None = None
    is_duplicate: bool = False
    message: str


class CustomerVerifyRequest(BaseModel):
    """Request to verify/add a customer to the verified list."""
    customer_name: str = Field(min_length=2, max_length=120)
    phone_number: str | None = Field(default=None, max_length=20)
    merge_with_existing_id: int | None = Field(default=None, ge=1, description="Optional: use an existing verified customer ID")
    link_bill_id: int | None = Field(
        default=None,
        ge=1,
        description="Optional: saved bill to add to this verified customer's history",
    )


class CustomerResponse(BaseModel):
    """Single verified customer response."""
    id: int
    name: str
    phone_number: str | None
    total_bills: int
    total_spent: float
    last_purchase_date: datetime | None
    created_at: datetime


class CustomerDetailResponse(BaseModel):
    """Detailed customer information with additional stats."""
    id: int
    name: str
    phone_number: str | None
    total_bills: int
    total_spent: float
    last_purchase_date: datetime | None
    created_at: datetime
    updated_at: datetime
    bill_count: int


class CustomerListResponse(BaseModel):
    """Paginated list of verified customers."""
    success: bool
    customers: list[CustomerResponse]
    total: int
    limit: int
    offset: int
    order_by: str


class BillSummary(BaseModel):
    """Summary of a single bill for customer history."""
    id: int
    total_amount: float
    total_items: int
    items: list[dict]
    payment_method: str
    bill_type: str
    billing_source: str
    bill_date: datetime
    created_at: datetime


class CustomerBillHistoryResponse(BaseModel):
    """Customer bill history with pagination."""
    success: bool
    customer: dict
    bills: list[BillSummary]
    total_bills: int
    limit: int
    offset: int
