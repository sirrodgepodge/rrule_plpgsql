-- ================================================================================================================
-- TIMEZONE-AWARE API TEST SUITE
-- ================================================================================================================
--
-- This test suite verifies that the timezone-aware API properly preserves wall-clock times across
-- Daylight Saving Time (DST) transitions.
--
-- KEY TEST SCENARIOS:
-- 1. DST Spring Forward (March 2025) - Wall-clock times should stay constant despite gaining an hour
-- 2. DST Fall Back (November 2025) - Wall-clock times should stay constant despite repeating an hour
-- 3. Multiple timezone support
-- 4. TZID parameter in RRULE string
-- 5. Explicit timezone parameter override
-- 6. UTC timezone (no DST)
-- 7. Range queries across DST boundaries
--
-- ================================================================================================================

\set ON_ERROR_STOP on
\set ECHO queries
\set QUIET off

BEGIN;

-- Test results table
CREATE TEMPORARY TABLE tz_api_test_results (
    test_suite VARCHAR,
    test_name VARCHAR,
    passed BOOLEAN,
    actual TEXT,
    expected TEXT
);

-- Helper function for simple assert tests (used by count/next/most_recent/overlaps tests)
CREATE OR REPLACE FUNCTION assert_equal(test_suite TEXT, test_name TEXT, actual TEXT, expected TEXT)
RETURNS TEXT AS $$
BEGIN
    INSERT INTO tz_api_test_results VALUES (test_suite, test_name, actual = expected, actual, expected);
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
-- TEST SUITE 1: DST Spring Forward (March 9, 2025 - America/New_York)
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 1: DST Spring Forward'
\echo '=================================================='
\echo 'Scenario: Daily meeting at 10:00 AM EST/EDT'
\echo 'Expected: Wall-clock time stays at 10:00 AM across DST boundary'
\echo 'Date: March 8-10, 2025 (DST spring forward on March 9 at 2 AM)'
\echo ''

-- Test 1.1: DAILY frequency across spring forward
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-08 10:00:00 EST',  -- Saturday, before DST
        '2025-03-09 10:00:00 EDT',  -- Sunday, after spring forward ← KEY TEST
        '2025-03-10 10:00:00 EDT'   -- Monday, after DST
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    -- Generate 3 daily occurrences starting March 8, 2025 at 10 AM EST
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,  -- 10 AM EST
        'America/New_York'
    ) ts;

    -- Format for comparison
    SELECT array_agg(to_char(ts, 'YYYY-MM-DD HH24:MI:SS TZ')) INTO actual FROM unnest(results) ts;

    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'DST Spring Forward',
        'DAILY frequency preserves 10 AM across spring forward',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );

    IF NOT matches THEN
        RAISE WARNING 'Test failed! Expected wall-clock time to stay at 10:00 AM';
        RAISE WARNING 'Expected: %', array_to_string(expected, ', ');
        RAISE WARNING 'Actual:   %', array_to_string(actual, ', ');
    END IF;
END;
$$;

-- Test 1.2: WEEKLY frequency across spring forward
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-08 10:00:00 EST',  -- Saturday
        '2025-03-15 10:00:00 EDT',  -- Next Saturday (after DST)
        '2025-03-22 10:00:00 EDT'   -- Next Saturday
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=WEEKLY;COUNT=3',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg(to_char(ts, 'YYYY-MM-DD HH24:MI:SS TZ')) INTO actual FROM unnest(results) ts;
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'DST Spring Forward',
        'WEEKLY frequency preserves 10 AM across spring forward',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;

-- Test 1.3: TZID parameter in RRULE string (no explicit timezone)
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-08 10:00:00 EST',
        '2025-03-09 10:00:00 EDT',
        '2025-03-10 10:00:00 EDT'
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    -- Use TZID in RRULE string instead of explicit parameter
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'TZID=America/New_York;FREQ=DAILY;COUNT=3',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        NULL  -- No explicit timezone, should use TZID from RRULE
    ) ts;

    SELECT array_agg(to_char(ts, 'YYYY-MM-DD HH24:MI:SS TZ')) INTO actual FROM unnest(results) ts;
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'DST Spring Forward',
        'TZID in RRULE string works correctly',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;


