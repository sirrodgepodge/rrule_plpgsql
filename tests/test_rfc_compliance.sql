/**
 * RFC 5545 & RFC 7529 Compliance Tests
 *
 * Tests RFC compliance for:
 * - RFC 7529 SKIP/RSCALE parameter relationships
 * - RSCALE auto-addition for RFC 7529 compliance
 * - RSCALE validation (only GREGORIAN supported)
 * - Backward compatibility with SKIP-only RRULEs
 *
 * Usage:
 *   psql -d your_database -f tests/test_rfc_compliance.sql
 *
 * Expected output: All tests pass
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
CREATE TEMP TABLE rfc_test_results (
    test_number SERIAL PRIMARY KEY,
    test_name TEXT,
    status TEXT
);

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 1: RFC 7529 - SKIP Without RSCALE (Auto-Addition)'
\echo '====================================================================='

-- Test 1: SKIP=BACKWARD without RSCALE (should auto-add GREGORIAN)
INSERT INTO rfc_test_results (test_name, status)
VALUES ('SKIP=BACKWARD without RSCALE (auto-add)',
    assert_occurrences_equal(
        'SKIP=BACKWARD auto-add RSCALE',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-04-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 2: SKIP=FORWARD without RSCALE (should auto-add GREGORIAN)
INSERT INTO rfc_test_results (test_name, status)
VALUES ('SKIP=FORWARD without RSCALE (auto-add)',
    assert_occurrences_equal(
        'SKIP=FORWARD auto-add RSCALE',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-01 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 3: SKIP=OMIT (default) without RSCALE (should NOT auto-add)
INSERT INTO rfc_test_results (test_name, status)
VALUES ('SKIP=OMIT without RSCALE (no auto-add)',
    assert_occurrences_equal(
        'SKIP=OMIT no RSCALE needed',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-31 10:00:00'::TIMESTAMP,
            '2025-07-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=OMIT;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 2: RFC 7529 - Explicit RSCALE=GREGORIAN'
\echo '====================================================================='

-- Test 4: SKIP=BACKWARD with explicit RSCALE=GREGORIAN
INSERT INTO rfc_test_results (test_name, status)
VALUES ('SKIP=BACKWARD with RSCALE=GREGORIAN',
    assert_occurrences_equal(
        'Explicit RSCALE=GREGORIAN BACKWARD',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-04-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;RSCALE=GREGORIAN;SKIP=BACKWARD;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 5: SKIP=FORWARD with explicit RSCALE=GREGORIAN
INSERT INTO rfc_test_results (test_name, status)
VALUES ('SKIP=FORWARD with RSCALE=GREGORIAN',
    assert_occurrences_equal(
        'Explicit RSCALE=GREGORIAN FORWARD',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-01 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;RSCALE=GREGORIAN;SKIP=FORWARD;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 6: RSCALE=GREGORIAN without SKIP (defaults to OMIT)
INSERT INTO rfc_test_results (test_name, status)
VALUES ('RSCALE=GREGORIAN without SKIP',
    assert_occurrences_equal(
        'RSCALE only, SKIP defaults to OMIT',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-31 10:00:00'::TIMESTAMP,
            '2025-07-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;RSCALE=GREGORIAN;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 3: RFC 7529 - RSCALE Validation'
\echo '====================================================================='

-- Test 7: Unsupported RSCALE value (should raise exception)
DO $$
DECLARE
    result TIMESTAMP[];
BEGIN
    -- This should fail with clear error message
    result := array(SELECT * FROM "all"(
        'FREQ=MONTHLY;BYMONTHDAY=31;RSCALE=HEBREW;SKIP=BACKWARD;COUNT=4',
        '2025-01-01 10:00:00'::TIMESTAMP
    ));

    -- If we get here, test failed
    RAISE EXCEPTION 'FAIL: RSCALE=HEBREW should have raised an exception';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%Unsupported RSCALE value%HEBREW%' THEN
            INSERT INTO rfc_test_results (test_name, status)
            VALUES ('RSCALE=HEBREW raises exception', 'PASS [RSCALE=HEBREW rejected]');
        ELSE
            RAISE EXCEPTION 'FAIL: Wrong exception for RSCALE=HEBREW: %', SQLERRM;
        END IF;
END $$;

-- Test 8: Case-insensitive RSCALE (gregorian -> GREGORIAN)
INSERT INTO rfc_test_results (test_name, status)
VALUES ('RSCALE=gregorian (lowercase) accepted',
    assert_occurrences_equal(
        'RSCALE case-insensitive',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-04-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;RSCALE=gregorian;SKIP=BACKWARD;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 4: Backward Compatibility'
\echo '====================================================================='

-- Test 9: No SKIP, no RSCALE (legacy behavior)
INSERT INTO rfc_test_results (test_name, status)
VALUES ('No SKIP, no RSCALE (legacy)',
    assert_occurrences_equal(
        'Legacy RRULE without SKIP/RSCALE',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-31 10:00:00'::TIMESTAMP,
            '2025-07-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 10: Complex RRULE with SKIP but no RSCALE (should work)
INSERT INTO rfc_test_results (test_name, status)
VALUES ('Complex RRULE with SKIP (auto-add RSCALE)',
    assert_occurrences_equal(
        'TZID + SKIP + multiple params',
        ARRAY[
            '2025-01-31 14:30:00'::TIMESTAMP,
            '2025-02-28 14:30:00'::TIMESTAMP,
            '2025-03-31 14:30:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD;INTERVAL=1;COUNT=3',
            '2025-01-01 14:30:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 5: RSCALE Parsing Edge Cases'
\echo '====================================================================='

-- Test 11: RSCALE in middle of RRULE string
INSERT INTO rfc_test_results (test_name, status)
VALUES ('RSCALE in middle of RRULE',
    assert_occurrences_equal(
        'RSCALE parameter position independence',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;RSCALE=GREGORIAN;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 12: RSCALE at end of RRULE string
INSERT INTO rfc_test_results (test_name, status)
VALUES ('RSCALE at end of RRULE',
    assert_occurrences_equal(
        'RSCALE at end',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=3;RSCALE=GREGORIAN',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 6: Integration with Other RFC 7529 Features'
\echo '====================================================================='

-- Test 13: RSCALE + SKIP with leap year
INSERT INTO rfc_test_results (test_name, status)
VALUES ('RSCALE + SKIP with leap year',
    assert_occurrences_equal(
        'RSCALE + SKIP leap year handling',
        ARRAY[
            '2024-02-29 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2026-02-28 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30;RSCALE=GREGORIAN;SKIP=BACKWARD;COUNT=3',
            '2024-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 14: RSCALE + SKIP with multiple BYMONTHDAY values (deduplication)
INSERT INTO rfc_test_results (test_name, status)
VALUES ('RSCALE + SKIP with deduplication',
    assert_occurrences_equal(
        'RSCALE + SKIP deduplication',
        ARRAY[
            '2025-01-30 10:00:00'::TIMESTAMP,
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2025-03-30 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence) FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=30,31;RSCALE=GREGORIAN;SKIP=BACKWARD;COUNT=5',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '====================================================================='
\echo 'Test Results Summary'
\echo '====================================================================='

-- Display all test results
SELECT
    test_number,
    test_name,
    status
FROM rfc_test_results
ORDER BY test_number;

-- Summary statistics
\echo ''
\echo 'Summary:'
SELECT
    COUNT(*) as total_tests,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') as passed,
    COUNT(*) FILTER (WHERE status LIKE 'FAIL%') as failed
FROM rfc_test_results;

-- Check if all tests passed
DO $$
DECLARE
    failed_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count
    FROM rfc_test_results
    WHERE status LIKE 'FAIL%';

    IF failed_count > 0 THEN
        RAISE EXCEPTION 'RFC COMPLIANCE TEST SUITE FAILED: % test(s) failed', failed_count;
    ELSE
        RAISE NOTICE 'RFC COMPLIANCE TEST SUITE PASSED: All tests passed successfully!';
    END IF;
END $$;

ROLLBACK;
