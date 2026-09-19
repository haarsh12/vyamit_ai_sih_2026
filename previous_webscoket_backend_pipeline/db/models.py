"""
Database Models
Clean, secure, and optimized for pgvector
"""
from sqlmodel import SQLModel, Field, Column
from sqlalchemy import Index, UniqueConstraint
from pgvector.sqlalchemy import Vector
from typing import Optional
from datetime import datetime


class TimestampModel(SQLModel):
    """Base model with timestamps for all tables"""
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class User(TimestampModel, table=True):
    """Shop owner/user model"""
    __tablename__ = "users"
    
    id: Optional[int] = Field(default=None, primary_key=True)
    phone_number: str = Field(index=True, unique=True)  # Primary phone (read-only)
    shop_name: Optional[str] = None
    owner_name: Optional[str] = None
    address: Optional[str] = None
    phone2: Optional[str] = None  # Secondary phone (editable)
    shop_category: str = Field(default="General", index=True)
    # Used only by Doctor Prescription mode.  The server snapshots these on
    # print so the client cannot impersonate another clinician.
    medical_registration_number: Optional[str] = Field(default=None, max_length=100)
    qualifications: Optional[str] = Field(default=None, max_length=500)
    is_active: bool = Field(default=True)
    role: str = Field(default="owner")


class OTP(SQLModel, table=True):
    """OTP codes for authentication"""
    __tablename__ = "otps"
    
    id: Optional[int] = Field(default=None, primary_key=True)
    phone_number: str = Field(index=True)
    otp_code: str
    expires_at: datetime
    is_used: bool = Field(default=False)


class Item(TimestampModel, table=True):
    """Inventory items with vector embeddings.

    ``shop_category`` is the inventory namespace.  It is deliberately
    separate from ``category``, which remains the product group shown inside
    the inventory UI (for example, ``Masale`` or ``Plumbing``).
    """
    __tablename__ = "items"
    
    id: Optional[int] = Field(default=None, primary_key=True)
    master_id: str = Field(index=True)  # Frontend master list ID
    names: str  # JSON array of multi-language names
    category: str = Field(index=True)
    shop_category: str = Field(default="General", index=True, max_length=60)
    price: float
    unit: str
    owner_id: Optional[int] = Field(default=None, foreign_key="users.id", index=True)
    # GST metadata is optional for old inventory.  The canonical tax rate is
    # stored as integer basis points (18% == 1800), never as a float.
    gst_rate_bps: int = Field(default=0, ge=0, le=4000)
    hsn_code: Optional[str] = Field(default=None, max_length=16)
    tax_category: Optional[str] = Field(default=None, max_length=80)
    
    # Vector embedding for semantic search (768D for Gemini)
    embedding: Optional[list] = Field(
        default=None,
        sa_column=Column(Vector(768))
    )
    
    __table_args__ = (
        Index(
            "idx_items_owner_shop_category",
            "owner_id",
            "shop_category",
        ),
        Index(
            "idx_items_owner_shop_category_master",
            "owner_id",
            "shop_category",
            "master_id",
        ),
        Index(
            "idx_items_embedding_ivfflat",
            "embedding",
            postgresql_using="ivfflat",
            postgresql_with={"lists": 100},
            postgresql_ops={"embedding": "vector_cosine_ops"}
        ),
    )


class Bill(TimestampModel, table=True):
    """Saved bills shared by a user, with an immutable category snapshot."""
    __tablename__ = "bills"
    
    id: Optional[int] = Field(default=None, primary_key=True)
    owner_id: int = Field(foreign_key="users.id", index=True)
    # Dashboard and bill history aggregate all categories, while AI context
    # filters this snapshot to prevent cross-category sales context.
    shop_category: str = Field(default="General", index=True, max_length=60)
    
    # Bill details
    total_amount: float
    total_items: int
    items_json: str  # JSON array of bill items
    
    # Customer info
    customer_phone: Optional[str] = Field(default=None, index=True)
    customer_name: Optional[str] = None
    # This link is intentionally optional. A spoken or printed name is not a
    # verified customer until the shop owner explicitly confirms it after the
    # bill has printed.
    verified_customer_id: Optional[int] = Field(
        default=None,
        foreign_key="verified_customers.id",
    )
    
    # Metadata
    bill_date: datetime = Field(default_factory=datetime.utcnow, index=True)
    payment_method: Optional[str] = "cash"

    __table_args__ = (
        Index(
            "idx_bills_owner_shop_category_date",
            "owner_id",
            "shop_category",
            "bill_date",
        ),
    )


