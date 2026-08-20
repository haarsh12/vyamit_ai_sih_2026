"""LiveKit token issuance after authenticated tenant context has been resolved."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from livekit import api
from sqlalchemy.ext.asyncio import AsyncSession

from app.config.settings import Settings
from app.db.tenant import TenantContext
from app.repositories.voice_sessions import VoiceSessionRepository
from app.schemas.voice import VoiceConnectionDetails, VoiceTokenRequest


class VoiceSessionService:
    async def issue_connection(
        self, session: AsyncSession, tenant: TenantContext, request: VoiceTokenRequest, settings: Settings
    ) -> VoiceConnectionDetails:
        settings.require_livekit()
        expires_at = datetime.now(UTC) + timedelta(minutes=settings.livekit_token_minutes)
        record = await VoiceSessionRepository(session).create(tenant, expires_at=expires_at)
        # The API creates both the room and identity. Neither comes from mobile input.
        token = (
            api.AccessToken(
                settings.livekit_api_key.get_secret_value(),
                settings.livekit_api_secret.get_secret_value(),
            )
            .with_identity(record.participant_identity)
            .with_name((request.participant_name or "Vyamit user").strip() or "Vyamit user")
            .with_ttl(timedelta(minutes=settings.livekit_token_minutes))
            .with_grants(api.VideoGrants(
                room_join=True, room=record.room_name, can_publish=True, can_subscribe=True, can_publish_data=True,
            ))
            .with_room_config(api.RoomConfiguration(
                agents=[api.RoomAgentDispatch(agent_name=settings.livekit_agent_name)]
            ))
        )
        await session.commit()
        return VoiceConnectionDetails(
            server_url=settings.livekit_url, participant_token=token.to_jwt(), room_name=record.room_name,
            participant_identity=record.participant_identity, session_id=str(record.id), expires_at=expires_at.isoformat(),
        )


voice_session_service = VoiceSessionService()
