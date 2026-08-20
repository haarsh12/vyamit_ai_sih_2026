"""Server-controlled LiveKit connection contracts."""

from __future__ import annotations

from pydantic import BaseModel, Field


class VoiceTokenRequest(BaseModel):
    participant_name: str | None = Field(default=None, max_length=64)


class VoiceConnectionDetails(BaseModel):
    server_url: str
    participant_token: str
    room_name: str
    participant_identity: str
    session_id: str
    expires_at: str
