"""Use India local hours for peak-sales analytics.

Revision ID: 20260927_0010
Revises: 20260927_0009
Create Date: 2026-09-27
"""

from __future__ import annotations

from alembic import op


revision = "20260927_0010"
down_revision = "20260927_0009"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Timestamps are deliberately retained in UTC.  Only the denormalised
    # grouping column is corrected so the dashboard shows local shop hours.
    op.execute(
        """
        UPDATE sale_items
        SET hour_of_day = EXTRACT(HOUR FROM sale_date AT TIME ZONE 'Asia/Kolkata')::INTEGER
        """
    )


def downgrade() -> None:
    op.execute(
        """
        UPDATE sale_items
        SET hour_of_day = EXTRACT(HOUR FROM sale_date AT TIME ZONE 'UTC')::INTEGER
        """
    )
