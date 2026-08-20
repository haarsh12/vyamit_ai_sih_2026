"""GST API request models. Totals are intentionally absent from client inputs."""

from __future__ import annotations

import re
from datetime import date
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

from app.gst.validation import (
    validate_gstin,
    validate_gstin_matches_state,
    validate_state_code,
    validate_state_matches_code,
)


class GstConfigurationInput(BaseModel):
    business_name: str = Field(min_length=2, max_length=160)
    legal_name: str | None = Field(default=None, max_length=160)
    gstin: str = Field(min_length=15, max_length=20)
    address_line: str = Field(min_length=5, max_length=300)
    city: str = Field(min_length=2, max_length=80)
    state: str = Field(min_length=2, max_length=80)
    state_code: str = Field(min_length=2, max_length=2)
    country: str = Field(default="India", min_length=2, max_length=80)
    pincode: str = Field(pattern=r"^\d{6}$")
    contact_number: str | None = Field(default=None, max_length=20)
    email: str | None = Field(default=None, max_length=254)
    registration_type: Literal["regular", "composition", "casual", "special"] = "regular"
    invoice_prefix: str = Field(default="GST", min_length=1, max_length=3)
    invoice_terms: str | None = Field(default=None, max_length=1000)
    allowed_gst_rates: list[Decimal] = Field(
        default_factory=lambda: [Decimal("0"), Decimal("5"), Decimal("12"), Decimal("18"), Decimal("28")],
        min_length=1,
        max_length=10,
    )
    bank_name: str | None = Field(default=None, max_length=120)
    account_name: str | None = Field(default=None, max_length=120)
    account_number: str | None = Field(default=None, max_length=30)
    ifsc: str | None = Field(default=None, max_length=20)

    @field_validator("gstin")
    @classmethod
    def gstin_is_structurally_valid(cls, value: str) -> str:
        return validate_gstin(value)

    @field_validator("state_code")
    @classmethod
    def state_code_is_known(cls, value: str) -> str:
        return validate_state_code(value)

    @field_validator("invoice_prefix")
    @classmethod
    def invoice_prefix_is_safe(cls, value: str) -> str:
        result = value.strip().upper()
        if not re.fullmatch(r"[A-Z0-9]{1,3}", result):
            raise ValueError("invoice_prefix must be 1 to 3 letters or digits")
        return result

    @field_validator("allowed_gst_rates")
    @classmethod
    def gst_rates_are_supported(cls, value: list[Decimal]) -> list[Decimal]:
        rates = sorted({rate.quantize(Decimal("0.01")) for rate in value})
        if any(rate < 0 or rate > 40 for rate in rates):
            raise ValueError("GST rates must be between 0 and 40 percent")
        return rates

    @model_validator(mode="after")
    def gstin_and_state_are_consistent(self) -> "GstConfigurationInput":
        validate_gstin_matches_state(self.gstin, self.state_code)
        self.state = validate_state_matches_code(self.state, self.state_code)
        return self


class GstCustomerInput(BaseModel):
    name: str | None = Field(default=None, max_length=120)
    gstin: str | None = Field(default=None, max_length=20)
    address_line: str | None = Field(default=None, max_length=300)
    city: str | None = Field(default=None, max_length=80)
    state: str | None = Field(default=None, max_length=80)
    state_code: str | None = Field(default=None, max_length=2)
    pincode: str | None = Field(default=None, pattern=r"^\d{6}$")
    phone: str | None = Field(default=None, max_length=20)

    @field_validator("gstin")
    @classmethod
    def optional_gstin_is_valid(cls, value: str | None) -> str | None:
        return validate_gstin(value) if value and value.strip() else None

    @field_validator("state_code")
    @classmethod
    def optional_state_code_is_valid(cls, value: str | None) -> str | None:
        return validate_state_code(value) if value and value.strip() else None


class GstInvoiceItemInput(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    quantity: Decimal = Field(gt=0, max_digits=12, decimal_places=3)
    unit: str = Field(default="unit", min_length=1, max_length=30)
    rate: Decimal = Field(ge=0, max_digits=12, decimal_places=2)
    gst_rate: Decimal = Field(ge=0, le=40, max_digits=4, decimal_places=2)
    hsn_code: str | None = Field(default=None, max_length=16)
    tax_category: str | None = Field(default=None, max_length=80)

    @field_validator("hsn_code")
    @classmethod
    def hsn_code_is_safe(cls, value: str | None) -> str | None:
        if not value:
            return None
        code = value.strip().upper()
        if not re.fullmatch(r"[A-Z0-9-]{4,16}", code):
            raise ValueError("HSN/SAC must contain 4 to 16 letters, numbers, or hyphens")
        return code


class GstSellerOverrideInput(BaseModel):
    business_name: str | None = Field(default=None, max_length=160)
    legal_name: str | None = Field(default=None, max_length=160)
    address_line: str | None = Field(default=None, max_length=300)
    city: str | None = Field(default=None, max_length=80)
    state: str | None = Field(default=None, max_length=80)
    state_code: str | None = Field(default=None, max_length=2)
    country: str | None = Field(default=None, max_length=80)
    pincode: str | None = Field(default=None, pattern=r"^\d{6}$")
    contact_number: str | None = Field(default=None, max_length=20)
    email: str | None = Field(default=None, max_length=254)
    invoice_terms: str | None = Field(default=None, max_length=1000)
    bank_name: str | None = Field(default=None, max_length=120)
    account_name: str | None = Field(default=None, max_length=120)
    account_number: str | None = Field(default=None, max_length=30)
    ifsc: str | None = Field(default=None, max_length=20)

    @field_validator("state_code")
    @classmethod
    def optional_seller_state_code_is_valid(cls, value: str | None) -> str | None:
        return validate_state_code(value) if value else None


class GstInvoiceDraftRequest(BaseModel):
    is_gst_invoice: bool = True
    customer: GstCustomerInput = Field(default_factory=GstCustomerInput)
    seller_override: GstSellerOverrideInput | None = None
    items: list[GstInvoiceItemInput] = Field(min_length=1, max_length=100)
    issue_date: date | None = None
    due_date: date | None = None
    payment_method: str = Field(default="cash", min_length=1, max_length=30)
    payment_status: Literal["PAID", "UNPAID", "PARTIAL"] = "PAID"
    reference_number: str | None = Field(default=None, max_length=50)
    bank_name: str | None = Field(default=None, max_length=120)
    account_name: str | None = Field(default=None, max_length=120)
    account_number: str | None = Field(default=None, max_length=30)
    ifsc: str | None = Field(default=None, max_length=20)

    @model_validator(mode="after")
    def due_date_cannot_precede_issue_date(self) -> "GstInvoiceDraftRequest":
        if self.issue_date and self.due_date and self.due_date < self.issue_date:
            raise ValueError("due_date cannot be before issue_date")
        return self


class GstPrintConfirmationRequest(BaseModel):
    print_reference: str | None = Field(default=None, max_length=80)
