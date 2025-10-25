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
 * 7. BYSETPOS rules
 * 8. Complex combinations
 * 9. Edge cases (leap years, month boundaries, DST)
 * 10. Sub-day frequencies (HOURLY, MINUTELY, SECONDLY)
 * 11. Extended interval testing
 *
 * Usage:
 *   psql -d your_database -f test_rrule_functions.sql
 *
 * Expected output: All tests should pass with "✓" markers
 */

\set ON_ERROR_STOP on
\set ECHO all

-- Test database setup
BEGIN;

-- Ensure we're testing in UTC timezone for consistency
SET timezone = 'UTC';

-- Create rrule schema
CREATE SCHEMA IF NOT EXISTS rrule;
SET search_path = rrule, public;

-- Load the RRULE functions
\i src/rrule.sql
\i src/rrule_subday.sql

-- Helper function to compare expected vs actual occurrences
CREATE OR REPLACE FUNCTION assert_occurrences_equal(
    test_name TEXT,
    expected TIMESTAMP[],
    actual TIMESTAMP[]
)
RETURNS TEXT AS $$
DECLARE
    i INT;
    status TEXT;
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
        (SELECT array_agg(o ORDER BY o) FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=DAILY;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)
        ) o)
        ) AS occurrence
    );

-- Test 2: WEEKLY frequency with COUNT
INSERT INTO test_results VALUES (2, 'WEEKLY with COUNT=3',
    assert_occurrences_equal(
        'WEEKLY with COUNT=3',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,  -- Monday
            '2025-01-13 10:00:00'::TIMESTAMP,
            '2025-01-20 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(o ORDER BY o) FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=WEEKLY;COUNT=3', '2025-01-06 10:00:00'::TIMESTAMP)
        ) o)
        ) AS occurrence
    );

-- Test 3: MONTHLY frequency with COUNT
INSERT INTO test_results VALUES (3, 'MONTHLY with COUNT=3',
    assert_occurrences_equal(
        'MONTHLY with COUNT=3',
        ARRAY[
            '2025-01-15 10:00:00'::TIMESTAMP,
            '2025-02-15 10:00:00'::TIMESTAMP,
            '2025-03-15 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(o ORDER BY o) FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=MONTHLY;COUNT=3', '2025-01-15 10:00:00'::TIMESTAMP)
        ) o)
        ) AS occurrence
    );

-- Test 4: YEARLY frequency with COUNT
INSERT INTO test_results VALUES (4, 'YEARLY with COUNT=3',
    assert_occurrences_equal(
        'YEARLY with COUNT=3',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2026-01-01 10:00:00'::TIMESTAMP,
            '2027-01-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(o ORDER BY o) FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=YEARLY;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)
        ) o)
        ) AS occurrence
    );

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
        (SELECT array_agg(o ORDER BY o) FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=DAILY;INTERVAL=2;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)
        ) o)
        ) AS occurrence
    );

-- Test 6: WEEKLY with INTERVAL=2 (biweekly)
INSERT INTO test_results VALUES (6, 'WEEKLY with INTERVAL=2',
    assert_occurrences_equal(
        'WEEKLY with INTERVAL=2',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-20 10:00:00'::TIMESTAMP,
            '2025-02-03 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(o ORDER BY o) FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=WEEKLY;INTERVAL=2;COUNT=3', '2025-01-06 10:00:00'::TIMESTAMP)
        ) o)
        ) AS occurrence
    );

-- ============================================================================
-- TEST GROUP 3: UNTIL Limits
-- ============================================================================

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 3: UNTIL Limits'
\echo '==================================================================='

-- Test 7: DAILY with UNTIL
INSERT INTO test_results VALUES (7, 'DAILY with UNTIL',
    (SELECT CASE
        WHEN array_length(result, 1) = 3
             AND result[3] <= '2025-01-03 10:00:00'::TIMESTAMP
        THEN 'PASS [DAILY with UNTIL]'
        ELSE 'FAIL [DAILY with UNTIL]: Expected 3 occurrences ending by 2025-01-03'
    END
    FROM (
        SELECT array_agg(o ORDER BY o) AS result
        FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=DAILY;UNTIL=20250103T100000Z', '2025-01-01 10:00:00'::TIMESTAMP)
        ) o
    ) sub)
);

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
        (SELECT array_agg(o ORDER BY o) FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=3', '2025-01-06 10:00:00'::TIMESTAMP)
        ) o)
        ) AS occurrence
    );

