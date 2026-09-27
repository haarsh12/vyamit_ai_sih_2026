"""Public contracts for the text-only Token Saver WebSocket mode."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

from app.schemas.workflows import BillDraftResponse
from app.schemas.ledger import LedgerDraftResponse


class TokenSaverTicketResponse(BaseModel):
    """A short-lived credential used only for opening one WebSocket."""

    ticket: str = Field(min_length=20)
    expires_at: datetime


class TokenSaverProcessResponse(BaseModel):
    """The validated result of one final on-device speech transcript."""

    type: Literal["BILL", "QUERY", "LEDGER", "ERROR"]
    message: str = Field(min_length=1, max_length=300)
    draft: BillDraftResponse | None = None
    ledger_draft: LedgerDraftResponse | None = None
    unresolved_items: list[str] = Field(default_factory=list, max_length=20)
