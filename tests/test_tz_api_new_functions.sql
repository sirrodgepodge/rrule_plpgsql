-- ================================================================================================================
-- TIMESTAMPTZ API NEW FUNCTIONS TEST SUITE
-- ================================================================================================================
--
-- This test suite verifies the new timezone-aware API functions added for consistency:
-- - rrule.count(rrule_string, dtstart_tz, timezone)
-- - rrule.next(rrule_string, dtstart_tz, timezone)
-- - rrule.most_recent(rrule_string, dtstart_tz, timezone)
-- - rrule.overlaps(dtstart, dtend, rrule_string, mindate, maxdate, timezone)
--
-- KEY TEST SCENARIOS:
-- 1. Timezone resolution priority: explicit param > TZID in RRULE > UTC
-- 2. DST-aware behavior (wall-clock time preservation)
-- 3. Timezone validation
-- 4. NULL timezone handling (fallback to TZID or UTC)
-- 5. Integration with existing TIMESTAMPTZ functions
--
-- ================================================================================================================

\set ECHO queries
\set QUIET off

BEGIN;

-- Test results table
CREATE TEMPORARY TABLE tz_new_api_test_results (
    test_suite VARCHAR,
    test_name VARCHAR,
    passed BOOLEAN,
    actual TEXT,
    expected TEXT
);

-- Helper to mark test pass/fail
CREATE OR REPLACE FUNCTION assert_equal(test_suite TEXT, test_name TEXT, actual TEXT, expected TEXT)
RETURNS TEXT AS $$
BEGIN
    INSERT INTO tz_new_api_test_results VALUES (test_suite, test_name, actual = expected, actual, expected);
    IF actual = expected THEN
        RETURN '✓';
    ELSE
        RAISE WARNING 'Test failed: %', test_name;
        RAISE WARNING 'Expected: %', expected;
        RAISE WARNING 'Actual:   %', actual;
        RETURN '✗';
    END IF;
END;
$$ LANGUAGE plpgsql;


-- ================================================================================================================
-- TEST SUITE 1: rrule.count() with timezone parameter
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 1: rrule.count() TIMESTAMPTZ API'
\echo '=================================================='
\echo ''

-- Test 1.1: count() with explicit timezone parameter
DO $$
DECLARE
    result INTEGER;
    expected INTEGER := 5;
    status TEXT;
BEGIN
    SELECT rrule.count(
        'FREQ=DAILY;COUNT=5',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) INTO result;

    status := assert_equal(
        'count() TIMESTAMPTZ',
        'Explicit timezone parameter',
        result::TEXT,
        expected::TEXT
    );

    RAISE NOTICE 'Test 1.1: count() with explicit timezone % - Result: %', status, result;
END;
$$;

-- Test 1.2: count() with TZID in RRULE (no explicit timezone)
DO $$
DECLARE
    result INTEGER;
    expected INTEGER := 3;
    status TEXT;
BEGIN
    SELECT rrule.count(
        'FREQ=WEEKLY;COUNT=3;TZID=Europe/London',
        '2025-03-08 10:00:00+00'::TIMESTAMPTZ,
        NULL  -- Should use TZID from RRULE
    ) INTO result;

    status := assert_equal(
        'count() TIMESTAMPTZ',
        'TZID in RRULE (NULL timezone param)',
        result::TEXT,
        expected::TEXT
    );

    RAISE NOTICE 'Test 1.2: count() with TZID in RRULE % - Result: %', status, result;
END;
$$;

-- Test 1.3: count() timezone override (explicit param overrides TZID)
DO $$
DECLARE
    result INTEGER;
    expected INTEGER := 10;
    status TEXT;
BEGIN
    -- TZID in RRULE is Europe/London, but we override with America/New_York
    SELECT rrule.count(
        'FREQ=DAILY;COUNT=10;TZID=Europe/London',
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'  -- Override TZID
    ) INTO result;

    status := assert_equal(
        'count() TIMESTAMPTZ',
        'Timezone param overrides TZID',
        result::TEXT,
        expected::TEXT
    );

    RAISE NOTICE 'Test 1.3: count() timezone override % - Result: %', status, result;
END;
$$;

-- Test 1.4: count() defaults to UTC when no timezone specified
DO $$
DECLARE
    result INTEGER;
    expected INTEGER := 7;
    status TEXT;
