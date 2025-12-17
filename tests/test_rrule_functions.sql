/**
 * Comprehensive Unit Tests for Pure PL/pgSQL RRULE Implementation
 *
 * These tests verify that our PL/pgSQL RRULE functions behave identically
 * to the pg_rrule C extension and rrule.js library.
 *
 * Test categories:
 * 1. Basic frequency patterns (DAILY, WEEKLY, MONTHLY, YEARLY)
 * 2. INTERVAL support
 * 3. COUNT and UNTIL limits
 * 4. BYDAY rules (weekdays)
 * 5. BYMONTHDAY rules (including negative indices for month-end)
 * 6. BYMONTH rules
 * 7. Complex combinations
 * 8. Edge cases (leap years, month boundaries)
 *
 * Usage:
 *   psql -d your_database -f test_rrule_functions.sql
 *
 * Expected output: All tests should pass
 */

\set ON_ERROR_STOP on
\set ECHO all

-- Test database setup
BEGIN;

-- Ensure we're testing in UTC timezone for consistency
SET timezone = 'UTC';

-- Create fresh rrule schema
DROP SCHEMA IF EXISTS rrule CASCADE;
CREATE SCHEMA IF NOT EXISTS rrule;
SET search_path = rrule, public;

-- Load the RRULE functions
\i src/rrule.sql

-- Helper function to compare expected vs actual occurrences
CREATE OR REPLACE FUNCTION assert_occurrences_equal(
    test_name TEXT,
    expected TIMESTAMP[],
    actual TIMESTAMP[]
)
RETURNS TEXT AS $$
DECLARE
    i INT;
BEGIN
    -- Check array lengths match
    IF array_length(expected, 1) IS DISTINCT FROM array_length(actual, 1) THEN
        RAISE EXCEPTION 'FAIL [%]: Expected % occurrences, got %',
            test_name,
            COALESCE(array_length(expected, 1), 0),
            COALESCE(array_length(actual, 1), 0);
    END IF;

    -- Check each element matches
    FOR i IN 1..COALESCE(array_length(expected, 1), 0) LOOP
        IF expected[i] IS DISTINCT FROM actual[i] THEN
            RAISE EXCEPTION 'FAIL [%]: Occurrence #% differs. Expected %, got %',
                test_name, i, expected[i], actual[i];
        END IF;
    END LOOP;

    RETURN 'PASS [' || test_name || ']';
END;
$$ LANGUAGE plpgsql;

-- Test results tracking
CREATE TEMP TABLE test_results (
    test_number INT,
    test_name TEXT,
    status TEXT,
    PRIMARY KEY (test_number)
);

-- ============================================================================
-- TEST GROUP 1: Basic Frequency Patterns
-- ============================================================================

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 1: Basic Frequency Patterns'
\echo '==================================================================='

-- Test 1: DAILY frequency with COUNT
INSERT INTO test_results VALUES (1, 'DAILY with COUNT=3',
    assert_occurrences_equal(
        'DAILY with COUNT=3',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"('FREQ=DAILY;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence)
    ));

-- Test 2: WEEKLY frequency with COUNT
INSERT INTO test_results VALUES (2, 'WEEKLY with COUNT=3',
    assert_occurrences_equal(
        'WEEKLY with COUNT=3',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,  -- Monday
            '2025-01-13 10:00:00'::TIMESTAMP,
            '2025-01-20 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"('FREQ=WEEKLY;COUNT=3', '2025-01-06 10:00:00'::TIMESTAMP) AS occurrence)
    ));

-- Test 3: MONTHLY frequency with COUNT
INSERT INTO test_results VALUES (3, 'MONTHLY with COUNT=3',
    assert_occurrences_equal(
        'MONTHLY with COUNT=3',
        ARRAY[
            '2025-01-15 10:00:00'::TIMESTAMP,
            '2025-02-15 10:00:00'::TIMESTAMP,
            '2025-03-15 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"('FREQ=MONTHLY;COUNT=3', '2025-01-15 10:00:00'::TIMESTAMP) AS occurrence)
    ));

-- Test 4: YEARLY frequency with COUNT
INSERT INTO test_results VALUES (4, 'YEARLY with COUNT=3',
    assert_occurrences_equal(
        'YEARLY with COUNT=3',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2026-01-01 10:00:00'::TIMESTAMP,
            '2027-01-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"('FREQ=YEARLY;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence)
    ));

-- ============================================================================
-- TEST GROUP 2: INTERVAL Support
-- ============================================================================

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 2: INTERVAL Support'
\echo '==================================================================='

-- Test 5: DAILY with INTERVAL=2 (every other day)
INSERT INTO test_results VALUES (5, 'DAILY with INTERVAL=2',
    assert_occurrences_equal(
        'DAILY with INTERVAL=2',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP,
            '2025-01-05 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"('FREQ=DAILY;INTERVAL=2;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence)
    ));

