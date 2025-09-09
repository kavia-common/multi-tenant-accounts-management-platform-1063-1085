-- Accounting Platform - PostgreSQL Schema
-- Multi-tenant, double-entry bookkeeping with RBAC, AP/AR, cash management, and real-time transaction logging.
-- This schema assumes a core platform with organizations(id) and users(id) tables exist.
-- All business data are tenant-scoped with tenant_id referencing organizations(id).

-- Safety and consistency settings
SET client_min_messages = WARNING;
SET search_path TO public;

-- Use transactional DDL to ensure atomic application
BEGIN;

-- Drop types if exist to allow re-run in dev environments (safe in dev)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'account_type') THEN
    DROP TYPE account_type;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'account_normal_balance') THEN
    DROP TYPE account_normal_balance;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'journal_status') THEN
    DROP TYPE journal_status;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_status') THEN
    DROP TYPE payment_status;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'document_status') THEN
    DROP TYPE document_status;
  END IF;
END $$;

-- Enumerations
CREATE TYPE account_type AS ENUM ('asset','liability','equity','revenue','expense','contra_asset','contra_liability','contra_equity','contra_revenue','contra_expense');
CREATE TYPE account_normal_balance AS ENUM ('debit','credit');
CREATE TYPE journal_status AS ENUM ('draft','posted','void');
CREATE TYPE payment_status AS ENUM ('pending','completed','failed','void');
CREATE TYPE document_status AS ENUM ('draft','issued','partially_paid','paid','void');

-- Organizations and Users references (soft, FK enabled)
-- Note: Ensure organizations(id) and users(id) exist in platform core schema.