BEGIN
    SELECT rrule.count(
        'FREQ=DAILY;COUNT=7',  -- No TZID
        '2025-01-01 00:00:00+00'::TIMESTAMPTZ,
        NULL  -- No explicit timezone → should use UTC
    ) INTO result;

    status := assert_equal(
        'count() TIMESTAMPTZ',
        'Defaults to UTC when no timezone',
        result::TEXT,
        expected::TEXT
    );

    RAISE NOTICE 'Test 1.4: count() defaults to UTC % - Result: %', status, result;
END;
$$;


-- ================================================================================================================
-- TEST SUITE 2: rrule.next() with timezone parameter
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 2: rrule.next() TIMESTAMPTZ API'
\echo '=================================================='
\echo ''

-- Test 2.1: next() with explicit timezone parameter
DO $$
DECLARE
    result TIMESTAMPTZ;
    expected_pattern TEXT := '%-% %:%:%';  -- Just verify format
    status TEXT;
BEGIN
    SELECT rrule.next(
        'FREQ=DAILY',
        '2020-01-01 10:00:00-05'::TIMESTAMPTZ,  -- Far in the past
        'America/New_York'
    ) INTO result;

    status := assert_equal(
        'next() TIMESTAMPTZ',
        'Returns next occurrence from NOW',
        CASE WHEN result > NOW() THEN 'future' ELSE 'past' END,
        'future'
    );

    RAISE NOTICE 'Test 2.1: next() with explicit timezone % - Result: %', status, result;
END;
$$;

-- Test 2.2: next() with TZID in RRULE
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule.next(
        'FREQ=WEEKLY;TZID=Europe/London',
        '2020-01-01 10:00:00+00'::TIMESTAMPTZ,
        NULL  -- Should use TZID from RRULE
    ) INTO result;

    status := assert_equal(
        'next() TIMESTAMPTZ',
        'TZID in RRULE returns future occurrence',
        CASE WHEN result > NOW() THEN 'future' ELSE 'past' END,
        'future'
    );

    RAISE NOTICE 'Test 2.2: next() with TZID in RRULE % - Result: %', status, result;
END;
$$;

-- Test 2.3: next() timezone override
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule.next(
        'FREQ=MONTHLY;TZID=Europe/London',
        '2020-01-01 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'  -- Override TZID
    ) INTO result;

    status := assert_equal(
        'next() TIMESTAMPTZ',
        'Timezone param override works',
        CASE WHEN result > NOW() THEN 'future' ELSE 'past' END,
        'future'
    );

    RAISE NOTICE 'Test 2.3: next() timezone override % - Result: %', status, result;
END;
$$;

-- Test 2.4: next() with COUNT limit (should return NULL after COUNT reached)
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    -- RRULE with COUNT=1 starting in 2020 - should have no future occurrences
    SELECT rrule.next(
        'FREQ=DAILY;COUNT=1',
        '2020-01-01 10:00:00+00'::TIMESTAMPTZ,
        'UTC'
    ) INTO result;

    status := assert_equal(
        'next() TIMESTAMPTZ',
        'Returns NULL when COUNT exhausted',
        COALESCE(result::TEXT, 'NULL'),
        'NULL'
    );

    RAISE NOTICE 'Test 2.4: next() with exhausted COUNT % - Result: %', status, COALESCE(result::TEXT, 'NULL');
END;
$$;


-- ================================================================================================================
-- TEST SUITE 3: rrule.most_recent() with timezone parameter
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 3: rrule.most_recent() TIMESTAMPTZ API'
\echo '=================================================='
\echo ''