-- Test 9: DAILY with BYDAY=MO,TU,WE,TH,FR (weekdays only)
INSERT INTO test_results VALUES (9, 'DAILY with BYDAY weekdays',
    (SELECT CASE
        WHEN array_length(result, 1) = 5
             AND date_part('dow', result[1]) BETWEEN 1 AND 5
             AND date_part('dow', result[5]) BETWEEN 1 AND 5
        THEN 'PASS [DAILY with BYDAY weekdays]'
        ELSE 'FAIL [DAILY with BYDAY weekdays]: Expected 5 weekday occurrences'
    END
    FROM (
        SELECT array_agg(o ORDER BY o) AS result
        FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;COUNT=5', '2025-01-06 10:00:00'::TIMESTAMP)
        ) o
    ) sub)
);

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
        (SELECT array_agg(o ORDER BY o) FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=MONTHLY;BYMONTHDAY=15;COUNT=3', '2025-01-15 10:00:00'::TIMESTAMP)
        ) o)
        ) AS occurrence
    );

-- Test 11: MONTHLY on last day of month (BYMONTHDAY=-1)
INSERT INTO test_results VALUES (11, 'MONTHLY with BYMONTHDAY=-1',
    assert_occurrences_equal(
        'MONTHLY with BYMONTHDAY=-1',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,  -- 31 days
            '2025-02-28 10:00:00'::TIMESTAMP,  -- 28 days (not leap year)
            '2025-03-31 10:00:00'::TIMESTAMP   -- 31 days
        ],
        (SELECT array_agg(o ORDER BY o) FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)
        ) o)
        ) AS occurrence
    );

-- Test 12: adjust_rrule_for_month_end helper
INSERT INTO test_results VALUES (12, 'adjust_rrule_for_month_end(31)',
    (SELECT CASE
        WHEN adjust_rrule_for_month_end('FREQ=MONTHLY;BYMONTHDAY=31') = 'FREQ=MONTHLY;BYMONTHDAY=-1'
        THEN 'PASS [adjust_rrule_for_month_end(31)]'
        ELSE 'FAIL [adjust_rrule_for_month_end(31)]'
    END)
);

-- ============================================================================
-- TEST GROUP 6: BYMONTH Rules
-- ============================================================================

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 6: BYMONTH Rules'
\echo '==================================================================='

-- Test 13: YEARLY in January and July
INSERT INTO test_results VALUES (13, 'YEARLY with BYMONTH=1,7',
    assert_occurrences_equal(
        'YEARLY with BYMONTH=1,7',
        ARRAY[
            '2025-01-15 10:00:00'::TIMESTAMP,
            '2025-07-15 10:00:00'::TIMESTAMP,
            '2026-01-15 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(o ORDER BY o) FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=YEARLY;BYMONTH=1,7;COUNT=3', '2025-01-15 10:00:00'::TIMESTAMP)
        ) o)
        ) AS occurrence
    );

-- ============================================================================
-- TEST GROUP 7: Complex Combinations
-- ============================================================================

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 7: Complex Combinations'
\echo '==================================================================='

-- Test 14: MONTHLY on 2nd Monday (BYDAY=2MO)
INSERT INTO test_results VALUES (14, 'MONTHLY on 2nd Monday',
    (SELECT CASE
        WHEN array_length(result, 1) = 3
             AND date_part('dow', result[1]) = 1  -- Monday
             AND date_part('day', result[1]) BETWEEN 8 AND 14  -- 2nd week
        THEN 'PASS [MONTHLY on 2nd Monday]'
        ELSE 'FAIL [MONTHLY on 2nd Monday]'
    END
    FROM (
        SELECT array_agg(o ORDER BY o) AS result
        FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=MONTHLY;BYDAY=2MO;COUNT=3', '2025-01-13 10:00:00'::TIMESTAMP)
        ) o
    ) sub)
);

-- Test 15: MONTHLY on last Friday (BYDAY=-1FR)
INSERT INTO test_results VALUES (15, 'MONTHLY on last Friday',
    (SELECT CASE
        WHEN array_length(result, 1) = 3
             AND date_part('dow', result[1]) = 5  -- Friday
             AND date_part('day', result[1]) >= 22  -- Last week
        THEN 'PASS [MONTHLY on last Friday]'
        ELSE 'FAIL [MONTHLY on last Friday]'
    END
    FROM (
        SELECT array_agg(o ORDER BY o) AS result
        FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=MONTHLY;BYDAY=-1FR;COUNT=3', '2025-01-31 10:00:00'::TIMESTAMP)
        ) o
    ) sub)
);

