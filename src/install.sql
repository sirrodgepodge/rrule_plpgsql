/**
 * Master Installation Script for Pure PL/pgSQL RRULE Implementation
 *
 * This script installs all necessary functions to provide pg_rrule-compatible
 * RRULE processing using pure PL/pgSQL (no C extensions required).
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
 * 1. DAVical RRULE base functions (adapted from DAVical CalDAV server)
 * 2. pg_rrule-compatible wrapper functions
 * 3. Helper functions (adjust_rrule_for_month_end, get_next_occurrence)
 *
 * @package novel-2 / pg_rrule_plpgsql
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

\echo 'Step 1/2: Installing DAVical RRULE base functions...'
\i davical_rrule_base.sql

\echo ''
\echo 'Step 2/2: Installing pg_rrule-compatible wrappers...'
\i pg_rrule_wrappers.sql

\echo ''
\echo '==================================================================='
\echo 'Installation Complete!'
\echo '==================================================================='
\echo ''
\echo 'Available functions:'
\echo '  - get_occurrences(rrule VARCHAR, dtstart TIMESTAMP) -> TIMESTAMP[]'
\echo '  - get_occurrences(rrule VARCHAR, dtstart TIMESTAMP, until TIMESTAMP) -> TIMESTAMP[]'
\echo '  - get_next_occurrence(rrule VARCHAR, dtstart TIMESTAMP, after TIMESTAMP) -> TIMESTAMP'
\echo '  - adjust_rrule_for_month_end(rrule VARCHAR) -> VARCHAR'
\echo ''
\echo 'Example usage:'
\echo '  SELECT unnest(get_occurrences('
\echo '    ''FREQ=DAILY;COUNT=5'','
\echo '    ''2025-01-01 10:00:00''::TIMESTAMP'
\echo '  ));'
\echo ''

COMMIT;
