"""Pure contracts for security and financial input validation."""

from decimal import Decimal

import pytest
from pydantic import ValidationError

from app.config.settings import Settings
from app.domain.billing_source import billing_source_from_items
from app.schemas.analytics import BillCreate


def test_production_rejects_insecure_cors_and_demo_otp() -> None:
    settings = Settings(
        app_env="production",
        jwt_secret_key="a-sufficiently-long-production-test-secret",
        cors_origins="http://localhost:3000",
        otp_demo_mode=True,
    )

    with pytest.raises(RuntimeError):
        settings.require_api_runtime_security()


def test_production_accepts_explicit_https_origin_and_non_demo_otp() -> None:
    settings = Settings(
        app_env="production",
        jwt_secret_key="a-sufficiently-long-production-test-secret",
        cors_origins="https://app.example.com",
        otp_demo_mode=False,
        log_otp_codes=False,
    )

    settings.require_api_runtime_security()


def test_bill_payload_requires_exact_line_and_grand_totals() -> None:
    payload = BillCreate.model_validate(
        {
            "items": [
                {"name": "Rice", "quantity": "2", "unit": "kg", "price": "45.50", "total": "91.00"},
                {"name": "Oil", "quantity": "1", "unit": "litre", "price": "110", "total": "110.00"},
            ],
            "total_amount": "201.00",
        }
    )

    assert payload.total_amount == Decimal("201.00")
    assert payload.bill_type == "printed"
    assert payload.billing_source == "voice"

    frequent_virtual_payload = BillCreate.model_validate(
        {
            "items": [
                {
                    "name": "Milk",
                    "quantity": "1",
                    "unit": "litre",
                    "price": "30",
                    "total": "30",
                }
            ],
            "total_amount": "30",
            "bill_type": "virtual",
            "billing_source": "frequent",
        }
    )
    assert frequent_virtual_payload.billing_source == "frequent"


def test_billing_source_marker_is_backward_compatible_with_existing_bill_json() -> None:
    assert billing_source_from_items([]) == "voice"
    assert billing_source_from_items([{"name": "Milk"}]) == "voice"
    assert billing_source_from_items([
        {"name": "Milk", "_billing_source": "frequent"},
    ]) == "frequent"

    with pytest.raises(ValidationError):
        BillCreate.model_validate(
            {
                "items": [{"name": "Rice", "quantity": 2, "unit": "kg", "price": 45, "total": 100}],
                "total_amount": 100,
            }
        )
