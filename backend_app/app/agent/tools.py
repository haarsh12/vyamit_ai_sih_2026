"""Tenant-scoped LiveKit tools; financial changes remain explicitly confirmed."""

from __future__ import annotations

import asyncio
import json
import re
import time
from collections.abc import Awaitable, Callable

from livekit.agents import Agent, function_tool
from sqlalchemy import or_, select

from app.db.models import Customer, User
from app.db.session import get_agent_db_session
from app.db.tenant import TenantContext
from app.domain.analytics import analytics_service
from app.domain.billing_source import billing_source_from_items
from app.domain.customer_ledger import customer_ledger_service
from app.domain.doctor_prescriptions import format_dictation
from app.domain.gst import gst_billing_service
from app.domain.voice_inventory import parse_inventory_dictation
from app.domain.workflows import workflow_service
from app.repositories.verified_customers import VerifiedCustomerRepository
from app.retrieval.customers import customer_search_service
from app.retrieval.inventory import inventory_search_service
from app.schemas.analytics import BillCreate
from app.schemas.ledger import LedgerAdjustmentRequest


_DEVANAGARI_DIGITS = str.maketrans("०१२३४५६७८९", "0123456789")
_SPOKEN_QUANTITY_PATTERN = re.compile(
    r"(?P<amount>\d+(?:\.\d+)?|half|quarter|aadha|adha|dedh|derh|"
    r"आधा|पाव|डेढ़|डेढ़|सवा|पौना)\s*"
    r"(?P<unit>kg|kilo(?:gram)?s?|किलो(?:ग्राम)?|g|gm|grams?|ग्राम|"
    r"l|lit(?:er|re)?s?|लीटर)",
    re.IGNORECASE,
)
_SPOKEN_NUMBER_VALUES: dict[str, float] = {
    "half": 0.5,
    "quarter": 0.25,
    "aadha": 0.5,
    "adha": 0.5,
    "आधा": 0.5,
    "पाव": 0.25,
    "dedh": 1.5,
    "derh": 1.5,
    "डेढ़": 1.5,
    "डेढ़": 1.5,
    "सवा": 1.25,
    "पौना": 0.75,
}


def _normalise_spoken_unit(unit: str) -> str:
    unit_key = unit.casefold().strip()
    if unit_key in {"kg", "kilo", "kilogram", "kilograms", "किलो", "किलोग्राम"}:
        return "kg"
    if unit_key in {"g", "gm", "gram", "grams", "ग्राम"}:
        return "g"
    if unit_key in {"l", "lit", "liter", "litre", "liters", "litres", "लीटर"}:
        return "liter"
    return unit_key


def _parse_spoken_quantities(text: str) -> list[tuple[float, str]]:
    """Read explicit number-plus-unit pairs from one final STT transcript."""

    normalised = text.translate(_DEVANAGARI_DIGITS)
    quantities: list[tuple[float, str]] = []
    for match in _SPOKEN_QUANTITY_PATTERN.finditer(normalised):
        raw_amount = match.group("amount").casefold()
        try:
            amount = _SPOKEN_NUMBER_VALUES.get(raw_amount)
            if amount is None:
                amount = float(raw_amount)
        except ValueError:
            continue
        if amount > 0:
            quantities.append((amount, _normalise_spoken_unit(match.group("unit"))))
    return quantities


def _quantity_in_catalog_unit(quantity: float, spoken_unit: str, catalog_unit: str) -> float:
    """Convert only compatible weight/volume units; otherwise preserve quantity."""

    target_unit = _normalise_spoken_unit(catalog_unit)
    if spoken_unit == target_unit:
        return quantity
    if spoken_unit == "g" and target_unit == "kg":
        return quantity / 1000
    if spoken_unit == "kg" and target_unit == "g":
        return quantity * 1000
    return quantity


