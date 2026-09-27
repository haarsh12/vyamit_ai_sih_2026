"""Migration-chain checks that run before a real Supabase migration."""

from pathlib import Path


_VERSIONS = Path(__file__).resolve().parents[1] / "migrations" / "versions"


def test_verified_customer_migrations_follow_the_existing_chain() -> None:
    verified_customers = (_VERSIONS / "20260824_0007_verified_customers.py").read_text(encoding="utf-8")
    bill_type = (_VERSIONS / "20260824_0008_add_bill_type.py").read_text(encoding="utf-8")
    ledger = (_VERSIONS / "20260927_0009_customer_ledger.py").read_text(encoding="utf-8")
    peak_hours = (_VERSIONS / "20260927_0010_localize_sale_item_hours.py").read_text(encoding="utf-8")

    assert 'revision = "20260824_0007"' in verified_customers
    assert 'down_revision = "20260821_0006"' in verified_customers
    assert '"verified_customers"' in verified_customers
    assert 'Vector(768)' in verified_customers
    assert 'revision = "20260824_0008"' in bill_type
    assert 'down_revision = "20260824_0007"' in bill_type
    assert 'revision = "20260927_0009"' in ledger
    assert 'down_revision = "20260824_0008"' in ledger
    assert '"customer_ledger_entries"' in ledger
    assert 'revision = "20260927_0010"' in peak_hours
    assert 'down_revision = "20260927_0009"' in peak_hours
    assert "Asia/Kolkata" in peak_hours


def test_initial_migration_enables_pgvector_before_schema_creation() -> None:
    content = (_VERSIONS / "20260818_0001_initial_schema.py").read_text(encoding="utf-8")

    assert 'CREATE EXTENSION IF NOT EXISTS vector' in content
    assert 'Base.metadata.create_all' in content
