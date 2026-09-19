"""GST configuration and immutable invoice orchestration."""

from __future__ import annotations

from datetime import date, datetime, timedelta
from decimal import Decimal
import json
from typing import Any

from fastapi import HTTPException, status
from sqlalchemy import text
from sqlmodel import Session, select

from core.shop_categories import stored_category
from db.models import GstConfiguration, GstInvoice, Item, User

from .calculation import (
    calculate_item,
    calculate_totals,
    decimal_to_paise,
    percent_to_basis_points,
    paise_to_rupees,
)
from .constants import GST_STATES
from .schemas import GstConfigurationInput, GstInvoiceDraftRequest
from .validation import (
    validate_gstin_matches_state,
    validate_state_code,
    validate_state_matches_code,
)


class GstBillingService:
    """Coordinates validation and persistence without leaking GST identifiers."""

    @staticmethod
    def _require_active_user(session: Session, user_id: int) -> User:
        user = session.get(User, user_id)
        if user is None or not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Account is unavailable",
            )
        return user

    @staticmethod
    def _allowed_rates(configuration: GstConfiguration) -> set[int]:
        try:
            parsed = json.loads(configuration.allowed_gst_rates_json)
            return {int(value) for value in parsed}
        except (TypeError, ValueError, json.JSONDecodeError):
            return {0}

    @staticmethod
    def _configuration_payload(configuration: GstConfiguration) -> dict[str, Any]:
        allowed_rates_bps = sorted(GstBillingService._allowed_rates(configuration))
        return {
            "is_enabled": configuration.is_enabled,
            "can_issue_tax_invoice": configuration.is_enabled
            and configuration.registration_type != "composition",
            "verification_status": "format_validated" if configuration.is_enabled else "not_configured",
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
            "allowed_gst_rates": [
                format(Decimal(rate) / Decimal("100"), "f") for rate in allowed_rates_bps
            ],
            # bank details for printing
            "bank_name": configuration.bank_name,
            "account_name": configuration.account_name,
            "account_number": configuration.account_number,
            "ifsc": configuration.ifsc,
            "updated_at": configuration.updated_at.isoformat(),
        }

    def get_configuration(self, session: Session, user_id: int) -> dict[str, Any]:
        self._require_active_user(session, user_id)
        configuration = session.exec(
            select(GstConfiguration).where(GstConfiguration.owner_id == user_id)
        ).first()
        if configuration is None:
            return {"is_enabled": False, "verification_status": "not_configured"}
        return self._configuration_payload(configuration)

    def save_configuration(
        self, session: Session, user_id: int, payload: GstConfigurationInput
    ) -> dict[str, Any]:
        self._require_active_user(session, user_id)
        configuration = session.exec(
            select(GstConfiguration).where(GstConfiguration.owner_id == user_id)
        ).first()
        allowed_rates_bps = [
            percent_to_basis_points(rate) for rate in payload.allowed_gst_rates
        ]
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
            "allowed_gst_rates_json": json.dumps(allowed_rates_bps),
            "is_enabled": True,
            "updated_at": datetime.utcnow(),
            # bank details
            "bank_name": payload.bank_name.strip() if payload.bank_name else None,
            "account_name": payload.account_name.strip() if payload.account_name else None,
            "account_number": payload.account_number.strip() if payload.account_number else None,
            "ifsc": payload.ifsc.strip() if payload.ifsc else None,
        }
        if configuration is None:
            configuration = GstConfiguration(owner_id=user_id, **values)
        else:
            for field, value in values.items():
                setattr(configuration, field, value)
        session.add(configuration)
        session.commit()
        session.refresh(configuration)
        return self._configuration_payload(configuration)

    def disable_configuration(self, session: Session, user_id: int) -> dict[str, Any]:
        self._require_active_user(session, user_id)
        configuration = session.exec(
            select(GstConfiguration).where(GstConfiguration.owner_id == user_id)
        ).first()
        if configuration is None:
            return {"is_enabled": False, "verification_status": "not_configured"}
        configuration.is_enabled = False
        configuration.updated_at = datetime.utcnow()
        session.add(configuration)
        session.commit()
        return {"is_enabled": False, "verification_status": "disabled"}

    def require_enabled_configuration(self, session: Session, user_id: int) -> GstConfiguration:
        self._require_active_user(session, user_id)
        configuration = session.exec(
            select(GstConfiguration).where(
                GstConfiguration.owner_id == user_id,
                GstConfiguration.is_enabled.is_(True),
            )
        ).first()
        if configuration is None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="GST Billing must be enabled and validated in Profile before creating a GST invoice",
            )
        return configuration

    def require_tax_invoice_configuration(self, session: Session, user_id: int) -> GstConfiguration:
        configuration = self.require_enabled_configuration(session, user_id)
        if configuration.registration_type == "composition":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Composition taxpayers must issue a bill of supply; GST tax invoices are unavailable",
            )
        return configuration

    @staticmethod
    def _seller_snapshot(
        configuration: GstConfiguration, request: GstInvoiceDraftRequest
    ) -> dict[str, Any]:
        seller = {
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
            "invoice_terms": configuration.invoice_terms,
            # bank details from config
            "bank_name": configuration.bank_name,
            "account_name": configuration.account_name,
            "account_number": configuration.account_number,
            "ifsc": configuration.ifsc,
        }
        if request.seller_override is not None:
            for key, value in request.seller_override.model_dump(exclude_none=True).items():
                seller[key] = value.strip() if isinstance(value, str) else value
            if seller["state_code"] != configuration.state_code:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="Seller state code cannot differ from the active GST registration",
                )
            try:
                seller["state"] = validate_state_matches_code(
                    seller["state"], seller["state_code"]
                )
            except ValueError as exc:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)
                ) from exc
        # Allow request-level bank details to override config
        for bank_field in ("bank_name", "account_name", "account_number", "ifsc"):
            val = getattr(request, bank_field, None)
            if val:
                seller[bank_field] = val.strip()
        return seller

    @staticmethod
    def _customer_snapshot(request: GstInvoiceDraftRequest, seller: dict[str, Any]) -> dict[str, Any]:
        customer = request.customer.model_dump()
        gstin = customer.get("gstin")
        state_code = customer.get("state_code")
        if gstin:
            derived_state_code = gstin[:2]
            if state_code and state_code != derived_state_code:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="Customer GSTIN state code must match the customer state code",
                )
            state_code = derived_state_code
        state_code = validate_state_code(state_code or seller["state_code"])
        customer["state_code"] = state_code
        try:
            customer["state"] = (
                validate_state_matches_code(customer["state"], state_code)
                if customer.get("state")
                else GST_STATES[state_code]
            )
        except ValueError as exc:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)
            ) from exc
        customer["name"] = (customer.get("name") or "Walk-in customer").strip()
        return customer

    @staticmethod
    def _trusted_inventory_by_name(
        session: Session, user_id: int, shop_category: str
    ) -> dict[str, Item]:
        items = session.exec(
            select(Item).where(
                Item.owner_id == user_id,
                Item.shop_category == shop_category,
            )
        ).all()
        result: dict[str, Item] = {}
        for item in items:
            try:
                for name in json.loads(item.names):
                    result.setdefault(str(name).strip().casefold(), item)
            except (TypeError, json.JSONDecodeError):
                continue
        return result

    def build_invoice_preview(
        self, session: Session, user_id: int, request: GstInvoiceDraftRequest
    ) -> dict[str, Any]:
        if not request.is_gst_invoice:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="GST invoice endpoint requires is_gst_invoice=true",
            )
        configuration = self.require_tax_invoice_configuration(session, user_id)
        user = self._require_active_user(session, user_id)
        seller = self._seller_snapshot(configuration, request)
        customer = self._customer_snapshot(request, seller)
        intra_state = seller["state_code"] == customer["state_code"]
        allowed_rates = self._allowed_rates(configuration)
        trusted_inventory = self._trusted_inventory_by_name(
            session, user_id, stored_category(user.shop_category)
        )
        calculated_items = []
        for source_item in request.items:
            gst_rate_bps = percent_to_basis_points(source_item.gst_rate)
            matched = trusted_inventory.get(source_item.name.strip().casefold())
            rate_paise = decimal_to_paise(source_item.rate)
            hsn_code = source_item.hsn_code
            tax_category = source_item.tax_category
            if matched is not None:
                rate_paise = decimal_to_paise(Decimal(str(matched.price)))
                gst_rate_bps = matched.gst_rate_bps
                hsn_code = hsn_code or matched.hsn_code
                tax_category = tax_category or matched.tax_category
            if gst_rate_bps not in allowed_rates:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"GST rate for '{source_item.name}' is not enabled in the shop configuration",
                )
            try:
                calculated_items.append(
                    calculate_item(
                        name=source_item.name.strip(),
                        quantity=source_item.quantity,
                        unit=source_item.unit.strip(),
                        rate_paise=rate_paise,
                        gst_rate_bps=gst_rate_bps,
                        hsn_code=hsn_code,
                        tax_category=tax_category,
                        intra_state=intra_state,
                    )
                )
            except ValueError as exc:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)
                ) from exc
        totals = calculate_totals(calculated_items)

        # GST breakdown per rate
        gst_breakdown: dict[str, int] = {}
        for item in calculated_items:
            rate_key = format(Decimal(item.gst_rate_bps) / Decimal("100"), "f")
            tax_amount = item.cgst_amount_paise + item.sgst_amount_paise + item.igst_amount_paise
            gst_breakdown[rate_key] = gst_breakdown.get(rate_key, 0) + tax_amount

        if not customer.get("gstin") and totals.taxable_value_paise >= 5_000_000:
            missing_recipient_details = [
                label
                for label, value in (
                    ("customer name", customer.get("name") not in {"", "Walk-in customer"}),
                    ("customer address", customer.get("address_line")),
                    ("customer city", customer.get("city")),
                )
                if not value
            ]
            if missing_recipient_details:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="Unregistered recipients for taxable supplies of Rs 50,000 or more require "
                    + ", ".join(missing_recipient_details),
                )
        issued_date = request.issue_date or date.today()
        due_date = request.due_date or (issued_date + timedelta(days=30))
        bank_details = {
            "bank_name": seller.get("bank_name"),
            "account_name": seller.get("account_name"),
            "account_number": seller.get("account_number"),
            "ifsc": seller.get("ifsc"),
        }
        return {
            "is_gst_invoice": True,
            "status": "preview",
            "seller": seller,
            "customer": customer,
            "place_of_supply": {
                "state": GST_STATES[customer["state_code"]],
                "state_code": customer["state_code"],
                "tax_type": "CGST_SGST" if intra_state else "IGST",
            },
            "issue_date": issued_date.isoformat(),
            "due_date": due_date.isoformat(),
            "payment_method": request.payment_method,
            "payment_status": request.payment_status,
            "reference_number": request.reference_number,
            "items": [item.to_dict() for item in calculated_items],
            "totals": totals.to_dict(),
            "gst_breakdown": {k: paise_to_rupees(v) for k, v in gst_breakdown.items()},
            "bank_details": bank_details,
        }

    @staticmethod
    def _financial_year(value: date) -> str:
        start_year = value.year if value.month >= 4 else value.year - 1
        return f"{start_year % 100:02d}-{(start_year + 1) % 100:02d}"

    @staticmethod
    def _next_invoice_sequence(session: Session, user_id: int, series_key: str) -> int:
        """Atomically reserve one serial in PostgreSQL (also SQLite-compatible).

        The invoice display series is calendar-year based so a configured
        prefix of ``GST`` yields ``GST-2026-00001`` exactly.  It remains
        unique within every financial year (and across the full calendar
        year), while the canonical financial year is stored separately.
        """
        now = datetime.utcnow()
        result = session.execute(
            text(
                """
                INSERT INTO gst_invoice_sequences
                    (owner_id, financial_year, next_number, created_at, updated_at)
                VALUES (:owner_id, :series_key, 2, :now, :now)
                ON CONFLICT (owner_id, financial_year)
                DO UPDATE SET
                    next_number = gst_invoice_sequences.next_number + 1,
                    updated_at = :now
                RETURNING next_number - 1
                """
            ),
            {
                "owner_id": user_id,
                "series_key": series_key,
                "now": now,
            },
        ).scalar_one()
        return int(result)

    def finalize_invoice(
        self, session: Session, user_id: int, request: GstInvoiceDraftRequest
    ) -> dict[str, Any]:
        preview = self.build_invoice_preview(session, user_id, request)
        configuration = self.require_tax_invoice_configuration(session, user_id)
        issued_date = date.fromisoformat(preview["issue_date"])
        financial_year = self._financial_year(issued_date)
        # The serial number is reserved in the same transaction as the
        # immutable snapshot; counting rows would race under concurrent use.
        year_str = str(issued_date.year)
        sequence = self._next_invoice_sequence(session, user_id, f"C{year_str}")
        invoice_number = f"{configuration.invoice_prefix}-{year_str}-{sequence:05d}"
        totals = preview["totals"]
        canonical = {**preview, "invoice_number": invoice_number, "financial_year": financial_year, "status": "finalized"}
        invoice = GstInvoice(
            owner_id=user_id,
            configuration_id=configuration.id,
            invoice_number=invoice_number,
            financial_year=financial_year,
            reference_number=request.reference_number,
            status="finalized",
            issued_at=datetime.combine(issued_date, datetime.min.time()),
            invoice_json=json.dumps(canonical, separators=(",", ":")),
            taxable_value_paise=int(totals["taxable_value_paise"]),
            cgst_amount_paise=int(totals["cgst_amount_paise"]),
            sgst_amount_paise=int(totals["sgst_amount_paise"]),
            igst_amount_paise=int(totals["igst_amount_paise"]),
            total_tax_paise=int(totals["total_tax_paise"]),
            grand_total_paise=int(totals["grand_total_paise"]),
        )
        session.add(invoice)
        session.commit()
        session.refresh(invoice)
        return {"invoice_id": invoice.id, "invoice": canonical}

    def get_invoice(self, session: Session, user_id: int, invoice_id: int) -> dict[str, Any]:
        invoice = session.get(GstInvoice, invoice_id)
        if invoice is None or invoice.owner_id != user_id:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="GST invoice not found")
        payload = json.loads(invoice.invoice_json)
        payload.update(
            {
                "invoice_id": invoice.id,
                "status": invoice.status,
                "printed_at": invoice.printed_at.isoformat() if invoice.printed_at else None,
            }
        )
        return payload

    def mark_printed(self, session: Session, user_id: int, invoice_id: int) -> dict[str, Any]:
        invoice = session.get(GstInvoice, invoice_id)
        if invoice is None or invoice.owner_id != user_id:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="GST invoice not found")
        if invoice.printed_at is None:
            invoice.printed_at = datetime.utcnow()
            invoice.status = "printed"
            invoice.updated_at = datetime.utcnow()
            session.add(invoice)
            session.commit()
        return {"invoice_id": invoice.id, "status": invoice.status, "printed_at": invoice.printed_at.isoformat()}


gst_billing_service = GstBillingService()