class VyamitAssistant(Agent):
    """One agent instance owns only one server-resolved tenant context."""

    def __init__(
        self,
        *,
        instructions: str,
        tenant: TenantContext,
        on_bill_draft_created: Callable[[dict[str, object]], Awaitable[None]] | None = None,
        on_ledger_draft_created: Callable[[dict[str, object]], Awaitable[None]] | None = None,
        on_prescription_draft_created: Callable[[dict[str, object]], Awaitable[None]] | None = None,
        on_inventory_draft_created: Callable[[dict[str, object]], Awaitable[None]] | None = None,
    ) -> None:
        super().__init__(instructions=instructions)
        self.tenant = tenant
        self._on_bill_draft_created = on_bill_draft_created
        self._on_ledger_draft_created = on_ledger_draft_created
        self._on_prescription_draft_created = on_prescription_draft_created
        self._on_inventory_draft_created = on_inventory_draft_created
        self._last_bill_request_signature: str | None = None
        self._last_bill_result: dict[str, object] | None = None
        self._last_bill_request_at = 0.0
        self._last_final_user_transcript = ""
        self._bill_draft_lock = asyncio.Lock()

    def remember_final_user_transcript(self, transcript: str) -> None:
        """Keep the current spoken turn authoritative for its bill tool call."""

        self._last_final_user_transcript = transcript.strip()

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
    async def search_verified_customers(self, query: str) -> dict[str, object]:
        """Search verified customers by name using hybrid exact/fuzzy/semantic matching.
        
        Use this tool when the user asks about a specific customer by name, or wants to
        see bill history for a customer. Returns customer details including purchase stats.
        """

        import logging
        logger = logging.getLogger("vyamit.agent.tools")
        
        clean_query = query.strip()
        if not clean_query:
            return {"matches": []}
        
        async with get_agent_db_session() as session:
            matches = await customer_search_service.search(session, self.tenant, clean_query, limit=5)
            result = {
                "matches": [match.to_tool_payload() for match in matches],
                "query": clean_query,
            }
            logger.info(
                "search_verified_customers_result",
                extra={
                    "query": clean_query,
                    "matches_count": len(matches),
                    "result": result,
                    "owner_id": self.tenant.owner_id,
                    "shop_category": self.tenant.shop_category,
                }
            )
            return result

    @function_tool()
    async def get_customer_bill_history(self, customer_id: int, recent_bills_count: int = 5) -> dict[str, object]:
        """Get recent bill history for a verified customer selected by search_verified_customers.

        Use this when the user asks about what a specific customer purchased previously,
        or wants to see their purchase history. Call search_verified_customers first
        and pass the chosen result's ``id``. Returns the most recent bills.

        Args:
            customer_id: The verified customer ID returned by search_verified_customers
            recent_bills_count: Number of recent bills to return (1-20, default 5)
        """

        import logging
        logger = logging.getLogger("vyamit.agent.tools")
        
        safe_limit = min(max(recent_bills_count, 1), 20)
        
        async with get_agent_db_session() as session:
            repository = VerifiedCustomerRepository(session)
            customer = await repository.get_by_id(self.tenant, customer_id)
            
            if not customer:
                logger.info(
                    "get_customer_bill_history_not_found",
                    extra={
                        "customer_id": customer_id,
                        "owner_id": self.tenant.owner_id,
                    }
                )
                return {
                    "found": False,
                    "message": "No verified customer found with that ID",
                }
            
            # Get bill history
            bills = await repository.get_bill_history(
                self.tenant,
                customer.id,
                limit=safe_limit,
                offset=0,
            )
            
            result = {
                "found": True,
                "customer": {
                    "id": customer.id,
                    "name": customer.name,
                    "phone_number": customer.phone_number,
                    "total_bills": customer.total_bills,
                    "total_spent": float(customer.total_spent),
                    "last_purchase_date": (
                        customer.last_purchase_date.isoformat()
                        if customer.last_purchase_date
                        else None
                    ),
                },
                "bills": [{
                    "id": bill.id,
                    "total_amount": float(bill.total_amount),
                    "total_items": bill.total_items,
                    "items": bill.items,
                    "payment_method": bill.payment_method,
                    "bill_type": bill.bill_type,
                    "billing_source": billing_source_from_items(bill.items),
                    "bill_date": bill.bill_date.isoformat(),
                } for bill in bills],
                "returned_count": len(bills),
            }
            
            logger.info(
                "get_customer_bill_history_success",
                extra={
                    "customer_id": customer.id,
                    "customer_name": customer.name,
                    "bills_count": len(bills),
                    "owner_id": self.tenant.owner_id,
                }
            )
            
            return result

    @function_tool()
    async def get_customer_ledger(self, customer_id: int, recent_entries_count: int = 10) -> dict[str, object]:
        """Get a verified customer's current udhaar balance and recent dated ledger entries.

        Call search_verified_customers first and pass the selected exact result's
        id. Use this whenever the owner asks how much a customer owes, their
        udhaar balance, or their recent payments. Never guess a customer.
        """

        safe_limit = min(max(recent_entries_count, 1), 20)
        async with get_agent_db_session() as session:
            statement = await customer_ledger_service.get_statement(
                session,
                self.tenant,
                customer_id,
                limit=safe_limit,
            )
            return statement.model_dump(mode="json")

    @function_tool()
    async def propose_customer_ledger_adjustment(
        self,
        customer_id: int,
        amount: float,
        adjustment_type: str,
        note: str | None = None,
    ) -> dict[str, object]:
        """Prepare, but never apply, a customer's udhaar or payment adjustment.

        Use only after search_verified_customers selected an unambiguous
        customer. ``adjustment_type`` is ``udhaar`` to increase outstanding
        credit or ``payment`` when the customer has paid and the balance must
        decrease. This always opens a confirmation box in the app; tell the
        owner to tap Confirm or Cancel. Do not claim that the balance changed
        until confirmation succeeds.
        """

        normalised_type = adjustment_type.strip().casefold()
        aliases = {"add": "udhaar", "increase": "udhaar", "paid": "payment", "reduce": "payment", "remove": "payment"}
        normalised_type = aliases.get(normalised_type, normalised_type)
        if normalised_type not in {"udhaar", "payment"}:
            return {"created": False, "message": "Please say udhaar add or payment received."}

        try:
            payload = LedgerAdjustmentRequest(
                entry_type=normalised_type,
                amount=amount,
                note=note,
                source="voice",
            )
        except Exception:
            return {"created": False, "message": "Please provide a valid positive amount."}

        async with get_agent_db_session() as session:
            try:
                draft = await customer_ledger_service.create_adjustment_draft(
                    session, self.tenant, customer_id, payload
                )
            except Exception as error:
                return {"created": False, "message": str(getattr(error, "detail", "Unable to prepare ledger change."))}

        result: dict[str, object] = {
            "created": True,
            "requires_user_confirmation": True,
            "draft": draft.model_dump(mode="json"),
        }
        if self._on_ledger_draft_created is not None:
            await self._on_ledger_draft_created(result)
        return result

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
        verified_customer_id: int | None = None,
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
                "verified_customer_id": verified_customer_id,
                "owner_id": self.tenant.owner_id,
                "shop_category": self.tenant.shop_category,
            }
        )

        if self.tenant.shop_category == "Doctor Prescription":
            return {"created": False, "message": "Billing drafts are unavailable in doctor mode."}

        spoken_quantities = _parse_spoken_quantities(self._last_final_user_transcript)
        use_spoken_quantities = len(spoken_quantities) == len(items)
        normalized_items: list[dict[str, object]] = []
        catalog_resolutions: list[dict[str, object]] = []
        unresolved_items: list[str] = []
        async with get_agent_db_session() as session:
            for index, item in enumerate(items):
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

                spoken_quantity = (
                    spoken_quantities[index] if use_spoken_quantities else None
                )
                if spoken_quantity is not None:
                    qty = spoken_quantity[0]

                supplied_price = next(
                    (
                        item.get(field)
                        for field in ("price", "rate", "unit_price", "price_per_unit", "cost")
                        if item.get(field) is not None and str(item.get(field)).strip()
                    ),
                    None,
                )
                try:
                    price = float(supplied_price) if supplied_price is not None else 0.0
                except (ValueError, TypeError):
                    price = 0.0

                supplied_unit = next(
                    (
                        str(item.get(field)).strip()
                        for field in ("unit", "unit_name")
                        if item.get(field) is not None and str(item.get(field)).strip()
                    ),
                    None,
                )

                # The model often knows the quantity and name but not the
                # price. Resolve that from the tenant-scoped catalogue here,
                # rather than allowing a zero-price line into the live bill.
                # A supplied positive price is kept as an explicit owner price.
                catalog_match = None
                if price <= 0.0 and name != "Item":
                    matches = await inventory_search_service.search(
                        session, self.tenant, name, limit=1
                    )
                    if matches:
                        catalog_match = matches[0]
                        try:
                            price = float(catalog_match.item.price)
                        except (ValueError, TypeError):
                            price = 0.0

                if price <= 0.0 and catalog_match is None:
                    unresolved_items.append(name)
                    logger.info(
                        "bill_item_price_unresolved",
                        extra={
                            "item_name": name,
                            "owner_id": self.tenant.owner_id,
                            "shop_category": self.tenant.shop_category,
                        },
                    )
                    continue

                catalog_unit = catalog_match.item.unit if catalog_match else None
                if spoken_quantity is not None:
                    unit = catalog_unit or spoken_quantity[1]
                    qty = _quantity_in_catalog_unit(qty, spoken_quantity[1], unit)
                else:
                    unit = supplied_unit or catalog_unit or "kg"
                item_total = round(qty * price, 2)
                normalized_items.append({
                    "name": name,
                    "quantity": qty,
                    "unit": unit,
                    "price": price,
                    "total": item_total,
                })
                if catalog_match is not None:
                    catalog_resolutions.append({
                        "requested_name": name,
                        "catalog_id": catalog_match.item.master_id,
                        "catalog_name": catalog_match.item.names[0] if catalog_match.item.names else name,
                        "price": price,
                        "unit": unit,
                        "match_source": catalog_match.source,
                    })

            if not normalized_items:
                names = ", ".join(unresolved_items) or "the requested item"
                return {
                    "created": False,
                    "message": f"No price could be resolved for {names}. Search the inventory or ask the owner for a price.",
                    "unresolved_items": unresolved_items,
                }

            final_total = round(sum(it["total"] for it in normalized_items), 2)

            try:
                payload = BillCreate.model_validate({
                    "items": normalized_items,
                    "total_amount": final_total,
                    "customer_phone": customer_phone,
                    "customer_name": customer_name,
                    "payment_method": payment_method,
                    "verified_customer_id": verified_customer_id,
                })
            except Exception as err:
                return {"created": False, "message": f"The proposed bill has invalid data: {err}"}

            if payload.payment_method == "udhaar":
                # A spoken name alone is never enough to charge an account.
                # Resolve the exact tenant-scoped verified customer now so the
                # final bill and ledger entry are linked atomically later.
                customer_repository = VerifiedCustomerRepository(session)
                verified_customer = (
                    await customer_repository.get_by_id(
                        self.tenant, payload.verified_customer_id
                    )
                    if payload.verified_customer_id is not None
                    else await customer_repository.find_by_exact_name(
                        self.tenant, payload.customer_name or ""
                    )
                )
                if verified_customer is None:
                    return {
                        "created": False,
                        "message": "Udhaar needs an exact verified customer. Please select or save the customer first.",
                    }
                payload = payload.model_copy(
                    update={
                        "verified_customer_id": verified_customer.id,
                        "customer_name": verified_customer.name,
                    }
                )

            payload_state = payload.model_dump(mode="json")
            request_signature = json.dumps(
                {
                    "items": payload_state["items"],
                    "customer_phone": payload_state["customer_phone"],
                    "customer_name": payload_state["customer_name"],
                    "payment_method": payload_state["payment_method"],
                    "verified_customer_id": payload_state["verified_customer_id"],
                },
                sort_keys=True,
                separators=(",", ":"),
            )
            async with self._bill_draft_lock:
                now = time.monotonic()
                if (
                    request_signature == self._last_bill_request_signature
                    and self._last_bill_result is not None
                    and now - self._last_bill_request_at < 1.0
                ):
                    # A retried LiveKit turn can call the same tool twice
                    # within milliseconds. Return the original answer without
                    # publishing a second bill draft to the mobile app.
                    return {**self._last_bill_result, "duplicate_suppressed": True}

                draft = await workflow_service.create_bill_draft(session, self.tenant, payload)
                result: dict[str, object] = {
                    "created": True,
                    "draft_id": str(draft.id),
                    "version": draft.version,
                    "expires_at": draft.expires_at.isoformat(),
                    "state": draft.state.model_dump(mode="json"),
                    "customer_verification_suggestion": (
                        draft.customer_verification_suggestion.model_dump(mode="json")
                        if draft.customer_verification_suggestion is not None
                        else None
                    ),
                    "requires_user_confirmation": False,
                    "catalog_resolutions": catalog_resolutions,
                    "unresolved_items": unresolved_items,
                }
                self._last_bill_request_signature = request_signature
                self._last_bill_result = result
                self._last_bill_request_at = now
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

