#!/bin/bash
set -euo pipefail

DB_NAME="${DB_NAME:-myapp}"
DB_USER="${DB_USER:-appuser}"
DB_PASSWORD="${DB_PASSWORD:-dbuser123}"
DB_PORT="${DB_PORT:-5000}"

echo "Applying contacts schema/migrations to ${DB_NAME} on port ${DB_PORT}..."

if [ ! -S /var/run/mysqld/mysqld.sock ]; then
  echo "MySQL socket not found at /var/run/mysqld/mysqld.sock. Ensure MySQL is running."
  exit 1
fi

if [ -f "schema_contacts.sql" ]; then
  echo "- Applying schema_contacts.sql"
  sudo mysql --socket=/var/run/mysqld/mysqld.sock -u root -p${DB_PASSWORD} ${DB_NAME} < schema_contacts.sql
else
  echo "schema_contacts.sql not found."
  exit 1
fi

if [ -f "seed_contacts.sql" ]; then
  echo "- Installing seed_contacts.sql (procedure)"
  sudo mysql --socket=/var/run/mysqld/mysqld.sock -u root -p${DB_PASSWORD} ${DB_NAME} < seed_contacts.sql
else
  echo "seed_contacts.sql not found."
fi

echo "Done."
