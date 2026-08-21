"""API composition and probe tests that do not require a live database."""

from unittest.mock import AsyncMock

import httpx

import app.api.v1.health as health
import app.main as main
from app.config.settings import Settings


async def test_api_starts_and_serves_liveness_without_database(monkeypatch) -> None:
    """A failed database should degrade readiness, never prevent liveness."""

    monkeypatch.setattr(main, "database_is_ready", AsyncMock(return_value=False))
    async with main.lifespan(main.app):
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=main.app),
            base_url="http://testserver",
        ) as client:
            response = await client.get("/health/live")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"


async def test_readiness_reports_degraded_when_database_is_unavailable(monkeypatch) -> None:
    monkeypatch.setattr(health, "database_is_ready", AsyncMock(return_value=False))

    response = await health.readiness(Settings())

    assert response.status_code == 503
    assert b'"database":false' in response.body


async def test_readiness_reports_ok_when_database_is_reachable(monkeypatch) -> None:
    monkeypatch.setattr(health, "database_is_ready", AsyncMock(return_value=True))

    response = await health.readiness(Settings())

    assert response.status_code == 200
    assert b'"database":true' in response.body


def test_only_intended_public_routes_are_composed() -> None:
    def route_paths(routes: list[object]) -> set[str]:
        paths: set[str] = set()
        for route in routes:
            path = getattr(route, "path", None)
            if isinstance(path, str):
                paths.add(path)
                continue
            # FastAPI 0.115+ defers included router expansion. Inspecting the
            # original router keeps this contract test version-independent.
            included = getattr(route, "original_router", None)
            if included is not None:
                paths.update(route_paths(list(included.routes)))
        return paths

    paths = route_paths(list(main.app.routes))

    assert {"/", "/health", "/health/live", "/health/ready", "/voice/token"} <= paths
    assert "/voice/ws/stream" not in paths
