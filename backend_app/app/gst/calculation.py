"""Deterministic paise-based GST calculations ported from the tested backend."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from decimal import Decimal, ROUND_HALF_UP
from typing import Iterable


PAISE_PER_RUPEE = Decimal("100")
TAX_RATE_DIVISOR = Decimal("10000")


def decimal_to_paise(value: Decimal) -> int:
    if value < 0:
        raise ValueError("Money values cannot be negative")
    return int((value * PAISE_PER_RUPEE).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def percent_to_basis_points(value: Decimal) -> int:
    if value < 0 or value > 40:
        raise ValueError("GST rate must be between 0 and 40 percent")
    return int((value * Decimal("100")).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def paise_to_rupees(value: int) -> str:
    return format((Decimal(value) / PAISE_PER_RUPEE).quantize(Decimal("0.01")), "f")


@dataclass(frozen=True)
class CalculatedGstItem:
    name: str
    quantity: str
    unit: str
    rate_paise: int
    gst_rate_bps: int
    hsn_code: str | None
    tax_category: str | None
    taxable_value_paise: int
    cgst_rate_bps: int
    cgst_amount_paise: int
    sgst_rate_bps: int
    sgst_amount_paise: int
    igst_rate_bps: int
    igst_amount_paise: int
    total_amount_paise: int

    def to_dict(self) -> dict[str, object]:
        result = asdict(self)
        result.update({
            "rate": paise_to_rupees(self.rate_paise),
            "taxable_value": paise_to_rupees(self.taxable_value_paise),
            "cgst_amount": paise_to_rupees(self.cgst_amount_paise),
            "sgst_amount": paise_to_rupees(self.sgst_amount_paise),
            "igst_amount": paise_to_rupees(self.igst_amount_paise),
            "total_amount": paise_to_rupees(self.total_amount_paise),
            "gst_rate": format(Decimal(self.gst_rate_bps) / Decimal("100"), "f"),
        })
        return result


@dataclass(frozen=True)
class GstInvoiceTotals:
    taxable_value_paise: int
    cgst_amount_paise: int
    sgst_amount_paise: int
    igst_amount_paise: int
    total_tax_paise: int
    grand_total_paise: int

    def to_dict(self) -> dict[str, object]:
        result = asdict(self)
        result.update({
            "taxable_value": paise_to_rupees(self.taxable_value_paise),
            "cgst_amount": paise_to_rupees(self.cgst_amount_paise),
            "sgst_amount": paise_to_rupees(self.sgst_amount_paise),
            "igst_amount": paise_to_rupees(self.igst_amount_paise),
            "total_tax": paise_to_rupees(self.total_tax_paise),
            "grand_total": paise_to_rupees(self.grand_total_paise),
        })
        return result


def calculate_item(
    *, name: str, quantity: Decimal, unit: str, rate_paise: int, gst_rate_bps: int,
    hsn_code: str | None, intra_state: bool, tax_category: str | None = None,
) -> CalculatedGstItem:
    if quantity <= 0:
        raise ValueError("Item quantity must be greater than zero")
    if rate_paise < 0:
        raise ValueError("Item rate cannot be negative")
    if not 0 <= gst_rate_bps <= 4000:
        raise ValueError("GST rate must be between 0 and 40 percent")
    taxable = int((Decimal(rate_paise) * quantity).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
    tax = int((Decimal(taxable) * Decimal(gst_rate_bps) / TAX_RATE_DIVISOR).quantize(
        Decimal("1"), rounding=ROUND_HALF_UP
    ))
    if intra_state:
        cgst = tax // 2
        return CalculatedGstItem(
            name=name, quantity=format(quantity.normalize(), "f"), unit=unit, rate_paise=rate_paise,
            gst_rate_bps=gst_rate_bps, hsn_code=hsn_code, tax_category=tax_category,
            taxable_value_paise=taxable, cgst_rate_bps=gst_rate_bps // 2, cgst_amount_paise=cgst,
            sgst_rate_bps=gst_rate_bps - (gst_rate_bps // 2), sgst_amount_paise=tax - cgst,
            igst_rate_bps=0, igst_amount_paise=0, total_amount_paise=taxable + tax,
        )
    return CalculatedGstItem(
        name=name, quantity=format(quantity.normalize(), "f"), unit=unit, rate_paise=rate_paise,
        gst_rate_bps=gst_rate_bps, hsn_code=hsn_code, tax_category=tax_category,
        taxable_value_paise=taxable, cgst_rate_bps=0, cgst_amount_paise=0, sgst_rate_bps=0,
        sgst_amount_paise=0, igst_rate_bps=gst_rate_bps, igst_amount_paise=tax,
        total_amount_paise=taxable + tax,
    )


def calculate_totals(items: Iterable[CalculatedGstItem]) -> GstInvoiceTotals:
    materialized = list(items)
    taxable = sum(item.taxable_value_paise for item in materialized)
    cgst = sum(item.cgst_amount_paise for item in materialized)
    sgst = sum(item.sgst_amount_paise for item in materialized)
    igst = sum(item.igst_amount_paise for item in materialized)
    total_tax = cgst + sgst + igst
    return GstInvoiceTotals(taxable, cgst, sgst, igst, total_tax, taxable + total_tax)
