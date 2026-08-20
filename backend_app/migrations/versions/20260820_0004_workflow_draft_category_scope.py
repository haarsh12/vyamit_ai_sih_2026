"""Scope workflow drafts to their active shop category.

Revision ID: 20260820_0004
Revises: 20260819_0003
Create Date: 2026-08-20
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "20260820_0004"
down_revision = "20260819_0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    columns = {column["name"] for column in inspector.get_columns("workflow_drafts")}
    if "shop_category" not in columns:
        op.add_column(
            "workflow_drafts",
            sa.Column("shop_category", sa.String(length=60), nullable=False, server_default="General"),
        )
        op.alter_column("workflow_drafts", "shop_category", server_default=None)
    indexes = {index["name"] for index in inspector.get_indexes("workflow_drafts")}
    if "ix_workflow_drafts_owner_category_kind" not in indexes:
        op.create_index(
            "ix_workflow_drafts_owner_category_kind",
            "workflow_drafts",
            ["owner_id", "shop_category", "kind"],
        )


def downgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    columns = {column["name"] for column in inspector.get_columns("workflow_drafts")}
    indexes = {index["name"] for index in inspector.get_indexes("workflow_drafts")}
    if "ix_workflow_drafts_owner_category_kind" in indexes:
        op.drop_index("ix_workflow_drafts_owner_category_kind", table_name="workflow_drafts")
    if "shop_category" in columns:
        op.drop_column("workflow_drafts", "shop_category")
