#!/usr/bin/env bash
#
# Manual Migration Installation Script for rrule_plpgsql
#
# This script installs RRULE functions to the 'rrule_update' schema
# to allow manual migration when you have dependencies on the 'rrule' schema.
#
# USE THIS ONLY FOR MANUAL MIGRATION - See MANUAL_MIGRATION.md for complete guide.
#
# Usage:
#   ./installManual.sh your_database
#
# Or with connection string:
#   PGHOST=localhost PGUSER=myuser ./installManual.sh mydb
#

set -e  # Exit on error

if [ -z "$1" ]; then
    echo "Error: Database name required"
    echo "Usage: $0 <database_name>"
    echo "Example: $0 mydb"
    exit 1
fi

DATABASE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "==================================================================="
echo "Installing RRULE to rrule_update schema (Manual Migration)"
echo "==================================================================="
echo ""
echo "WARNING: This installs to rrule_update schema for manual migration."
echo "See MANUAL_MIGRATION.md for complete migration guide."
echo ""
echo "Database: $DATABASE"
echo ""

# Create the rrule_update schema
echo "Creating rrule_update schema..."
psql -d "$DATABASE" <<SQL
DROP SCHEMA IF EXISTS rrule_update;
CREATE SCHEMA rrule_update;
SQL

# Install rrule.sql with schema name replaced
echo "Installing RRULE functions to rrule_update schema..."
sed \
  -e 's/SET search_path = rrule,/SET search_path = rrule_update,/g' \
  -e "s/nspname = 'rrule'/nspname = 'rrule_update'/g" \
  "$SCRIPT_DIR/rrule.sql" | psql -d "$DATABASE"

echo ""
echo "==================================================================="
echo "Installation to rrule_update Complete!"
echo "==================================================================="
echo ""
echo "Functions installed in rrule_update schema:"
echo "  - rrule_update.all(rrule, dtstart) -> SETOF TIMESTAMP"
echo "  - rrule_update.between(rrule, dtstart, start_date, end_date) -> SETOF TIMESTAMP"
echo "  - rrule_update.after(rrule, dtstart, after_date) -> TIMESTAMP"
echo "  - rrule_update.before(rrule, dtstart, before_date) -> TIMESTAMP"
echo "  - rrule_update.count(rrule, dtstart) -> INTEGER"
echo "  - rrule_update.next(rrule, dtstart) -> TIMESTAMP"
echo "  - rrule_update.most_recent(rrule, dtstart) -> TIMESTAMP"
echo "  - rrule_update.overlaps(dtstart, dtend, rrule, mindate, maxdate) -> BOOLEAN"
echo ""
echo "Next steps (see MANUAL_MIGRATION.md for details):"
echo "  1. Update your dependent objects to use rrule_update schema"
echo "  2. Test your application with rrule_update"
echo "  3. Drop the old rrule schema: DROP SCHEMA rrule;"
echo "  4. Rename rrule_update to rrule: ALTER SCHEMA rrule_update RENAME TO rrule;"
echo "  5. Update your objects back to use rrule schema"
echo ""