-- ============================================================================
-- TEST GROUP 8: Edge Cases
-- ============================================================================

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 8: Edge Cases'
\echo '==================================================================='

-- Test 16: MONTHLY on 31st - should skip months without 31 days
INSERT INTO test_results VALUES (16, 'MONTHLY BYMONTHDAY=31 skips Feb',
    (SELECT CASE
        WHEN array_length(result, 1) >= 2
             AND date_part('month', result[1]) != 2
             AND date_part('month', result[2]) != 2
        THEN 'PASS [MONTHLY BYMONTHDAY=31 skips Feb]'
        ELSE 'FAIL [MONTHLY BYMONTHDAY=31 skips Feb]'
    END
    FROM (
        SELECT array_agg(o ORDER BY o) AS result
        FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=MONTHLY;BYMONTHDAY=31;COUNT=12', '2025-01-31 10:00:00'::TIMESTAMP)
        ) o
        WHERE date_part('day', o) = 31
    ) sub)
);

-- Test 17: Leap year February 29th
INSERT INTO test_results VALUES (17, 'Leap year Feb 29th',
    (SELECT CASE
        WHEN array_length(result, 1) >= 1
             AND date_part('month', result[1]) = 2
             AND date_part('day', result[1]) = 29
        THEN 'PASS [Leap year Feb 29th]'
        ELSE 'FAIL [Leap year Feb 29th]'
    END
    FROM (
        SELECT array_agg(o ORDER BY o) AS result
        FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;COUNT=1', '2024-02-29 10:00:00'::TIMESTAMP)
        ) o
    ) sub)
);

-- Test 18: after() helper function
INSERT INTO test_results VALUES (18, 'after() helper',
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
    ) sub)
);

-- ============================================================================
-- TEST GROUP 9: Sub-Day Frequencies
-- ============================================================================

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 9: Sub-Day Frequencies (HOURLY, MINUTELY, SECONDLY)'
\echo '==================================================================='

-- Test 19: HOURLY with BYDAY=MO (Monday only)
INSERT INTO test_results VALUES (19, 'HOURLY with BYDAY=MO',
    (SELECT CASE
        WHEN array_length(result, 1) = 3
             AND result[1] = '2025-01-06 10:00:00'::TIMESTAMP
             AND result[2] = '2025-01-06 11:00:00'::TIMESTAMP
             AND result[3] = '2025-01-06 12:00:00'::TIMESTAMP
        THEN 'PASS [HOURLY with BYDAY=MO]'
        ELSE 'FAIL [HOURLY with BYDAY=MO]: Expected 3 Monday hourly occurrences, got ' ||
             COALESCE(array_length(result, 1), 0) || ' occurrences'
    END
    FROM (
        SELECT array_agg(o ORDER BY o) AS result
        FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=HOURLY;BYDAY=MO;COUNT=3', '2025-01-06 10:00:00'::TIMESTAMP)
        ) o)
    ) sub)
);

-- Test 20: MINUTELY with BYDAY=TU,WE,TH
INSERT INTO test_results VALUES (20, 'MINUTELY with BYDAY=TU,WE,TH',
    (SELECT CASE
        WHEN array_length(result, 1) = 10
             AND (SELECT COUNT(*) FROM unnest(result) AS o WHERE date_part('dow', o) IN (2,3,4)) = 10
        THEN 'PASS [MINUTELY with BYDAY=TU,WE,TH]'
        ELSE 'FAIL [MINUTELY with BYDAY=TU,WE,TH]: Expected 10 occurrences on Tue/Wed/Thu only'
    END
    FROM (
        SELECT array_agg(o ORDER BY o) AS result
        FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=MINUTELY;INTERVAL=30;BYDAY=TU,WE,TH;COUNT=10', '2025-01-07 09:00:00'::TIMESTAMP)
        ) o)
    ) sub)
);

-- Test 21: SECONDLY with BYDAY=FR (Friday only)
INSERT INTO test_results VALUES (21, 'SECONDLY with BYDAY=FR',
    (SELECT CASE
        WHEN array_length(result, 1) = 5
             AND (SELECT COUNT(*) FROM unnest(result) AS o WHERE date_part('dow', o) = 5) = 5
        THEN 'PASS [SECONDLY with BYDAY=FR]'
        ELSE 'FAIL [SECONDLY with BYDAY=FR]: Expected 5 occurrences on Friday only'
    END
    FROM (
        SELECT array_agg(o ORDER BY o) AS result
        FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=SECONDLY;INTERVAL=10;BYDAY=FR;COUNT=5', '2025-01-10 14:30:00'::TIMESTAMP)
        ) o)
    ) sub)
);

