"""Migration-owned ORM entities for Vyamit's business and realtime state."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Any
from uuid import UUID, uuid4

from pgvector.sqlalchemy import Vector
from sqlalchemy import (
    JSON,
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin


class User(TimestampMixin, Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    phone_number: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    shop_name: Mapped[str | None] = mapped_column(String(160))
    owner_name: Mapped[str | None] = mapped_column(String(120))
    address: Mapped[str | None] = mapped_column(String(500))
    phone2: Mapped[str | None] = mapped_column(String(20))
    shop_category: Mapped[str] = mapped_column(String(60), index=True, default="General")
    medical_registration_number: Mapped[str | None] = mapped_column(String(100))
    qualifications: Mapped[str | None] = mapped_column(String(500))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    role: Mapped[str] = mapped_column(String(32), default="owner", nullable=False)


class OTP(TimestampMixin, Base):
    __tablename__ = "otps"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    phone_number: Mapped[str] = mapped_column(String(20), index=True)
    code_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    is_used: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    failed_attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    locked_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)


class Item(TimestampMixin, Base):
    __tablename__ = "items"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    master_id: Mapped[str] = mapped_column(String(100), nullable=False)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    names: Mapped[list[str]] = mapped_column(JSON, nullable=False)
    category: Mapped[str] = mapped_column(String(60), nullable=False, default="General")
    shop_category: Mapped[str] = mapped_column(String(60), nullable=False, default="General")
    price: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
    unit: Mapped[str] = mapped_column(String(30), nullable=False)
    gst_rate_bps: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    hsn_code: Mapped[str | None] = mapped_column(String(16))
    tax_category: Mapped[str | None] = mapped_column(String(80))
    # Vertex text-embedding-004 is verified at 768 dimensions before migration.
    embedding: Mapped[list[float] | None] = mapped_column(Vector(768))
    embedding_source_hash: Mapped[str | None] = mapped_column(String(64))
    embedding_model: Mapped[str | None] = mapped_column(String(120))
    embedding_updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    __table_args__ = (
        UniqueConstraint("owner_id", "shop_category", "master_id"),
        CheckConstraint("price >= 0", name="item_price_non_negative"),
        CheckConstraint("gst_rate_bps BETWEEN 0 AND 4000", name="item_gst_rate_range"),
        Index("ix_items_owner_category", "owner_id", "shop_category"),
        Index(
            "ix_items_embedding_hnsw",
            "embedding",
            postgresql_using="hnsw",
            postgresql_ops={"embedding": "vector_cosine_ops"},
        ),
    )


class Bill(TimestampMixin, Base):
    __tablename__ = "bills"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    shop_category: Mapped[str] = mapped_column(String(60), nullable=False, default="General")
    total_amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
    total_items: Mapped[int] = mapped_column(Integer, nullable=False)
    items: Mapped[list[dict[str, Any]]] = mapped_column(JSON, nullable=False)
    customer_phone: Mapped[str | None] = mapped_column(String(20), index=True)
    customer_name: Mapped[str | None] = mapped_column(String(120))
    verified_customer_id: Mapped[int | None] = mapped_column(ForeignKey("verified_customers.id", ondelete="SET NULL"))
    payment_method: Mapped[str] = mapped_column(String(30), nullable=False, default="cash")
    bill_type: Mapped[str] = mapped_column(String(20), nullable=False, default="printed")  # "printed" or "virtual"
    bill_date: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)

    __table_args__ = (
        CheckConstraint("total_amount >= 0", name="bill_total_non_negative"),
        Index("ix_bills_owner_category_date", "owner_id", "shop_category", "bill_date"),
        Index("ix_bills_verified_customer_id", "verified_customer_id"),
        Index("ix_bills_bill_type", "bill_type"),
    )


class SaleItem(TimestampMixin, Base):
    __tablename__ = "sale_items"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    bill_id: Mapped[int] = mapped_column(ForeignKey("bills.id", ondelete="CASCADE"), nullable=False)
    shop_category: Mapped[str] = mapped_column(String(60), nullable=False, default="General")
    item_name: Mapped[str] = mapped_column(String(120), nullable=False)
    item_category: Mapped[str] = mapped_column(String(60), nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Numeric(14, 3), nullable=False)
    unit: Mapped[str] = mapped_column(String(30), nullable=False)
    price_per_unit: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
    total_price: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
    sale_date: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    hour_of_day: Mapped[int] = mapped_column(Integer, nullable=False)

    __table_args__ = (
        CheckConstraint("hour_of_day BETWEEN 0 AND 23", name="sale_item_hour_range"),
        Index("ix_sale_items_owner_category_date", "owner_id", "shop_category", "sale_date"),
    )


class Customer(TimestampMixin, Base):
    __tablename__ = "customers"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    shop_category: Mapped[str] = mapped_column(String(60), nullable=False, default="General")
    phone_number: Mapped[str] = mapped_column(String(20), nullable=False)
    name: Mapped[str | None] = mapped_column(String(120))
    total_bills: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    total_spent: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False, default=0)
    last_purchase_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    __table_args__ = (
        UniqueConstraint(
            "owner_id",
            "shop_category",
            "phone_number",
            name="uq_customers_owner_category_phone",
        ),
        Index("ix_customers_owner_category_name", "owner_id", "shop_category", "name"),
    )


class VerifiedCustomer(TimestampMixin, Base):
    __tablename__ = "verified_customers"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    shop_category: Mapped[str] = mapped_column(String(60), nullable=False)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    phone_number: Mapped[str | None] = mapped_column(String(20))
    name_embedding: Mapped[list[float] | None] = mapped_column(Vector(768))
    embedding_source_hash: Mapped[str | None] = mapped_column(String(64))
    embedding_model: Mapped[str | None] = mapped_column(String(120))
    embedding_updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    total_bills: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    total_spent: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False, default=0)
    last_purchase_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    __table_args__ = (
        UniqueConstraint("owner_id", "shop_category", "name", name="uq_verified_customers_owner_category_name"),
        Index("ix_verified_customers_owner_category", "owner_id", "shop_category"),
        Index("ix_verified_customers_name", "name"),
        Index(
            "ix_verified_customers_embedding_hnsw",
            "name_embedding",
            postgresql_using="hnsw",
            postgresql_ops={"name_embedding": "vector_cosine_ops"},
        ),
    )


class GstConfiguration(TimestampMixin, Base):
    __tablename__ = "gst_configurations"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), unique=True)
    is_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    business_name: Mapped[str] = mapped_column(String(160), nullable=False)
    legal_name: Mapped[str | None] = mapped_column(String(160))
    gstin: Mapped[str] = mapped_column(String(15), nullable=False, index=True)
    address_line: Mapped[str] = mapped_column(String(300), nullable=False)
    city: Mapped[str] = mapped_column(String(80), nullable=False)
    state: Mapped[str] = mapped_column(String(80), nullable=False)
    state_code: Mapped[str] = mapped_column(String(2), nullable=False)
    country: Mapped[str] = mapped_column(String(80), nullable=False, default="India")
    pincode: Mapped[str] = mapped_column(String(6), nullable=False)
    contact_number: Mapped[str | None] = mapped_column(String(20))
    email: Mapped[str | None] = mapped_column(String(254))
    registration_type: Mapped[str] = mapped_column(String(20), nullable=False, default="regular")
    invoice_prefix: Mapped[str] = mapped_column(String(3), nullable=False, default="GST")
    invoice_terms: Mapped[str | None] = mapped_column(String(1000))
    allowed_gst_rates_bps: Mapped[list[int]] = mapped_column(JSON, nullable=False, default=list)
    bank_name: Mapped[str | None] = mapped_column(String(120))
    account_name: Mapped[str | None] = mapped_column(String(120))
    account_number: Mapped[str | None] = mapped_column(String(30))
    ifsc: Mapped[str | None] = mapped_column(String(20))


class GstInvoiceSequence(TimestampMixin, Base):
    __tablename__ = "gst_invoice_sequences"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    financial_year: Mapped[str] = mapped_column(String(8), nullable=False)
    next_number: Mapped[int] = mapped_column(Integer, nullable=False, default=1)

    __table_args__ = (UniqueConstraint("owner_id", "financial_year"),)


class GstInvoice(TimestampMixin, Base):
    __tablename__ = "gst_invoices"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    configuration_id: Mapped[int] = mapped_column(ForeignKey("gst_configurations.id"), nullable=False)
    invoice_number: Mapped[str] = mapped_column(String(24), nullable=False)
    financial_year: Mapped[str] = mapped_column(String(8), nullable=False)
    reference_number: Mapped[str | None] = mapped_column(String(50))
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="finalized")
    issued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    printed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    invoice: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    taxable_value_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    cgst_amount_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    sgst_amount_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    igst_amount_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    total_tax_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    grand_total_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)

    __table_args__ = (
        UniqueConstraint("owner_id", "invoice_number"),
        Index("ix_gst_invoices_owner_issued", "owner_id", "issued_at"),
    )


class DoctorPatient(TimestampMixin, Base):
    __tablename__ = "doctor_patients"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    full_name: Mapped[str] = mapped_column(String(120), nullable=False)
    age: Mapped[int | None] = mapped_column(Integer)
    gender: Mapped[str | None] = mapped_column(String(30))
    phone_number: Mapped[str | None] = mapped_column(String(20))

    __table_args__ = (Index("ix_doctor_patients_owner_name", "owner_id", "full_name"),)


class DoctorPrescription(TimestampMixin, Base):
    __tablename__ = "doctor_prescriptions"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    patient_id: Mapped[int | None] = mapped_column(ForeignKey("doctor_patients.id", ondelete="SET NULL"))
    patient_name: Mapped[str] = mapped_column(String(120), nullable=False)
    patient_age: Mapped[int | None] = mapped_column(Integer)
    patient_gender: Mapped[str | None] = mapped_column(String(30))
    patient_phone: Mapped[str | None] = mapped_column(String(20))
    diagnosis: Mapped[str | None] = mapped_column(String(500))
    additional_notes: Mapped[str | None] = mapped_column(String(1500))
    medications: Mapped[list[dict[str, Any]]] = mapped_column(JSON, nullable=False)
    doctor_name: Mapped[str] = mapped_column(String(120), nullable=False)
    doctor_qualifications: Mapped[str | None] = mapped_column(String(500))
    medical_registration_number: Mapped[str] = mapped_column(String(100), nullable=False)
    signature: Mapped[list[list[list[float]]] | None] = mapped_column(JSON)
    prescribed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    printed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)

    __table_args__ = (
        Index("ix_doctor_prescriptions_owner_printed", "owner_id", "printed_at"),
        Index("ix_doctor_prescriptions_patient_printed", "patient_id", "printed_at"),
    )


class VoiceSession(TimestampMixin, Base):
    __tablename__ = "voice_sessions"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    shop_category: Mapped[str] = mapped_column(String(60), nullable=False)
    room_name: Mapped[str] = mapped_column(String(96), nullable=False, unique=True)
    participant_identity: Mapped[str] = mapped_column(String(128), nullable=False, unique=True)
    status: Mapped[str] = mapped_column(String(24), nullable=False, default="issued")
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    primary_llm: Mapped[str | None] = mapped_column(String(120))
    fallback_used: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    __table_args__ = (Index("ix_voice_sessions_owner_created", "owner_id", "created_at"),)


class WorkflowDraft(TimestampMixin, Base):
    __tablename__ = "workflow_drafts"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    shop_category: Mapped[str] = mapped_column(String(60), nullable=False, default="General")
    voice_session_id: Mapped[UUID | None] = mapped_column(ForeignKey("voice_sessions.id", ondelete="SET NULL"))
    kind: Mapped[str] = mapped_column(String(32), nullable=False)
    state: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    confirmation_status: Mapped[str] = mapped_column(String(24), nullable=False, default="draft")
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)

    __table_args__ = (Index("ix_workflow_drafts_owner_category_kind", "owner_id", "shop_category", "kind"),)


class EmbeddingJob(TimestampMixin, Base):
    __tablename__ = "embedding_jobs"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    entity_type: Mapped[str] = mapped_column(String(32), nullable=False)
    entity_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    operation: Mapped[str] = mapped_column(String(16), nullable=False)
    source_hash: Mapped[str | None] = mapped_column(String(64))
    status: Mapped[str] = mapped_column(String(24), nullable=False, default="pending")
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    available_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    last_error_code: Mapped[str | None] = mapped_column(String(80))

    __table_args__ = (Index("ix_embedding_jobs_status_available", "status", "available_at"),)


class AgentMemory(TimestampMixin, Base):
    __tablename__ = "agent_memory"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    summary: Mapped[str] = mapped_column(Text, nullable=False)
    embedding: Mapped[list[float] | None] = mapped_column(Vector(768))
    source: Mapped[str] = mapped_column(String(32), nullable=False)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    consented_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class AuditEvent(Base):
    __tablename__ = "audit_events"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    owner_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    session_id: Mapped[UUID | None] = mapped_column(ForeignKey("voice_sessions.id", ondelete="SET NULL"))
    action: Mapped[str] = mapped_column(String(80), nullable=False)
    outcome: Mapped[str] = mapped_column(String(32), nullable=False)
    metadata_: Mapped[dict[str, Any]] = mapped_column("metadata", JSON, nullable=False, default=dict)


class IdempotencyKey(TimestampMixin, Base):
    __tablename__ = "idempotency_keys"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    key: Mapped[str] = mapped_column(String(128), nullable=False)
    action: Mapped[str] = mapped_column(String(80), nullable=False)
    response: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    status_code: Mapped[int | None] = mapped_column(Integer)

    __table_args__ = (UniqueConstraint("owner_id", "key", "action"),)
