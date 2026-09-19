"""
Database Connection and Session Management
Includes pgvector extension setup
"""
from sqlmodel import SQLModel, create_engine, Session
from sqlalchemy import inspect, text
from dotenv import load_dotenv
import os
from typing import Generator, Optional

from fastapi import HTTPException, status

load_dotenv()

# Get database URL
DATABASE_URL = os.getenv("DATABASE_URL")

# Clean up the URL (strip whitespace, newlines that might come from copy-paste errors)
if DATABASE_URL:
    DATABASE_URL = DATABASE_URL.strip()
    
    # Fix Supabase/Render postgres:// to postgresql://
    if DATABASE_URL.startswith("postgres://"):
        DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)
    
    # Remove unsupported pgbouncer parameter if present (psycopg2 doesn't need it)
    if "?pgbouncer=true" in DATABASE_URL:
        DATABASE_URL = DATABASE_URL.replace("?pgbouncer=true", "")
        print("[INFO] Removed unsupported pgbouncer parameter from DATABASE_URL")

# A missing database must not prevent health checks, OpenAPI, or deployment
# diagnostics from starting.  Protected routes receive a clear 503 until the
# operator configures DATABASE_URL.
DB_CONNECT_TIMEOUT = int(os.getenv("DB_CONNECT_TIMEOUT", "30"))
DB_POOL_TIMEOUT = int(os.getenv("DB_POOL_TIMEOUT", "30"))
engine = None

if DATABASE_URL and DATABASE_URL.strip():
    # Fail fast when a remote database is unavailable. Without an explicit
    # connect timeout, a DNS/network issue can block a worker indefinitely.
    engine = create_engine(
        DATABASE_URL,
        echo=os.getenv("DB_ECHO", "0") in ("1", "true"),
        pool_pre_ping=True,
        pool_recycle=300,
        pool_size=3,
        max_overflow=5,
        pool_timeout=DB_POOL_TIMEOUT,
        connect_args={
            "connect_timeout": DB_CONNECT_TIMEOUT,
            "keepalives": 1,
            "keepalives_idle": 30,
            "keepalives_interval": 10,
            "keepalives_count": 5,
        },
    )


def database_is_configured() -> bool:
    """Return whether an engine can be opened for protected data operations."""
    return engine is not None


def enable_pgvector():
    """Enable pgvector extension in database"""
    if engine is None:
        raise RuntimeError("DATABASE_URL is not configured")
    try:
        with Session(engine) as session:
            session.exec(text("CREATE EXTENSION IF NOT EXISTS vector"))
            session.commit()
            print("[OK] pgvector extension enabled")
    except Exception as e:
        print(f"[WARN] Could not enable pgvector: {e}")
        print("[INFO] Ensure your database supports pgvector extension")


def create_db_and_tables():
    """Create all tables and enable extensions"""
    if engine is None:
        raise RuntimeError("DATABASE_URL is not configured")
    try:
        # Enable pgvector first
        enable_pgvector()
        
        # Upgrade an existing items table before SQLModel creates the new
        # category-scope indexes. New installations have no items table yet,
        # so the helper simply returns and SQLModel creates it from the model.
        _ensure_category_scoped_inventory_schema()
        _ensure_category_scoped_sales_context_schema()
        _ensure_doctor_prescription_schema()
        _ensure_gst_schema()
        # Create additive tables first, then add the foreign-key column to
        # existing bills installations. SQLModel's create_all does not alter
        # legacy tables, hence the narrow guard below.
        SQLModel.metadata.create_all(engine)
        _ensure_verified_customer_schema()
        print("[OK] Database tables created successfully")
    except Exception as e:
        print(f"[ERROR] Database initialization failed: {e}")
        raise


