-- Preserve a server-owned category snapshot on sales data.
-- Dashboard and bill-history endpoints still aggregate every category for a
-- user. RAG analytics filters these snapshots by the active profile category.
-- Legacy records are safely assigned to General instead of inferred.

ALTER TABLE bills ADD COLUMN IF NOT EXISTS shop_category VARCHAR(60);
UPDATE bills SET shop_category = 'General' WHERE shop_category IS NULL;
ALTER TABLE bills
    ALTER COLUMN shop_category SET DEFAULT 'General',
    ALTER COLUMN shop_category SET NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bills_owner_shop_category_date
    ON bills (owner_id, shop_category, bill_date);

ALTER TABLE sale_items ADD COLUMN IF NOT EXISTS shop_category VARCHAR(60);
UPDATE sale_items SET shop_category = 'General' WHERE shop_category IS NULL;
ALTER TABLE sale_items
    ALTER COLUMN shop_category SET DEFAULT 'General',
    ALTER COLUMN shop_category SET NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sale_items_owner_shop_category_date
    ON sale_items (owner_id, shop_category, sale_date);
