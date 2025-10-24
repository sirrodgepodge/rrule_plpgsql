/**
 * Master Installation Script for rrule_plpgsql
 *
 * This script installs all necessary functions for RRULE processing
 * using pure PL/pgSQL (no C extensions required).
 *
 * Installation:
 *   psql -d your_database -f install.sql
 *
 * Or from within psql:
 *   \i install.sql
 *
 * Dependencies: PostgreSQL 12+ (tested with PostgreSQL 16)
 *
 * Components installed:
 * 1. RRULE schema (namespace isolation)
 * 2. RRULE core functions (comprehensive RFC 5545 & RFC 7529 implementation)
 * 3. RRULE public API (standard rrule.js/python-dateutil compatible methods)
 * 4. Full validation with descriptive error messages
 *
 * @package rrule_plpgsql
 * @license MIT
 */

\set ON_ERROR_STOP on

BEGIN;

\echo ''
\echo '==================================================================='
\echo 'Installing Pure PL/pgSQL RRULE Implementation'
\echo '==================================================================='
\echo ''

-- Set timezone to UTC for consistent behavior
SET timezone = 'UTC';

-- Drop and recreate schema for clean reinstall
-- Note: Without CASCADE, this will error if there are dependent objects
-- (e.g., user views using rrule functions). This is safer than silently
-- dropping user objects.
\echo 'Creating rrule schema...'

-- Try to drop schema with helpful error message if dependencies exist
DO $$
DECLARE
    dep_list TEXT;
    error_msg TEXT;
BEGIN
    -- Try to drop the schema
    EXECUTE 'DROP SCHEMA IF EXISTS rrule';
EXCEPTION
    WHEN dependent_objects_still_exist THEN
        -- Query to find dependent objects
        SELECT string_agg('  - ' || n.nspname || '.' || c.relname || ' (' ||
               CASE c.relkind
                   WHEN 'v' THEN 'view'
                   WHEN 'r' THEN 'table'
                   WHEN 'm' THEN 'materialized view'
                   ELSE 'object'
               END || ')', E'\n')
        INTO dep_list
        FROM pg_class c
        JOIN pg_namespace n ON c.relnamespace = n.oid
        JOIN pg_depend d ON d.refobjid = c.oid
        JOIN pg_proc p ON d.objid = p.oid
        JOIN pg_namespace pn ON p.pronamespace = pn.oid
        WHERE pn.nspname = 'rrule'
          AND c.relkind IN ('v', 'r', 'm')
          AND n.nspname != 'rrule';

        -- Build detailed error message with dependency list
        error_msg := E'\n\n' ||
            '╔════════════════════════════════════════════════════════════════════════════╗' || E'\n' ||
            '║ ERROR: Cannot drop rrule schema - dependent objects exist                 ║' || E'\n' ||
            '╠════════════════════════════════════════════════════════════════════════════╣' || E'\n' ||
            '║                                                                            ║' || E'\n' ||
            '║ The following objects depend on the rrule schema:                         ║' || E'\n' ||
            '║                                                                            ║' || E'\n' ||
            COALESCE(dep_list, '  (Unable to list dependencies - check manually)') || E'\n' ||
            '║                                                                            ║' || E'\n' ||
            '║ SOLUTION: Manual Migration Process                                        ║' || E'\n' ||
            '║                                                                            ║' || E'\n' ||
            '║ See the complete migration guide:                                         ║' || E'\n' ||
            '║   https://github.com/sirrodgepodge/rrule_plpgsql/blob/main/MANUAL_MIGRATION.md ║' || E'\n' ||
            '║                                                                            ║' || E'\n' ||
            '║ You will need to:                                                         ║' || E'\n' ||
            '║   1. Install new version to rrule_update schema (installManual.sh)        ║' || E'\n' ||
            '║   2. Update YOUR dependencies above to use rrule_update                   ║' || E'\n' ||
            '║   3. Test thoroughly with your application                                ║' || E'\n' ||
            '║   4. Drop old rrule schema and rename rrule_update to rrule               ║' || E'\n' ||
            '║                                                                            ║' || E'\n' ||
            '║ The guide includes example scripts you can adapt for your specific needs. ║' || E'\n' ||
            '║                                                                            ║' || E'\n' ||
            '╚════════════════════════════════════════════════════════════════════════════╝' || E'\n';

        RAISE EXCEPTION '%', error_msg;
