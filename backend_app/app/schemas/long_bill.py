"""Validated contracts for the manual-stop Long Bill dictation flow."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, field_validator

from app.schemas.workflows import BillDraftResponse


class LongBillTranscriptRequest(BaseModel):
    """A device-recognized transcript; raw microphone audio is never uploaded."""

    transcript: str = Field(min_length=2, max_length=2_000)

    @field_validator("transcript")
    @classmethod
    def normalise_transcript(cls, value: str) -> str:
        return " ".join(value.split())


class LongBillTranscriptResponse(BaseModel):
    """A reviewable, server-created bill draft or a safe no-match result."""

    status: Literal["draft", "needs_review"]
    message: str = Field(max_length=300)
    draft: BillDraftResponse | None = None
    resolved_item_count: int = Field(ge=0, le=30)
    unresolved_segments: list[str] = Field(default_factory=list, max_length=30)
