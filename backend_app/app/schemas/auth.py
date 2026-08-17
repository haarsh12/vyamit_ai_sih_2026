"""Authentication contracts retained for Flutter compatibility."""

from __future__ import annotations

import re

from pydantic import BaseModel, Field, field_validator


def normalise_indian_phone(value: str) -> str:
    cleaned = re.sub(r"[\s()\-]", "", value)
    digits = cleaned[1:] if cleaned.startswith("+") else cleaned
    if digits.startswith("91") and len(digits) == 12:
        digits = digits[2:]
    if not re.fullmatch(r"[6-9]\d{9}", digits):
        raise ValueError("phone_number must be a valid Indian 10-digit mobile number")
    return f"+91{digits}"


class OTPRequest(BaseModel):
    phone_number: str = Field(min_length=10, max_length=20)
    is_login: bool = True

    @field_validator("phone_number")
    @classmethod
    def validate_phone(cls, value: str) -> str:
        return normalise_indian_phone(value)


class VerifyOTPRequest(OTPRequest):
    otp_code: str = Field(min_length=6, max_length=6)
    shop_name: str | None = Field(default=None, max_length=160)
    owner_name: str | None = Field(default=None, max_length=120)
    address: str | None = Field(default=None, max_length=500)
    shop_category: str | None = Field(default=None, max_length=60)


class UpdateProfileRequest(BaseModel):
    shop_name: str | None = Field(default=None, max_length=160)
    owner_name: str | None = Field(default=None, max_length=120)
    address: str | None = Field(default=None, max_length=500)
    phone2: str | None = Field(default=None, max_length=20)
    shop_category: str | None = Field(default=None, max_length=60)
    medical_registration_number: str | None = Field(default=None, max_length=100)
    qualifications: str | None = Field(default=None, max_length=500)

    @field_validator("phone2", "medical_registration_number", "qualifications")
    @classmethod
    def strip_optional_text(cls, value: str | None) -> str | None:
        return value.strip() if value is not None else None
