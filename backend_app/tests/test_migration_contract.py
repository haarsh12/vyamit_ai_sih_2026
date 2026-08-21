"""Migration-chain checks that run before a real Supabase migration."""

from pathlib import Path


_VERSIONS = Path(__file__).resolve().parents[1] / "migrations" / "versions"


def test_latest_migration_is_customer_category_uniqueness_fix() -> None:
    migration = _VERSIONS / "20260821_0006_customer_category_unique_key.py"
    content = migration.read_text(encoding="utf-8")

    assert 'revision = "20260821_0006"' in content
    assert 'down_revision = "20260820_0005"' in content
    assert '"owner_id", "shop_category", "phone_number"' in content


def test_initial_migration_enables_pgvector_before_schema_creation() -> None:
    content = (_VERSIONS / "20260818_0001_initial_schema.py").read_text(encoding="utf-8")

    assert 'CREATE EXTENSION IF NOT EXISTS vector' in content
    assert 'Base.metadata.create_all' in content
