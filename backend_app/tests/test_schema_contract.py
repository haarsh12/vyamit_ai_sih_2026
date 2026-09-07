"""Static schema contracts that must hold before a Supabase migration runs."""

from app.db.models import Bill, Customer, Item


def test_customer_identity_is_scoped_to_owner_and_shop_category() -> None:
    unique_sets = {
        tuple(constraint.columns.keys())
        for constraint in Customer.__table__.constraints
        if constraint.__class__.__name__ == "UniqueConstraint"
    }

    assert ("owner_id", "shop_category", "phone_number") in unique_sets
    assert ("owner_id", "phone_number") not in unique_sets


def test_inventory_embedding_has_the_locked_pgvector_dimension_and_hnsw_index() -> None:
    embedding_type = Item.__table__.c.embedding.type
    index_names = {index.name for index in Item.__table__.indexes}

    assert getattr(embedding_type, "dim", None) == 768
    assert "ix_items_embedding_hnsw" in index_names


def test_bill_records_type() -> None:
    index_names = {index.name for index in Bill.__table__.indexes}

    assert Bill.__table__.c.bill_type.default.arg == "printed"
    assert "ix_bills_bill_type" in index_names
