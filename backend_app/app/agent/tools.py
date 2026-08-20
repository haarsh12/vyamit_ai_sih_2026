"""Read-only LiveKit tool adapters. All authorization stays inside repositories/services."""

from __future__ import annotations

from collections.abc import Awaitable, Callable

from livekit.agents import Agent, function_tool
from sqlalchemy import or_, select

from app.db.models import Customer, User
from app.db.session import get_session_factory
from app.db.tenant import TenantContext
from app.domain.analytics import analytics_service
from app.domain.doctor_prescriptions import format_dictation
from app.domain.gst import gst_billing_service
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
    ) -> None:
        super().__init__(instructions=instructions)
        self.tenant = tenant
        self._on_bill_draft_created = on_bill_draft_created
        self._on_prescription_draft_created = on_prescription_draft_created

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

    @function_tool()
    async def create_bill_draft(
        self,
        items: list[dict[str, object]],
        total_amount: float,
        customer_phone: str | None = None,
        customer_name: str | None = None,
        payment_method: str = "cash",
    ) -> dict[str, object]:
        """Create an editable bill draft after confirming each item, quantity, and price.

        This never saves a bill. The mobile app must display the returned draft
        and call its separate confirmation endpoint after an explicit user tap.
        Never invent item prices or quantities.
        """

        if self.tenant.shop_category == "Doctor Prescription":
            return {"created": False, "message": "Billing drafts are unavailable in doctor mode."}
        factory = get_session_factory()
        if factory is None:
            return {"created": False, "message": "Billing is temporarily unavailable."}
        try:
            payload = BillCreate.model_validate({
                "items": items,
                "total_amount": total_amount,
                "customer_phone": customer_phone,
                "customer_name": customer_name,
                "payment_method": payment_method,
            })
        except ValueError:
            return {"created": False, "message": "The proposed bill has invalid totals or line items."}
        async with factory() as session:
            draft = await workflow_service.create_bill_draft(session, self.tenant, payload)
            result: dict[str, object] = {
                "created": True,
                "draft_id": str(draft.id),
                "version": draft.version,
                "expires_at": draft.expires_at.isoformat(),
                "state": draft.state.model_dump(mode="json"),
                "requires_user_confirmation": True,
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
