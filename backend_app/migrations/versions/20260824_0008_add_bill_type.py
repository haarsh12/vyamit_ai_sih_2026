"""Add bill_type to distinguish printed vs virtual bills.

Revision ID: 20260824_0008
Revises: 20260824_0007
Create Date: 2026-08-24
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20260824_0008"
down_revision = "20260824_0007"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add bill_type column with default 'printed' for existing bills
    op.add_column(
        "bills",
        sa.Column(
            "bill_type",
            sa.String(length=20),
            nullable=False,
            server_default="printed"
        ),
    )
    
    # Create index for filtering by bill type
    op.create_index(
        "ix_bills_bill_type",
        "bills",
        ["bill_type"],
    )


def downgrade() -> None:
    op.drop_index("ix_bills_bill_type", table_name="bills")
    op.drop_column("bills", "bill_type")
