"""Persist OTP verification failures to prevent unlimited code guessing.

Revision ID: 20260819_0002
Revises: 20260818_0001
Create Date: 2026-08-19
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "20260819_0002"
down_revision = "20260818_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # The first revision uses the initial ORM metadata to create an empty
    # deployment.  Guard these additions so both a fresh database and an
    # already-initialised early deployment can advance safely.
    inspector = sa.inspect(op.get_bind())
    columns = {column["name"] for column in inspector.get_columns("otps")}
    if "failed_attempts" not in columns:
        op.add_column("otps", sa.Column("failed_attempts", sa.Integer(), nullable=False, server_default="0"))
        op.alter_column("otps", "failed_attempts", server_default=None)
    if "locked_until" not in columns:
        op.add_column("otps", sa.Column("locked_until", sa.DateTime(timezone=True), nullable=True))
    indexes = {index["name"] for index in inspector.get_indexes("otps")}
    if "ix_otps_locked_until" not in indexes:
        op.create_index("ix_otps_locked_until", "otps", ["locked_until"])


def downgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    columns = {column["name"] for column in inspector.get_columns("otps")}
    indexes = {index["name"] for index in inspector.get_indexes("otps")}
    if "ix_otps_locked_until" in indexes:
        op.drop_index("ix_otps_locked_until", table_name="otps")
    if "locked_until" in columns:
        op.drop_column("otps", "locked_until")
    if "failed_attempts" in columns:
        op.drop_column("otps", "failed_attempts")
