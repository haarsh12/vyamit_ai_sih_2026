"""
Pydantic Schemas for API Request/Response
"""
import re

from pydantic import BaseModel, Field, field_validator
from typing import Optional, List
from datetime import datetime


# ---- Authentication Schemas ----

def _normalise_indian_phone(value: str) -> str:
    """Validate common Indian mobile-number input and return E.164 form."""
    cleaned = re.sub(r"[\s()\-]", "", value)
    digits = cleaned[1:] if cleaned.startswith("+") else cleaned
    if digits.startswith("91") and len(digits) == 12:
        digits = digits[2:]
    if not re.fullmatch(r"[6-9]\d{9}", digits):
        raise ValueError("phone_number must be a valid Indian 10-digit mobile number")
    return f"+91{digits}"

class OTPRequest(BaseModel):
    """Request OTP for login/register"""
    phone_number: str = Field(..., min_length=10, max_length=15)
    is_login: bool = True

    @field_validator("phone_number")
    @classmethod
    def validate_phone_number(cls, value: str) -> str:
        return _normalise_indian_phone(value)


class VerifyOTPRequest(BaseModel):
    """Verify OTP and optionally register"""
    phone_number: str = Field(..., min_length=10, max_length=15)
    otp_code: str = Field(..., min_length=6, max_length=6)
    
    # Required for new user registration
    shop_name: Optional[str] = None
    owner_name: Optional[str] = None
    address: Optional[str] = None
    shop_category: Optional[str] = None

    @field_validator("phone_number")
    @classmethod
    def validate_phone_number(cls, value: str) -> str:
        return _normalise_indian_phone(value)


class TokenResponse(BaseModel):
    """JWT token response"""
    access_token: str
    token_type: str = "bearer"
    is_new_user: bool
    
    # User profile
    user_id: int
    shop_name: Optional[str] = None
    owner_name: Optional[str] = None
    address: Optional[str] = None
    phone2: Optional[str] = None
    shop_category: str = "General"
    medical_registration_number: Optional[str] = None
    qualifications: Optional[str] = None


class UpdateProfileRequest(BaseModel):
    """Update user profile"""
    shop_name: Optional[str] = None
    owner_name: Optional[str] = None
    address: Optional[str] = None
    phone2: Optional[str] = None
    shop_category: Optional[str] = None
    medical_registration_number: Optional[str] = Field(default=None, max_length=100)
    qualifications: Optional[str] = Field(default=None, max_length=500)

    @field_validator("medical_registration_number", "qualifications")
    @classmethod
    def strip_optional_text(cls, value: Optional[str]) -> Optional[str]:
        # Keep an explicitly submitted empty string.  This lets a doctor
        # remove an outdated registration number and automatically blocks
        # future prescription printing until a valid replacement is saved.
        return value.strip() if value is not None else None


# ---- Item Schemas ----

class ItemBase(BaseModel):
    """Base item schema"""
    names: List[str] = Field(..., min_length=1, max_length=20)
    price: float = Field(..., ge=0, le=10_000_000)
    unit: str = Field(..., min_length=1, max_length=30)
    category: str = Field(default="General", min_length=1, max_length=60)
    gst_rate: float = Field(default=0, ge=0, le=40)
    hsn_code: Optional[str] = Field(default=None, max_length=16)
    tax_category: Optional[str] = Field(default=None, max_length=80)


class ItemCreate(ItemBase):
    """Create new item"""
    id: str = Field(..., min_length=1, max_length=100)  # master_id from frontend


class ItemUpdate(ItemBase):
    """Update existing item"""
    pass


class ItemResponse(ItemBase):
    """Item response"""
    id: str  # master_id
    owner_id: int
    master_id: str
    # Read-only namespace assigned from the authenticated user's profile.
    # Clients must never choose this value in an item payload.
    shop_category: str
    created_at: datetime
    updated_at: datetime


# ---- Bill Schemas ----

class BillItem(BaseModel):
    """Individual item in a bill"""
    name: str = Field(..., min_length=1, max_length=100)
    quantity: float = Field(..., gt=0, le=100_000)
    unit: str = Field(..., min_length=1, max_length=30)
    price: float = Field(..., ge=0, le=10_000_000)
    total: float = Field(..., ge=0, le=1_000_000_000)


class BillCreate(BaseModel):
    """Create new bill"""
    items: List[BillItem] = Field(..., min_length=1, max_length=100)
    total_amount: float = Field(..., ge=0, le=1_000_000_000)
    customer_phone: Optional[str] = None
    customer_name: Optional[str] = None
    payment_method: Optional[str] = "cash"


class BillResponse(BaseModel):
    """Bill response"""
    id: int
    owner_id: int
    total_amount: float
    total_items: int
    customer_phone: Optional[str] = None
    customer_name: Optional[str] = None
    payment_method: str
    bill_date: datetime
    items: List[BillItem]


class VerifyCustomerBillRequest(BaseModel):
    """Request made after the merchant accepts the post-print prompt."""

    bill_id: int = Field(..., gt=0)


class VerifiedCustomerResponse(BaseModel):
    id: int
    name: str
    bill_count: int
    total_spent: float
    last_purchase_date: Optional[datetime] = None


# ---- Analytics Schemas ----

class AnalyticsPeriod(BaseModel):
    """Analytics time period"""
    days: Optional[int] = 30


class TopItem(BaseModel):
    """Top selling item"""
    name: str
    category: str
    total_quantity: float
    total_revenue: float
    sale_count: int


class PeakHour(BaseModel):
    """Peak sales hour"""
    hour: int
    total_sales: float
    bill_count: int


class AnalyticsResponse(BaseModel):
    """Complete analytics response"""
    period_days: int
    total_revenue: float
    total_bills: int
    average_bill_value: float
    top_items: List[TopItem]
    peak_hours: List[PeakHour]
    category_breakdown: dict


# ---- RAG/Voice Schemas ----

class VoiceQueryRequest(BaseModel):
    """Voice query request"""
    query: str
    include_analytics: bool = True
    include_customers: bool = True


class VoiceQueryResponse(BaseModel):
    """Voice query response"""
    type: str  # BILL, QUERY, ERROR
    items: List[dict]
    msg: str
    should_stop: bool
    metadata: Optional[dict] = None
