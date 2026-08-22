"""Async PostgreSQL session management with explicit readiness checks."""

from __future__ import annotations

from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from functools import lru_cache

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool
from sqlalchemy.sql import text

from app.config.settings import Settings, get_settings


class DatabaseUnavailableError(RuntimeError):
    """Raised when a protected operation is attempted without a configured database."""


@lru_cache
def get_engine() -> AsyncEngine | None:
    settings = get_settings()
    database_url = settings.async_database_url
    if database_url is None:
        return None
    return create_async_engine(
        database_url,
        pool_pre_ping=True,
        pool_recycle=300,
        pool_size=5,
        max_overflow=10,
        pool_timeout=30,
        connect_args={
            "command_timeout": 30,
            "statement_cache_size": 0,  # Required for Supabase pooler
        },
    )


@lru_cache
def get_session_factory() -> async_sessionmaker[AsyncSession] | None:
    engine = get_engine()
    if engine is None:
        return None
    return async_sessionmaker(engine, expire_on_commit=False, autoflush=False)


async def get_db_session() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI dependency for routes that require PostgreSQL."""

    session_factory = get_session_factory()
    if session_factory is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database is not configured.",
        )
    async with session_factory() as session:
        yield session


@asynccontextmanager
async def get_agent_db_session() -> AsyncGenerator[AsyncSession, None]:
    """Create an event-loop-local database session for an AgentServer job.

    LiveKit starts each dispatched job in its own asyncio event loop. asyncpg
    connections from the API's cached pool are bound to their original loop,
    so sharing that pool makes a job crash before its agent session starts.
    NullPool deliberately creates no reusable cross-loop connections.
    """

    database_url = get_settings().require_database()
    engine = create_async_engine(
        database_url,
        poolclass=NullPool,
        pool_reset_on_return=None,
        connect_args={"command_timeout": 30, "statement_cache_size": 0},
    )
    factory = async_sessionmaker(engine, expire_on_commit=False, autoflush=False)
    session = factory()
    try:
        yield session
    finally:
        try:
            await session.close()
        except Exception:
            pass
        try:
            await engine.dispose()
        except Exception:
            pass


async def database_is_ready(settings: Settings | None = None) -> bool:
    """Perform a small connection check without exposing connection details."""

    _ = settings
    session_factory = get_session_factory()
    if session_factory is None:
        return False
    try:
        async with session_factory() as session:
            await session.execute(text("SELECT 1"))
        return True
    except Exception:
        return False
