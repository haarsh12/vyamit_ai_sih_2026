from unittest.mock import AsyncMock, MagicMock, patch
import pytest

from app.agent.tools import VyamitAssistant
from app.db.models import Item
from app.db.tenant import TenantContext
from app.retrieval.inventory import inventory_search_service


def test_retail_voice_agent_exposes_tenant_scoped_inventory_tools() -> None:
    agent = VyamitAssistant(
        instructions="test",
        tenant=TenantContext(owner_id=7, shop_category="Kirana"),
    )

    tool_ids = {tool.id for tool in agent.tools}

    assert {
        "search_inventory",
        "create_bill_draft",
        "find_customer",
        "search_verified_customers",
        "get_customer_bill_history",
    } <= tool_ids


@pytest.mark.asyncio
async def test_create_bill_draft_with_unit_price_and_alternative_field_names() -> None:
    callback_mock = AsyncMock()
    agent = VyamitAssistant(
        instructions="test",
        tenant=TenantContext(owner_id=5, shop_category="General"),
        on_bill_draft_created=callback_mock,
    )

    fake_draft = MagicMock()
    fake_draft.id = "12345678-1234-1234-1234-123456789012"
    fake_draft.version = 1
    fake_draft.expires_at.isoformat.return_value = "2026-08-22T18:00:00Z"
    fake_draft.state.model_dump.return_value = {
        "items": [{"name": "चावल", "quantity": 2.0, "unit": "kg", "price": 50.0, "total": 100.0}],
        "total_amount": 100.0,
        "payment_method": "cash",
    }

    with patch("app.agent.tools.workflow_service.create_bill_draft", return_value=fake_draft), \
         patch("app.agent.tools.get_agent_db_session") as mock_db:

        mock_session = AsyncMock()
        mock_db.return_value.__aenter__.return_value = mock_session

        # LLM passes alternative keys: 'unit_price', 'quantity', 'name'
        result = await agent.create_bill_draft(
            items=[{"name": "चावल", "unit_price": 50, "quantity": 2}],
            total_amount=100.0,
        )

        assert result["created"] is True
        assert result["requires_user_confirmation"] is False
        assert callback_mock.called
        event_payload = callback_mock.call_args[0][0]
        assert event_payload["created"] is True
        assert event_payload["state"]["items"][0]["name"] == "चावल"
        assert event_payload["state"]["items"][0]["price"] == 50.0
        assert event_payload["state"]["total_amount"] == 100.0


@pytest.mark.asyncio
async def test_inventory_search_hindi_transliteration_and_stop_words() -> None:
    session_mock = AsyncMock()

    item_atta = Item(
        id=1, owner_id=5, shop_category="General", master_id="atta-1",
        names=["Atta", "Wheat Flour"], price=45.0, unit="kg", gst_rate_bps=0
    )
    item_milk = Item(
        id=2, owner_id=5, shop_category="General", master_id="milk-1",
        names=["Milk", "Doodh"], price=30.0, unit="liter", gst_rate_bps=0
    )

    with patch.object(inventory_search_service, "list_catalog", new_callable=AsyncMock, return_value=[item_atta, item_milk]):
        tenant = TenantContext(owner_id=5, shop_category="General")

        # Test Hindi query "आटा" -> matches "Atta"
        matches = await inventory_search_service.search(session_mock, tenant, "आटा")
        assert len(matches) > 0
        assert matches[0].item.master_id == "atta-1"

        # Test Hindi query with stop words "1 किलो आटा चाहिए" -> matches "Atta"
        matches_phrase = await inventory_search_service.search(session_mock, tenant, "1 किलो आटा चाहिए")
        assert len(matches_phrase) > 0
        assert matches_phrase[0].item.master_id == "atta-1"

        # Test Hindi query "दूध" -> matches "Milk"
        matches_milk = await inventory_search_service.search(session_mock, tenant, "दूध")
        assert len(matches_milk) > 0
        assert matches_milk[0].item.master_id == "milk-1"