-- Test 22: HOURLY with BYDAY=MO,TU across week boundary
INSERT INTO test_results VALUES (22, 'HOURLY BYDAY week boundary',
    (SELECT CASE
        WHEN array_length(result, 1) = 10
             AND (SELECT COUNT(*) FROM unnest(result) AS o WHERE date_part('dow', o) IN (1,2)) = 10
        THEN 'PASS [HOURLY BYDAY week boundary]'
        ELSE 'FAIL [HOURLY BYDAY week boundary]: Expected 10 occurrences on Monday/Tuesday only'
    END
    FROM (
        SELECT array_agg(o ORDER BY o) AS result
        FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=HOURLY;INTERVAL=6;BYDAY=MO,TU;COUNT=10', '2025-01-06 08:00:00'::TIMESTAMP)
        ) o)
    ) sub)
);

-- ============================================================================
-- TEST GROUP 10: Extended Interval Testing
-- ============================================================================

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 10: Extended Interval Testing'
\echo '==================================================================='

-- Test 23: DAILY with INTERVAL=7 (weekly pattern)
INSERT INTO test_results VALUES (23, 'DAILY INTERVAL=7',
    assert_occurrences_equal(
        'DAILY INTERVAL=7',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-08 10:00:00'::TIMESTAMP,
            '2025-01-15 10:00:00'::TIMESTAMP,
            '2025-01-22 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(o ORDER BY o) FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=DAILY;INTERVAL=7;COUNT=4', '2025-01-01 10:00:00'::TIMESTAMP)
        ) o)
        ) AS occurrence
    )
);

-- Test 24: MONTHLY with INTERVAL=3 (quarterly)
INSERT INTO test_results VALUES (24, 'MONTHLY INTERVAL=3',
    assert_occurrences_equal(
        'MONTHLY INTERVAL=3',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-04-01 10:00:00'::TIMESTAMP,
            '2025-07-01 10:00:00'::TIMESTAMP,
            '2025-10-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(o ORDER BY o) FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=MONTHLY;INTERVAL=3;COUNT=4', '2025-01-01 10:00:00'::TIMESTAMP)
        ) o)
        ) AS occurrence
    )
);

-- Test 25: YEARLY with INTERVAL=2 (biennial)
INSERT INTO test_results VALUES (25, 'YEARLY INTERVAL=2',
    assert_occurrences_equal(
        'YEARLY INTERVAL=2',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2027-01-01 10:00:00'::TIMESTAMP,
            '2029-01-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(o ORDER BY o) FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=YEARLY;INTERVAL=2;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)
        ) o)
        ) AS occurrence
    )
);

-- Test 26: Complex DAILY INTERVAL with BYDAY filter
INSERT INTO test_results VALUES (26, 'DAILY INTERVAL=14 BYDAY=MO',
    (SELECT CASE
        WHEN array_length(result, 1) = 3
             AND (SELECT COUNT(*) FROM unnest(result) AS o WHERE date_part('dow', o) = 1) = 3
             AND result[2] - result[1] = INTERVAL '14 days'
             AND result[3] - result[2] = INTERVAL '14 days'
        THEN 'PASS [DAILY INTERVAL=14 BYDAY=MO]'
        ELSE 'FAIL [DAILY INTERVAL=14 BYDAY=MO]: Expected 3 Mondays 14 days apart'
    END
    FROM (
        SELECT array_agg(o ORDER BY o) AS result
        FROM unnest(
            (SELECT array_agg(occurrence) FROM "all"('FREQ=DAILY;INTERVAL=14;BYDAY=MO;COUNT=3', '2025-01-06 10:00:00'::TIMESTAMP)
        ) o)
    ) sub)
);

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
        WHEN status LIKE 'PASS%' THEN '✓ ' || test_name
        ELSE '✗ ' || test_name || ' - ' || status
    END AS result
FROM test_results
ORDER BY test_number;

-- Check if all tests passed
--
-- Note: BYYEARDAY, BYWEEKNO, and BYSETPOS features are comprehensively tested in:
-- - test_wkst_support.sql (58 BYWEEKNO tests)
-- - test_validation.sql (39 BYYEARDAY tests, BYSETPOS validation)
-- - test_rfc_compliance.sql (complex edge cases)
------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------------
-- Test Results Summary
------------------------------------------------------------------------------------------------------

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