-- ================================================================================================================
-- TEST SUITE 2: DST Fall Back (November 2, 2025 - America/New_York)
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 2: DST Fall Back'
\echo '=================================================='
\echo 'Scenario: Daily meeting at 10:00 AM EDT/EST'
\echo 'Expected: Wall-clock time stays at 10:00 AM across DST boundary'
\echo 'Date: November 1-3, 2025 (DST fall back on November 2 at 2 AM)'
\echo ''

-- Test 2.1: DAILY frequency across fall back
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-11-01 10:00:00 EDT',  -- Saturday, before DST
        '2025-11-02 10:00:00 EST',  -- Sunday, after fall back ← KEY TEST
        '2025-11-03 10:00:00 EST'   -- Monday, after DST
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3',
        '2025-11-01 10:00:00-04'::TIMESTAMPTZ,  -- 10 AM EDT
        'America/New_York'
    ) ts;

    SELECT array_agg(to_char(ts, 'YYYY-MM-DD HH24:MI:SS TZ')) INTO actual FROM unnest(results) ts;
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'DST Fall Back',
        'DAILY frequency preserves 10 AM across fall back',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );

    IF NOT matches THEN
        RAISE WARNING 'Test failed! Expected wall-clock time to stay at 10:00 AM';
        RAISE WARNING 'Expected: %', array_to_string(expected, ', ');
        RAISE WARNING 'Actual:   %', array_to_string(actual, ', ');
    END IF;
END;
$$;


-- ================================================================================================================
-- TEST SUITE 3: UTC Timezone (No DST)
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 3: UTC Timezone'
\echo '=================================================='
\echo 'Scenario: UTC has no DST, should behave consistently'
\echo ''

