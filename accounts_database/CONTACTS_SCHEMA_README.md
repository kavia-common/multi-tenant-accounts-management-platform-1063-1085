# Contacts Management Database Schema (MySQL)

This module adds a comprehensive, multi-tenant contact management schema to the `myapp` database.

## Tables

- contact_categories: Category dictionary per tenant (Lead, Prospect, Customer, Vendor; customizable).
- contacts: Core contact entity (name, email, phone, company, address, job_title, category).
- contact_category_map: Many-to-many mapping for contacts with multiple categories.
- contact_tags: Tag dictionary per tenant.
- contact_tag_map: Many-to-many mapping for contacts and tags.
- custom_field_definitions: Per-tenant custom field definitions for `contact`.
- custom_field_values: EAV storage for custom field values on contacts.
- contact_timeline: Notes and timeline events (note/call/meeting/email/etc.).
- contact_duplicates: Potential duplicate pairs with similarity score and status.
- contact_merge_audit: Merge operations audit/history.
- contact_emails: Email sync/index table for correlating messages to contacts.
- contact_import_jobs: Import job tracking.
- contact_import_errors: Row-level import errors.
- contact_audit_logs: Audit events specific to contacts module.

All business tables include `tenant_id` and have FKs to `organizations(id)` and user-scoped audit fields (created_by/updated_by) referencing `users(id)`.

## Multi-tenancy

- Each table includes `tenant_id` referencing `organizations(id)` to ensure isolation.
- Unique constraints and indexes are scoped by `tenant_id` (e.g., tag and category names).

## Referential Integrity

- Foreign keys connect:
  - contacts -> organizations, contact_categories, users
  - mapping tables -> contacts, tags/categories, organizations
  - custom field values -> definitions, contacts, organizations
  - timeline/duplicates/merge_audit/emails -> contacts, organizations, users

## Setup

The `startup.sh` script automatically:
- Creates DB and users (if needed)
- Applies `schema_contacts.sql`
- Installs `seed_contacts.sql` procedure

Manual migration on a running DB:
```
cd accounts_database
./migrate_contacts.sh
```

## Seeding Default Categories

After creating a tenant (organization), seed the default categories using:
```
mysql -u appuser -pdbuser123 -h localhost -P 5000 myapp \
  -e "CALL seed_default_contact_categories(<tenant_id>, NULL);"
```

This will create Lead, Prospect, Customer, and Vendor for that tenant (if they don't already exist).

## Notes

- This schema assumes tables `organizations(id)` and `users(id)` already exist in the platform database.
- Email sync table `contact_emails` is provided to correlate emails to contacts and timeline; actual sync logic is implemented in the backend.
- Additional indexes for specific query patterns can be added as the backend search API stabilizes.