-- Test 6: WEEKLY with INTERVAL=2 (biweekly)
INSERT INTO test_results VALUES (6, 'WEEKLY with INTERVAL=2',
    assert_occurrences_equal(
        'WEEKLY with INTERVAL=2',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-20 10:00:00'::TIMESTAMP,
            '2025-02-03 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"('FREQ=WEEKLY;INTERVAL=2;COUNT=3', '2025-01-06 10:00:00'::TIMESTAMP) AS occurrence)
    ));

-- ============================================================================
-- TEST GROUP 3: UNTIL Limits
-- ============================================================================

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 3: UNTIL Limits'
\echo '==================================================================='

-- Test 7: DAILY with UNTIL
INSERT INTO test_results VALUES (7, 'DAILY with UNTIL',
    assert_occurrences_equal(
        'DAILY with UNTIL',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"('FREQ=DAILY;UNTIL=20250103T100000Z', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence)
    ));

-- ============================================================================
-- TEST GROUP 4: BYDAY Rules
-- ============================================================================

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 4: BYDAY Rules'
\echo '==================================================================='

-- Test 8: WEEKLY on Monday, Wednesday, Friday
INSERT INTO test_results VALUES (8, 'WEEKLY with BYDAY=MO,WE,FR',
    assert_occurrences_equal(
        'WEEKLY with BYDAY=MO,WE,FR',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,  -- Monday
            '2025-01-08 10:00:00'::TIMESTAMP,  -- Wednesday
            '2025-01-10 10:00:00'::TIMESTAMP   -- Friday
        ],
        (SELECT array_agg(occurrence) FROM "all"('FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=3', '2025-01-06 10:00:00'::TIMESTAMP) AS occurrence)
    ));

-- Test 9: DAILY with BYDAY=MO,TU,WE,TH,FR (weekdays only)
INSERT INTO test_results VALUES (9, 'DAILY with BYDAY weekdays',
    assert_occurrences_equal(
        'DAILY with BYDAY weekdays',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,  -- Monday
            '2025-01-07 10:00:00'::TIMESTAMP,  -- Tuesday
            '2025-01-08 10:00:00'::TIMESTAMP,  -- Wednesday
            '2025-01-09 10:00:00'::TIMESTAMP,  -- Thursday
            '2025-01-10 10:00:00'::TIMESTAMP   -- Friday
        ],
        (SELECT array_agg(occurrence) FROM "all"('FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;COUNT=5', '2025-01-06 10:00:00'::TIMESTAMP) AS occurrence)
    ));

-- ============================================================================
-- TEST GROUP 5: BYMONTHDAY Rules (including month-end)
-- ============================================================================

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 5: BYMONTHDAY Rules'
\echo '==================================================================='

