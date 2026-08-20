"""Server-owned mapping from LiveKit rooms to authenticated tenant context."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import VoiceSession
from app.db.tenant import TenantContext


class VoiceSessionRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def create(self, tenant: TenantContext, *, expires_at: datetime) -> VoiceSession:
        nonce = uuid4().hex
        record = VoiceSession(
            owner_id=tenant.owner_id,
            shop_category=tenant.shop_category,
            room_name=f"vyamit-{nonce[:24]}",
            participant_identity=f"user-{tenant.owner_id}-{nonce}",
            expires_at=expires_at,
            status="issued",
        )
        self.session.add(record)
        await self.session.flush()
        return record

    async def expected_participant_identity(self, room_name: str) -> str | None:
        """Return only the short-lived identity bound to a still-valid room."""

        return await self.session.scalar(select(VoiceSession.participant_identity).where(
            VoiceSession.room_name == room_name,
            VoiceSession.expires_at > datetime.now(UTC),
            VoiceSession.status.in_(("issued", "active")),
        ))

    async def resolve_tenant(self, room_name: str, participant_identity: str) -> TenantContext | None:
        """Atomically validate both token-bound room and participant identity."""

        record = await self.session.scalar(select(VoiceSession).where(
            VoiceSession.room_name == room_name,
            VoiceSession.participant_identity == participant_identity,
            VoiceSession.expires_at > datetime.now(UTC),
            VoiceSession.status.in_(("issued", "active")),
        ).with_for_update())
        if record is None:
            return None
        record.status = "active"
        return TenantContext(
            owner_id=record.owner_id,
            shop_category=record.shop_category,
            session_id=record.id,
            room_name=record.room_name,
        )

    async def close(self, session_id: object) -> None:
        record = await self.session.get(VoiceSession, session_id)
        if record is not None and record.status != "closed":
            record.status = "closed"
            record.closed_at = datetime.now(UTC)
