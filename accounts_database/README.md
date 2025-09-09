# Accounts Database (MySQL)

This directory contains the MySQL schema and seed scripts for the multi-tenant accounts management platform.

Contents:
- schema.sql: DDL for tenant-aware tables (organizations, users, roles, permissions, role_permissions, user_roles, password_resets, audit_logs) with proper indexes and foreign keys.
- seed.sql: Initial seed for a default tenant (tenant_id = 1), default roles (Admin, Manager, Sales Rep, Viewer), baseline permissions, and an admin user.

Multi-tenancy:
- Implemented via tenant_id column on each row. All queries from the backend must be scoped by tenant_id to enforce isolation.

Usage:
- The startup.sh script initializes MySQL, creates the database and users, and automatically applies schema.sql and seed.sql if present.
- Connection info is stored in db_connection.txt and db_visualizer/mysql.env.

Security:
- The seed admin password uses a demo bcrypt hash and must be replaced in production. Ensure secrets are provided via environment variables in deployment pipelines.
