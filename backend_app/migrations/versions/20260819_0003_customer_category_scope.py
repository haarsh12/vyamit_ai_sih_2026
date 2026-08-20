"""Scope customer summaries to the category active when the sale occurred.

Revision ID: 20260819_0003
Revises: 20260819_0002
Create Date: 2026-08-19
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "20260819_0003"
down_revision = "20260819_0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    columns = {column["name"] for column in inspector.get_columns("customers")}
    if "shop_category" not in columns:
        op.add_column(
            "customers",
            sa.Column("shop_category", sa.String(length=60), nullable=False, server_default="General"),
        )
        op.alter_column("customers", "shop_category", server_default=None)
    indexes = {index["name"] for index in inspector.get_indexes("customers")}
    if "ix_customers_owner_category_name" not in indexes:
        op.create_index("ix_customers_owner_category_name", "customers", ["owner_id", "shop_category", "name"])


def downgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    columns = {column["name"] for column in inspector.get_columns("customers")}
    indexes = {index["name"] for index in inspector.get_indexes("customers")}
    if "ix_customers_owner_category_name" in indexes:
        op.drop_index("ix_customers_owner_category_name", table_name="customers")
    if "shop_category" in columns:
        op.drop_column("customers", "shop_category")
