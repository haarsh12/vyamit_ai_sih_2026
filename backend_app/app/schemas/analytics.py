"""Bill and analytics request contracts with exact decimal validation."""

from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP

from pydantic import AliasChoices, BaseModel, Field, field_validator, model_validator


MONEY_QUANTUM = Decimal("0.01")


class BillItemInput(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    quantity: Decimal = Field(validation_alias=AliasChoices("quantity", "qty"), gt=0, max_digits=12, decimal_places=3)
    unit: str = Field(default="unit", min_length=1, max_length=30)
    price: Decimal = Field(validation_alias=AliasChoices("price", "rate"), ge=0, max_digits=12, decimal_places=2)
    total: Decimal = Field(validation_alias=AliasChoices("total", "line_total"), ge=0, max_digits=14, decimal_places=2)

    @model_validator(mode="after")
    def ensure_total_matches(self) -> "BillItemInput":
        expected = (self.quantity * self.price).quantize(MONEY_QUANTUM, rounding=ROUND_HALF_UP)
        if expected != self.total.quantize(MONEY_QUANTUM, rounding=ROUND_HALF_UP):
            raise ValueError("total must equal quantity multiplied by price")
        return self


class BillCreate(BaseModel):
    items: list[BillItemInput] = Field(min_length=1, max_length=100)
    total_amount: Decimal = Field(ge=0, max_digits=14, decimal_places=2)
    customer_phone: str | None = Field(default=None, max_length=20)
    customer_name: str | None = Field(default=None, max_length=120)
    payment_method: str = Field(default="cash", min_length=1, max_length=30)
    bill_type: str = Field(default="printed", pattern="^(printed|virtual)$", description="Bill type: 'printed' or 'virtual'")
    billing_source: str = Field(
        default="voice",
        pattern="^(voice|frequent)$",
        description="Billing screen that created the bill",
    )

    @model_validator(mode="after")
    def ensure_grand_total_matches(self) -> "BillCreate":
        expected = sum((item.total for item in self.items), Decimal("0")).quantize(MONEY_QUANTUM, rounding=ROUND_HALF_UP)
        if expected != self.total_amount.quantize(MONEY_QUANTUM, rounding=ROUND_HALF_UP):
            raise ValueError("total_amount must equal the sum of item totals")
        return self

    @field_validator("customer_phone", "customer_name")
    @classmethod
    def normalise_optional_text(cls, value: str | None) -> str | None:
        return value.strip() if value else None
