"""Create the Vyamit Supabase schema and pgvector extension.

Revision ID: 20260818_0001
Revises:
Create Date: 2026-08-18

The new project starts with an empty Supabase database.  This revision is the
only schema creation path; application startup never calls create_all.
"""

from __future__ import annotations

from alembic import op

from app.db import models  # noqa: F401 - register all entities
from app.db.base import Base


revision = "20260818_0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")
    Base.metadata.create_all(bind=op.get_bind(), checkfirst=True)


def downgrade() -> None:
    # Intentional destructive rollback of this initial empty-project schema.
    Base.metadata.drop_all(bind=op.get_bind(), checkfirst=True)
