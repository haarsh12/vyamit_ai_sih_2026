-- GST Billing: additive, backwards-compatible PostgreSQL migration.
-- Existing non-GST bills and inventory remain untouched.

ALTER TABLE items ADD COLUMN IF NOT EXISTS gst_rate_bps INTEGER NOT NULL DEFAULT 0;
ALTER TABLE items ADD COLUMN IF NOT EXISTS hsn_code VARCHAR(16);
ALTER TABLE items ADD COLUMN IF NOT EXISTS tax_category VARCHAR(80);

CREATE TABLE IF NOT EXISTS gst_configurations (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    owner_id INTEGER NOT NULL UNIQUE REFERENCES users(id),
    is_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    business_name VARCHAR(160) NOT NULL,
    legal_name VARCHAR(160),
    gstin VARCHAR(15) NOT NULL,
    address_line VARCHAR(300) NOT NULL,
    city VARCHAR(80) NOT NULL,
    state VARCHAR(80) NOT NULL,
    state_code VARCHAR(2) NOT NULL,
    country VARCHAR(80) NOT NULL DEFAULT 'India',
    pincode VARCHAR(6) NOT NULL,
    contact_number VARCHAR(20),
    email VARCHAR(254),
    registration_type VARCHAR(20) NOT NULL DEFAULT 'regular',
    invoice_prefix VARCHAR(3) NOT NULL DEFAULT 'GST',
    invoice_terms VARCHAR(1000),
    allowed_gst_rates_json TEXT NOT NULL DEFAULT '[0, 500, 1200, 1800, 2800]'
);
CREATE INDEX IF NOT EXISTS ix_gst_configurations_is_enabled ON gst_configurations(is_enabled);
CREATE INDEX IF NOT EXISTS ix_gst_configurations_gstin ON gst_configurations(gstin);

CREATE TABLE IF NOT EXISTS gst_invoice_sequences (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    owner_id INTEGER NOT NULL REFERENCES users(id),
    financial_year VARCHAR(5) NOT NULL,
    next_number INTEGER NOT NULL DEFAULT 1,
    CONSTRAINT uq_gst_sequence_owner_year UNIQUE (owner_id, financial_year)
);

CREATE TABLE IF NOT EXISTS gst_invoices (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    owner_id INTEGER NOT NULL REFERENCES users(id),
    configuration_id INTEGER NOT NULL REFERENCES gst_configurations(id),
    invoice_number VARCHAR(16) NOT NULL,
    financial_year VARCHAR(5) NOT NULL,
    reference_number VARCHAR(50),
    status VARCHAR(20) NOT NULL DEFAULT 'finalized',
    issued_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    printed_at TIMESTAMP,
    invoice_json TEXT NOT NULL,
    taxable_value_paise INTEGER NOT NULL,
    cgst_amount_paise INTEGER NOT NULL,
    sgst_amount_paise INTEGER NOT NULL,
    igst_amount_paise INTEGER NOT NULL,
    total_tax_paise INTEGER NOT NULL,
    grand_total_paise INTEGER NOT NULL,
    CONSTRAINT uq_gst_invoice_owner_number UNIQUE (owner_id, invoice_number)
);
CREATE INDEX IF NOT EXISTS idx_gst_invoices_owner_issued ON gst_invoices(owner_id, issued_at);
CREATE INDEX IF NOT EXISTS ix_gst_invoices_status ON gst_invoices(status);

