"""Trusted tenant context passed from authentication/session binding to repositories."""

from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID


@dataclass(frozen=True, slots=True)
class TenantContext:
    owner_id: int
    shop_category: str
    session_id: UUID | None = None
    room_name: str | None = None


class TenantBoundaryError(PermissionError):
    """Raised when a requested record is outside the authenticated tenant boundary."""