-- Test 3.1: DAILY in UTC
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-08 10:00:00 UTC',
        '2025-03-09 10:00:00 UTC',
        '2025-03-10 10:00:00 UTC'
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3',
        '2025-03-08 10:00:00+00'::TIMESTAMPTZ,
        'UTC'
    ) ts;

    -- Convert to target timezone (UTC) before formatting
    SELECT array_agg(to_char(ts AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS') || ' UTC') INTO actual FROM unnest(results) ts;
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'UTC Timezone',
        'UTC has no DST drift',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;


-- ================================================================================================================
-- TEST SUITE 4: Different Timezones
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 4: Multiple Timezones'
\echo '=================================================='
\echo 'Scenario: Test various timezones with different DST rules'
\echo ''

-- Test 4.1: Los Angeles (different DST dates than NY)
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-08 10:00:00 PST',
        '2025-03-09 10:00:00 PDT',  -- DST spring forward (same date as NY)
        '2025-03-10 10:00:00 PDT'
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3',
        '2025-03-08 10:00:00-08'::TIMESTAMPTZ,
        'America/Los_Angeles'
    ) ts;

    -- Convert to target timezone and detect DST abbreviation based on LA offset
    SELECT array_agg(
        to_char(ts AT TIME ZONE 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI:SS') || ' ' ||
        CASE
            -- Calculate LA offset: (epoch_utc - epoch_naive) / 3600
            WHEN (EXTRACT(epoch FROM ts)::bigint - EXTRACT(epoch FROM (ts AT TIME ZONE 'America/Los_Angeles'))::bigint) / 3600 = 8
            THEN 'PST'
            ELSE 'PDT'
        END
    ) INTO actual FROM unnest(results) ts;
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'Multiple Timezones',
        'Los Angeles PST/PDT transition works correctly',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;

-- Test 4.2: Europe/London (different DST rules)
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-29 10:00:00 GMT',  -- Saturday before DST
        '2025-03-30 10:00:00 BST',  -- Sunday, spring forward to BST
        '2025-03-31 10:00:00 BST'   -- Monday
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3',
        '2025-03-29 10:00:00+00'::TIMESTAMPTZ,
        'Europe/London'
    ) ts;

    -- Convert to target timezone and detect GMT/BST based on London offset
    SELECT array_agg(
        to_char(ts AT TIME ZONE 'Europe/London', 'YYYY-MM-DD HH24:MI:SS') || ' ' ||
        CASE
            -- Calculate London offset: (epoch_utc - epoch_naive) / 3600
            -- GMT = 0, BST = -1 (negative because London is ahead of UTC in summer)
            WHEN (EXTRACT(epoch FROM ts)::bigint - EXTRACT(epoch FROM (ts AT TIME ZONE 'Europe/London'))::bigint) / 3600 = 0
            THEN 'GMT'
            ELSE 'BST'
        END
    ) INTO actual FROM unnest(results) ts;
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'Multiple Timezones',
        'London GMT/BST transition works correctly',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;


-- ================================================================================================================
-- TEST SUITE 5: Range Queries
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 5: Range Queries (between)'
\echo '=================================================='
\echo 'Scenario: Query occurrences within a date range spanning DST'
\echo ''

-- Test 5.1: between() across spring forward
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-09 10:00:00 EDT',  -- Only the middle occurrence
        '2025-03-10 10:00:00 EDT'
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."between"(
        'FREQ=DAILY;COUNT=10',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        '2025-03-09 00:00:00-04'::TIMESTAMPTZ,  -- Range: March 9-10
        '2025-03-11 00:00:00-04'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg(to_char(ts, 'YYYY-MM-DD HH24:MI:SS TZ')) INTO actual FROM unnest(results) ts;
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'Range Queries',
        'between() works across DST boundary',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;


-- ================================================================================================================
-- TEST SUITE 6: Offset Queries
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 6: Offset Queries (after/before)'
\echo '=================================================='
\echo 'Scenario: Get N occurrences after/before a date'
\echo ''

-- Test 6.1: after() across DST
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-09 10:00:00 EDT',
        '2025-03-10 10:00:00 EDT'
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."after"(
        'FREQ=DAILY;COUNT=10',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        '2025-03-08 15:00:00-05'::TIMESTAMPTZ,  -- After first occurrence
        2,  -- Get 2 occurrences
        'America/New_York'
    ) ts;

    SELECT array_agg(to_char(ts, 'YYYY-MM-DD HH24:MI:SS TZ')) INTO actual FROM unnest(results) ts;
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'Offset Queries',
        'after() works across DST boundary',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;

-- Test 6.2: before() across DST
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-08 10:00:00 EST',
        '2025-03-09 10:00:00 EDT'
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."before"(
        'FREQ=DAILY;COUNT=10',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        '2025-03-10 00:00:00-04'::TIMESTAMPTZ,  -- Before last occurrence
        2,  -- Get 2 occurrences
        'America/New_York'
    ) ts;

    SELECT array_agg(to_char(ts, 'YYYY-MM-DD HH24:MI:SS TZ')) INTO actual FROM unnest(results) ts;
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'Offset Queries',
        'before() works across DST boundary',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;


-- ================================================================================================================
-- TEST SUITE 7: Complex RRULE Patterns
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 7: Complex Patterns'
\echo '=================================================='
\echo 'Scenario: Test complex RRULE patterns with BYxxx rules'
\echo ''

-- Test 7.1: BYDAY with DST
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-10 10:00:00 EDT',  -- Monday (first after DST)
        '2025-03-12 10:00:00 EDT',  -- Wednesday
        '2025-03-14 10:00:00 EDT'   -- Friday
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=DAILY;BYDAY=MO,WE,FR;COUNT=3',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,  -- Saturday (not included)
        'America/New_York'
    ) ts;

    SELECT array_agg(to_char(ts, 'YYYY-MM-DD HH24:MI:SS TZ')) INTO actual FROM unnest(results) ts;
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'Complex Patterns',
        'BYDAY filter works across DST',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;

-- Test 7.2: MONTHLY with DST
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-02-15 10:00:00 EST',  -- Before DST
        '2025-03-15 10:00:00 EDT',  -- After DST spring forward
        '2025-04-15 10:00:00 EDT'   -- After DST
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=15;COUNT=3',
        '2025-02-15 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg(to_char(ts, 'YYYY-MM-DD HH24:MI:SS TZ')) INTO actual FROM unnest(results) ts;
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'Complex Patterns',
        'MONTHLY frequency works across DST',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;


-- ================================================================================================================
-- TEST SUITE 8: rrule.count() with timezone parameter
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 8: rrule.count() TIMESTAMPTZ API'
\echo '=================================================='
\echo ''

-- Test 8.1: count() with explicit timezone parameter
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
        'count() API',
        'Explicit timezone parameter',
        result::TEXT,
        expected::TEXT
    );

    RAISE NOTICE 'Test 8.1: count() with explicit timezone % - Result: %', status, result;
