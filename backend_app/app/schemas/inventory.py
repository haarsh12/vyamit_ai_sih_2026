"""Inventory contracts matching the existing Flutter item model."""

from __future__ import annotations

from decimal import Decimal

from pydantic import BaseModel, Field, field_validator


class ItemBase(BaseModel):
    names: list[str] = Field(min_length=1, max_length=20)
    price: Decimal = Field(ge=0, le=10_000_000)
    unit: str = Field(min_length=1, max_length=30)
    category: str = Field(default="General", min_length=1, max_length=60)
    gst_rate: Decimal = Field(default=0, ge=0, le=40)
    hsn_code: str | None = Field(default=None, max_length=16)
    tax_category: str | None = Field(default=None, max_length=80)

    @field_validator("names")
    @classmethod
    def normalise_names(cls, value: list[str]) -> list[str]:
        names = list(dict.fromkeys(name.strip() for name in value if name and name.strip()))
        if not names:
            raise ValueError("names must contain at least one non-empty value")
        return names


class ItemCreate(ItemBase):
    id: str = Field(min_length=1, max_length=100)


class ItemUpdate(ItemBase):
    pass


class ItemResponse(ItemBase):
    id: str
    master_id: str
    owner_id: int
    shop_category: str

    @classmethod
    def from_entity(cls, item: object) -> "ItemResponse":
        return cls(
            id=getattr(item, "master_id"),
            master_id=getattr(item, "master_id"),
            owner_id=getattr(item, "owner_id"),
            names=getattr(item, "names"),
            price=getattr(item, "price"),
            unit=getattr(item, "unit"),
            category=getattr(item, "category"),
            gst_rate=Decimal(getattr(item, "gst_rate_bps")) / Decimal(100),
            hsn_code=getattr(item, "hsn_code"),
            tax_category=getattr(item, "tax_category"),
            shop_category=getattr(item, "shop_category"),
        )
