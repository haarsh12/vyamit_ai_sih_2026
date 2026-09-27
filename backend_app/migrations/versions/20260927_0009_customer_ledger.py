"""Add an append-only customer udhaar ledger.

Revision ID: 20260927_0009
Revises: 20260824_0008
Create Date: 2026-09-27
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20260927_0009"
down_revision = "20260824_0008"
branch_labels = None
depends_on = None


def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    customer_columns = {
        column["name"] for column in inspector.get_columns("verified_customers")
    }
    if "ledger_balance" not in customer_columns:
        op.add_column(
            "verified_customers",
            sa.Column(
                "ledger_balance",
                sa.Numeric(14, 2),
                nullable=False,
                server_default="0",
            ),
        )
        op.create_check_constraint(
            "ck_verified_customers_verified_customer_ledger_non_negative",
            "verified_customers",
            "ledger_balance >= 0",
        )

    inspector = sa.inspect(op.get_bind())
    if "customer_ledger_entries" not in inspector.get_table_names():
        op.create_table(
            "customer_ledger_entries",
            sa.Column("id", sa.BigInteger(), nullable=False),
            sa.Column("owner_id", sa.BigInteger(), nullable=False),
            sa.Column("shop_category", sa.String(length=60), nullable=False),
            sa.Column("verified_customer_id", sa.BigInteger(), nullable=False),
            sa.Column("bill_id", sa.BigInteger(), nullable=True),
            sa.Column("entry_type", sa.String(length=16), nullable=False),
            sa.Column("amount", sa.Numeric(14, 2), nullable=False),
            sa.Column("balance_after", sa.Numeric(14, 2), nullable=False),
            sa.Column("source", sa.String(length=24), nullable=False),
            sa.Column("note", sa.String(length=240), nullable=True),
            sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column(
                "created_at",
                sa.DateTime(timezone=True),
                nullable=False,
                server_default=sa.text("CURRENT_TIMESTAMP"),
            ),
            sa.Column(
                "updated_at",
                sa.DateTime(timezone=True),
                nullable=False,
                server_default=sa.text("CURRENT_TIMESTAMP"),
            ),
            sa.CheckConstraint("amount > 0", name="customer_ledger_amount_positive"),
            sa.CheckConstraint(
                "balance_after >= 0", name="customer_ledger_balance_non_negative"
            ),
            sa.CheckConstraint(
                "entry_type IN ('udhaar', 'payment')",
                name="customer_ledger_entry_type",
            ),
            sa.ForeignKeyConstraint(["owner_id"], ["users.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(
                ["verified_customer_id"], ["verified_customers.id"], ondelete="RESTRICT"
            ),
            sa.ForeignKeyConstraint(["bill_id"], ["bills.id"], ondelete="SET NULL"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint(
                "bill_id", "entry_type", name="uq_customer_ledger_entries_bill_type"
            ),
        )

    inspector = sa.inspect(op.get_bind())
    entry_indexes = {
        index["name"] for index in inspector.get_indexes("customer_ledger_entries")
    }
    if "ix_customer_ledger_entries_customer_occurred" not in entry_indexes:
        op.create_index(
            "ix_customer_ledger_entries_customer_occurred",
            "customer_ledger_entries",
            ["verified_customer_id", "occurred_at"],
        )
    if "ix_customer_ledger_entries_owner_category_occurred" not in entry_indexes:
        op.create_index(
            "ix_customer_ledger_entries_owner_category_occurred",
            "customer_ledger_entries",
            ["owner_id", "shop_category", "occurred_at"],
        )
    if "ix_customer_ledger_entries_occurred_at" not in entry_indexes:
        op.create_index(
            "ix_customer_ledger_entries_occurred_at",
            "customer_ledger_entries",
            ["occurred_at"],
        )


def downgrade() -> None:
    op.drop_table("customer_ledger_entries")
    op.drop_constraint(
        "ck_verified_customers_verified_customer_ledger_non_negative",
        "verified_customers",
        type_="check",
    )
    op.drop_column("verified_customers", "ledger_balance")
