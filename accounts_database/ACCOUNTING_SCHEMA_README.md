# Accounting Database Schema (PostgreSQL)

This module defines a robust, multi-tenant accounting schema implementing:
- Double-entry bookkeeping (journal_entries, journal_lines)
- Chart of Accounts with categories and hierarchies
- RBAC (roles, permissions, role_permissions, user_roles)
- Accounts Receivable and Payable (customers, vendors, invoices, bills, payments, payment_applications)
- Cash management (cash_transfers; cash accounts flagged in accounts)
- Real-time transaction logging (transaction_log)
- General ledger balances (gl_balances) and a trial balance view
- Fiscal periods and period closure checks

All business tables include `tenant_id` and reference `organizations(id)`; audit fields reference `users(id)`.

## Files

- schema_accounting_postgres.sql: Full PostgreSQL DDL with integrity constraints and triggers.

## Key Integrity Features

- Journal lines enforce exclusive debit/credit per line and non-negative amounts.
- Journal status 'posted' requires balanced lines; enforced via trigger.
- Statement-level deferred constraint verifies posted journal remains balanced after any line change.
- Posted journals block further line mutations (update/delete).
- Fiscal period closure prevents posting entries into closed periods.
- AP/AR payment applications enforce exclusive targets (invoice or bill).
- Cash transfers require distinct from/to accounts.

## Multi-tenancy

- Every business table contains `tenant_id` with FK to `organizations(id)`.
- Uniqueness and search indices are scoped to `tenant_id` where applicable.
- Numbering sequences support per-tenant human-friendly identifiers via `next_sequence(tenant_id, name)`.

## RBAC

- roles: per-tenant role definitions (e.g., Admin, Accountant, Viewer).
- permissions: system-wide permission codes (e.g., "accounting:view", "journal:post").
- role_permissions: assigning permissions to roles.
- user_roles: assigning users to roles per tenant.

Note: Populate default roles and permission codes in your backend seeding process.

## Double-entry Flow (Automated)

- Backend should generate balanced `journal_lines` for every `journal_entries` record.
- Set `source_module` and `source_id` on journal entries to link originating transaction (invoice, bill, payment, transfer).
- When updating to `status='posted'`, triggers validate the entry is balanced.

## AP/AR Overview

- invoices/invoice_lines: AR documents scoped by tenant; balances track open amounts.
- bills/bill_lines: AP documents; balances track amounts due.
- payments: represent cash movement; use `customer_id` for AR or `vendor_id` for AP.
- payment_applications: link payments to invoices or bills; cumulative applied amount should be maintained by backend and reflected in document balances.

## Cash Management

- accounts.is_cash marks cash/bank accounts.
- cash_transfers: movement between cash accounts; backend should post corresponding journals (credit from, debit to).

## Real-time Transaction Log

- transaction_log is append-only for auditing and streaming.
- Use it to emit events when journals are posted, documents created/paid, transfers recorded, etc.

## Balances

- gl_balances stores per-period totals and opening/closing balances for fast reporting.
- A reporting job or triggers in your backend should aggregate posted journals into gl_balances.
- v_trial_balance view gives live trial balance from posted journals.

## Assumptions

- Core tables `organizations(id)` and `users(id)` exist.
- Backend (Express/Node) manages transactions, sequence calls, and idempotent posting.
- Currency handling is basic; for full multi-currency, extend with FX rates and more granular currency columns.

## Applying the Schema

1. Ensure PostgreSQL is running and the database is selected.
2. Apply the DDL:
   psql -h <host> -p <port> -U <user> -d <db> -f accounts_database/schema_accounting_postgres.sql

Environment variables will be handled by your deployment system. Do not hardcode secrets in code.

## Future Extensions

- Add tax tables and tax posting templates.
- Add inventory integration and COGS postings.
- Add recurring journals and amortization schedules.
- Add comprehensive locking/closing workflow (year-end close).
- Add ledger snapshots and materialized views for performance.
