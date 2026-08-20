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


class BillDraftResponse(BaseModel):
    id: UUID
    kind: str
    version: int
    confirmation_status: str
    expires_at: datetime
    state: BillCreate
