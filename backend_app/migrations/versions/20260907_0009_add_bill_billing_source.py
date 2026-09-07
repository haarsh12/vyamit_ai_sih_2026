"""Track whether a bill came from voice or Frequent Billing.

Revision ID: 20260907_0009
Revises: 20260824_0008
Create Date: 2026-09-07
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20260907_0009"
down_revision = "20260824_0008"
branch_labels = None
depends_on = None


def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    columns = {column["name"] for column in inspector.get_columns("bills")}
    if "billing_source" not in columns:
        op.add_column(
            "bills",
            sa.Column(
                "billing_source",
                sa.String(length=20),
                nullable=False,
                server_default="voice",
            ),
        )

    inspector = sa.inspect(op.get_bind())
    indexes = {index["name"] for index in inspector.get_indexes("bills")}
    if "ix_bills_billing_source" not in indexes:
        op.create_index("ix_bills_billing_source", "bills", ["billing_source"])


def downgrade() -> None:
    op.drop_index("ix_bills_billing_source", table_name="bills")
    op.drop_column("bills", "billing_source")
