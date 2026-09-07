"""Contracts for server-owned, explicitly confirmed workflow drafts."""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field

from app.schemas.analytics import BillCreate


class BillDraftReplace(BillCreate):
    expected_version: int = Field(ge=1)


class DraftConfirmation(BaseModel):
    expected_version: int = Field(ge=1)
    verified_customer_id: int | None = Field(
        default=None,
        description="Optional: Link this bill to a verified customer"
    )


class CustomerVerificationSuggestion(BaseModel):
    """Suggested customer verification after bill draft creation."""
    should_verify: bool
    customer_name: str | None = None
    existing_customer_id: int | None = None
    existing_customer_name: str | None = None
    is_duplicate: bool = False
    message: str


class BillDraftResponse(BaseModel):
    id: UUID
    kind: str
    version: int
    confirmation_status: str
    expires_at: datetime
    state: BillCreate
    customer_verification_suggestion: CustomerVerificationSuggestion | None = None