def _ensure_category_scoped_inventory_schema() -> None:
    """Add the inventory namespace to pre-existing PostgreSQL installations.

    The production migration is also checked in under ``db/migrations``.  This
    narrow runtime guard means a deployed instance is not left with code that
    queries a column its older table does not have.  It only backfills when the
    column is first introduced; it never reassigns an existing scope after a
    shop changes category.
    """
    if engine is None or engine.dialect.name != "postgresql":
        return
    inspector = inspect(engine)
    if "items" not in inspector.get_table_names():
        return
    existing_columns = {column["name"] for column in inspector.get_columns("items")}
    if "shop_category" in existing_columns:
        return

    with engine.begin() as connection:
        connection.execute(text("ALTER TABLE items ADD COLUMN shop_category VARCHAR(60)"))
        connection.execute(
            text(
                """
                UPDATE users
                SET shop_category = CASE LOWER(TRIM(COALESCE(shop_category, '')))
                    WHEN 'kirana' THEN 'Kirana'
                    WHEN 'stationery' THEN 'Stationery'
                    WHEN 'stationary' THEN 'Stationery'
                    WHEN 'staationary' THEN 'Stationery'
                    WHEN 'pharmacy' THEN 'Pharmacy'
                    WHEN 'medical' THEN 'Pharmacy'
                    WHEN 'doctor prescription' THEN 'Doctor Prescription'
                    WHEN 'doctor' THEN 'Doctor Prescription'
                    WHEN 'prescription' THEN 'Doctor Prescription'
                    WHEN 'dairy' THEN 'Dairy'
                    WHEN 'hardware' THEN 'Hardware'
                    WHEN 'fast food' THEN 'Fast Food'
                    WHEN 'fastfood' THEN 'Fast Food'
                    WHEN 'restaurant' THEN 'Fast Food'
                    WHEN 'general' THEN 'General'
                    WHEN 'clothing' THEN 'Clothing'
                    WHEN 'other' THEN 'Other'
                    ELSE 'General'
                END
                """
            )
        )
        connection.execute(
            text(
                """
                UPDATE items AS item
                SET shop_category = COALESCE(NULLIF(owner.shop_category, ''), 'General')
                FROM users AS owner
                WHERE item.owner_id = owner.id
                """
            )
        )
        connection.execute(text("UPDATE items SET shop_category = 'General' WHERE shop_category IS NULL"))
        connection.execute(text("ALTER TABLE items ALTER COLUMN shop_category SET DEFAULT 'General'"))
        connection.execute(text("ALTER TABLE items ALTER COLUMN shop_category SET NOT NULL"))
        connection.execute(
            text(
                "CREATE INDEX IF NOT EXISTS idx_items_owner_shop_category "
                "ON items (owner_id, shop_category)"
            )
        )
        connection.execute(
            text(
                "CREATE INDEX IF NOT EXISTS idx_items_owner_shop_category_master "
                "ON items (owner_id, shop_category, master_id)"
            )
        )
    print("[OK] Category-scoped inventory migration applied")


def _ensure_category_scoped_sales_context_schema() -> None:
    """Add category snapshots to existing bills and sale items for RAG safety.

    Legacy records are assigned to General instead of being guessed from the
    user's current profile. Dashboard and bill-history endpoints remain shared
    per user; only the AI analytics context filters these immutable snapshots.
    """
    if engine is None or engine.dialect.name != "postgresql":
        return

    inspector = inspect(engine)
    table_names = set(inspector.get_table_names())
    if not {"bills", "sale_items"}.issubset(table_names):
        return

    bill_columns = {column["name"] for column in inspector.get_columns("bills")}
    sale_item_columns = {
        column["name"] for column in inspector.get_columns("sale_items")
    }
    if "shop_category" in bill_columns and "shop_category" in sale_item_columns:
        return

    with engine.begin() as connection:
        if "shop_category" not in bill_columns:
            connection.execute(text("ALTER TABLE bills ADD COLUMN shop_category VARCHAR(60)"))
            connection.execute(text("UPDATE bills SET shop_category = 'General' WHERE shop_category IS NULL"))
            connection.execute(text("ALTER TABLE bills ALTER COLUMN shop_category SET DEFAULT 'General'"))
            connection.execute(text("ALTER TABLE bills ALTER COLUMN shop_category SET NOT NULL"))
            connection.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS idx_bills_owner_shop_category_date "
                    "ON bills (owner_id, shop_category, bill_date)"
                )
            )
        if "shop_category" not in sale_item_columns:
            connection.execute(text("ALTER TABLE sale_items ADD COLUMN shop_category VARCHAR(60)"))
            connection.execute(text("UPDATE sale_items SET shop_category = 'General' WHERE shop_category IS NULL"))
            connection.execute(text("ALTER TABLE sale_items ALTER COLUMN shop_category SET DEFAULT 'General'"))
            connection.execute(text("ALTER TABLE sale_items ALTER COLUMN shop_category SET NOT NULL"))
            connection.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS idx_sale_items_owner_shop_category_date "
                    "ON sale_items (owner_id, shop_category, sale_date)"
                )
            )
    print("[OK] Category-scoped sales context migration applied")