class SaleItem(TimestampModel, table=True):
    """Individual sale items for analytics and category-scoped AI context."""
    __tablename__ = "sale_items"
    
    id: Optional[int] = Field(default=None, primary_key=True)
    owner_id: int = Field(foreign_key="users.id", index=True)
    bill_id: int = Field(foreign_key="bills.id", index=True)
    shop_category: str = Field(default="General", index=True, max_length=60)
    
    # Item details
    item_name: str
    item_category: str = Field(index=True)
    quantity: float
    unit: str
    price_per_unit: float
    total_price: float
    
    # Analytics
    sale_date: datetime = Field(default_factory=datetime.utcnow, index=True)
    hour_of_day: int = Field(index=True)  # 0-23

    __table_args__ = (
        Index(
            "idx_sale_items_owner_shop_category_date",
            "owner_id",
            "shop_category",
            "sale_date",
        ),
    )


class Customer(TimestampModel, table=True):
    """Customer profiles with purchase history embeddings"""
    __tablename__ = "customers"
    
    id: Optional[int] = Field(default=None, primary_key=True)
    owner_id: int = Field(foreign_key="users.id", index=True)
    
    # Customer info
    phone_number: str = Field(index=True)
    name: Optional[str] = None
    
    # Purchase summary
    total_bills: int = Field(default=0)
    total_spent: float = Field(default=0.0)
    last_purchase_date: Optional[datetime] = None
    
    # Vector embedding for customer purchase patterns (768D)
    embedding: Optional[list] = Field(
        default=None,
        sa_column=Column(Vector(768))
    )

    __table_args__ = (
        Index(
            "idx_customers_owner_phone",
            "owner_id",
            "phone_number",
            unique=True
        ),
        Index(
            "idx_customers_embedding_ivfflat",
            "embedding",
            postgresql_using="ivfflat",
            postgresql_with={"lists": 100},
            postgresql_ops={"embedding": "vector_cosine_ops"}
        ),
    )


class VerifiedCustomer(TimestampModel, table=True):
    """Owner-approved customer directory used for name-based bill retrieval.

    ``customers`` above is retained for backwards compatibility with the old
    phone-number aggregate.  This table is the source of truth for the
    explicit "Verified Customer List" feature: its canonical name is unique
    per shop, its vector represents the name, and bills are linked only after
    the merchant approves the post-print confirmation.
    """

    __tablename__ = "verified_customers"

    id: Optional[int] = Field(default=None, primary_key=True)
    owner_id: int = Field(foreign_key="users.id", index=True)
    name: str = Field(index=True, max_length=100)
    # Case- and whitespace-normalised form used for safe, deterministic
    # de-duplication (for example "Rahul" and " rahul " are one customer).
    name_normalized: str = Field(max_length=100)
    embedding: list = Field(sa_column=Column(Vector(768), nullable=False))
    verified_at: datetime = Field(default_factory=datetime.utcnow, index=True)

    __table_args__ = (
        UniqueConstraint(
            "owner_id",
            "name_normalized",
            name="uq_verified_customers_owner_name",
        ),
        Index("idx_verified_customers_owner_name", "owner_id", "name"),
        Index(
            "idx_verified_customers_embedding_ivfflat",
            "embedding",
            postgresql_using="ivfflat",
            postgresql_with={"lists": 100},
            postgresql_ops={"embedding": "vector_cosine_ops"},
        ),
    )


class DoctorPatient(TimestampModel, table=True):
    """Doctor-owned directory entry, created only after the doctor consents."""
    __tablename__ = "doctor_patients"

    id: Optional[int] = Field(default=None, primary_key=True)
    owner_id: int = Field(foreign_key="users.id", index=True)
    full_name: str = Field(index=True, max_length=120)
    age: Optional[int] = Field(default=None, ge=0, le=130)
    gender: Optional[str] = Field(default=None, max_length=30)
    phone_number: Optional[str] = Field(default=None, max_length=20)

    __table_args__ = (
        Index("idx_doctor_patients_owner_name", "owner_id", "full_name"),
    )


