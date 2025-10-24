/**
 * Installation Script with Sub-Day Frequencies Support
 *
 * ⚠️  WARNING: SECURITY-SENSITIVE INSTALLATION ⚠️
 *
 * This script installs the RRULE implementation WITH support for HOURLY,
 * MINUTELY, and SECONDLY frequencies.
 *
 * SECURITY IMPLICATIONS:
 * - HOURLY can generate 8,760 occurrences per year
 * - MINUTELY can generate 525,600 occurrences per year
 * - SECONDLY can generate 31,536,000 occurrences per year
 *
 * ⚠️  DO NOT USE THIS in multi-tenant environments without strict validation!
 *
 * REQUIRED BEFORE INSTALLATION:
 * 1. Review rrule_subday.sql header for complete security documentation
 * 2. Implement application-level validation (COUNT/UNTIL limits)
 * 3. Configure statement_timeout to prevent runaway queries:
 *    ALTER DATABASE your_db SET statement_timeout = '30s';
 * 4. Set up monitoring for long-running queries
 * 5. Test thoroughly in staging environment first
 *
 * RECOMMENDED VALIDATION LIMITS:
 * - HOURLY: COUNT <= 1000, UNTIL <= 7 days from dtstart
 * - MINUTELY: COUNT <= 1000, UNTIL <= 24 hours from dtstart
 * - SECONDLY: COUNT <= 1000, UNTIL <= 1 hour from dtstart
 *
 * INSTALLATION:
 *   cd src
 *   psql -d your_database -f install_with_subday.sql
 *
 * Or from within psql:
 *   \i src/install_with_subday.sql
 *
 * ALTERNATIVE (Safer):
 * If you don't need sub-day frequencies, use install.sql instead
 *
 * @package rrule_plpgsql
 * @license MIT
 * @security CRITICAL - Review before use
 */

\set ON_ERROR_STOP on

BEGIN;

\echo ''
\echo '====================================================================='
\echo 'Installing Pure PL/pgSQL RRULE Implementation WITH Sub-Day Frequencies'
\echo '====================================================================='
\echo ''
\echo '⚠️  WARNING: This installation includes HOURLY, MINUTELY, and SECONDLY'
\echo '⚠️  frequency support which can generate millions of occurrences.'
\echo ''
\echo '⚠️  SECURITY REQUIREMENTS:'
\echo '⚠️  - Implement application-level validation (see rrule_subday.sql)'
\echo '⚠️  - Configure statement_timeout'
\echo '⚠️  - Monitor for long-running queries'
\echo ''

-- Set timezone to UTC for consistent behavior
SET timezone = 'UTC';

-- Drop and recreate schema for clean reinstall
\echo 'Creating rrule schema...'

DO $$
DECLARE
    dep_list TEXT;
    error_msg TEXT;
BEGIN
    EXECUTE 'DROP SCHEMA IF EXISTS rrule';
EXCEPTION
    WHEN dependent_objects_still_exist THEN
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
            '╚════════════════════════════════════════════════════════════════════════════╝' || E'\n';

        RAISE EXCEPTION '%', error_msg;
END $$;

CREATE SCHEMA rrule;

\echo 'Installing core RRULE functions...'
\i rrule.sql

\echo 'Installing sub-day frequency support...'
\i rrule_subday.sql

\echo ''
\echo '====================================================================='
\echo 'Installation Complete!'
\echo '====================================================================='
\echo ''
\echo 'Installed API (rrule.js/python-dateutil compatible):'
\echo '  - rrule.all(rrule, dtstart) -> SETOF TIMESTAMP'
\echo '  - rrule.between(rrule, dtstart, start_date, end_date) -> SETOF TIMESTAMP'
\echo '  - rrule.after(rrule, dtstart, after_date) -> TIMESTAMP'
\echo '  - rrule.before(rrule, dtstart, before_date) -> TIMESTAMP'
\echo '  - rrule.count(rrule, dtstart) -> INTEGER'
\echo ''
\echo 'Supported Frequencies:'
\echo '  ✅ DAILY, WEEKLY, MONTHLY, YEARLY'
\echo '  ⚠️  HOURLY, MINUTELY, SECONDLY (USE WITH CAUTION)'
\echo ''
\echo '⚠️  IMPORTANT SECURITY REMINDERS:'
\echo ''
\echo '1. Implement application-level validation:'
\echo '   - HOURLY: Limit COUNT to 1000, UNTIL to 7 days'
\echo '   - MINUTELY: Limit COUNT to 1000, UNTIL to 24 hours'
\echo '   - SECONDLY: Limit COUNT to 1000, UNTIL to 1 hour'
\echo ''
\echo '2. Configure database timeout:'
\echo '   ALTER DATABASE your_db SET statement_timeout = ''30s'';'
\echo ''
\echo '3. Monitor for long-running queries:'
\echo '   SELECT * FROM pg_stat_activity'
\echo '   WHERE state = ''active'' AND query_start < now() - interval ''10 seconds'';'
\echo ''
\echo 'See rrule_subday.sql for complete security documentation.'
\echo ''

COMMIT;
