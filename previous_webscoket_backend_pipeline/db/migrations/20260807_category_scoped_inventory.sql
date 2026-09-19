-- Category-scoped inventory migration
--
-- Run this once in the Supabase SQL editor before deploying the application
-- version that contains category-scoped inventory.  Existing items inherit
-- their owner's category at the time of the migration.

BEGIN;

ALTER TABLE items ADD COLUMN IF NOT EXISTS shop_category VARCHAR(60);

-- Canonicalise legacy profile spellings before using them to namespace stock.
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
END;

UPDATE items AS item
SET shop_category = COALESCE(NULLIF(owner.shop_category, ''), 'General')
FROM users AS owner
WHERE item.owner_id = owner.id
  AND item.shop_category IS NULL;

UPDATE items
SET shop_category = 'General'
WHERE shop_category IS NULL;

ALTER TABLE items
    ALTER COLUMN shop_category SET DEFAULT 'General',
    ALTER COLUMN shop_category SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_items_owner_shop_category
    ON items (owner_id, shop_category);
CREATE INDEX IF NOT EXISTS idx_items_owner_shop_category_master
    ON items (owner_id, shop_category, master_id);

COMMIT;
