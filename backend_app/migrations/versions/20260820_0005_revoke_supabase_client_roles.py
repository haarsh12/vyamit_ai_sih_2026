"""Block Supabase browser roles from reading application tables directly.

Revision ID: 20260820_0005
Revises: 20260820_0004
Create Date: 2026-08-20

The Flutter app uses FastAPI only. The API's server-only database role remains
responsible for tenant filtering; Supabase anon/authenticated roles have no
table or sequence privileges in this architecture.
"""

from __future__ import annotations

from alembic import op


revision = "20260820_0005"
down_revision = "20260820_0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        DO $$
        BEGIN
          IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
            EXECUTE 'REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM anon';
            EXECUTE 'REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM anon';
          END IF;
          IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
            EXECUTE 'REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM authenticated';
            EXECUTE 'REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM authenticated';
          END IF;
        END $$;
        """
    )


def downgrade() -> None:
    # Privileges are deployment policy. Do not guess permissive grants on rollback.
    pass
