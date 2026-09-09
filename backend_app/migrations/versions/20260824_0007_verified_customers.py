"""Add verified customers table with pgvector embedding support.

Revision ID: 20260824_0007
Revises: 20260821_0006
Create Date: 2026-08-24
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from pgvector.sqlalchemy import Vector


revision = "20260824_0007"
down_revision = "20260821_0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # The original bootstrap migration creates the ORM metadata for an empty
    # database.  On that path the current table/columns may already exist; the
    # guards keep this revision valid for both a fresh install and an upgrade
    # from a database created before verified customers existed.
    inspector = sa.inspect(op.get_bind())
    if "verified_customers" not in inspector.get_table_names():
        op.create_table(
            "verified_customers",
            sa.Column("id", sa.BigInteger(), nullable=False),
            sa.Column("owner_id", sa.BigInteger(), nullable=False),
            sa.Column("shop_category", sa.String(length=60), nullable=False),
            sa.Column("name", sa.String(length=120), nullable=False),
            sa.Column("phone_number", sa.String(length=20), nullable=True),
            sa.Column("name_embedding", Vector(768), nullable=True),
            sa.Column("embedding_source_hash", sa.String(length=64), nullable=True),
            sa.Column("embedding_model", sa.String(length=120), nullable=True),
            sa.Column("embedding_updated_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("total_bills", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("total_spent", sa.Numeric(14, 2), nullable=False, server_default="0"),
            sa.Column("last_purchase_date", sa.DateTime(timezone=True), nullable=True),
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
            sa.ForeignKeyConstraint(["owner_id"], ["users.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("owner_id", "shop_category", "name", name="uq_verified_customers_owner_category_name"),
        )

    inspector = sa.inspect(op.get_bind())
    customer_indexes = {index["name"] for index in inspector.get_indexes("verified_customers")}
    if "ix_verified_customers_owner_category" not in customer_indexes:
        op.create_index("ix_verified_customers_owner_category", "verified_customers", ["owner_id", "shop_category"])
    if "ix_verified_customers_name" not in customer_indexes:
        op.create_index("ix_verified_customers_name", "verified_customers", ["name"])
    if "ix_verified_customers_embedding_hnsw" not in customer_indexes:
        op.create_index(
            "ix_verified_customers_embedding_hnsw",
            "verified_customers",
            ["name_embedding"],
            postgresql_using="hnsw",
            postgresql_ops={"name_embedding": "vector_cosine_ops"},
        )

    bill_columns = {column["name"] for column in inspector.get_columns("bills")}
    if "verified_customer_id" not in bill_columns:
        op.add_column("bills", sa.Column("verified_customer_id", sa.BigInteger(), nullable=True))

    inspector = sa.inspect(op.get_bind())
    bill_foreign_keys = inspector.get_foreign_keys("bills")
    if not any(foreign_key["constrained_columns"] == ["verified_customer_id"] for foreign_key in bill_foreign_keys):
        op.create_foreign_key(
            "fk_bills_verified_customer_id",
            "bills",
            "verified_customers",
            ["verified_customer_id"],
            ["id"],
            ondelete="SET NULL",
        )

    bill_indexes = {index["name"] for index in inspector.get_indexes("bills")}
    if "ix_bills_verified_customer_id" not in bill_indexes:
        op.create_index("ix_bills_verified_customer_id", "bills", ["verified_customer_id"])


def downgrade() -> None:
    # Drop indexes and foreign key on bills
    op.drop_index("ix_bills_verified_customer_id", table_name="bills")
    op.drop_constraint("fk_bills_verified_customer_id", "bills", type_="foreignkey")
    op.drop_column("bills", "verified_customer_id")
    
    # Drop verified_customers table and all its indexes
    op.drop_index("ix_verified_customers_embedding_hnsw", table_name="verified_customers")
    op.drop_index("ix_verified_customers_name", table_name="verified_customers")
    op.drop_index("ix_verified_customers_owner_category", table_name="verified_customers")
    op.drop_table("verified_customers")