END $$;

CREATE SCHEMA rrule;

\echo 'Installing RRULE functions...'
\i rrule.sql

\echo ''
\echo '==================================================================='
\echo 'Installation Complete!'
\echo '==================================================================='
\echo ''
\echo 'PUBLIC API - All functions support both TIMESTAMP and TIMESTAMPTZ:'
\echo ''
\echo 'Core Functions:'
\echo '  - rrule.all(rrule, dtstart) -> SETOF TIMESTAMP'
\echo '  - rrule.all(rrule, dtstart_tz, timezone DEFAULT NULL) -> SETOF TIMESTAMPTZ'
\echo '  - rrule.between(rrule, dtstart, start, end) -> SETOF TIMESTAMP'
\echo '  - rrule.between(rrule, dtstart_tz, start_tz, end_tz, tz DEFAULT NULL) -> SETOF TIMESTAMPTZ'
\echo '  - rrule.after(rrule, dtstart, after) -> TIMESTAMP'
\echo '  - rrule.after(rrule, dtstart_tz, after_tz, cnt, tz DEFAULT NULL) -> SETOF TIMESTAMPTZ'
\echo '  - rrule.before(rrule, dtstart, before) -> TIMESTAMP'
\echo '  - rrule.before(rrule, dtstart_tz, before_tz, cnt, tz DEFAULT NULL) -> SETOF TIMESTAMPTZ'
\echo '  - rrule.count(rrule, dtstart) -> INTEGER'
\echo '  - rrule.count(rrule, dtstart_tz, timezone DEFAULT NULL) -> INTEGER'
\echo ''
\echo 'Convenience Functions:'
\echo '  - rrule.next(rrule, dtstart) -> TIMESTAMP'
\echo '  - rrule.next(rrule, dtstart_tz, timezone DEFAULT NULL) -> TIMESTAMPTZ'
\echo '  - rrule.most_recent(rrule, dtstart) -> TIMESTAMP'
\echo '  - rrule.most_recent(rrule, dtstart_tz, timezone DEFAULT NULL) -> TIMESTAMPTZ'
\echo ''
\echo 'Advanced:'
\echo '  - rrule.overlaps(dtstart_tz, dtend_tz, rrule, min_tz, max_tz, tz DEFAULT NULL) -> BOOLEAN'
\echo ''
\echo 'Timezone Resolution Priority (for TIMESTAMPTZ functions):'
\echo '  1. Explicit timezone parameter (if provided)'
\echo '  2. TZID in RRULE string (e.g., TZID=America/New_York)'
\echo '  3. UTC (fallback)'
\echo ''
\echo 'Features:'
\echo '  - Full RFC 5545 & RFC 7529 compliance'
\echo '  - TZID (timezone) support'
\echo '  - SKIP parameter (OMIT, BACKWARD, FORWARD) for month-end handling'
\echo '  - 16 RFC 5545 constraint validations with descriptive errors'
\echo '  - Schema-based namespacing (rrule.* prevents conflicts)'
\echo ''
\echo 'Example usage (SETOF - streaming, memory efficient):'
\echo '  SELECT * FROM rrule.all('
\echo '    ''FREQ=DAILY;COUNT=5'','
\echo '    ''2025-01-01 10:00:00''::TIMESTAMP'
\echo '  );'
\echo ''
\echo 'Example usage (array - if you need materialized array):'
\echo '  SELECT array_agg(occurrence) FROM rrule.all('
\echo '    ''FREQ=DAILY;COUNT=5;TZID=America/New_York'','
\echo '    ''2025-01-01 10:00:00''::TIMESTAMP'
\echo '  ) AS occurrence;'
\echo ''
\echo 'To use functions without schema prefix, add to search_path:'
\echo '  SET search_path TO rrule, public;'
\echo ''

COMMIT;
