-- Add bank details columns to gst_configurations table
-- Date: 2026-08-12

ALTER TABLE gst_configurations 
ADD COLUMN IF NOT EXISTS bank_name VARCHAR(120),
ADD COLUMN IF NOT EXISTS account_name VARCHAR(120),
ADD COLUMN IF NOT EXISTS account_number VARCHAR(30),
ADD COLUMN IF NOT EXISTS ifsc VARCHAR(20);

-- Add comment
COMMENT ON COLUMN gst_configurations.bank_name IS 'Bank name for GST invoice';
COMMENT ON COLUMN gst_configurations.account_name IS 'Account holder name';
COMMENT ON COLUMN gst_configurations.account_number IS 'Bank account number';
COMMENT ON COLUMN gst_configurations.ifsc IS 'IFSC code for bank';

