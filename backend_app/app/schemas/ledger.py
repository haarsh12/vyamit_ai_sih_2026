"""Validated contracts for customer udhaar ledger records and proposals."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


class LedgerAdjustmentRequest(BaseModel):
    """A proposed change; it cannot write a ledger entry by itself."""

    entry_type: Literal["udhaar", "payment"]
    amount: Decimal = Field(gt=0, max_digits=14, decimal_places=2)
    note: str | None = Field(default=None, max_length=240)
    source: Literal["app", "voice", "token_saver"] = "app"

    @field_validator("note")
    @classmethod
    def normalise_note(cls, value: str | None) -> str | None:
        clean = " ".join(value.split()) if value else None
        return clean or None


class LedgerDraftConfirmation(BaseModel):
    expected_version: int = Field(ge=1)


class LedgerDraftResponse(BaseModel):
    id: UUID
    version: int
    confirmation_status: str
    expires_at: datetime
    customer_id: int
    customer_name: str
    entry_type: Literal["udhaar", "payment"]
    amount: float
    current_balance: float
    proposed_balance: float
    note: str | None = None


class CustomerLedgerEntryResponse(BaseModel):
    id: int
    bill_id: int | None
    entry_type: Literal["udhaar", "payment"]
    amount: float
    balance_after: float
    source: str
    note: str | None
    occurred_at: datetime
    created_at: datetime


class CustomerLedgerResponse(BaseModel):
    success: bool
    customer_id: int
    customer_name: str
    current_balance: float
    entries: list[CustomerLedgerEntryResponse]
    total: int
    limit: int
    offset: int
