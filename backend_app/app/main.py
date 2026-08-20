"""FastAPI composition root. Database schema changes run only through Alembic."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from contextlib import asynccontextmanager
from time import perf_counter
from uuid import uuid4

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import router as v1_router
from app.config.settings import get_settings
from app.core.logging import configure_logging
from app.db.session import database_is_ready


configure_logging()
settings = get_settings()


@asynccontextmanager
async def lifespan(_: FastAPI):
    """Avoid side-effectful schema creation at startup; migrations are explicit."""

    settings.require_api_runtime_security()
    await database_is_ready(settings)
    yield


app = FastAPI(
    title=settings.app_name,
    version="0.1.0",
    lifespan=lifespan,
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Idempotency-Key", "X-Request-Id"],
)


@app.middleware("http")
async def request_correlation(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    request_id = request.headers.get("X-Request-Id", uuid4().hex)
    started_at = perf_counter()
    response = await call_next(request)
    response.headers["X-Request-Id"] = request_id
    response.headers["Server-Timing"] = f"app;dur={(perf_counter() - started_at) * 1000:.1f}"
    return response


app.include_router(v1_router)


# Keep the existing deployment health contract while callers migrate to /health/live.
@app.get("/health", tags=["health"])
async def legacy_health() -> dict[str, object]:
    return {"status": "ok", "database_configured": settings.async_database_url is not None}


@app.get("/", tags=["health"])
async def root() -> dict[str, str]:
    return {"status": "active", "system": settings.app_name, "version": "0.1.0"}