-- Tenants meta (optional helper table if platform doesn't exist; not created here)

-- RBAC tables
CREATE TABLE IF NOT EXISTS roles (
  id              BIGSERIAL PRIMARY KEY,
  tenant_id       BIGINT NOT NULL,
  name            VARCHAR(50) NOT NULL,
  description     VARCHAR(255),
  is_system       BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by      BIGINT,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by      BIGINT,
  UNIQUE (tenant_id, name),
  CONSTRAINT fk_roles_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_roles_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_roles_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS permissions (
  id              BIGSERIAL PRIMARY KEY,
  code            VARCHAR(100) NOT NULL UNIQUE,
  description     VARCHAR(255)
);

-- Default permission codes suggestion:
-- 'admin:*', 'accounting:manage', 'accounting:view', 'journal:create','journal:post','journal:void',
-- 'coa:manage','ap:manage','ar:manage','cash:manage','report:view'

CREATE TABLE IF NOT EXISTS role_permissions (
  role_id         BIGINT NOT NULL,
  permission_id   BIGINT NOT NULL,
  PRIMARY KEY (role_id, permission_id),
  CONSTRAINT fk_role_permissions_role FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE,
  CONSTRAINT fk_role_permissions_permission FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS user_roles (
  user_id         BIGINT NOT NULL,
  role_id         BIGINT NOT NULL,
  tenant_id       BIGINT NOT NULL,
  PRIMARY KEY (user_id, role_id, tenant_id),
  CONSTRAINT fk_user_roles_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_user_roles_role FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE,
  CONSTRAINT fk_user_roles_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE
);

-- Chart of Accounts Categories (for grouping)
CREATE TABLE IF NOT EXISTS account_categories (
  id              BIGSERIAL PRIMARY KEY,
  tenant_id       BIGINT NOT NULL,
  name            VARCHAR(100) NOT NULL,
  description     VARCHAR(255),
  parent_id       BIGINT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by      BIGINT,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by      BIGINT,
  UNIQUE (tenant_id, name),
  CONSTRAINT fk_acc_cat_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_acc_cat_parent FOREIGN KEY (parent_id) REFERENCES account_categories(id) ON DELETE SET NULL,
  CONSTRAINT fk_acc_cat_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_acc_cat_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL
);

-- Chart of Accounts
CREATE TABLE IF NOT EXISTS accounts (
  id                BIGSERIAL PRIMARY KEY,
  tenant_id         BIGINT NOT NULL,
  code              VARCHAR(50) NOT NULL,
  name              VARCHAR(150) NOT NULL,
  description       VARCHAR(255),
  type              account_type NOT NULL,
  normal_balance    account_normal_balance NOT NULL,
  category_id       BIGINT,
  parent_id         BIGINT,
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  is_cash           BOOLEAN NOT NULL DEFAULT FALSE, -- mark cash/bank accounts
  currency          VARCHAR(3), -- ISO 4217 code if multi-currency by account
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by        BIGINT,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by        BIGINT,
  UNIQUE (tenant_id, code),
  UNIQUE (tenant_id, name),
  CONSTRAINT fk_accounts_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_accounts_category FOREIGN KEY (category_id) REFERENCES account_categories(id) ON DELETE SET NULL,
  CONSTRAINT fk_accounts_parent FOREIGN KEY (parent_id) REFERENCES accounts(id) ON DELETE SET NULL,
  CONSTRAINT fk_accounts_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_accounts_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT chk_normal_balance_type CHECK (
    (type IN ('asset','expense','contra_liability','contra_equity','contra_revenue') AND normal_balance='debit')
    OR
    (type IN ('liability','equity','revenue','contra_asset','contra_expense') AND normal_balance='credit')
  )
);

-- Fiscal periods (optional but helpful for locking/closing)
CREATE TABLE IF NOT EXISTS fiscal_periods (
  id              BIGSERIAL PRIMARY KEY,
  tenant_id       BIGINT NOT NULL,
  period_name     VARCHAR(50) NOT NULL, -- e.g., 2025-01
  start_date      DATE NOT NULL,
  end_date        DATE NOT NULL,
  is_closed       BOOLEAN NOT NULL DEFAULT FALSE,
  closed_by       BIGINT,
  closed_at       TIMESTAMPTZ,
  UNIQUE (tenant_id, period_name),
  CONSTRAINT fk_fp_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_fp_closed_by FOREIGN KEY (closed_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT chk_fp_dates CHECK (start_date <= end_date)
);

-- Journals (headers)
CREATE TABLE IF NOT EXISTS journal_entries (
  id                BIGSERIAL PRIMARY KEY,
  tenant_id         BIGINT NOT NULL,
  journal_no        VARCHAR(50) NOT NULL, -- sequence per tenant
  status            journal_status NOT NULL DEFAULT 'draft',
  entry_date        DATE NOT NULL,
  period_id         BIGINT,
  description       VARCHAR(255),
  source_module     VARCHAR(50),  -- 'manual','ap','ar','cash','system'
  source_id         BIGINT,       -- reference to invoice/payment/transfer etc.
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by        BIGINT,
  posted_at         TIMESTAMPTZ,
  posted_by         BIGINT,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by        BIGINT,
  UNIQUE (tenant_id, journal_no),
  CONSTRAINT fk_je_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_je_period FOREIGN KEY (period_id) REFERENCES fiscal_periods(id) ON DELETE SET NULL,
  CONSTRAINT fk_je_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_je_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_je_posted_by FOREIGN KEY (posted_by) REFERENCES users(id) ON DELETE SET NULL
);

-- Journal lines
CREATE TABLE IF NOT EXISTS journal_lines (
  id                BIGSERIAL PRIMARY KEY,
  tenant_id         BIGINT NOT NULL,
  journal_entry_id  BIGINT NOT NULL,
  line_no           INT NOT NULL,
  account_id        BIGINT NOT NULL,
  description       VARCHAR(255),
  debit             NUMERIC(18,2) NOT NULL DEFAULT 0,
  credit            NUMERIC(18,2) NOT NULL DEFAULT 0,
  currency          VARCHAR(3),
  amount_currency   NUMERIC(18,2),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by        BIGINT,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by        BIGINT,
  UNIQUE (journal_entry_id, line_no),
  CONSTRAINT fk_jl_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_jl_journal FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE CASCADE,
  CONSTRAINT fk_jl_account FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE RESTRICT,
  CONSTRAINT fk_jl_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_jl_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT chk_debit_credit_nonnegative CHECK (debit >= 0 AND credit >= 0),
  CONSTRAINT chk_debit_xor_credit CHECK (
    (debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0)
  )
);

-- Ensure journal balance at DB level via constraint trigger
CREATE OR REPLACE FUNCTION trg_check_journal_balanced() RETURNS trigger AS $$
DECLARE
  total_debit NUMERIC(30,6);
  total_credit NUMERIC(30,6);
  je_status journal_status;
BEGIN
  SELECT status INTO je_status FROM journal_entries WHERE id = NEW.journal_entry_id FOR UPDATE;
  IF TG_OP IN ('INSERT','UPDATE','DELETE') THEN
    -- Only check on posted
    IF je_status = 'posted' THEN
      SELECT COALESCE(SUM(debit),0), COALESCE(SUM(credit),0)
      INTO total_debit, total_credit
      FROM journal_lines
      WHERE journal_entry_id = NEW.journal_entry_id;
      IF total_debit <> total_credit THEN
        RAISE EXCEPTION 'Journal % not balanced: debit % <> credit %', NEW.journal_entry_id, total_debit, total_credit;
      END IF;
    END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Firing statement-level trigger after any line change and after journal status changes
DROP TRIGGER IF EXISTS journal_lines_balance_insupd ON journal_lines;
CREATE CONSTRAINT TRIGGER journal_lines_balance_insupd
AFTER INSERT OR UPDATE OR DELETE ON journal_lines
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE trg_check_journal_balanced();

-- Trigger to enforce period closure: cannot post to closed period
CREATE OR REPLACE FUNCTION trg_enforce_period_open() RETURNS trigger AS $$
DECLARE
  is_closed BOOLEAN;
  pid BIGINT;
  ed DATE;
BEGIN
  IF TG_TABLE_NAME = 'journal_entries' THEN
    ed := NEW.entry_date;
    pid := NEW.period_id;
  ELSE
    RETURN NEW;
  END IF;

  IF pid IS NOT NULL THEN
    SELECT is_closed INTO is_closed FROM fiscal_periods WHERE id = pid;
    IF is_closed THEN
      RAISE EXCEPTION 'Cannot post to a closed period';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS je_period_check ON journal_entries;
CREATE TRIGGER je_period_check
BEFORE INSERT OR UPDATE ON journal_entries
FOR EACH ROW
EXECUTE PROCEDURE trg_enforce_period_open();

-- General Ledger Balances (running, by period)
CREATE TABLE IF NOT EXISTS gl_balances (
  id              BIGSERIAL PRIMARY KEY,
  tenant_id       BIGINT NOT NULL,
  account_id      BIGINT NOT NULL,
  period_id       BIGINT NOT NULL,
  opening_debit   NUMERIC(18,2) NOT NULL DEFAULT 0,
  opening_credit  NUMERIC(18,2) NOT NULL DEFAULT 0,
  period_debit    NUMERIC(18,2) NOT NULL DEFAULT 0,
  period_credit   NUMERIC(18,2) NOT NULL DEFAULT 0,
  closing_debit   NUMERIC(18,2) NOT NULL DEFAULT 0,
  closing_credit  NUMERIC(18,2) NOT NULL DEFAULT 0,
  UNIQUE (tenant_id, account_id, period_id),
  CONSTRAINT fk_glb_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_glb_account FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE,
  CONSTRAINT fk_glb_period FOREIGN KEY (period_id) REFERENCES fiscal_periods(id) ON DELETE CASCADE
);

-- Real-time transaction log (append-only)
CREATE TABLE IF NOT EXISTS transaction_log (
  id              BIGSERIAL PRIMARY KEY,
  tenant_id       BIGINT NOT NULL,
  event_time      TIMESTAMPTZ NOT NULL DEFAULT now(),
  event_type      VARCHAR(50) NOT NULL, -- 'journal_posted','invoice_created','payment_applied','transfer_recorded', etc.
  entity_type     VARCHAR(50) NOT NULL, -- 'journal','invoice','payment','transfer','account'
  entity_id       BIGINT NOT NULL,
  user_id         BIGINT,
  details_json    JSONB,
  CONSTRAINT fk_tl_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_tl_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_tl_tenant_eventtime ON transaction_log(tenant_id, event_time DESC);
CREATE INDEX IF NOT EXISTS idx_tl_entity ON transaction_log(entity_type, entity_id);

-- AP/AR Core Entities
CREATE TABLE IF NOT EXISTS customers (
  id              BIGSERIAL PRIMARY KEY,
  tenant_id       BIGINT NOT NULL,
  name            VARCHAR(200) NOT NULL,
  email           VARCHAR(190),
  phone           VARCHAR(50),
  billing_address JSONB,
  shipping_address JSONB,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by      BIGINT,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by      BIGINT,
  UNIQUE (tenant_id, name),
  CONSTRAINT fk_cust_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_cust_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_cust_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS vendors (
  id              BIGSERIAL PRIMARY KEY,
  tenant_id       BIGINT NOT NULL,
  name            VARCHAR(200) NOT NULL,
  email           VARCHAR(190),
  phone           VARCHAR(50),
  billing_address JSONB,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by      BIGINT,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by      BIGINT,
  UNIQUE (tenant_id, name),
  CONSTRAINT fk_vend_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_vend_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_vend_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL
);

-- Invoices (AR)
CREATE TABLE IF NOT EXISTS invoices (
  id              BIGSERIAL PRIMARY KEY,
  tenant_id       BIGINT NOT NULL,
  invoice_no      VARCHAR(50) NOT NULL,
  customer_id     BIGINT NOT NULL,
  issue_date      DATE NOT NULL,
  due_date        DATE,
  currency        VARCHAR(3),
  total_amount    NUMERIC(18,2) NOT NULL DEFAULT 0,
  balance_due     NUMERIC(18,2) NOT NULL DEFAULT 0,
  status          document_status NOT NULL DEFAULT 'draft',
  ar_account_id   BIGINT, -- Accounts Receivable account
  revenue_account_id BIGINT, -- default revenue acct for lines if needed
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by      BIGINT,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by      BIGINT,
  UNIQUE (tenant_id, invoice_no),
  CONSTRAINT fk_inv_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_inv_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE RESTRICT,
  CONSTRAINT fk_inv_ar_account FOREIGN KEY (ar_account_id) REFERENCES accounts(id) ON DELETE SET NULL,
  CONSTRAINT fk_inv_rev_account FOREIGN KEY (revenue_account_id) REFERENCES accounts(id) ON DELETE SET NULL,
  CONSTRAINT fk_inv_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_inv_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS invoice_lines (
  id              BIGSERIAL PRIMARY KEY,
  tenant_id       BIGINT NOT NULL,
  invoice_id      BIGINT NOT NULL,
  line_no         INT NOT NULL,
  description     VARCHAR(255) NOT NULL,
  quantity        NUMERIC(18,4) NOT NULL DEFAULT 1,
  unit_price      NUMERIC(18,4) NOT NULL DEFAULT 0,
  line_total      NUMERIC(18,2) NOT NULL DEFAULT 0,
  revenue_account_id BIGINT, -- revenue account for the line
  tax_amount      NUMERIC(18,2) NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by      BIGINT,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by      BIGINT,
  UNIQUE (invoice_id, line_no),
  CONSTRAINT fk_invl_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_invl_invoice FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
  CONSTRAINT fk_invl_rev_account FOREIGN KEY (revenue_account_id) REFERENCES accounts(id) ON DELETE SET NULL,
  CONSTRAINT fk_invl_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_invl_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT chk_invl_amounts CHECK (quantity >= 0 AND unit_price >= 0 AND line_total >= 0 AND tax_amount >= 0)
);

-- Bills (AP)
CREATE TABLE IF NOT EXISTS bills (
  id              BIGSERIAL PRIMARY KEY,
  tenant_id       BIGINT NOT NULL,
  bill_no         VARCHAR(50) NOT NULL,
  vendor_id       BIGINT NOT NULL,
  issue_date      DATE NOT NULL,
  due_date        DATE,
  currency        VARCHAR(3),
  total_amount    NUMERIC(18,2) NOT NULL DEFAULT 0,
  balance_due     NUMERIC(18,2) NOT NULL DEFAULT 0,
  status          document_status NOT NULL DEFAULT 'draft',
  ap_account_id   BIGINT, -- Accounts Payable account
  expense_account_id BIGINT, -- default expense acct for lines if needed
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by      BIGINT,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by      BIGINT,
  UNIQUE (tenant_id, bill_no),
  CONSTRAINT fk_bill_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_bill_vendor FOREIGN KEY (vendor_id) REFERENCES vendors(id) ON DELETE RESTRICT,
  CONSTRAINT fk_bill_ap_account FOREIGN KEY (ap_account_id) REFERENCES accounts(id) ON DELETE SET NULL,
  CONSTRAINT fk_bill_exp_account FOREIGN KEY (expense_account_id) REFERENCES accounts(id) ON DELETE SET NULL,
  CONSTRAINT fk_bill_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_bill_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS bill_lines (
  id              BIGSERIAL PRIMARY KEY,
  tenant_id       BIGINT NOT NULL,
  bill_id         BIGINT NOT NULL,
  line_no         INT NOT NULL,
  description     VARCHAR(255) NOT NULL,
  quantity        NUMERIC(18,4) NOT NULL DEFAULT 1,
  unit_price      NUMERIC(18,4) NOT NULL DEFAULT 0,
  line_total      NUMERIC(18,2) NOT NULL DEFAULT 0,
  expense_account_id BIGINT, -- expense account for the line
  tax_amount      NUMERIC(18,2) NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by      BIGINT,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by      BIGINT,
  UNIQUE (bill_id, line_no),
  CONSTRAINT fk_bl_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_bl_bill FOREIGN KEY (bill_id) REFERENCES bills(id) ON DELETE CASCADE,
  CONSTRAINT fk_bl_exp_account FOREIGN KEY (expense_account_id) REFERENCES accounts(id) ON DELETE SET NULL,
  CONSTRAINT fk_bl_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_bl_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT chk_bl_amounts CHECK (quantity >= 0 AND unit_price >= 0 AND line_total >= 0 AND tax_amount >= 0)
);

-- Payments: customer payments (AR) and vendor payments (AP)
CREATE TABLE IF NOT EXISTS payments (
  id              BIGSERIAL PRIMARY KEY,
  tenant_id       BIGINT NOT NULL,
  payment_no      VARCHAR(50) NOT NULL,
  payment_date    DATE NOT NULL,
  amount          NUMERIC(18,2) NOT NULL CHECK (amount >= 0),
  currency        VARCHAR(3),
  method          VARCHAR(50), -- 'cash','bank_transfer','credit_card','check'
  status          payment_status NOT NULL DEFAULT 'pending',
  customer_id     BIGINT, -- not null for AR payment
  vendor_id       BIGINT, -- not null for AP payment
  cash_account_id BIGINT NOT NULL, -- cash/bank account used
  notes           VARCHAR(255),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by      BIGINT,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by      BIGINT,
  UNIQUE (tenant_id, payment_no),
  CONSTRAINT fk_pay_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_pay_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL,
  CONSTRAINT fk_pay_vendor FOREIGN KEY (vendor_id) REFERENCES vendors(id) ON DELETE SET NULL,
  CONSTRAINT fk_pay_cash_account FOREIGN KEY (cash_account_id) REFERENCES accounts(id) ON DELETE RESTRICT,
  CONSTRAINT fk_pay_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_pay_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT chk_pay_party CHECK (
    (customer_id IS NOT NULL AND vendor_id IS NULL) OR (customer_id IS NULL AND vendor_id IS NOT NULL)
  )
);

-- Payment applications: link payments to invoices or bills
CREATE TABLE IF NOT EXISTS payment_applications (
  id               BIGSERIAL PRIMARY KEY,
  tenant_id        BIGINT NOT NULL,
  payment_id       BIGINT NOT NULL,
  invoice_id       BIGINT,
  bill_id          BIGINT,
  amount_applied   NUMERIC(18,2) NOT NULL CHECK (amount_applied > 0),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by       BIGINT,
  UNIQUE (payment_id, invoice_id, bill_id),
  CONSTRAINT fk_papp_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_papp_payment FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE CASCADE,
  CONSTRAINT fk_papp_invoice FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
  CONSTRAINT fk_papp_bill FOREIGN KEY (bill_id) REFERENCES bills(id) ON DELETE CASCADE,
  CONSTRAINT fk_papp_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT chk_papp_target CHECK (
    (invoice_id IS NOT NULL AND bill_id IS NULL) OR (invoice_id IS NULL AND bill_id IS NOT NULL)
  )
);

-- Cash Accounts (view over accounts where is_cash = true) - optional materialized
-- Cash Transfers between cash accounts
CREATE TABLE IF NOT EXISTS cash_transfers (
  id                BIGSERIAL PRIMARY KEY,
  tenant_id         BIGINT NOT NULL,
  transfer_no       VARCHAR(50) NOT NULL,
  transfer_date     DATE NOT NULL,
  from_account_id   BIGINT NOT NULL,
  to_account_id     BIGINT NOT NULL,
  amount            NUMERIC(18,2) NOT NULL CHECK (amount > 0),
  currency          VARCHAR(3),
  memo              VARCHAR(255),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by        BIGINT,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by        BIGINT,
  UNIQUE (tenant_id, transfer_no),
  CONSTRAINT fk_ct_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_ct_from FOREIGN KEY (from_account_id) REFERENCES accounts(id) ON DELETE RESTRICT,
  CONSTRAINT fk_ct_to FOREIGN KEY (to_account_id) REFERENCES accounts(id) ON DELETE RESTRICT,
  CONSTRAINT fk_ct_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_ct_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT chk_ct_diff_accounts CHECK (from_account_id <> to_account_id)
);

-- Index hints
CREATE INDEX IF NOT EXISTS idx_accounts_tenant ON accounts(tenant_id);
CREATE INDEX IF NOT EXISTS idx_journal_entries_tenant_date ON journal_entries(tenant_id, entry_date);
CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON journal_lines(account_id);
CREATE INDEX IF NOT EXISTS idx_invoices_tenant_status ON invoices(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_bills_tenant_status ON bills(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_payments_tenant_status ON payments(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_cash_transfers_tenant_date ON cash_transfers(tenant_id, transfer_date);

-- Helpers for automatic journal generation (documented; actual posting logic in backend)
-- The following constraints support safe posting/voiding flows.

-- Constraint: Cannot set a journal to 'posted' unless balanced.
CREATE OR REPLACE FUNCTION trg_check_post_balanced() RETURNS trigger AS $$
DECLARE
  total_debit NUMERIC(30,6);
  total_credit NUMERIC(30,6);
BEGIN
  IF NEW.status = 'posted' THEN
    SELECT COALESCE(SUM(debit),0), COALESCE(SUM(credit),0)
    INTO total_debit, total_credit
    FROM journal_lines
    WHERE journal_entry_id = NEW.id;
    IF total_debit <> total_credit OR total_debit = 0 THEN
      RAISE EXCEPTION 'Cannot post unbalanced or zero-value journal %: debit % credit %', NEW.id, total_debit, total_credit;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS je_status_post_check ON journal_entries;
CREATE TRIGGER je_status_post_check
BEFORE UPDATE OF status ON journal_entries
FOR EACH ROW
WHEN (NEW.status = 'posted' AND OLD.status IS DISTINCT FROM NEW.status)
EXECUTE PROCEDURE trg_check_post_balanced();

-- Constraint: Prevent changes to lines of posted journals
CREATE OR REPLACE FUNCTION trg_block_change_posted_lines() RETURNS trigger AS $$
DECLARE
  st journal_status;
BEGIN
  IF TG_TABLE_NAME = 'journal_lines' THEN
    SELECT status INTO st FROM journal_entries WHERE id = COALESCE(NEW.journal_entry_id, OLD.journal_entry_id);
    IF st = 'posted' THEN
      RAISE EXCEPTION 'Cannot modify lines of a posted journal';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS jl_block_update ON journal_lines;
CREATE TRIGGER jl_block_update
BEFORE UPDATE OR DELETE ON journal_lines
FOR EACH ROW EXECUTE PROCEDURE trg_block_change_posted_lines();

-- Balances maintenance is expected to be done by backend services or stored procedures.
-- Provide a view for trial balance to assist reporting
CREATE OR REPLACE VIEW v_trial_balance AS
SELECT
  je.tenant_id,
  a.id as account_id,
  a.code as account_code,
  a.name as account_name,
  a.type as account_type,
  SUM(jl.debit) AS total_debit,
  SUM(jl.credit) AS total_credit,
  SUM(jl.debit - jl.credit) AS net_debit_credit
FROM journal_lines jl
JOIN journal_entries je ON je.id = jl.journal_entry_id AND je.status = 'posted'
JOIN accounts a ON a.id = jl.account_id
GROUP BY je.tenant_id, a.id, a.code, a.name, a.type;

-- Optional sequences per tenant: emulate per-tenant numbering via table
CREATE TABLE IF NOT EXISTS numbering_sequences (
  id            BIGSERIAL PRIMARY KEY,
  tenant_id     BIGINT NOT NULL,
  name          VARCHAR(50) NOT NULL, -- 'journal','invoice','bill','payment','transfer'
  prefix        VARCHAR(20),
  current_value BIGINT NOT NULL DEFAULT 0,
  pad_length    INT NOT NULL DEFAULT 5,
  UNIQUE (tenant_id, name),
  CONSTRAINT fk_numseq_tenant FOREIGN KEY (tenant_id) REFERENCES organizations(id) ON DELETE CASCADE
);

-- Function to get next number (to be called in app transaction)
CREATE OR REPLACE FUNCTION next_sequence(p_tenant BIGINT, p_name TEXT)
RETURNS TEXT AS $$
DECLARE
  v_prefix TEXT;
  v_val BIGINT;
  v_pad INT;
BEGIN
  UPDATE numbering_sequences
  SET current_value = current_value + 1
  WHERE tenant_id = p_tenant AND name = p_name
  RETURNING prefix, current_value, pad_length INTO v_prefix, v_val, v_pad;

  IF NOT FOUND THEN
    INSERT INTO numbering_sequences(tenant_id, name, prefix, current_value, pad_length)
    VALUES (p_tenant, p_name, UPPER(SUBSTRING(p_name,1,3))||'-', 1, 5)
    RETURNING prefix, current_value, pad_length INTO v_prefix, v_val, v_pad;
  END IF;

  RETURN COALESCE(v_prefix,'') || LPAD(v_val::text, v_pad, '0');
END;
$$ LANGUAGE plpgsql;

COMMIT;

-- End of schema
