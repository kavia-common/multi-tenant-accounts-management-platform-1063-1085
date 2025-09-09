-- Contacts Management Module Schema (MySQL)
-- Multi-tenant (tenant_id scoped) with referential integrity to organizations and users
-- This file can be executed after database creation to provision tables.

-- NOTE:
-- - This schema assumes existence of organizations and users tables:
--     organizations(id BIGINT PRIMARY KEY, name ...)
--     users(id BIGINT PRIMARY KEY, organization_id BIGINT NULL, ...)
-- - All business data are tenant-scoped using organizations.id as tenant_id.
-- - created_by, updated_by, deleted_by reference users.id where applicable.

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- Helper: ensure organizations and users exist (soft check via views would fail at runtime if not)
-- We do not create them here to avoid duplicating core auth schema.

-- Categories: Lead, Prospect, Customer, Vendor, plus customizable per tenant
CREATE TABLE IF NOT EXISTS contact_categories (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id     BIGINT UNSIGNED NOT NULL,
  name          VARCHAR(100)    NOT NULL,
  description   VARCHAR(255)    NULL,
  is_system     TINYINT(1)      NOT NULL DEFAULT 0,  -- 1 if default seeded (Lead, Prospect, ...)
  created_by    BIGINT UNSIGNED NULL,
  created_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_by    BIGINT UNSIGNED NULL,
  updated_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT uq_contact_categories_tenant_name UNIQUE (tenant_id, name),
  CONSTRAINT fk_contact_categories_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_contact_categories_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_contact_categories_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Contacts
CREATE TABLE IF NOT EXISTS contacts (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id       BIGINT UNSIGNED NOT NULL,
  -- core fields
  first_name      VARCHAR(100)    NULL,
  last_name       VARCHAR(100)    NULL,
  display_name    VARCHAR(200)    GENERATED ALWAYS AS (TRIM(CONCAT(COALESCE(first_name,''), ' ', COALESCE(last_name,'')))) VIRTUAL,
  email           VARCHAR(190)    NULL,
  phone           VARCHAR(50)     NULL,
  company         VARCHAR(150)    NULL,
  job_title       VARCHAR(100)    NULL,
  address_line1   VARCHAR(150)    NULL,
  address_line2   VARCHAR(150)    NULL,
  city            VARCHAR(100)    NULL,
  state           VARCHAR(100)    NULL,
  postal_code     VARCHAR(20)     NULL,
  country         VARCHAR(100)    NULL,
  -- optional reference to primary category
  category_id     BIGINT UNSIGNED NULL,
  -- flags
  is_active       TINYINT(1)      NOT NULL DEFAULT 1,
  -- audit
  created_by      BIGINT UNSIGNED NULL,
  created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_by      BIGINT UNSIGNED NULL,
  updated_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_by      BIGINT UNSIGNED NULL,
  deleted_at      DATETIME        NULL,
  PRIMARY KEY (id),
  INDEX idx_contacts_tenant (tenant_id),
  INDEX idx_contacts_tenant_email (tenant_id, email),
  INDEX idx_contacts_tenant_phone (tenant_id, phone),
  INDEX idx_contacts_tenant_company (tenant_id, company),
  INDEX idx_contacts_tenant_category (tenant_id, category_id),
  CONSTRAINT fk_contacts_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_contacts_category FOREIGN KEY (category_id) REFERENCES contact_categories(id) ON DELETE SET NULL,
  CONSTRAINT fk_contacts_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_contacts_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_contacts_deleted_by FOREIGN KEY (deleted_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Many-to-many: contacts <-> categories (for multiple categories per contact)
CREATE TABLE IF NOT EXISTS contact_category_map (
  contact_id   BIGINT UNSIGNED NOT NULL,
  category_id  BIGINT UNSIGNED NOT NULL,
  tenant_id    BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (contact_id, category_id),
  INDEX idx_ccm_tenant (tenant_id),
  CONSTRAINT fk_ccm_contact FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE CASCADE,
  CONSTRAINT fk_ccm_category FOREIGN KEY (category_id) REFERENCES contact_categories(id) ON DELETE CASCADE,
  CONSTRAINT fk_ccm_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Tags (free-form labels per tenant)
CREATE TABLE IF NOT EXISTS contact_tags (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id   BIGINT UNSIGNED NOT NULL,
  name        VARCHAR(100)    NOT NULL,
  color       VARCHAR(20)     NULL, -- hex or name
  created_by  BIGINT UNSIGNED NULL,
  created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_by  BIGINT UNSIGNED NULL,
  updated_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT uq_contact_tags_tenant_name UNIQUE (tenant_id, name),
  CONSTRAINT fk_contact_tags_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_contact_tags_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_contact_tags_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Many-to-many: contacts <-> tags
CREATE TABLE IF NOT EXISTS contact_tag_map (
  contact_id BIGINT UNSIGNED NOT NULL,
  tag_id     BIGINT UNSIGNED NOT NULL,
  tenant_id  BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (contact_id, tag_id),
  INDEX idx_ctm_tenant (tenant_id),
  CONSTRAINT fk_ctm_contact FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE CASCADE,
  CONSTRAINT fk_ctm_tag FOREIGN KEY (tag_id) REFERENCES contact_tags(id) ON DELETE CASCADE,
  CONSTRAINT fk_ctm_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Custom Fields (Definitions per tenant)
CREATE TABLE IF NOT EXISTS custom_field_definitions (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id     BIGINT UNSIGNED NOT NULL,
  -- scope/entity
  entity        ENUM('contact') NOT NULL DEFAULT 'contact',
  name          VARCHAR(100)    NOT NULL,  -- internal key
  label         VARCHAR(150)    NOT NULL,
  field_type    ENUM('text','number','date','datetime','boolean','select','multiselect','json') NOT NULL DEFAULT 'text',
  required      TINYINT(1)      NOT NULL DEFAULT 0,
  options_json  JSON            NULL,  -- for select/multiselect
  help_text     VARCHAR(255)    NULL,
  order_index   INT             NOT NULL DEFAULT 0,
  created_by    BIGINT UNSIGNED NULL,
  created_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_by    BIGINT UNSIGNED NULL,
  updated_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT uq_cfd_tenant_entity_name UNIQUE (tenant_id, entity, name),
  CONSTRAINT fk_cfd_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_cfd_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_cfd_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Custom Field Values (EAV style)
CREATE TABLE IF NOT EXISTS custom_field_values (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id        BIGINT UNSIGNED NOT NULL,
  entity           ENUM('contact') NOT NULL DEFAULT 'contact',
  entity_id        BIGINT UNSIGNED NOT NULL, -- contacts.id
  field_definition_id BIGINT UNSIGNED NOT NULL,
  -- store value variants to support indexing and type safety
  value_text       TEXT            NULL,
  value_number     DECIMAL(18,6)   NULL,
  value_date       DATE            NULL,
  value_datetime   DATETIME        NULL,
  value_boolean    TINYINT(1)      NULL,
  value_json       JSON            NULL,
  created_by       BIGINT UNSIGNED NULL,
  created_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_by       BIGINT UNSIGNED NULL,
  updated_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_cfv_tenant_entity (tenant_id, entity, entity_id),
  INDEX idx_cfv_field (field_definition_id),
  CONSTRAINT fk_cfv_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_cfv_field FOREIGN KEY (field_definition_id) REFERENCES custom_field_definitions(id) ON DELETE CASCADE,
  CONSTRAINT fk_cfv_contact FOREIGN KEY (entity_id) REFERENCES contacts(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Timeline / Notes
CREATE TABLE IF NOT EXISTS contact_timeline (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id     BIGINT UNSIGNED NOT NULL,
  contact_id    BIGINT UNSIGNED NOT NULL,
  type          ENUM('note','call','meeting','email','task','status_change','system') NOT NULL DEFAULT 'note',
  title         VARCHAR(200)    NULL,
  content       TEXT            NULL,
  metadata_json JSON            NULL,  -- e.g., call duration, meeting link, email-id
  occurred_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_by    BIGINT UNSIGNED NULL,
  created_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_by    BIGINT UNSIGNED NULL,
  updated_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_ct_tenant_contact (tenant_id, contact_id),
  CONSTRAINT fk_ct_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_ct_contact FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE CASCADE,
  CONSTRAINT fk_ct_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_ct_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Duplicate detection and merge tracking
CREATE TABLE IF NOT EXISTS contact_duplicates (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id       BIGINT UNSIGNED NOT NULL,
  contact_id_1    BIGINT UNSIGNED NOT NULL,
  contact_id_2    BIGINT UNSIGNED NOT NULL,
  similarity      DECIMAL(5,4)    NOT NULL, -- 0.0000 - 1.0000
  reason          VARCHAR(255)    NULL,     -- e.g., "email_match", "name_phone_fuzzy"
  status          ENUM('potential','ignored','merged') NOT NULL DEFAULT 'potential',
  created_by      BIGINT UNSIGNED NULL,
  created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  resolved_by     BIGINT UNSIGNED NULL,
  resolved_at     DATETIME        NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_cd_pair (tenant_id, LEAST(contact_id_1, contact_id_2), GREATEST(contact_id_1, contact_id_2)),
  INDEX idx_cd_tenant_status (tenant_id, status),
  CONSTRAINT fk_cd_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_cd_c1 FOREIGN KEY (contact_id_1) REFERENCES contacts(id) ON DELETE CASCADE,
  CONSTRAINT fk_cd_c2 FOREIGN KEY (contact_id_2) REFERENCES contacts(id) ON DELETE CASCADE,
  CONSTRAINT fk_cd_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_cd_resolved_by FOREIGN KEY (resolved_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS contact_merge_audit (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id        BIGINT UNSIGNED NOT NULL,
  source_contact_id BIGINT UNSIGNED NOT NULL,
  target_contact_id BIGINT UNSIGNED NOT NULL,
  merged_by        BIGINT UNSIGNED NULL,
  merged_at        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  details_json     JSON            NULL, -- which fields won, losing ids, etc.
  PRIMARY KEY (id),
  INDEX idx_cma_tenant_target (tenant_id, target_contact_id),
  CONSTRAINT fk_cma_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_cma_source FOREIGN KEY (source_contact_id) REFERENCES contacts(id) ON DELETE CASCADE,
  CONSTRAINT fk_cma_target FOREIGN KEY (target_contact_id) REFERENCES contacts(id) ON DELETE CASCADE,
  CONSTRAINT fk_cma_merged_by FOREIGN KEY (merged_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Email sync index table (to correlate emails with contacts/timeline)
CREATE TABLE IF NOT EXISTS contact_emails (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id     BIGINT UNSIGNED NOT NULL,
  contact_id    BIGINT UNSIGNED NULL,   -- nullable until matched
  email_address VARCHAR(190)    NOT NULL,
  external_id   VARCHAR(190)    NULL,   -- e.g., provider message id
  subject       VARCHAR(255)    NULL,
  snippet       TEXT            NULL,
  direction     ENUM('inbound','outbound') NOT NULL,
  occurred_at   DATETIME        NOT NULL,
  raw_headers   MEDIUMTEXT      NULL,
  raw_body      MEDIUMTEXT      NULL,
  created_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_by    BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  INDEX idx_ce_tenant_email (tenant_id, email_address),
  INDEX idx_ce_tenant_contact (tenant_id, contact_id),
  CONSTRAINT fk_ce_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_ce_contact FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE SET NULL,
  CONSTRAINT fk_ce_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Import/Export jobs tracking
CREATE TABLE IF NOT EXISTS contact_import_jobs (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id     BIGINT UNSIGNED NOT NULL,
  initiated_by  BIGINT UNSIGNED NULL,
  source        ENUM('csv','xlsx','google','microsoft','other') NOT NULL,
  status        ENUM('pending','running','completed','failed','partial') NOT NULL DEFAULT 'pending',
  total_rows    INT             NULL,
  processed_rows INT            NULL,
  success_count INT             NULL,
  error_count   INT             NULL,
  options_json  JSON            NULL, -- mapping, dedupe strategy, etc.
  started_at    DATETIME        NULL,
  finished_at   DATETIME        NULL,
  created_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_cij_tenant_status (tenant_id, status),
  CONSTRAINT fk_cij_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_cij_user FOREIGN KEY (initiated_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS contact_import_errors (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  import_job_id   BIGINT UNSIGNED NOT NULL,
  row_number      INT             NOT NULL,
  error_message   VARCHAR(500)    NOT NULL,
  raw_row_data    MEDIUMTEXT      NULL,
  created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_cie_job (import_job_id),
  CONSTRAINT fk_cie_job FOREIGN KEY (import_job_id) REFERENCES contact_import_jobs(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Audit logging specific to contacts (in addition to platform-level audit logs)
CREATE TABLE IF NOT EXISTS contact_audit_logs (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id     BIGINT UNSIGNED NOT NULL,
  contact_id    BIGINT UNSIGNED NULL, -- null for bulk operations
  action        ENUM('create','update','delete','restore','merge','import','export') NOT NULL,
  actor_id      BIGINT UNSIGNED NULL,
  details_json  JSON            NULL, -- changed fields, previous values, etc.
  created_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_cal_tenant_contact (tenant_id, contact_id),
  CONSTRAINT fk_cal_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_cal_contact FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE SET NULL,
  CONSTRAINT fk_cal_actor FOREIGN KEY (actor_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Useful views/index hints for advanced search/filtering could be added later.

SET FOREIGN_KEY_CHECKS = 1;
