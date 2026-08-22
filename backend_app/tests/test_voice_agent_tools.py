from app.agent.tools import VyamitAssistant
from app.db.tenant import TenantContext


def test_retail_voice_agent_exposes_tenant_scoped_inventory_tools() -> None:
    agent = VyamitAssistant(
        instructions="test",
        tenant=TenantContext(owner_id=7, shop_category="Kirana"),
    )

    tool_ids = {tool.id for tool in agent.tools}

    assert {"search_inventory", "list_inventory", "find_customer"} <= tool_ids
