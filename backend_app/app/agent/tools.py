"""Read-only LiveKit tool adapters. All authorization stays inside repositories/services."""

from __future__ import annotations

from livekit.agents import Agent, function_tool
from sqlalchemy import or_, select

from app.db.models import Customer, User
from app.db.session import get_session_factory
from app.db.tenant import TenantContext
from app.domain.analytics import analytics_service
from app.domain.gst import gst_billing_service
from app.retrieval.inventory import inventory_search_service


class VyamitAssistant(Agent):
    """One agent instance owns only one server-resolved tenant context."""

    def __init__(self, *, instructions: str, tenant: TenantContext) -> None:
        super().__init__(instructions=instructions)
        self.tenant = tenant

    @function_tool()
    async def get_shop_profile(self) -> dict[str, object]:
        """Get the active shop's public profile when the user asks about their shop details."""

        factory = get_session_factory()
        if factory is None:
            return {"available": False}
        async with factory() as session:
            user = await session.get(User, self.tenant.owner_id)
            if user is None or not user.is_active:
                return {"available": False}
            return {
                "available": True, "shop_name": user.shop_name, "owner_name": user.owner_name,
                "address": user.address, "shop_category": self.tenant.shop_category,
            }

    @function_tool()
    async def search_inventory(self, query: str) -> dict[str, object]:
        """Search only this shop's active catalog by an item name, alias, or description."""

        factory = get_session_factory()
        if factory is None:
            return {"matches": [], "message": "Catalog is temporarily unavailable."}
        async with factory() as session:
            matches = await inventory_search_service.search(session, self.tenant, query)
            return {
                "matches": [match.to_tool_payload() for match in matches],
                "catalog_has_quantity_tracking": False,
            }

    @function_tool()
    async def find_customer(self, query: str) -> dict[str, object]:
        """Find customers belonging only to the authenticated shop by name or phone fragment."""

        clean = query.strip()
        if not clean:
            return {"matches": []}
        factory = get_session_factory()
        if factory is None:
            return {"matches": [], "message": "Customer data is temporarily unavailable."}
        async with factory() as session:
            rows = (await session.scalars(select(Customer).where(
                Customer.owner_id == self.tenant.owner_id,
                Customer.shop_category == self.tenant.shop_category,
                or_(Customer.name.ilike(f"%{clean}%"), Customer.phone_number.ilike(f"%{clean}%")),
            ).order_by(Customer.last_purchase_date.desc()).limit(5))).all()
            return {"matches": [{
                "name": customer.name or "Unnamed customer",
                "phone_last_four": customer.phone_number[-4:], "total_bills": customer.total_bills,
                "last_purchase_date": customer.last_purchase_date.isoformat() if customer.last_purchase_date else None,
            } for customer in rows]}

    @function_tool()
    async def get_sales_summary(self, days: int = 30) -> dict[str, object]:
        """Get aggregate sales totals for the current shop; accepts one to 3650 days."""

        factory = get_session_factory()
        if factory is None:
            return {"available": False}
        async with factory() as session:
            return await analytics_service.overview(session, self.tenant, days=days)

    @function_tool()
    async def get_gst_configuration(self) -> dict[str, object]:
        """Get the current shop's GST readiness and configuration, when the user asks about it."""

        factory = get_session_factory()
        if factory is None:
            return {"is_enabled": False, "verification_status": "unavailable"}
        async with factory() as session:
            return await gst_billing_service.get_configuration(session, self.tenant)