END;
$$;

-- Test 8.2: count() with TZID in RRULE (no explicit timezone)
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
        'count() API',
        'TZID in RRULE (NULL timezone param)',
        result::TEXT,
        expected::TEXT
    );

    RAISE NOTICE 'Test 8.2: count() with TZID in RRULE % - Result: %', status, result;
END;
$$;

-- Test 8.3: count() timezone override (explicit param overrides TZID)
DO $$
DECLARE
    result INTEGER;
    expected INTEGER := 10;
    status TEXT;
BEGIN
    SELECT rrule.count(
        'FREQ=DAILY;COUNT=10;TZID=Europe/London',
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'  -- Override TZID
    ) INTO result;

    status := assert_equal(
        'count() API',
        'Timezone param overrides TZID',
        result::TEXT,
        expected::TEXT
    );

    RAISE NOTICE 'Test 8.3: count() timezone override % - Result: %', status, result;
END;
$$;

-- Test 8.4: count() defaults to UTC when no timezone specified
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
        'count() API',
        'Defaults to UTC when no timezone',
        result::TEXT,
        expected::TEXT
    );

    RAISE NOTICE 'Test 8.4: count() defaults to UTC % - Result: %', status, result;
END;
$$;


-- ================================================================================================================
-- TEST SUITE 9: rrule.next() with timezone parameter
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 9: rrule.next() TIMESTAMPTZ API'
\echo '=================================================='
\echo ''