class DoctorPrescription(TimestampModel, table=True):
    """Immutable doctor-owned record, created only once its print succeeds."""
    __tablename__ = "doctor_prescriptions"

    id: Optional[int] = Field(default=None, primary_key=True)
    owner_id: int = Field(foreign_key="users.id", index=True)
    patient_id: Optional[int] = Field(default=None, foreign_key="doctor_patients.id", index=True)

    # Snapshots protect the historical record from later profile edits.
    patient_name: str = Field(max_length=120)
    patient_age: Optional[int] = Field(default=None, ge=0, le=130)
    patient_gender: Optional[str] = Field(default=None, max_length=30)
    patient_phone: Optional[str] = Field(default=None, max_length=20)
    diagnosis: Optional[str] = Field(default=None, max_length=500)
    additional_notes: Optional[str] = Field(default=None, max_length=1500)
    medications_json: str

    doctor_name: str = Field(max_length=120)
    doctor_qualifications: Optional[str] = Field(default=None, max_length=500)
    medical_registration_number: str = Field(max_length=100)
    signature_json: Optional[str] = Field(default=None, max_length=20000)
    prescribed_at: datetime = Field(default_factory=datetime.utcnow, index=True)
    printed_at: datetime = Field(default_factory=datetime.utcnow, index=True)

    __table_args__ = (
        Index("idx_doctor_prescriptions_owner_printed", "owner_id", "printed_at"),
        Index("idx_doctor_prescriptions_patient_printed", "patient_id", "printed_at"),
    )


class GstConfiguration(TimestampModel, table=True):
    """Current seller GST configuration owned by exactly one shop user."""

    __tablename__ = "gst_configurations"

    id: Optional[int] = Field(default=None, primary_key=True)
    owner_id: int = Field(foreign_key="users.id", index=True, unique=True)
    is_enabled: bool = Field(default=False, index=True)
    business_name: str = Field(max_length=160)
    legal_name: Optional[str] = Field(default=None, max_length=160)
    gstin: str = Field(max_length=15, index=True)
    address_line: str = Field(max_length=300)
    city: str = Field(max_length=80)
    state: str = Field(max_length=80)
    state_code: str = Field(max_length=2)
    country: str = Field(default="India", max_length=80)
    pincode: str = Field(max_length=6)
    contact_number: Optional[str] = Field(default=None, max_length=20)
    email: Optional[str] = Field(default=None, max_length=254)
    registration_type: str = Field(default="regular", max_length=20)
    invoice_prefix: str = Field(default="GST", max_length=3)
    invoice_terms: Optional[str] = Field(default=None, max_length=1000)
    allowed_gst_rates_json: str = Field(default="[0, 500, 1200, 1800, 2800]")
    # Optional bank details for printing on tax invoices
    bank_name: Optional[str] = Field(default=None, max_length=120)
    account_name: Optional[str] = Field(default=None, max_length=120)
    account_number: Optional[str] = Field(default=None, max_length=30)
    ifsc: Optional[str] = Field(default=None, max_length=20)


class GstInvoiceSequence(TimestampModel, table=True):
    """Per-shop, per-financial-year counter used for safe GST serial numbers."""

    __tablename__ = "gst_invoice_sequences"

    id: Optional[int] = Field(default=None, primary_key=True)
    owner_id: int = Field(foreign_key="users.id", index=True)
    financial_year: str = Field(max_length=5)
    next_number: int = Field(default=1, ge=1)

    __table_args__ = (
        UniqueConstraint("owner_id", "financial_year", name="uq_gst_sequence_owner_year"),
    )


class GstInvoice(TimestampModel, table=True):
    """Immutable canonical GST invoice snapshot, created only at finalization."""

    __tablename__ = "gst_invoices"

    id: Optional[int] = Field(default=None, primary_key=True)
    owner_id: int = Field(foreign_key="users.id", index=True)
    configuration_id: int = Field(foreign_key="gst_configurations.id", index=True)
    invoice_number: str = Field(max_length=16, index=True)
    financial_year: str = Field(max_length=5, index=True)
    reference_number: Optional[str] = Field(default=None, max_length=50)
    status: str = Field(default="finalized", max_length=20, index=True)
    issued_at: datetime = Field(default_factory=datetime.utcnow, index=True)
    printed_at: Optional[datetime] = Field(default=None, index=True)
    invoice_json: str
    taxable_value_paise: int = Field(ge=0)
    cgst_amount_paise: int = Field(ge=0)
    sgst_amount_paise: int = Field(ge=0)
    igst_amount_paise: int = Field(ge=0)
    total_tax_paise: int = Field(ge=0)
    grand_total_paise: int = Field(ge=0)

    __table_args__ = (
        UniqueConstraint("owner_id", "invoice_number", name="uq_gst_invoice_owner_number"),
        Index("idx_gst_invoices_owner_issued", "owner_id", "issued_at"),
    )
