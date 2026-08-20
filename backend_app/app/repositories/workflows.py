"""Persistence operations for category-scoped expiring drafts."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import WorkflowDraft
from app.db.tenant import TenantContext


class WorkflowDraftRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get(self, tenant: TenantContext, draft_id: UUID, *, lock: bool = False) -> WorkflowDraft | None:
        statement = select(WorkflowDraft).where(
            WorkflowDraft.id == draft_id,
            WorkflowDraft.owner_id == tenant.owner_id,
            WorkflowDraft.shop_category == tenant.shop_category,
            WorkflowDraft.expires_at > datetime.now(UTC),
        )
        if lock:
            statement = statement.with_for_update()
        return await self.session.scalar(statement)
