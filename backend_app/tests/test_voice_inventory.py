from app.domain.voice_inventory import parse_inventory_dictation


def test_inventory_dictation_is_an_editable_non_mutating_proposal() -> None:
    result = parse_inventory_dictation(
        "category grains wheat flour 45 kg",
        existing_items=[{"id": "flour-1", "names": ["Wheat Flour"], "price": "40", "unit": "kg"}],
        existing_categories=["Grains"],
    )
    item = result["categories"][0]["items"][0]
    assert result["categories"][0]["name"] == "Grains"
    assert item["name"] == "Wheat Flour"
    assert item["is_existing"] is True
    assert item["existing_id"] == "flour-1"
    assert item["old_price"] == 40.0


def test_inventory_dictation_never_requires_an_llm_or_database_write() -> None:
    result = parse_inventory_dictation("mango", existing_items=[], existing_categories=[])
    assert result["categories"][0]["items"][0]["name"] == "Mango"
    assert result["categories"][0]["items"][0]["price"] == 0.0
