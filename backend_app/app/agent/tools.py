"""Read-only LiveKit tool adapters. All authorization stays inside repositories/services."""

from __future__ import annotations

from collections.abc import Awaitable, Callable

from livekit.agents import Agent, function_tool
from sqlalchemy import or_, select

from app.db.models import Customer, User
from app.db.session import get_agent_db_session
from app.db.tenant import TenantContext
from app.domain.analytics import analytics_service
from app.domain.doctor_prescriptions import format_dictation
from app.domain.gst import gst_billing_service
from app.domain.voice_inventory import parse_inventory_dictation
from app.domain.workflows import workflow_service
from app.retrieval.inventory import inventory_search_service
from app.schemas.analytics import BillCreate


class VyamitAssistant(Agent):
    """One agent instance owns only one server-resolved tenant context."""

    def __init__(
        self,
        *,
        instructions: str,
        tenant: TenantContext,
        on_bill_draft_created: Callable[[dict[str, object]], Awaitable[None]] | None = None,
        on_prescription_draft_created: Callable[[dict[str, object]], Awaitable[None]] | None = None,
        on_inventory_draft_created: Callable[[dict[str, object]], Awaitable[None]] | None = None,
    ) -> None:
        super().__init__(instructions=instructions)
        self.tenant = tenant
        self._on_bill_draft_created = on_bill_draft_created
        self._on_prescription_draft_created = on_prescription_draft_created
        self._on_inventory_draft_created = on_inventory_draft_created

    @function_tool()
    async def get_shop_profile(self) -> dict[str, object]:
        """Get the active shop's public profile when the user asks about their shop details."""

        async with get_agent_db_session() as session:
            user = await session.get(User, self.tenant.owner_id)
            if user is None or not user.is_active:
                return {"available": False}
            return {
                "available": True, "shop_name": user.shop_name, "owner_name": user.owner_name,
                "address": user.address, "shop_category": self.tenant.shop_category,
            }

    @function_tool()
    async def search_inventory(self, query: str) -> dict[str, object]:
        """Search only this shop's active catalog by an item name, alias, or description.
        
        Returns a dict with:
        - "matches": list of matching items (empty list if no matches)
        - "catalog_has_quantity_tracking": boolean
        
        If matches list is non-empty, the items ARE in inventory.
        If matches list is empty, the items are NOT in inventory.
        """

        import logging
        logger = logging.getLogger("vyamit.agent.tools")
        
        async with get_agent_db_session() as session:
            matches = await inventory_search_service.search(session, self.tenant, query)
            result = {
                "matches": [match.to_tool_payload() for match in matches],
                "catalog_has_quantity_tracking": False,
            }
            logger.info(
                "search_inventory_result",
                extra={
                    "query": query,
                    "matches_count": len(matches),
                    "result": result,
                    "owner_id": self.tenant.owner_id,
                    "shop_category": self.tenant.shop_category,
                }
            )
            return result

    @function_tool()
    async def find_customer(self, query: str) -> dict[str, object]:
        """Find customers belonging only to the authenticated shop by name or phone fragment."""

        clean = query.strip()
        if not clean:
            return {"matches": []}
        async with get_agent_db_session() as session:
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

        async with get_agent_db_session() as session:
            return await analytics_service.overview(session, self.tenant, days=days)

    @function_tool()
    async def get_gst_configuration(self) -> dict[str, object]:
        """Get the current shop's GST readiness and configuration, when the user asks about it."""

        async with get_agent_db_session() as session:
            return await gst_billing_service.get_configuration(session, self.tenant)

    @function_tool()
    async def create_bill_draft(
        self,
        items: list[dict[str, object]],
        total_amount: float = 0.0,
        customer_phone: str | None = None,
        customer_name: str | None = None,
        payment_method: str = "cash",
    ) -> dict[str, object]:
        """Create or update an editable bill draft directly in the mobile app's Live Bill Box.

        Call this tool IMMEDIATELY whenever the user asks to add or update items in the bill.
        Do NOT ask the user for verbal confirmation before calling this tool.
        """

        import logging
        logger = logging.getLogger("vyamit.agent.tools")
        logger.info(
            "create_bill_draft_called",
            extra={
                "items": items,
                "total_amount": total_amount,
                "customer_phone": customer_phone,
                "customer_name": customer_name,
                "payment_method": payment_method,
                "owner_id": self.tenant.owner_id,
                "shop_category": self.tenant.shop_category,
            }
        )

        if self.tenant.shop_category == "Doctor Prescription":
            return {"created": False, "message": "Billing drafts are unavailable in doctor mode."}

        normalized_items: list[dict[str, object]] = []
        async with get_agent_db_session() as session:
            for item in items:
                name = str(
                    item.get("name")
                    or item.get("item")
                    or item.get("item_name")
                    or item.get("product")
                    or item.get("product_name")
                    or "Item"
                ).strip()

                try:
                    qty = float(
                        item.get("quantity")
                        or item.get("qty")
                        or item.get("count")
                        or 1.0
                    )
                except (ValueError, TypeError):
                    qty = 1.0

                try:
                    price = float(
                        item.get("price")
                        or item.get("rate")
                        or item.get("unit_price")
                        or item.get("price_per_unit")
                        or item.get("cost")
                        or 0.0
                    )
                except (ValueError, TypeError):
                    price = 0.0

                # Auto catalog price lookup if price was not supplied by user/LLM
                if price <= 0.0 and name and name != "Item":
                    matches = await inventory_search_service.search(session, self.tenant, name)
                    if matches:
                        try:
                            price = float(matches[0].item.price)
                        except (ValueError, TypeError):
                            pass

                item_total = round(qty * price, 2)
                unit = str(item.get("unit") or item.get("unit_name") or "kg").strip()
                normalized_items.append({
                    "name": name,
                    "quantity": qty,
                    "unit": unit,
                    "price": price,
                    "total": item_total,
                })

            final_total = round(sum(it["total"] for it in normalized_items), 2)

            try:
                payload = BillCreate.model_validate({
                    "items": normalized_items,
                    "total_amount": final_total,
                    "customer_phone": customer_phone,
                    "customer_name": customer_name,
                    "payment_method": payment_method,
                })
            except Exception as err:
                return {"created": False, "message": f"The proposed bill has invalid data: {err}"}

            draft = await workflow_service.create_bill_draft(session, self.tenant, payload)
            result: dict[str, object] = {
                "created": True,
                "draft_id": str(draft.id),
                "version": draft.version,
                "expires_at": draft.expires_at.isoformat(),
                "state": draft.state.model_dump(mode="json"),
                "requires_user_confirmation": False,
            }
            if self._on_bill_draft_created is not None:
                await self._on_bill_draft_created(result)
            return result

    @function_tool()
    async def format_prescription_dictation(self, text: str) -> dict[str, object]:
        """Format a doctor's dictated words into an editable prescription draft.

        Use only in Doctor Prescription mode. It does not diagnose, prescribe,
        or store a record; the doctor must review the preview before printing.
        """

        if self.tenant.shop_category != "Doctor Prescription":
            return {"created": False, "message": "Prescription formatting is available only in doctor mode."}
        if not text.strip() or len(text) > 2_000:
            return {"created": False, "message": "Dictation must be between 1 and 2000 characters."}
        result = format_dictation(text)
        if self._on_prescription_draft_created is not None:
            await self._on_prescription_draft_created(result)
        return result

    @function_tool()
    async def parse_inventory_changes(self, text: str) -> dict[str, object]:
        """Turn spoken inventory additions or price changes into an editable proposal.

        This tool never adds or updates inventory. Use it when the user asks to
        change catalog items, then ask them to review and save in the app.
        """

        if self.tenant.shop_category == "Doctor Prescription":
            return {"created": False, "message": "Inventory is unavailable in doctor mode."}
        if not text.strip() or len(text) > 2_000:
            return {"created": False, "message": "Inventory dictation must be between 1 and 2000 characters."}
        async with get_agent_db_session() as session:
            items = await inventory_search_service.list_catalog(session, self.tenant)
        proposal = parse_inventory_dictation(
            text,
            existing_items=[{"id": item.master_id, "names": item.names, "price": item.price, "unit": item.unit} for item in items],
            existing_categories=sorted({item.category for item in items if item.category}),
        )
        proposal["requires_user_confirmation"] = True
        if self._on_inventory_draft_created is not None:
            await self._on_inventory_draft_created(proposal)
        return proposal

