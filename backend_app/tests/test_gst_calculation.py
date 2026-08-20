from decimal import Decimal

from app.gst.calculation import calculate_item, calculate_totals, decimal_to_paise


def test_intra_state_gst_splits_tax_evenly() -> None:
    totals = calculate_totals([calculate_item(
        name="Tea", quantity=Decimal("2"), unit="cup", rate_paise=decimal_to_paise(Decimal("100")),
        gst_rate_bps=500, hsn_code=None, intra_state=True,
    )])
    assert totals.taxable_value_paise == 20_000
    assert totals.cgst_amount_paise == 500
    assert totals.sgst_amount_paise == 500
    assert totals.igst_amount_paise == 0
    assert totals.grand_total_paise == 21_000


def test_inter_state_gst_uses_igst() -> None:
    totals = calculate_totals([calculate_item(
        name="Tea", quantity=Decimal("1"), unit="cup", rate_paise=decimal_to_paise(Decimal("100")),
        gst_rate_bps=1800, hsn_code=None, intra_state=False,
    )])
    assert totals.cgst_amount_paise == 0
    assert totals.sgst_amount_paise == 0
    assert totals.igst_amount_paise == 1_800