def _ensure_doctor_prescription_schema() -> None:
    """Add doctor-only profile fields to existing PostgreSQL users tables.

    SQLModel creates the separate prescription tables on a new deployment.
    This guard covers upgrades before API code attempts to read the two new
    profile fields.
    """
    if engine is None or engine.dialect.name != "postgresql":
        return
    inspector = inspect(engine)
    if "users" not in inspector.get_table_names():
        return
    columns = {column["name"] for column in inspector.get_columns("users")}
    with engine.begin() as connection:
        if "medical_registration_number" not in columns:
            connection.execute(
                text("ALTER TABLE users ADD COLUMN medical_registration_number VARCHAR(100)")
            )
        if "qualifications" not in columns:
            connection.execute(text("ALTER TABLE users ADD COLUMN qualifications VARCHAR(500)"))
    print("[OK] Doctor prescription profile migration applied")


def _ensure_gst_schema() -> None:
    """Upgrade existing inventory tables before GST APIs read item tax fields.

    New GST tables are created by SQLModel metadata immediately after this
    guard.  This migration only backfills additive fields on old ``items``
    tables and never alters historical non-GST bills.
    """
    if engine is None or engine.dialect.name != "postgresql":
        return
    inspector = inspect(engine)
    if "items" not in inspector.get_table_names():
        return
    columns = {column["name"] for column in inspector.get_columns("items")}
    with engine.begin() as connection:
        if "gst_rate_bps" not in columns:
            connection.execute(text("ALTER TABLE items ADD COLUMN gst_rate_bps INTEGER NOT NULL DEFAULT 0"))
        if "hsn_code" not in columns:
            connection.execute(text("ALTER TABLE items ADD COLUMN hsn_code VARCHAR(16)"))
        if "tax_category" not in columns:
            connection.execute(text("ALTER TABLE items ADD COLUMN tax_category VARCHAR(80)"))
    print("[OK] GST inventory migration applied")


def _ensure_verified_customer_schema() -> None:
    """Add the optional verified-customer link to existing bill tables.

    The new directory table itself is created by SQLModel immediately before
    this guard. Existing bill records remain unverified and untouched; only
    future post-print confirmations add a link.
    """
    if engine is None or engine.dialect.name != "postgresql":
        return
    inspector = inspect(engine)
    if "bills" not in inspector.get_table_names():
        return
    columns = {column["name"] for column in inspector.get_columns("bills")}
    with engine.begin() as connection:
        if "verified_customer_id" not in columns:
            connection.execute(
                text(
                    "ALTER TABLE bills ADD COLUMN verified_customer_id INTEGER "
                    "REFERENCES verified_customers(id)"
                )
            )
        connection.execute(
            text(
                "CREATE INDEX IF NOT EXISTS idx_bills_verified_customer_id "
                "ON bills (verified_customer_id)"
            )
        )
    print("[OK] Verified customer bill-link migration applied")


def get_session() -> Generator[Session, None, None]:
    """Dependency for getting database sessions"""
    if engine is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database is not configured. Set DATABASE_URL and restart the service.",
        )
    with Session(engine) as session:
        yield session
