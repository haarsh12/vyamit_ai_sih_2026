"""Authenticated LiveKit connection API. It replaces legacy voice WebSockets."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.config.settings import Settings, get_settings
from app.core.security import get_current_user_id
from app.db.session import get_db_session
from app.domain.voice_sessions import voice_session_service
from app.repositories.tenants import get_tenant_context
from app.schemas.voice import VoiceConnectionDetails, VoiceTokenRequest


router = APIRouter(prefix="/voice", tags=["realtime voice"])


@router.post("/token", response_model=VoiceConnectionDetails, status_code=status.HTTP_201_CREATED)
async def create_connection(
    payload: VoiceTokenRequest,
    user_id: int = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db_session),
    settings: Settings = Depends(get_settings),
) -> VoiceConnectionDetails:
    try:
        return await voice_session_service.issue_connection(
            session, await get_tenant_context(session, user_id), payload, settings
        )
    except RuntimeError as error:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Voice service is not configured") from error
