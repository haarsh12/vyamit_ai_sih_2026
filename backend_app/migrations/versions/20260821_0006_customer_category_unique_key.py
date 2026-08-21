"""Align customer uniqueness with tenant category isolation.

Revision ID: 20260821_0006
Revises: 20260820_0005
Create Date: 2026-08-21
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20260821_0006"
down_revision = "20260820_0005"
branch_labels = None
depends_on = None


_NEW_COLUMNS = {"owner_id", "shop_category", "phone_number"}
_OLD_COLUMNS = {"owner_id", "phone_number"}


def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    constraints = inspector.get_unique_constraints("customers")
    for constraint in constraints:
        if set(constraint.get("column_names") or []) == _OLD_COLUMNS:
            name = constraint.get("name")
            if name:
                op.drop_constraint(name, "customers", type_="unique")
    if not any(set(item.get("column_names") or []) == _NEW_COLUMNS for item in constraints):
        op.create_unique_constraint(
            "uq_customers_owner_category_phone",
            "customers",
            ["owner_id", "shop_category", "phone_number"],
        )


def downgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    constraints = inspector.get_unique_constraints("customers")
    for constraint in constraints:
        if set(constraint.get("column_names") or []) == _NEW_COLUMNS:
            name = constraint.get("name")
            if name:
                op.drop_constraint(name, "customers", type_="unique")
    op.create_unique_constraint("uq_customers_owner_phone", "customers", ["owner_id", "phone_number"])
