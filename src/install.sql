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
 * - Complete RRULE parser and generator (RFC 5545 compliant)
 * - API functions (get_occurrences, get_next_occurrence, adjust_rrule_for_month_end)
 *
 * @package rrule_plpgsql
 * @license MIT
 * @copyright 2025 Novel Platform
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

\echo 'Installing RRULE functions...'
\i rrule.sql

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