-- Test 9.1: next() with explicit timezone parameter
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule.next(
        'FREQ=DAILY',
        '2020-01-01 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) INTO result;

    status := assert_equal(
        'next() API',
        'Returns next occurrence from NOW',
        CASE WHEN result > NOW() THEN 'future' ELSE 'past' END,
        'future'
    );

    RAISE NOTICE 'Test 9.1: next() with explicit timezone % - Result: %', status, result;
END;
$$;

-- Test 9.2: next() with TZID in RRULE
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule.next(
        'FREQ=WEEKLY;TZID=Europe/London',
        '2020-01-01 10:00:00+00'::TIMESTAMPTZ,
        NULL
    ) INTO result;

    status := assert_equal(
        'next() API',
        'TZID in RRULE returns future occurrence',
        CASE WHEN result > NOW() THEN 'future' ELSE 'past' END,
        'future'
    );

    RAISE NOTICE 'Test 9.2: next() with TZID in RRULE % - Result: %', status, result;
END;
$$;

-- Test 9.3: next() timezone override
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule.next(
        'FREQ=MONTHLY;TZID=Europe/London',
        '2020-01-01 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) INTO result;

    status := assert_equal(
        'next() API',
        'Timezone param override works',
        CASE WHEN result > NOW() THEN 'future' ELSE 'past' END,
        'future'
    );

    RAISE NOTICE 'Test 9.3: next() timezone override % - Result: %', status, result;
END;
$$;

-- Test 9.4: next() with COUNT limit (should return NULL after COUNT reached)
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule.next(
        'FREQ=DAILY;COUNT=1',
        '2020-01-01 10:00:00+00'::TIMESTAMPTZ,
        'UTC'
    ) INTO result;

    status := assert_equal(
        'next() API',
        'Returns NULL when COUNT exhausted',
        COALESCE(result::TEXT, 'NULL'),
        'NULL'
    );

    RAISE NOTICE 'Test 9.4: next() with exhausted COUNT % - Result: %', status, COALESCE(result::TEXT, 'NULL');
END;
$$;


-- ================================================================================================================
-- TEST SUITE 10: rrule.most_recent() with timezone parameter
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 10: rrule.most_recent() TIMESTAMPTZ API'
\echo '=================================================='
\echo ''

-- Test 10.1: most_recent() with explicit timezone parameter
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
        'most_recent() API',
        'Returns occurrence before NOW',
        CASE WHEN result < NOW() AND result > '2020-01-01'::TIMESTAMPTZ THEN 'valid_past' ELSE 'invalid' END,
        'valid_past'
    );

    RAISE NOTICE 'Test 10.1: most_recent() with explicit timezone % - Result: %', status, result;
END;
$$;

-- Test 10.2: most_recent() with TZID in RRULE
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule.most_recent(
        'FREQ=WEEKLY;TZID=Europe/London',
        '2020-01-01 10:00:00+00'::TIMESTAMPTZ,
        NULL
    ) INTO result;

    status := assert_equal(
        'most_recent() API',
        'TZID in RRULE returns past occurrence',
        CASE WHEN result < NOW() AND result > '2020-01-01'::TIMESTAMPTZ THEN 'valid_past' ELSE 'invalid' END,
        'valid_past'
    );

    RAISE NOTICE 'Test 10.2: most_recent() with TZID in RRULE % - Result: %', status, result;
END;
$$;

-- Test 10.3: most_recent() timezone override
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule.most_recent(
        'FREQ=MONTHLY;TZID=Europe/London',
        '2020-01-01 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) INTO result;

    status := assert_equal(
        'most_recent() API',
        'Timezone param override works',
        CASE WHEN result < NOW() AND result > '2020-01-01'::TIMESTAMPTZ THEN 'valid_past' ELSE 'invalid' END,
        'valid_past'
    );

    RAISE NOTICE 'Test 10.3: most_recent() timezone override % - Result: %', status, result;
END;
$$;

-- Test 10.4: most_recent() with dtstart in future (should return NULL)
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule.most_recent(
        'FREQ=DAILY',
        (NOW() + INTERVAL '1 year')::TIMESTAMPTZ,
        'UTC'
    ) INTO result;

    status := assert_equal(
        'most_recent() API',
        'Returns NULL when dtstart is in future',
        COALESCE(result::TEXT, 'NULL'),
        'NULL'
    );

    RAISE NOTICE 'Test 10.4: most_recent() with future dtstart % - Result: %', status, COALESCE(result::TEXT, 'NULL');
END;
$$;


-- ================================================================================================================
-- TEST SUITE 11: rrule.overlaps() with timezone parameter
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 11: rrule.overlaps() TIMESTAMPTZ API'
\echo '=================================================='
\echo ''

-- Test 11.1: overlaps() with explicit timezone parameter - TRUE case
DO $$
DECLARE
    result BOOLEAN;
    status TEXT;
BEGIN
    SELECT rrule.overlaps(
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
        '2025-01-01 11:00:00-05'::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=30',
        '2025-01-05 00:00:00-05'::TIMESTAMPTZ,
        '2025-01-10 23:59:59-05'::TIMESTAMPTZ,
        'America/New_York'
    ) INTO result;

    status := assert_equal(
        'overlaps() API',
        'Returns TRUE when event overlaps range',
        result::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 11.1: overlaps() TRUE case % - Result: %', status, result;
END;
$$;

-- Test 11.2: overlaps() with explicit timezone parameter - FALSE case
DO $$
DECLARE
    result BOOLEAN;
    status TEXT;
BEGIN
    SELECT rrule.overlaps(
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
        '2025-01-01 11:00:00-05'::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=3',
        '2025-02-01 00:00:00-05'::TIMESTAMPTZ,
        '2025-02-28 23:59:59-05'::TIMESTAMPTZ,
        'America/New_York'
    ) INTO result;

    status := assert_equal(
        'overlaps() API',
        'Returns FALSE when no overlap',
        result::TEXT,
        'false'
    );

    RAISE NOTICE 'Test 11.2: overlaps() FALSE case % - Result: %', status, result;
END;
$$;

-- Test 11.3: overlaps() with TZID in RRULE
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
        NULL
    ) INTO result;

    status := assert_equal(
        'overlaps() API',
        'TZID in RRULE works correctly',
        result::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 11.3: overlaps() with TZID in RRULE % - Result: %', status, result;
END;
$$;

-- Test 11.4: overlaps() timezone override
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
        'America/New_York'
    ) INTO result;

    status := assert_equal(
        'overlaps() API',
        'Timezone param overrides TZID',
        result::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 11.4: overlaps() timezone override % - Result: %', status, result;
END;
$$;

-- Test 11.5: overlaps() across DST boundary
DO $$
DECLARE
    result BOOLEAN;
    status TEXT;
BEGIN
    SELECT rrule.overlaps(
        '2025-03-01 10:00:00-05'::TIMESTAMPTZ,
        '2025-03-01 11:00:00-05'::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=15',
        '2025-03-08 00:00:00-05'::TIMESTAMPTZ,
        '2025-03-10 23:59:59-04'::TIMESTAMPTZ,
        'America/New_York'
    ) INTO result;

    status := assert_equal(
        'overlaps() API',
        'Handles DST transitions correctly',
        result::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 11.5: overlaps() across DST % - Result: %', status, result;
END;
$$;

-- Test 11.6: overlaps() with NULL RRULE (single event, no recurrence)
DO $$
DECLARE
    result BOOLEAN;
    status TEXT;
BEGIN
    SELECT rrule.overlaps(
        '2025-01-15 10:00:00-05'::TIMESTAMPTZ,
        '2025-01-15 11:00:00-05'::TIMESTAMPTZ,
        NULL,
        '2025-01-01 00:00:00-05'::TIMESTAMPTZ,
        '2025-01-31 23:59:59-05'::TIMESTAMPTZ,
        'America/New_York'
    ) INTO result;

    status := assert_equal(
        'overlaps() API',
        'Handles NULL RRULE (single event)',
        result::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 11.6: overlaps() with NULL RRULE % - Result: %', status, result;
END;
$$;


-- ================================================================================================================
-- TEST SUITE 12: Timezone validation
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 12: Timezone Validation'
\echo '=================================================='
\echo ''

-- Test 12.1: Invalid timezone should raise exception
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

    RAISE NOTICE 'Test 12.1: Invalid timezone validation % - Error raised: %', status, error_raised;
END;
$$;


-- ================================================================================================================
-- RESULTS SUMMARY
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST RESULTS SUMMARY'
\echo '=================================================='
\echo ''

SELECT
    test_suite,
    test_name,
    CASE WHEN passed THEN '✓ PASS' ELSE '✗ FAIL' END as status
FROM tz_api_test_results
ORDER BY
    CASE test_suite
        WHEN 'DST Spring Forward' THEN 1
        WHEN 'DST Fall Back' THEN 2
        WHEN 'UTC Timezone' THEN 3
        WHEN 'Multiple Timezones' THEN 4
        WHEN 'Range Queries' THEN 5
        WHEN 'Offset Queries' THEN 6
        WHEN 'Complex Patterns' THEN 7
        WHEN 'count() API' THEN 8
        WHEN 'next() API' THEN 9
        WHEN 'most_recent() API' THEN 10
        WHEN 'overlaps() API' THEN 11
        WHEN 'Timezone Validation' THEN 12
    END,
    test_name;

\echo ''
\echo 'Detailed failures (if any):'
\echo ''

SELECT
    test_suite || ': ' || test_name as test,
    'Expected: ' || expected as expected_output,
    'Actual: ' || actual as actual_output
FROM tz_api_test_results
WHERE NOT passed;

\echo ''
\echo 'Overall Summary:'
SELECT
    COUNT(*) as total_tests,
    SUM(CASE WHEN passed THEN 1 ELSE 0 END) as passed,
    SUM(CASE WHEN NOT passed THEN 1 ELSE 0 END) as failed,
    ROUND(100.0 * SUM(CASE WHEN passed THEN 1 ELSE 0 END) / COUNT(*), 1) || '%' as pass_rate
FROM tz_api_test_results;

-- Fail transaction if any tests failed
DO $$
DECLARE
    failure_count INT;
BEGIN
    SELECT COUNT(*) INTO failure_count FROM tz_api_test_results WHERE NOT passed;
    IF failure_count > 0 THEN
        RAISE EXCEPTION '% test(s) failed', failure_count;
    END IF;
END;
$$;

ROLLBACK;

\echo ''
\echo '=================================================='
\echo 'All tests completed successfully!'
\echo '=================================================='
