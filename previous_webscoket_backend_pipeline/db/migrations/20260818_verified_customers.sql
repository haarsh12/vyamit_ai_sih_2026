-- Owner-approved, name-based customer directory for printed bills.
-- Run this once in Supabase SQL Editor for an existing deployment, then
-- deploy the backend. Existing bills are intentionally left unverified.

CREATE TABLE IF NOT EXISTS verified_customers (
    id SERIAL PRIMARY KEY,
    owner_id INTEGER NOT NULL REFERENCES users(id),
    name VARCHAR(100) NOT NULL,
    name_normalized VARCHAR(100) NOT NULL,
    embedding vector(768) NOT NULL,
    verified_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_verified_customers_owner_name UNIQUE (owner_id, name_normalized)
);

ALTER TABLE bills
    ADD COLUMN IF NOT EXISTS verified_customer_id INTEGER
    REFERENCES verified_customers(id);

CREATE INDEX IF NOT EXISTS idx_verified_customers_owner_name
    ON verified_customers (owner_id, name);
CREATE INDEX IF NOT EXISTS idx_bills_verified_customer_id
    ON bills (verified_customer_id);
CREATE INDEX IF NOT EXISTS idx_verified_customers_embedding_ivfflat
    ON verified_customers USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);
