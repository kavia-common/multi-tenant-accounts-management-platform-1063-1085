-- Seed logic for default contact categories for a given tenant
-- Usage: CALL seed_default_contact_categories(<tenant_id>, <user_id_or_null>);
DELIMITER $$

CREATE PROCEDURE IF NOT EXISTS seed_default_contact_categories(
  IN p_tenant_id BIGINT UNSIGNED,
  IN p_user_id BIGINT UNSIGNED
)
BEGIN
  DECLARE cnt INT DEFAULT 0;

  -- Insert if not exists for each category
  IF NOT EXISTS (SELECT 1 FROM contact_categories WHERE tenant_id = p_tenant_id AND name = 'Lead') THEN
    INSERT INTO contact_categories(tenant_id, name, description, is_system, created_by)
    VALUES(p_tenant_id, 'Lead', 'Potential customer at early stage', 1, p_user_id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM contact_categories WHERE tenant_id = p_tenant_id AND name = 'Prospect') THEN
    INSERT INTO contact_categories(tenant_id, name, description, is_system, created_by)
    VALUES(p_tenant_id, 'Prospect', 'Qualified potential customer', 1, p_user_id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM contact_categories WHERE tenant_id = p_tenant_id AND name = 'Customer') THEN
    INSERT INTO contact_categories(tenant_id, name, description, is_system, created_by)
    VALUES(p_tenant_id, 'Customer', 'Paying customer', 1, p_user_id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM contact_categories WHERE tenant_id = p_tenant_id AND name = 'Vendor') THEN
    INSERT INTO contact_categories(tenant_id, name, description, is_system, created_by)
    VALUES(p_tenant_id, 'Vendor', 'Supplier or vendor', 1, p_user_id);
  END IF;
END $$

DELIMITER ;
