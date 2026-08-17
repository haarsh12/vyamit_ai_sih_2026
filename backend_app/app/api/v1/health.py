"""Unauthenticated liveness/readiness probes."""

from __future__ import annotations

from fastapi import APIRouter, Depends, status
from fastapi.responses import JSONResponse

from app.config.settings import Settings, get_settings
from app.db.session import database_is_ready


router = APIRouter(tags=["health"])


@router.get("/health/live")
async def liveness(settings: Settings = Depends(get_settings)) -> dict[str, str]:
    """Report that the API process is alive without revealing any configuration."""

    return {"status": "ok", "service": settings.app_name}


@router.get("/health/ready")
async def readiness(settings: Settings = Depends(get_settings)) -> JSONResponse:
    """Report database reachability; provider secrets are never inspected here."""

    database_ready = await database_is_ready(settings)
    payload: dict[str, object] = {"status": "ok" if database_ready else "degraded", "database": database_ready}
    return JSONResponse(
        content=payload,
        status_code=status.HTTP_200_OK if database_ready else status.HTTP_503_SERVICE_UNAVAILABLE,
    )
