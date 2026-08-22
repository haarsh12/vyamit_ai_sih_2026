"""Opt-in checks for the actual Supabase project.

Run with RUN_SUPABASE_INTEGRATION=true. These tests only read catalog metadata
and `SELECT 1`; they never create, mutate, or delete business data.
"""

from __future__ import annotations

import os

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from app.config.settings import Settings


def _integration_url() -> str:
    if os.getenv("RUN_SUPABASE_INTEGRATION", "").lower() != "true":
        pytest.skip("Set RUN_SUPABASE_INTEGRATION=true to test the configured Supabase project.")
    return Settings().require_database()


@pytest.mark.integration
@pytest.mark.asyncio
async def test_supabase_connection_is_encrypted_and_reachable() -> None:
    url = _integration_url()
    # `ssl=require` is translated from Supabase's libpq URL to asyncpg's URL
    # by Settings. Supavisor does not expose the client TLS leg in pg_stat_ssl.
    assert "ssl=require" in url
    engine = create_async_engine(
        url,
        pool_pre_ping=True,
        connect_args={"statement_cache_size": 0}  # Required for Supabase pooler
    )
    try:
        async with engine.connect() as connection:
            assert await connection.scalar(text("SELECT 1")) == 1
    finally:
        await engine.dispose()


@pytest.mark.integration
@pytest.mark.asyncio
async def test_supabase_schema_and_vector_security_after_migration() -> None:
    engine = create_async_engine(
        _integration_url(),
        pool_pre_ping=True,
        connect_args={"statement_cache_size": 0}  # Required for Supabase pooler
    )
    expected_tables = {
        "users", "otps", "items", "bills", "sale_items", "customers",
        "gst_configurations", "gst_invoice_sequences", "gst_invoices",
        "doctor_patients", "doctor_prescriptions", "voice_sessions",
        "workflow_drafts", "embedding_jobs", "agent_memory", "audit_events",
        "idempotency_keys",
    }
    try:
        async with engine.connect() as connection:
            extension = await connection.scalar(
                text("SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'vector')")
            )
            assert extension is True

            revision = await connection.scalar(text("SELECT version_num FROM alembic_version"))
            assert revision == "20260821_0006"

            tables = set((await connection.execute(text("""
                SELECT tablename FROM pg_tables
                WHERE schemaname = 'public'
            """))).scalars())
            assert expected_tables <= tables

            vector_type = await connection.scalar(text("""
                SELECT format_type(attribute.atttypid, attribute.atttypmod)
                FROM pg_attribute AS attribute
                JOIN pg_class AS relation ON relation.oid = attribute.attrelid
                JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
                WHERE namespace.nspname = 'public'
                  AND relation.relname = 'items'
                  AND attribute.attname = 'embedding'
                  AND NOT attribute.attisdropped
            """))
            assert vector_type == "vector(768)"

            hnsw_index = await connection.scalar(text("""
                SELECT EXISTS (
                    SELECT 1 FROM pg_indexes
                    WHERE schemaname = 'public'
                      AND indexname = 'ix_items_embedding_hnsw'
                      AND indexdef ILIKE '%USING hnsw%'
                )
            """))
            assert hnsw_index is True

            browser_can_read = await connection.scalar(text("""
                SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon')
                    THEN has_table_privilege('anon', 'public.items', 'SELECT')
                    ELSE false
                END
            """))
            assert browser_can_read is False

            customer_key = await connection.scalar(text("""
                SELECT EXISTS (
                    SELECT 1
                    FROM pg_constraint
                    WHERE conrelid = 'public.customers'::regclass
                      AND contype = 'u'
                      AND pg_get_constraintdef(oid) LIKE '%(owner_id, shop_category, phone_number)%'
                )
            """))
            assert customer_key is True
    finally:
        await engine.dispose()
