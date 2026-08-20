"""Authorized, deterministic GST configuration and immutable invoice workflows."""

from __future__ import annotations

from datetime import UTC, date, datetime, time, timedelta
from decimal import Decimal
from typing import Any

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import AuditEvent, GstConfiguration, GstInvoice, GstInvoiceSequence, IdempotencyKey
from app.db.tenant import TenantContext
from app.gst.calculation import calculate_item, calculate_totals, decimal_to_paise, paise_to_rupees, percent_to_basis_points
from app.gst.constants import GST_STATES
from app.gst.validation import validate_state_code, validate_state_matches_code
from app.repositories.gst import GstRepository
from app.schemas.gst import GstConfigurationInput, GstInvoiceDraftRequest


class GstBillingService:
    """The LLM may propose invoice facts; this service owns all legal calculations and writes."""

    @staticmethod
    def _allowed_rates(configuration: GstConfiguration) -> set[int]:
        return {int(value) for value in configuration.allowed_gst_rates_bps}

    @staticmethod
    def _configuration_payload(configuration: GstConfiguration) -> dict[str, Any]:
        rates = sorted({int(value) for value in configuration.allowed_gst_rates_bps})
        return {
            "is_enabled": configuration.is_enabled,
            "verification_status": "verified" if configuration.is_enabled else "disabled",
            "business_name": configuration.business_name,
            "legal_name": configuration.legal_name,
            "gstin": configuration.gstin,
            "address_line": configuration.address_line,
            "city": configuration.city,
            "state": configuration.state,
            "state_code": configuration.state_code,
            "country": configuration.country,
            "pincode": configuration.pincode,
            "contact_number": configuration.contact_number,
            "email": configuration.email,
            "registration_type": configuration.registration_type,
            "invoice_prefix": configuration.invoice_prefix,
            "invoice_terms": configuration.invoice_terms,
            "allowed_gst_rates": [format(Decimal(rate) / Decimal("100"), "f") for rate in rates],
            "bank_name": configuration.bank_name,
            "account_name": configuration.account_name,
            "account_number": configuration.account_number,
            "ifsc": configuration.ifsc,
            "updated_at": configuration.updated_at.isoformat(),
        }

    async def get_configuration(self, session: AsyncSession, tenant: TenantContext) -> dict[str, Any]:
        configuration = await GstRepository(session).configuration(tenant)
        if configuration is None:
            return {"is_enabled": False, "verification_status": "not_configured"}
        return self._configuration_payload(configuration)

    async def save_configuration(
        self, session: AsyncSession, tenant: TenantContext, payload: GstConfigurationInput
    ) -> dict[str, Any]:
        repository = GstRepository(session)
        configuration = await repository.configuration(tenant)
        values = {
            "business_name": payload.business_name.strip(),
            "legal_name": payload.legal_name.strip() if payload.legal_name else None,
            "gstin": payload.gstin,
            "address_line": payload.address_line.strip(),
            "city": payload.city.strip(),
            "state": validate_state_matches_code(payload.state, payload.state_code),
            "state_code": payload.state_code,
            "country": payload.country.strip(),
            "pincode": payload.pincode,
            "contact_number": payload.contact_number.strip() if payload.contact_number else None,
            "email": payload.email.strip().lower() if payload.email else None,
            "registration_type": payload.registration_type,
            "invoice_prefix": payload.invoice_prefix,
            "invoice_terms": payload.invoice_terms.strip() if payload.invoice_terms else None,
            "allowed_gst_rates_bps": [percent_to_basis_points(rate) for rate in payload.allowed_gst_rates],
            "is_enabled": True,
            "bank_name": payload.bank_name.strip() if payload.bank_name else None,
            "account_name": payload.account_name.strip() if payload.account_name else None,
            "account_number": payload.account_number.strip() if payload.account_number else None,
            "ifsc": payload.ifsc.strip().upper() if payload.ifsc else None,
        }
        if configuration is None:
            configuration = GstConfiguration(owner_id=tenant.owner_id, **values)
            session.add(configuration)
        else:
            for field, value in values.items():
                setattr(configuration, field, value)
        session.add(AuditEvent(
            created_at=datetime.now(UTC), owner_id=tenant.owner_id, session_id=tenant.session_id,
            action="gst.configuration.save", outcome="success", metadata_={},
        ))
        await session.commit()
        await session.refresh(configuration)
        return self._configuration_payload(configuration)

    async def disable_configuration(self, session: AsyncSession, tenant: TenantContext) -> dict[str, Any]:
        configuration = await GstRepository(session).configuration(tenant)
        if configuration is None:
            return {"is_enabled": False, "verification_status": "not_configured"}
        configuration.is_enabled = False
        session.add(AuditEvent(
            created_at=datetime.now(UTC), owner_id=tenant.owner_id, session_id=tenant.session_id,
            action="gst.configuration.disable", outcome="success", metadata_={},
        ))
        await session.commit()
        return {"is_enabled": False, "verification_status": "disabled"}

    async def _require_tax_invoice_configuration(
        self, session: AsyncSession, tenant: TenantContext
    ) -> GstConfiguration:
        configuration = await GstRepository(session).configuration(tenant, enabled_only=True)
        if configuration is None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="GST Billing must be enabled and validated in Profile before creating a GST invoice",
            )
        if configuration.registration_type == "composition":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Composition taxpayers must issue a bill of supply; GST tax invoices are unavailable",
            )
        return configuration

    @staticmethod
    def _seller_snapshot(configuration: GstConfiguration, request: GstInvoiceDraftRequest) -> dict[str, Any]:
        seller = {
            "business_name": configuration.business_name, "legal_name": configuration.legal_name,
            "gstin": configuration.gstin, "address_line": configuration.address_line,
            "city": configuration.city, "state": configuration.state, "state_code": configuration.state_code,
            "country": configuration.country, "pincode": configuration.pincode,
            "contact_number": configuration.contact_number, "email": configuration.email,
            "registration_type": configuration.registration_type, "invoice_terms": configuration.invoice_terms,
            "bank_name": configuration.bank_name, "account_name": configuration.account_name,
            "account_number": configuration.account_number, "ifsc": configuration.ifsc,
        }
        if request.seller_override is not None:
            for key, value in request.seller_override.model_dump(exclude_none=True).items():
                seller[key] = value.strip() if isinstance(value, str) else value
            if seller["state_code"] != configuration.state_code:
                raise HTTPException(status_code=422, detail="Seller state code cannot differ from the active GST registration")
            seller["state"] = validate_state_matches_code(seller["state"], seller["state_code"])
        for field in ("bank_name", "account_name", "account_number", "ifsc"):
            value = getattr(request, field)
            if value:
                seller[field] = value.strip()
        return seller

    @staticmethod
    def _customer_snapshot(request: GstInvoiceDraftRequest, seller: dict[str, Any]) -> dict[str, Any]:
        customer = request.customer.model_dump()
        gstin = customer.get("gstin")
        state_code = customer.get("state_code")
        if gstin:
            derived = gstin[:2]
            if state_code and state_code != derived:
                raise HTTPException(status_code=422, detail="Customer GSTIN state code must match the customer state code")
            state_code = derived
        state_code = validate_state_code(state_code or seller["state_code"])
        customer["state_code"] = state_code
        customer["state"] = (
            validate_state_matches_code(customer["state"], state_code)
            if customer.get("state") else GST_STATES[state_code]
        )
        customer["name"] = (customer.get("name") or "Walk-in customer").strip()
        return customer

    async def build_invoice_preview(
        self, session: AsyncSession, tenant: TenantContext, request: GstInvoiceDraftRequest
    ) -> dict[str, Any]:
        if not request.is_gst_invoice:
            raise HTTPException(status_code=422, detail="GST invoice endpoint requires is_gst_invoice=true")
        configuration = await self._require_tax_invoice_configuration(session, tenant)
        seller = self._seller_snapshot(configuration, request)
        customer = self._customer_snapshot(request, seller)
        intra_state = seller["state_code"] == customer["state_code"]
        allowed_rates = self._allowed_rates(configuration)
        trusted_inventory = await GstRepository(session).inventory_by_alias(tenant)
        calculated_items = []
        for source in request.items:
            matched = trusted_inventory.get(source.name.strip().casefold())
            rate_paise = decimal_to_paise(source.rate)
            rate_bps = percent_to_basis_points(source.gst_rate)
            hsn_code, tax_category = source.hsn_code, source.tax_category
            if matched is not None:
                rate_paise = decimal_to_paise(Decimal(matched.price))
                rate_bps = matched.gst_rate_bps
                hsn_code = hsn_code or matched.hsn_code
                tax_category = tax_category or matched.tax_category
            if rate_bps not in allowed_rates:
                raise HTTPException(status_code=422, detail=f"GST rate for '{source.name}' is not enabled in the shop configuration")
            calculated_items.append(calculate_item(
                name=source.name.strip(), quantity=source.quantity, unit=source.unit.strip(),
                rate_paise=rate_paise, gst_rate_bps=rate_bps, hsn_code=hsn_code,
                tax_category=tax_category, intra_state=intra_state,
            ))
        totals = calculate_totals(calculated_items)
        if not customer.get("gstin") and totals.taxable_value_paise >= 5_000_000:
            missing = [label for label, present in (
                ("customer name", customer["name"] not in {"", "Walk-in customer"}),
                ("customer address", customer.get("address_line")), ("customer city", customer.get("city")),
            ) if not present]
            if missing:
                raise HTTPException(status_code=422, detail="Unregistered recipients for taxable supplies of Rs 50,000 or more require " + ", ".join(missing))
        breakdown: dict[str, int] = {}
        for item in calculated_items:
            key = format(Decimal(item.gst_rate_bps) / Decimal("100"), "f")
            breakdown[key] = breakdown.get(key, 0) + item.cgst_amount_paise + item.sgst_amount_paise + item.igst_amount_paise
        issued_date = request.issue_date or date.today()
        return {
            "is_gst_invoice": True, "status": "preview", "seller": seller, "customer": customer,
            "place_of_supply": {"state": GST_STATES[customer["state_code"]], "state_code": customer["state_code"], "tax_type": "CGST_SGST" if intra_state else "IGST"},
            "issue_date": issued_date.isoformat(), "due_date": (request.due_date or issued_date + timedelta(days=30)).isoformat(),
            "payment_method": request.payment_method, "payment_status": request.payment_status,
            "reference_number": request.reference_number, "items": [item.to_dict() for item in calculated_items],
            "totals": totals.to_dict(), "gst_breakdown": {key: paise_to_rupees(value) for key, value in breakdown.items()},
            "bank_details": {key: seller.get(key) for key in ("bank_name", "account_name", "account_number", "ifsc")},
        }

    @staticmethod
    def _financial_year(value: date) -> str:
        start_year = value.year if value.month >= 4 else value.year - 1
        return f"{start_year % 100:02d}-{(start_year + 1) % 100:02d}"

    async def _next_invoice_sequence(self, session: AsyncSession, owner_id: int, series_key: str) -> int:
        now = datetime.now(UTC)
        statement = insert(GstInvoiceSequence).values(
            owner_id=owner_id, financial_year=series_key, next_number=2, created_at=now, updated_at=now
        ).on_conflict_do_update(
            index_elements=["owner_id", "financial_year"],
            set_={"next_number": GstInvoiceSequence.next_number + 1, "updated_at": now},
        ).returning(GstInvoiceSequence.next_number - 1)
        return int((await session.execute(statement)).scalar_one())

    async def finalize_invoice(
        self, session: AsyncSession, tenant: TenantContext, request: GstInvoiceDraftRequest, *, idempotency_key: str
    ) -> dict[str, Any]:
        existing = await session.scalar(select(IdempotencyKey).where(
            IdempotencyKey.owner_id == tenant.owner_id, IdempotencyKey.key == idempotency_key,
            IdempotencyKey.action == "gst.invoice.finalize",
        ).with_for_update())
        if existing is not None:
            if existing.response is not None:
                return existing.response
            raise HTTPException(status_code=409, detail="An invoice request with this idempotency key is still processing")
        request_key = IdempotencyKey(owner_id=tenant.owner_id, key=idempotency_key, action="gst.invoice.finalize")
        session.add(request_key)
        try:
            await session.flush()
        except IntegrityError as error:
            await session.rollback()
            raise HTTPException(status_code=409, detail="Duplicate invoice submission is processing") from error
        preview = await self.build_invoice_preview(session, tenant, request)
        configuration = await self._require_tax_invoice_configuration(session, tenant)
        issued_date = date.fromisoformat(preview["issue_date"])
        sequence = await self._next_invoice_sequence(session, tenant.owner_id, f"C{issued_date.year}")
        invoice_number = f"{configuration.invoice_prefix}-{issued_date.year}-{sequence:05d}"
        financial_year = self._financial_year(issued_date)
        totals = preview["totals"]
        canonical = {**preview, "invoice_number": invoice_number, "financial_year": financial_year, "status": "finalized"}
        invoice = GstInvoice(
            owner_id=tenant.owner_id, configuration_id=configuration.id, invoice_number=invoice_number,
            financial_year=financial_year, reference_number=request.reference_number, status="finalized",
            issued_at=datetime.combine(issued_date, time.min, tzinfo=UTC), invoice=canonical,
            taxable_value_paise=int(totals["taxable_value_paise"]), cgst_amount_paise=int(totals["cgst_amount_paise"]),
            sgst_amount_paise=int(totals["sgst_amount_paise"]), igst_amount_paise=int(totals["igst_amount_paise"]),
            total_tax_paise=int(totals["total_tax_paise"]), grand_total_paise=int(totals["grand_total_paise"]),
        )
        session.add(invoice)
        await session.flush()
        result = {"invoice_id": invoice.id, "invoice": canonical}
        request_key.response, request_key.status_code = result, status.HTTP_201_CREATED
        session.add(AuditEvent(
            created_at=datetime.now(UTC), owner_id=tenant.owner_id, session_id=tenant.session_id,
            action="gst.invoice.finalize", outcome="success", metadata_={"invoice_id": invoice.id},
        ))
        await session.commit()
        return result

    async def get_invoice(self, session: AsyncSession, tenant: TenantContext, invoice_id: int) -> dict[str, Any]:
        invoice = await GstRepository(session).invoice(tenant, invoice_id)
        if invoice is None:
            raise HTTPException(status_code=404, detail="GST invoice not found")
        return {**invoice.invoice, "invoice_id": invoice.id, "status": invoice.status, "printed_at": invoice.printed_at.isoformat() if invoice.printed_at else None}

    async def mark_printed(self, session: AsyncSession, tenant: TenantContext, invoice_id: int) -> dict[str, Any]:
        invoice = await GstRepository(session).invoice(tenant, invoice_id)
        if invoice is None:
            raise HTTPException(status_code=404, detail="GST invoice not found")
        if invoice.printed_at is None:
            invoice.printed_at = datetime.now(UTC)
            invoice.status = "printed"
            session.add(AuditEvent(
                created_at=datetime.now(UTC), owner_id=tenant.owner_id, session_id=tenant.session_id,
                action="gst.invoice.printed", outcome="success", metadata_={"invoice_id": invoice.id},
            ))
            await session.commit()
        return {"invoice_id": invoice.id, "status": invoice.status, "printed_at": invoice.printed_at.isoformat()}


gst_billing_service = GstBillingService()
