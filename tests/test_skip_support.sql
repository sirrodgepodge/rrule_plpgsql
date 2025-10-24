/**
 * RFC 7529 SKIP Parameter Tests
 *
 * Tests the SKIP parameter for handling invalid dates in BYMONTHDAY:
 * - SKIP=OMIT (default): Skip invalid dates entirely
 * - SKIP=BACKWARD: Use last valid day of month
 * - SKIP=FORWARD: Use first day of next month
 *
 * Usage:
 *   psql -d your_database -f tests/test_skip_support.sql
 *
 * Expected output: All tests pass with ✓ markers
 */

\set ON_ERROR_STOP on
\set ECHO all

-- Test database setup
BEGIN;

-- Ensure we're testing in UTC timezone for consistency
SET timezone = 'UTC';
SET search_path = rrule, public;

-- Load the RRULE functions if not already loaded
\i src/rrule.sql
\i src/rrule_wrappers.sql

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
    IF array_length(expected, 1) IS DISTINCT FROM array_length(actual, 1) THEN
        RAISE EXCEPTION 'FAIL [%]: Expected % occurrences, got %',
            test_name,
            COALESCE(array_length(expected, 1), 0),
            COALESCE(array_length(actual, 1), 0);
    END IF;

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
CREATE TEMP TABLE skip_test_results (
    test_number SERIAL PRIMARY KEY,
    test_name TEXT,
    status TEXT
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 1: SKIP=OMIT (Default RFC 7529 behavior)'
\echo '==================================================================='

-- Test 1: SKIP=OMIT on Feb 31 (explicit)
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=OMIT on Feb 31 (explicit)',
    assert_occurrences_equal(
        'SKIP=OMIT explicit',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,  -- Jan has 31 days ✓
            '2025-03-31 10:00:00'::TIMESTAMP,  -- Feb 31 skipped (OMIT)
            '2025-05-31 10:00:00'::TIMESTAMP,  -- Apr 31 skipped (OMIT)
            '2025-07-31 10:00:00'::TIMESTAMP   -- Jun 31 skipped (OMIT)
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=OMIT;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
);

-- Test 2: SKIP=OMIT on Feb 31 (default, no SKIP parameter)
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=OMIT on Feb 31 (default)',
    assert_occurrences_equal(
        'SKIP=OMIT default',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-31 10:00:00'::TIMESTAMP,
            '2025-07-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;COUNT=4',  -- No SKIP, defaults to OMIT
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
);

-- Test 3: SKIP=OMIT on Feb 30
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=OMIT on Feb 30',
    assert_occurrences_equal(
        'SKIP=OMIT on day 30',
        ARRAY[
            '2025-01-30 10:00:00'::TIMESTAMP,  -- Jan 30 ✓
            '2025-03-30 10:00:00'::TIMESTAMP,  -- Feb 30 skipped (OMIT)
            '2025-04-30 10:00:00'::TIMESTAMP,  -- Apr 30 ✓
            '2025-05-30 10:00:00'::TIMESTAMP   -- May 30 ✓
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=30;SKIP=OMIT;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 2: SKIP=BACKWARD (Use last valid day)'
\echo '==================================================================='

-- Test 4: SKIP=BACKWARD on Feb 31
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=BACKWARD on Feb 31',
    assert_occurrences_equal(
        'SKIP=BACKWARD on day 31',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,  -- Jan 31 ✓
            '2025-02-28 10:00:00'::TIMESTAMP,  -- Feb 31 → 28 (BACKWARD)
            '2025-03-31 10:00:00'::TIMESTAMP,  -- Mar 31 ✓
            '2025-04-30 10:00:00'::TIMESTAMP   -- Apr 31 → 30 (BACKWARD)
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
);

-- Test 5: SKIP=BACKWARD on Feb 30
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=BACKWARD on Feb 30',
    assert_occurrences_equal(
        'SKIP=BACKWARD on day 30',
        ARRAY[
            '2025-01-30 10:00:00'::TIMESTAMP,  -- Jan 30 ✓
            '2025-02-28 10:00:00'::TIMESTAMP,  -- Feb 30 → 28 (BACKWARD)
            '2025-03-30 10:00:00'::TIMESTAMP,  -- Mar 30 ✓
            '2025-04-30 10:00:00'::TIMESTAMP   -- Apr 30 ✓
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=30;SKIP=BACKWARD;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
);

-- Test 6: SKIP=BACKWARD with leap year
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=BACKWARD with leap year',
    assert_occurrences_equal(
        'SKIP=BACKWARD leap year',
        ARRAY[
            '2024-02-29 10:00:00'::TIMESTAMP,  -- Leap year: Feb 30 → 29
            '2025-02-28 10:00:00'::TIMESTAMP,  -- Normal year: Feb 30 → 28
            '2026-02-28 10:00:00'::TIMESTAMP   -- Normal year: Feb 30 → 28
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30;SKIP=BACKWARD;COUNT=3',
            '2024-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 3: SKIP=FORWARD (Use first of next month)'
\echo '==================================================================='

-- Test 7: SKIP=FORWARD on Feb 31
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=FORWARD on Feb 31',
    assert_occurrences_equal(
        'SKIP=FORWARD on day 31',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,  -- Jan 31 ✓
            '2025-03-01 10:00:00'::TIMESTAMP,  -- Feb 31 → Mar 1 (FORWARD)
            '2025-03-31 10:00:00'::TIMESTAMP,  -- Mar 31 ✓
            '2025-05-01 10:00:00'::TIMESTAMP   -- Apr 31 → May 1 (FORWARD)
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
);

-- Test 8: SKIP=FORWARD on Feb 30
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=FORWARD on Feb 30',
    assert_occurrences_equal(
        'SKIP=FORWARD on day 30',
        ARRAY[
            '2025-01-30 10:00:00'::TIMESTAMP,  -- Jan 30 ✓
            '2025-03-01 10:00:00'::TIMESTAMP,  -- Feb 30 → Mar 1 (FORWARD)
            '2025-03-30 10:00:00'::TIMESTAMP,  -- Mar 30 ✓
            '2025-04-30 10:00:00'::TIMESTAMP   -- Apr 30 ✓
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=30;SKIP=FORWARD;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 4: Multiple BYMONTHDAY values with SKIP'
\echo '==================================================================='

-- Test 9: Multiple days with SKIP=BACKWARD (deduplication test)
INSERT INTO skip_test_results (test_name, status)
VALUES ('Multiple BYMONTHDAY with SKIP=BACKWARD',
    assert_occurrences_equal(
        'Multiple days BACKWARD',
        ARRAY[
            '2025-01-30 10:00:00'::TIMESTAMP,  -- Jan 30 ✓
            '2025-01-31 10:00:00'::TIMESTAMP,  -- Jan 31 ✓
            '2025-02-28 10:00:00'::TIMESTAMP,  -- Feb 30 → 28, Feb 31 → 28 (deduped!)
            '2025-03-30 10:00:00'::TIMESTAMP,  -- Mar 30 ✓
            '2025-03-31 10:00:00'::TIMESTAMP   -- Mar 31 ✓
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=30,31;SKIP=BACKWARD;COUNT=5',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
);

-- Test 10: Multiple days with SKIP=OMIT
INSERT INTO skip_test_results (test_name, status)
VALUES ('Multiple BYMONTHDAY with SKIP=OMIT',
    assert_occurrences_equal(
        'Multiple days OMIT',
        ARRAY[
            '2025-01-30 10:00:00'::TIMESTAMP,  -- Jan 30 ✓
            '2025-01-31 10:00:00'::TIMESTAMP,  -- Jan 31 ✓
            '2025-03-30 10:00:00'::TIMESTAMP,  -- Feb skipped
            '2025-03-31 10:00:00'::TIMESTAMP,  -- Feb skipped
            '2025-04-30 10:00:00'::TIMESTAMP   -- Apr 30 ✓, Apr 31 skipped
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=30,31;SKIP=OMIT;COUNT=5',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 5: SKIP with BYDAY intersection'
\echo '==================================================================='

-- Test 11: SKIP=BACKWARD with BYDAY (filters after adjustment)
-- Feb 31 → Feb 28 (BACKWARD), Feb 28, 2025 IS Friday, so it passes BYDAY filter
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=BACKWARD with BYDAY filter',
    assert_occurrences_equal(
        'SKIP+BYDAY interaction',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,  -- Jan 31 = Friday ✓
            '2025-02-28 10:00:00'::TIMESTAMP   -- Feb 31 → 28 (BACKWARD), Feb 28 = Friday ✓
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;BYDAY=FR;SKIP=BACKWARD;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 6: SKIP with negative BYMONTHDAY (always valid)'
\echo '==================================================================='

-- Test 12: Negative BYMONTHDAY unaffected by SKIP
INSERT INTO skip_test_results (test_name, status)
VALUES ('Negative BYMONTHDAY ignores SKIP',
    assert_occurrences_equal(
        'Negative BYMONTHDAY',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,  -- -1 = last day = Jan 31
            '2025-02-28 10:00:00'::TIMESTAMP,  -- -1 = last day = Feb 28
            '2025-03-31 10:00:00'::TIMESTAMP,  -- -1 = last day = Mar 31
            '2025-04-30 10:00:00'::TIMESTAMP   -- -1 = last day = Apr 30
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=-1;SKIP=FORWARD;COUNT=4',  -- SKIP ignored
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 7: SKIP with YEARLY frequency'
\echo '==================================================================='

-- Test 13: YEARLY with SKIP=BACKWARD
INSERT INTO skip_test_results (test_name, status)
VALUES ('YEARLY;BYMONTH=2;BYMONTHDAY=31;SKIP=BACKWARD',
    assert_occurrences_equal(
        'YEARLY SKIP=BACKWARD',
        ARRAY[
            '2025-02-28 10:00:00'::TIMESTAMP,  -- 2025: Feb 31 → 28
            '2026-02-28 10:00:00'::TIMESTAMP,  -- 2026: Feb 31 → 28
            '2027-02-28 10:00:00'::TIMESTAMP   -- 2027: Feb 31 → 28
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
);

-- Test 14: YEARLY with SKIP=OMIT (skips entire year)
INSERT INTO skip_test_results (test_name, status)
VALUES ('YEARLY;BYMONTH=2;BYMONTHDAY=31;SKIP=OMIT',
    assert_occurrences_equal(
        'YEARLY SKIP=OMIT',
        ARRAY[]::TIMESTAMP[],  -- All years skipped (Feb never has 31 days)
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=31;SKIP=OMIT;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 8: Time preservation with SKIP'
\echo '==================================================================='

-- Test 15: SKIP preserves time component
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP preserves time component',
    assert_occurrences_equal(
        'Time preservation',
        ARRAY[
            '2025-01-31 14:30:00'::TIMESTAMP,  -- 2:30 PM preserved
            '2025-02-28 14:30:00'::TIMESTAMP,  -- 2:30 PM preserved (BACKWARD)
            '2025-03-31 14:30:00'::TIMESTAMP   -- 2:30 PM preserved
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=3',
            '2025-01-01 14:30:00'::TIMESTAMP
        ) AS occurrence
    )
);

\echo ''
\echo '==================================================================='
\echo 'Test Results Summary'
\echo '==================================================================='

-- Display all test results
SELECT
    test_number,
    test_name,
    status
FROM skip_test_results
ORDER BY test_number;

-- Summary statistics
\echo ''
\echo 'Summary:'
SELECT
    COUNT(*) as total_tests,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') as passed,
    COUNT(*) FILTER (WHERE status LIKE 'FAIL%') as failed
FROM skip_test_results;

-- Check if all tests passed
DO $$
DECLARE
    failed_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count
    FROM skip_test_results
    WHERE status LIKE 'FAIL%';

    IF failed_count > 0 THEN
        RAISE EXCEPTION 'SKIP TEST SUITE FAILED: % test(s) failed', failed_count;
    ELSE
        RAISE NOTICE 'SKIP TEST SUITE PASSED: All tests passed successfully!';
    END IF;
END $$;

ROLLBACK;