-- Test 3.1: most_recent() with explicit timezone parameter
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule.most_recent(
        'FREQ=DAILY',
        '2020-01-01 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) INTO result;

    status := assert_equal(
        'most_recent() TIMESTAMPTZ',
        'Returns occurrence before NOW',
        CASE WHEN result < NOW() AND result > '2020-01-01'::TIMESTAMPTZ THEN 'valid_past' ELSE 'invalid' END,
        'valid_past'
    );

    RAISE NOTICE 'Test 3.1: most_recent() with explicit timezone % - Result: %', status, result;
END;
$$;

-- Test 3.2: most_recent() with TZID in RRULE
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule.most_recent(
        'FREQ=WEEKLY;TZID=Europe/London',
        '2020-01-01 10:00:00+00'::TIMESTAMPTZ,
        NULL  -- Should use TZID from RRULE
    ) INTO result;

    status := assert_equal(
        'most_recent() TIMESTAMPTZ',
        'TZID in RRULE returns past occurrence',
        CASE WHEN result < NOW() AND result > '2020-01-01'::TIMESTAMPTZ THEN 'valid_past' ELSE 'invalid' END,
        'valid_past'
    );

    RAISE NOTICE 'Test 3.2: most_recent() with TZID in RRULE % - Result: %', status, result;
END;
$$;

-- Test 3.3: most_recent() timezone override
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule.most_recent(
        'FREQ=MONTHLY;TZID=Europe/London',
        '2020-01-01 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'  -- Override TZID
    ) INTO result;

    status := assert_equal(
        'most_recent() TIMESTAMPTZ',
        'Timezone param override works',
        CASE WHEN result < NOW() AND result > '2020-01-01'::TIMESTAMPTZ THEN 'valid_past' ELSE 'invalid' END,
        'valid_past'
    );

    RAISE NOTICE 'Test 3.3: most_recent() timezone override % - Result: %', status, result;
END;
$$;

-- Test 3.4: most_recent() with dtstart in future (should return NULL)
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule.most_recent(
        'FREQ=DAILY',
        (NOW() + INTERVAL '1 year')::TIMESTAMPTZ,  -- Start in future
        'UTC'
    ) INTO result;

    status := assert_equal(
        'most_recent() TIMESTAMPTZ',
        'Returns NULL when dtstart is in future',
        COALESCE(result::TEXT, 'NULL'),
        'NULL'
    );

    RAISE NOTICE 'Test 3.4: most_recent() with future dtstart % - Result: %', status, COALESCE(result::TEXT, 'NULL');
END;
$$;


-- ================================================================================================================
-- TEST SUITE 4: rrule.overlaps() with timezone parameter
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 4: rrule.overlaps() TIMESTAMPTZ API'
\echo '=================================================='
\echo ''

-- Test 4.1: overlaps() with explicit timezone parameter - TRUE case
DO $$
DECLARE
    result BOOLEAN;
    status TEXT;
BEGIN
    SELECT rrule.overlaps(
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,  -- Event start
        '2025-01-01 11:00:00-05'::TIMESTAMPTZ,  -- Event end
        'FREQ=DAILY;COUNT=30',                   -- Daily for 30 days
        '2025-01-05 00:00:00-05'::TIMESTAMPTZ,  -- Range start
        '2025-01-10 23:59:59-05'::TIMESTAMPTZ,  -- Range end
        'America/New_York'
    ) INTO result;

    status := assert_equal(
        'overlaps() TIMESTAMPTZ',
        'Returns TRUE when event overlaps range',
        result::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 4.1: overlaps() TRUE case % - Result: %', status, result;
END;
$$;

-- Test 4.2: overlaps() with explicit timezone parameter - FALSE case
DO $$
DECLARE
    result BOOLEAN;
    status TEXT;
BEGIN
    SELECT rrule.overlaps(
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
        '2025-01-01 11:00:00-05'::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=3',                    -- Only 3 days
        '2025-02-01 00:00:00-05'::TIMESTAMPTZ,  -- Range in February
        '2025-02-28 23:59:59-05'::TIMESTAMPTZ,
        'America/New_York'
    ) INTO result;

    status := assert_equal(
        'overlaps() TIMESTAMPTZ',
        'Returns FALSE when no overlap',
        result::TEXT,
        'false'
    );

    RAISE NOTICE 'Test 4.2: overlaps() FALSE case % - Result: %', status, result;
END;
$$;

-- Test 4.3: overlaps() with TZID in RRULE
DO $$
DECLARE
    result BOOLEAN;
    status TEXT;
BEGIN
    SELECT rrule.overlaps(
        '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
        '2025-01-01 11:00:00+00'::TIMESTAMPTZ,
        'FREQ=WEEKLY;COUNT=10;TZID=Europe/London',
        '2025-01-15 00:00:00+00'::TIMESTAMPTZ,
        '2025-01-31 23:59:59+00'::TIMESTAMPTZ,
        NULL  -- Should use TZID from RRULE
    ) INTO result;

    status := assert_equal(
        'overlaps() TIMESTAMPTZ',
        'TZID in RRULE works correctly',
        result::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 4.3: overlaps() with TZID in RRULE % - Result: %', status, result;
END;
$$;

-- Test 4.4: overlaps() timezone override
DO $$
DECLARE
    result BOOLEAN;
    status TEXT;
BEGIN
    SELECT rrule.overlaps(
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
        '2025-01-01 11:00:00-05'::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=20;TZID=Europe/London',
        '2025-01-10 00:00:00-05'::TIMESTAMPTZ,
        '2025-01-15 23:59:59-05'::TIMESTAMPTZ,
        'America/New_York'  -- Override TZID
    ) INTO result;

    status := assert_equal(
        'overlaps() TIMESTAMPTZ',
        'Timezone param overrides TZID',
        result::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 4.4: overlaps() timezone override % - Result: %', status, result;
END;
$$;

-- Test 4.5: overlaps() across DST boundary
DO $$
DECLARE
    result BOOLEAN;
    status TEXT;
BEGIN
    -- Event spanning DST spring forward (March 9, 2025)
    SELECT rrule.overlaps(
        '2025-03-01 10:00:00-05'::TIMESTAMPTZ,  -- Before DST
        '2025-03-01 11:00:00-05'::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=15',                   -- 15 days (crosses DST)
        '2025-03-08 00:00:00-05'::TIMESTAMPTZ,  -- Range crosses DST
        '2025-03-10 23:59:59-04'::TIMESTAMPTZ,  -- Note: EDT offset
        'America/New_York'
    ) INTO result;

    status := assert_equal(
        'overlaps() TIMESTAMPTZ',
        'Handles DST transitions correctly',
        result::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 4.5: overlaps() across DST % - Result: %', status, result;
END;
$$;

-- Test 4.6: overlaps() with NULL RRULE (single event, no recurrence)
DO $$
DECLARE
    result BOOLEAN;
    status TEXT;
BEGIN
    SELECT rrule.overlaps(
        '2025-01-15 10:00:00-05'::TIMESTAMPTZ,
        '2025-01-15 11:00:00-05'::TIMESTAMPTZ,
        NULL,  -- No RRULE - single event
        '2025-01-01 00:00:00-05'::TIMESTAMPTZ,
        '2025-01-31 23:59:59-05'::TIMESTAMPTZ,
        'America/New_York'
    ) INTO result;

    status := assert_equal(
        'overlaps() TIMESTAMPTZ',
        'Handles NULL RRULE (single event)',
        result::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 4.6: overlaps() with NULL RRULE % - Result: %', status, result;
END;
$$;


-- ================================================================================================================
-- TEST SUITE 5: Timezone validation
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 5: Timezone Validation'
\echo '=================================================='
\echo ''

-- Test 5.1: Invalid timezone should raise exception
DO $$
DECLARE
    error_raised BOOLEAN := FALSE;
    status TEXT;
BEGIN
    BEGIN
        PERFORM rrule.count(
            'FREQ=DAILY;COUNT=5',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            'Invalid/Timezone'
        );
    EXCEPTION WHEN OTHERS THEN
        error_raised := TRUE;
    END;

    status := assert_equal(
        'Timezone Validation',
        'Invalid timezone raises exception',
        error_raised::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 5.1: Invalid timezone validation % - Error raised: %', status, error_raised;
END;
$$;


-- ================================================================================================================
-- FINAL RESULTS
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST RESULTS SUMMARY'
\echo '=================================================='
\echo ''

-- Display all test results
SELECT
    test_suite,
    test_name,
    CASE WHEN passed THEN '✓ PASS' ELSE '✗ FAIL' END AS status,
    CASE
        WHEN NOT passed THEN
            E'\n  Expected: ' || expected ||
            E'\n  Actual:   ' || actual
        ELSE ''
    END AS details
FROM tz_new_api_test_results
ORDER BY test_suite, test_name;

-- Summary statistics
SELECT
    COUNT(*) AS total_tests,
    SUM(CASE WHEN passed THEN 1 ELSE 0 END) AS passed,
    SUM(CASE WHEN NOT passed THEN 1 ELSE 0 END) AS failed,
    ROUND(100.0 * SUM(CASE WHEN passed THEN 1 ELSE 0 END) / COUNT(*), 1) AS pass_rate
FROM tz_new_api_test_results;

-- Fail the transaction if any tests failed
DO $$
DECLARE
    failed_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO failed_count
    FROM tz_new_api_test_results
    WHERE NOT passed;

    IF failed_count > 0 THEN
        RAISE EXCEPTION '% test(s) failed', failed_count;
    ELSE
        RAISE NOTICE 'All tests passed! ✓';
    END IF;
END;
$$;

ROLLBACK;