-- Test 10: MONTHLY on 15th of each month
INSERT INTO test_results VALUES (10, 'MONTHLY with BYMONTHDAY=15',
    assert_occurrences_equal(
        'MONTHLY with BYMONTHDAY=15',
        ARRAY[
            '2025-01-15 10:00:00'::TIMESTAMP,
            '2025-02-15 10:00:00'::TIMESTAMP,
            '2025-03-15 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"('FREQ=MONTHLY;BYMONTHDAY=15;COUNT=3', '2025-01-15 10:00:00'::TIMESTAMP) AS occurrence)
    ));

-- Test 11: MONTHLY on last day of month (BYMONTHDAY=-1)
INSERT INTO test_results VALUES (11, 'MONTHLY with BYMONTHDAY=-1',
    assert_occurrences_equal(
        'MONTHLY with BYMONTHDAY=-1',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,  -- 31 days
            '2025-02-28 10:00:00'::TIMESTAMP,  -- 28 days (not leap year)
            '2025-03-31 10:00:00'::TIMESTAMP   -- 31 days
        ],
        (SELECT array_agg(occurrence) FROM "all"('FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence)
    ));

-- ============================================================================
-- TEST GROUP 6: BYMONTH Rules
-- ============================================================================

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 6: BYMONTH Rules'
\echo '==================================================================='

-- Test 12: YEARLY in January and July
INSERT INTO test_results VALUES (12, 'YEARLY with BYMONTH=1,7',
    assert_occurrences_equal(
        'YEARLY with BYMONTH=1,7',
        ARRAY[
            '2025-01-15 10:00:00'::TIMESTAMP,
            '2025-07-15 10:00:00'::TIMESTAMP,
            '2026-01-15 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"('FREQ=YEARLY;BYMONTH=1,7;COUNT=3', '2025-01-15 10:00:00'::TIMESTAMP) AS occurrence)
    ));

-- ============================================================================
-- TEST GROUP 7: Complex Combinations
-- ============================================================================

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 7: Complex Combinations'
\echo '==================================================================='

-- Test 13: MONTHLY on 2nd Monday (BYDAY=2MO)
INSERT INTO test_results VALUES (13, 'MONTHLY on 2nd Monday',
    assert_occurrences_equal(
        'MONTHLY on 2nd Monday',
        ARRAY[
            '2025-01-13 10:00:00'::TIMESTAMP,  -- 2nd Monday of Jan 2025
            '2025-02-10 10:00:00'::TIMESTAMP,  -- 2nd Monday of Feb 2025
            '2025-03-10 10:00:00'::TIMESTAMP   -- 2nd Monday of Mar 2025
        ],
        (SELECT array_agg(occurrence) FROM "all"('FREQ=MONTHLY;BYDAY=2MO;COUNT=3', '2025-01-13 10:00:00'::TIMESTAMP) AS occurrence)
    ));

-- Test 14: MONTHLY on last Friday (BYDAY=-1FR)
INSERT INTO test_results VALUES (14, 'MONTHLY on last Friday',
    assert_occurrences_equal(
        'MONTHLY on last Friday',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,  -- Last Friday of Jan 2025
            '2025-02-28 10:00:00'::TIMESTAMP,  -- Last Friday of Feb 2025
            '2025-03-28 10:00:00'::TIMESTAMP   -- Last Friday of Mar 2025
        ],
        (SELECT array_agg(occurrence) FROM "all"('FREQ=MONTHLY;BYDAY=-1FR;COUNT=3', '2025-01-31 10:00:00'::TIMESTAMP) AS occurrence)
    ));

-- ============================================================================
-- TEST GROUP 8: Edge Cases
-- ============================================================================

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 8: Edge Cases'
\echo '==================================================================='

-- Test 15: MONTHLY on 31st - should skip months without 31 days
INSERT INTO test_results VALUES (15, 'MONTHLY BYMONTHDAY=31 skips short months',
    assert_occurrences_equal(
        'MONTHLY BYMONTHDAY=31 skips short months',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,  -- Jan 31 exists
            '2025-03-31 10:00:00'::TIMESTAMP,  -- Feb has no 31, Mar 31 exists
            '2025-05-31 10:00:00'::TIMESTAMP,  -- Apr has no 31, May 31 exists
            '2025-07-31 10:00:00'::TIMESTAMP   -- Jun has no 31, Jul 31 exists
        ],
        (SELECT array_agg(occurrence) FROM "all"('FREQ=MONTHLY;BYMONTHDAY=31;COUNT=4', '2025-01-31 10:00:00'::TIMESTAMP) AS occurrence)
    ));

-- Test 16: Leap year February 29th
INSERT INTO test_results VALUES (16, 'Leap year Feb 29th',
    assert_occurrences_equal(
        'Leap year Feb 29th',
        ARRAY[
            '2024-02-29 10:00:00'::TIMESTAMP   -- 2024 is leap year
        ],
        (SELECT array_agg(occurrence) FROM "all"('FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;COUNT=1', '2024-02-29 10:00:00'::TIMESTAMP) AS occurrence)
    ));

-- Test 17: after() helper function
INSERT INTO test_results VALUES (17, 'after() helper',
    (SELECT CASE
        WHEN result = '2025-01-02 10:00:00'::TIMESTAMP
        THEN 'PASS [after() helper]'
        ELSE 'FAIL [after() helper]: Expected 2025-01-02 10:00:00, got ' || result::TEXT
    END
    FROM (
        SELECT "after"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 12:00:00'::TIMESTAMP
        ) AS result
    ) sub));

-- ============================================================================
-- Print Test Results Summary
-- ============================================================================

\echo ''
\echo '==================================================================='
\echo 'TEST RESULTS SUMMARY'
\echo '==================================================================='

SELECT
    COUNT(*) AS total_tests,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') AS passed,
    COUNT(*) FILTER (WHERE status LIKE 'FAIL%') AS failed
FROM test_results;

\echo ''
\echo 'Detailed Results:'
\echo ''

SELECT
    test_number,
    CASE
        WHEN status LIKE 'PASS%' THEN 'PASS ' || test_name
        ELSE 'FAIL ' || test_name || ' - ' || status
    END AS result
FROM test_results
ORDER BY test_number;

-- Check if all tests passed
--
-- Note: BYYEARDAY, BYWEEKNO, and BYSETPOS features are comprehensively tested in:
-- - test_wkst_support.sql (BYWEEKNO tests)
-- - test_validation.sql (BYYEARDAY tests, BYSETPOS validation)
-- - test_rfc_compliance.sql (complex edge cases)

DO $$
DECLARE
    failed_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count
    FROM test_results
    WHERE status LIKE 'FAIL%';

    IF failed_count > 0 THEN
        RAISE EXCEPTION 'TEST SUITE FAILED: % test(s) failed', failed_count;
    ELSE
        RAISE NOTICE 'TEST SUITE PASSED: All tests passed successfully!';
    END IF;
END $$;

ROLLBACK;  -- Rollback to clean up test functions and tables
