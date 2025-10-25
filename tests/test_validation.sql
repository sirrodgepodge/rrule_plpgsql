/**
 * RFC 5545 Constraint Validation Tests
 *
 * Tests all 16 RFC 5545 MUST/MUST NOT constraint validations implemented
 * in parse_rrule_parts() to ensure invalid RRULEs are properly rejected
 * with clear, descriptive error messages.
 *
 * Usage:
 *   psql -d your_database -f tests/test_validation.sql
 *
 * Expected output: All tests pass with ✓ markers
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

-- Load the RRULE functions if not already loaded
\i src/rrule.sql

-- Helper function to test that invalid RRULEs are rejected
CREATE OR REPLACE FUNCTION assert_rrule_rejected(
    test_name TEXT,
    invalid_rrule TEXT,
    expected_error_pattern TEXT
)
RETURNS TEXT AS $$
DECLARE
    result TIMESTAMP[];
BEGIN
    -- Try to use the invalid RRULE
    BEGIN
        result := (SELECT array_agg(occurrence) FROM "all"(invalid_rrule, '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence);
        -- If we get here, the RRULE was NOT rejected (test failed)
        RAISE EXCEPTION 'FAIL [%]: RRULE was accepted when it should have been rejected: %',
            test_name, invalid_rrule;
    EXCEPTION
        WHEN OTHERS THEN
            -- Check if error message matches expected pattern
            IF SQLERRM LIKE expected_error_pattern THEN
                RETURN 'PASS [' || test_name || ']';
            ELSE
                RAISE EXCEPTION 'FAIL [%]: Wrong error message. Expected pattern: %, Got: %',
                    test_name, expected_error_pattern, SQLERRM;
            END IF;
    END;
END;
$$ LANGUAGE plpgsql;

-- Helper function to test that valid RRULEs are accepted
CREATE OR REPLACE FUNCTION assert_rrule_accepted(
    test_name TEXT,
    valid_rrule TEXT,
    expected_count INT
)
RETURNS TEXT AS $$
DECLARE
    result TIMESTAMP[];
    actual_count INT;
BEGIN
    result := (SELECT array_agg(occurrence) FROM "all"(valid_rrule, '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence);
    actual_count := array_length(result, 1);

    IF actual_count IS DISTINCT FROM expected_count THEN
        RAISE EXCEPTION 'FAIL [%]: Expected % occurrences, got %',
            test_name, expected_count, actual_count;
    END IF;

    RETURN 'PASS [' || test_name || ']';
END;
$$ LANGUAGE plpgsql;

-- Test results tracking
CREATE TEMP TABLE validation_test_results (
    test_number SERIAL PRIMARY KEY,
    test_category TEXT,
    test_name TEXT,
    status TEXT
);

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 1: Critical MUST/MUST NOT Constraint Violations'
\echo '====================================================================='

-- Test 1.1: FREQ is REQUIRED
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('FREQ Required', 'Missing FREQ (should be rejected)',
    assert_rrule_rejected(
        'Missing FREQ',
        'COUNT=10;BYMONTHDAY=15',
        '%FREQ parameter is required%'
    )
);

-- Test 1.2: Valid FREQ accepted
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('FREQ Required', 'Valid FREQ=DAILY (should be accepted)',
    assert_rrule_accepted(
        'Valid FREQ',
        'FREQ=DAILY;COUNT=5',
        5
    )
);

-- Test 1.3: COUNT and UNTIL mutually exclusive
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('COUNT+UNTIL Mutual Exclusion', 'COUNT and UNTIL together (should be rejected)',
    assert_rrule_rejected(
        'COUNT + UNTIL together',
        'FREQ=DAILY;COUNT=10;UNTIL=20251231T235959',
        '%COUNT and UNTIL are mutually exclusive%'
    )
);

-- Test 1.4: COUNT alone is valid
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('COUNT+UNTIL Mutual Exclusion', 'COUNT alone (should be accepted)',
    assert_rrule_accepted(
        'COUNT alone',
        'FREQ=DAILY;COUNT=5',
        5
    )
);

-- Test 1.5: UNTIL alone is valid
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('COUNT+UNTIL Mutual Exclusion', 'UNTIL alone (should be accepted)',
    assert_rrule_accepted(
        'UNTIL alone',
        'FREQ=DAILY;UNTIL=20250105T235959',
        5
    )
);

-- Test 1.6: BYWEEKNO only with YEARLY
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYWEEKNO Only With YEARLY', 'BYWEEKNO with MONTHLY (should be rejected)',
    assert_rrule_rejected(
        'BYWEEKNO with MONTHLY',
        'FREQ=MONTHLY;BYWEEKNO=10;COUNT=3',
        '%BYWEEKNO can only be used with FREQ=YEARLY%'
    )
);

-- Test 1.7: BYWEEKNO with WEEKLY should fail
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYWEEKNO Only With YEARLY', 'BYWEEKNO with WEEKLY (should be rejected)',
    assert_rrule_rejected(
        'BYWEEKNO with WEEKLY',
        'FREQ=WEEKLY;BYWEEKNO=5;COUNT=3',
        '%BYWEEKNO can only be used with FREQ=YEARLY%'
    )
);

-- Test 1.8: BYWEEKNO with DAILY should fail
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYWEEKNO Only With YEARLY', 'BYWEEKNO with DAILY (should be rejected)',
    assert_rrule_rejected(
        'BYWEEKNO with DAILY',
        'FREQ=DAILY;BYWEEKNO=1;COUNT=3',
        '%BYWEEKNO can only be used with FREQ=YEARLY%'
    )
);

-- Test 1.9: BYWEEKNO with YEARLY is valid
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYWEEKNO Only With YEARLY', 'BYWEEKNO with YEARLY (should be accepted)',
    assert_rrule_accepted(
        'BYWEEKNO with YEARLY',
        'FREQ=YEARLY;BYWEEKNO=1;COUNT=3',
        3
    )
);

-- Test 1.10: BYYEARDAY not with DAILY
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYYEARDAY Not With DAILY/WEEKLY/MONTHLY', 'BYYEARDAY with DAILY (should be rejected)',
    assert_rrule_rejected(
        'BYYEARDAY with DAILY',
        'FREQ=DAILY;BYYEARDAY=100;COUNT=3',
        '%BYYEARDAY cannot be used with FREQ=DAILY%'
    )
);

-- Test 1.11: BYYEARDAY not with WEEKLY
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYYEARDAY Not With DAILY/WEEKLY/MONTHLY', 'BYYEARDAY with WEEKLY (should be rejected)',
    assert_rrule_rejected(
        'BYYEARDAY with WEEKLY',
        'FREQ=WEEKLY;BYYEARDAY=200;COUNT=3',
        '%BYYEARDAY cannot be used with FREQ=WEEKLY%'
    )
);

-- Test 1.12: BYYEARDAY not with MONTHLY
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYYEARDAY Not With DAILY/WEEKLY/MONTHLY', 'BYYEARDAY with MONTHLY (should be rejected)',
    assert_rrule_rejected(
        'BYYEARDAY with MONTHLY',
        'FREQ=MONTHLY;BYYEARDAY=300;COUNT=3',
        '%BYYEARDAY cannot be used with FREQ=MONTHLY%'
    )
);

-- Test 1.13: BYYEARDAY with YEARLY is valid
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYYEARDAY Not With DAILY/WEEKLY/MONTHLY', 'BYYEARDAY with YEARLY (should be accepted)',
    assert_rrule_accepted(
        'BYYEARDAY with YEARLY',
        'FREQ=YEARLY;BYYEARDAY=100;COUNT=3',
        3
    )
);

-- Test 1.14: BYDAY ordinals only with MONTHLY/YEARLY
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinals Only With MONTHLY/YEARLY', 'BYDAY=2MO with WEEKLY (should be rejected)',
    assert_rrule_rejected(
        'BYDAY ordinal with WEEKLY',
        'FREQ=WEEKLY;BYDAY=2MO;COUNT=3',
        '%BYDAY with ordinal%can only be used with FREQ=MONTHLY or FREQ=YEARLY%'
    )
);

-- Test 1.15: BYDAY ordinal with DAILY should fail
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinals Only With MONTHLY/YEARLY', 'BYDAY=-1FR with DAILY (should be rejected)',
    assert_rrule_rejected(
        'BYDAY ordinal with DAILY',
        'FREQ=DAILY;BYDAY=-1FR;COUNT=3',
        '%BYDAY with ordinal%can only be used with FREQ=MONTHLY or FREQ=YEARLY%'
    )
);

-- Test 1.16: BYDAY without ordinal with WEEKLY is valid
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinals Only With MONTHLY/YEARLY', 'BYDAY=MO,FR with WEEKLY (should be accepted)',
    assert_rrule_accepted(
        'BYDAY no ordinal with WEEKLY',
        'FREQ=WEEKLY;BYDAY=MO,FR;COUNT=6',
        6
    )
);

-- Test 1.17: BYDAY with ordinal and MONTHLY is valid
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinals Only With MONTHLY/YEARLY', 'BYDAY=2TU with MONTHLY (should be accepted)',
    assert_rrule_accepted(
        'BYDAY ordinal with MONTHLY',
        'FREQ=MONTHLY;BYDAY=2TU;COUNT=3',
        3
    )
);

-- Test 1.18: BYDAY with ordinal and YEARLY is valid
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinals Only With MONTHLY/YEARLY', 'BYDAY=-1FR with YEARLY (should be accepted)',
    assert_rrule_accepted(
        'BYDAY ordinal with YEARLY',
        'FREQ=YEARLY;BYDAY=-1FR;BYMONTH=12;COUNT=3',
        3
    )
);

-- Test 1.18a: BYDAY ordinal cannot be zero (0MO)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinal Cannot Be Zero', 'BYDAY=0MO with MONTHLY (should be rejected)',
    assert_rrule_rejected(
        'BYDAY zero ordinal',
        'FREQ=MONTHLY;BYDAY=0MO;COUNT=3',
        '%BYDAY ordinal cannot be zero%'
    )
);

-- Test 1.18b: BYDAY ordinal cannot be +0 (positive zero)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinal Cannot Be Zero', 'BYDAY=+0TU with YEARLY (should be rejected)',
    assert_rrule_rejected(
        'BYDAY positive zero ordinal',
        'FREQ=YEARLY;BYDAY=+0TU;BYMONTH=3;COUNT=3',
        '%BYDAY ordinal cannot be zero%'
    )
);

-- Test 1.18c: BYDAY ordinal cannot be -0 (negative zero)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinal Cannot Be Zero', 'BYDAY=-0FR with MONTHLY (should be rejected)',
    assert_rrule_rejected(
        'BYDAY negative zero ordinal',
        'FREQ=MONTHLY;BYDAY=-0FR;COUNT=3',
        '%BYDAY ordinal cannot be zero%'
    )
);

-- Test 1.18d: BYDAY ordinal cannot be 00 (double zero)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinal Cannot Be Zero', 'BYDAY=00WE with YEARLY (should be rejected)',
    assert_rrule_rejected(
        'BYDAY double zero ordinal',
        'FREQ=YEARLY;BYDAY=00WE;BYMONTH=6;COUNT=3',
        '%BYDAY ordinal cannot be zero%'
    )
);

-- Test 1.18e: BYDAY without ordinal is still valid (MO)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinal Cannot Be Zero', 'BYDAY=MO with MONTHLY (should be accepted)',
    assert_rrule_accepted(
        'BYDAY without ordinal',
        'FREQ=MONTHLY;BYDAY=MO;COUNT=3',
        3
    )
);

-- Test 1.18f: BYDAY with valid positive ordinal is still valid (1MO, 2TU)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinal Cannot Be Zero', 'BYDAY=1MO,2TU with MONTHLY (should be accepted)',
    assert_rrule_accepted(
        'BYDAY valid positive ordinals',
        'FREQ=MONTHLY;BYDAY=1MO,2TU;COUNT=3',
        3
    )
);

-- Test 1.19: BYSETPOS requires another BYxxx
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSETPOS Requires Other BYxxx', 'BYSETPOS alone (should be rejected)',
    assert_rrule_rejected(
        'BYSETPOS alone',
        'FREQ=DAILY;BYSETPOS=1;COUNT=3',
        '%BYSETPOS requires at least one other BYxxx parameter%'
    )
);

-- Test 1.20: BYSETPOS with BYDAY is valid
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSETPOS Requires Other BYxxx', 'BYSETPOS with BYDAY (should be accepted)',
    assert_rrule_accepted(
        'BYSETPOS with BYDAY',
        'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3',
        3
    )
);

-- Test 1.21: BYMONTHDAY not valid with WEEKLY
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTHDAY Not With WEEKLY', 'BYMONTHDAY with WEEKLY (should be rejected)',
    assert_rrule_rejected(
        'BYMONTHDAY with WEEKLY',
        'FREQ=WEEKLY;BYMONTHDAY=15;COUNT=3',
        '%BYMONTHDAY cannot be used with FREQ=WEEKLY%'
    )
);

-- Test 1.22: BYMONTHDAY valid with DAILY (alternative)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTHDAY Not With WEEKLY', 'BYMONTHDAY with DAILY (should be accepted)',
    assert_rrule_accepted(
        'BYMONTHDAY with DAILY',
        'FREQ=DAILY;BYMONTHDAY=15;COUNT=3',
        3
    )
);

-- Test 1.23: BYDAY with ordinals cannot be used with YEARLY + BYWEEKNO
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinals Not With YEARLY+BYWEEKNO', 'BYDAY ordinals with YEARLY+BYWEEKNO (should be rejected)',
    assert_rrule_rejected(
        'BYDAY ordinals with YEARLY+BYWEEKNO',
        'FREQ=YEARLY;BYWEEKNO=10;BYDAY=2MO;COUNT=3',
        '%BYDAY with ordinal%cannot be used when FREQ=YEARLY and BYWEEKNO is specified%'
    )
);

-- Test 1.24: BYDAY without ordinals valid with YEARLY + BYWEEKNO
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinals Not With YEARLY+BYWEEKNO', 'BYDAY without ordinals with YEARLY+BYWEEKNO (should be accepted)',
    assert_rrule_accepted(
        'BYDAY without ordinals with YEARLY+BYWEEKNO',
        'FREQ=YEARLY;BYWEEKNO=10;BYDAY=MO;COUNT=3',
        3
    )
);

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 2: Parameter Range Validations'
\echo '====================================================================='

-- Test 2.1-2.4: BYSECOND range (0-60)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSECOND Range 0-60', 'BYSECOND=61 (should be rejected)',
    assert_rrule_rejected(
        'BYSECOND out of range high',
        'FREQ=DAILY;BYSECOND=61;COUNT=1',
        '%BYSECOND=61 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSECOND Range 0-60', 'BYSECOND=-1 (should be rejected)',
    assert_rrule_rejected(
        'BYSECOND negative',
        'FREQ=DAILY;BYSECOND=-1;COUNT=1',
        '%BYSECOND=-1 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSECOND Range 0-60', 'BYSECOND=0 (should be accepted)',
    assert_rrule_accepted(
        'BYSECOND=0 valid',
        'FREQ=DAILY;BYSECOND=0;COUNT=2',
        2
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSECOND Range 0-60', 'BYSECOND=59 (should be accepted)',
    assert_rrule_accepted(
        'BYSECOND=59 valid',
        'FREQ=DAILY;BYSECOND=59;COUNT=2',
        2
    )
);

-- Test 2.5-2.8: BYMINUTE range (0-59)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMINUTE Range 0-59', 'BYMINUTE=60 (should be rejected)',
    assert_rrule_rejected(
        'BYMINUTE out of range',
        'FREQ=DAILY;BYMINUTE=60;COUNT=1',
        '%BYMINUTE=60 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMINUTE Range 0-59', 'BYMINUTE=-1 (should be rejected)',
    assert_rrule_rejected(
        'BYMINUTE negative',
        'FREQ=DAILY;BYMINUTE=-1;COUNT=1',
        '%BYMINUTE=-1 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMINUTE Range 0-59', 'BYMINUTE=0 (should be accepted)',
    assert_rrule_accepted(
        'BYMINUTE=0 valid',
        'FREQ=DAILY;BYMINUTE=0;COUNT=2',
        2
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMINUTE Range 0-59', 'BYMINUTE=59 (should be accepted)',
    assert_rrule_accepted(
        'BYMINUTE=59 valid',
        'FREQ=DAILY;BYMINUTE=59;COUNT=2',
        2
    )
);

-- Test 2.9-2.12: BYHOUR range (0-23)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYHOUR Range 0-23', 'BYHOUR=24 (should be rejected)',
    assert_rrule_rejected(
        'BYHOUR out of range',
        'FREQ=DAILY;BYHOUR=24;COUNT=1',
        '%BYHOUR=24 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYHOUR Range 0-23', 'BYHOUR=-1 (should be rejected)',
    assert_rrule_rejected(
        'BYHOUR negative',
        'FREQ=DAILY;BYHOUR=-1;COUNT=1',
        '%BYHOUR=-1 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYHOUR Range 0-23', 'BYHOUR=12 (should be accepted)',
    assert_rrule_accepted(
        'BYHOUR=12 valid',
        'FREQ=DAILY;BYHOUR=12;COUNT=2',
        2
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYHOUR Range 0-23', 'BYHOUR=23 (should be accepted - 11 PM)',
    assert_rrule_accepted(
        'BYHOUR=23 valid',
        'FREQ=DAILY;BYHOUR=23;COUNT=2',
        2
    )
);

-- Test 2.13-2.16: BYMONTH range (1-12)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTH Range 1-12', 'BYMONTH=13 (should be rejected)',
    assert_rrule_rejected(
        'BYMONTH out of range high',
        'FREQ=YEARLY;BYMONTH=13;COUNT=1',
        '%BYMONTH=13 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTH Range 1-12', 'BYMONTH=0 (should be rejected)',
    assert_rrule_rejected(
        'BYMONTH out of range low',
        'FREQ=YEARLY;BYMONTH=0;COUNT=1',
        '%BYMONTH=0 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTH Range 1-12', 'BYMONTH=1 (should be accepted - January)',
    assert_rrule_accepted(
        'BYMONTH=1 valid',
        'FREQ=YEARLY;BYMONTH=1;COUNT=2',
        2
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTH Range 1-12', 'BYMONTH=12 (should be accepted - December)',
    assert_rrule_accepted(
        'BYMONTH=12 valid',
        'FREQ=YEARLY;BYMONTH=12;COUNT=2',
        2
    )
);

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 3: Zero Values and Extended Range Validations'
\echo '====================================================================='

-- Test 3.1-3.4: BYMONTHDAY validation
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTHDAY Validation', 'BYMONTHDAY=0 (should be rejected)',
    assert_rrule_rejected(
        'BYMONTHDAY=0 invalid',
        'FREQ=MONTHLY;BYMONTHDAY=0;COUNT=1',
        '%BYMONTHDAY=0 is not valid%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTHDAY Validation', 'BYMONTHDAY=32 (should be rejected)',
    assert_rrule_rejected(
        'BYMONTHDAY out of range',
        'FREQ=MONTHLY;BYMONTHDAY=32;COUNT=1',
        '%BYMONTHDAY=32 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTHDAY Validation', 'BYMONTHDAY=-32 (should be rejected)',
    assert_rrule_rejected(
        'BYMONTHDAY negative out of range',
        'FREQ=MONTHLY;BYMONTHDAY=-32;COUNT=1',
        '%BYMONTHDAY=-32 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTHDAY Validation', 'BYMONTHDAY=-1 (should be accepted - last day)',
    assert_rrule_accepted(
        'BYMONTHDAY=-1 valid',
        'FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=3',
        3
    )
);

-- Test 3.5-3.8: BYYEARDAY validation
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYYEARDAY Validation', 'BYYEARDAY=0 (should be rejected)',
    assert_rrule_rejected(
        'BYYEARDAY=0 invalid',
        'FREQ=YEARLY;BYYEARDAY=0;COUNT=1',
        '%BYYEARDAY=0 is not valid%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYYEARDAY Validation', 'BYYEARDAY=367 (should be rejected)',
    assert_rrule_rejected(
        'BYYEARDAY out of range',
        'FREQ=YEARLY;BYYEARDAY=367;COUNT=1',
        '%BYYEARDAY=367 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYYEARDAY Validation', 'BYYEARDAY=-367 (should be rejected)',
    assert_rrule_rejected(
        'BYYEARDAY negative out of range',
        'FREQ=YEARLY;BYYEARDAY=-367;COUNT=1',
        '%BYYEARDAY=-367 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYYEARDAY Validation', 'BYYEARDAY=-1 (should be accepted - Dec 31)',
    assert_rrule_accepted(
        'BYYEARDAY=-1 valid',
        'FREQ=YEARLY;BYYEARDAY=-1;COUNT=3',
        3
    )
);

-- Test 3.9-3.12: BYWEEKNO validation
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYWEEKNO Validation', 'BYWEEKNO=0 (should be rejected)',
    assert_rrule_rejected(
        'BYWEEKNO=0 invalid',
        'FREQ=YEARLY;BYWEEKNO=0;COUNT=1',
        '%BYWEEKNO=0 is not valid%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYWEEKNO Validation', 'BYWEEKNO=54 (should be rejected)',
    assert_rrule_rejected(
        'BYWEEKNO out of range',
        'FREQ=YEARLY;BYWEEKNO=54;COUNT=1',
        '%BYWEEKNO=54 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYWEEKNO Validation', 'BYWEEKNO=-54 (should be rejected)',
    assert_rrule_rejected(
        'BYWEEKNO negative out of range',
        'FREQ=YEARLY;BYWEEKNO=-54;COUNT=1',
        '%BYWEEKNO=-54 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYWEEKNO Validation', 'BYWEEKNO=1 (should be accepted - first week)',
    assert_rrule_accepted(
        'BYWEEKNO=1 valid',
        'FREQ=YEARLY;BYWEEKNO=1;COUNT=3',
        3
    )
);

-- Test 3.13-3.16: BYSETPOS validation
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSETPOS Validation', 'BYSETPOS=0 (should be rejected)',
    assert_rrule_rejected(
        'BYSETPOS=0 invalid',
        'FREQ=MONTHLY;BYDAY=MO;BYSETPOS=0;COUNT=1',
        '%BYSETPOS=0 is not valid%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSETPOS Validation', 'BYSETPOS=367 (should be rejected)',
    assert_rrule_rejected(
        'BYSETPOS out of range',
        'FREQ=MONTHLY;BYDAY=MO;BYSETPOS=367;COUNT=1',
        '%BYSETPOS=367 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSETPOS Validation', 'BYSETPOS=-367 (should be rejected)',
    assert_rrule_rejected(
        'BYSETPOS negative out of range',
        'FREQ=MONTHLY;BYDAY=MO;BYSETPOS=-367;COUNT=1',
        '%BYSETPOS=-367 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSETPOS Validation', 'BYSETPOS=-1 (should be accepted - last position)',
    assert_rrule_accepted(
        'BYSETPOS=-1 valid',
        'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3',
        3
    )
);

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 4: Complex Validation Scenarios'
\echo '====================================================================='

-- Test 4.1: Multiple violations (should report first one encountered)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Complex Scenarios', 'Multiple violations (missing FREQ + COUNT+UNTIL)',
    assert_rrule_rejected(
        'Multiple violations',
        'COUNT=10;UNTIL=20251231T235959;BYMONTHDAY=15',
        '%FREQ parameter is required%'  -- First validation should trigger
    )
);

-- Test 4.2: Complex valid RRULE with many parameters
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Complex Scenarios', 'Complex valid RRULE (all constraints satisfied)',
    assert_rrule_accepted(
        'Complex valid RRULE',
        'FREQ=MONTHLY;BYMONTHDAY=13;BYDAY=FR;BYMONTH=1,2,3;COUNT=5',
        5
    )
);

-- Test 4.3: Edge case - BYMONTHDAY=31 (valid even though not all months have 31 days)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Complex Scenarios', 'BYMONTHDAY=31 (valid - handled by SKIP logic)',
    assert_rrule_accepted(
        'BYMONTHDAY=31 valid',
        'FREQ=MONTHLY;BYMONTHDAY=31;COUNT=12',
        12
    )
);

-- Test 4.4: BYYEARDAY=366 (valid - leap years)
-- Note: With 10-year default window from 2025, only 2 leap years exist (2028, 2032)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Complex Scenarios', 'BYYEARDAY=366 (valid for leap years)',
    assert_rrule_accepted(
        'BYYEARDAY=366 valid',
        'FREQ=YEARLY;BYYEARDAY=366;COUNT=2',
        2
    )
);

-- Test 4.5: Multiple BYxxx with BYSETPOS (valid)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Complex Scenarios', 'Multiple BYxxx + BYSETPOS (valid complex pattern)',
    assert_rrule_accepted(
        'Multiple BYxxx + BYSETPOS',
        'FREQ=YEARLY;BYMONTH=1,7;BYDAY=MO,FR;BYSETPOS=1,-1;COUNT=4',
        4
    )
);

\echo ''
\echo '====================================================================='
\echo 'Test Results Summary'
\echo '====================================================================='

-- Display all test results grouped by category
SELECT
    test_category,
    COUNT(*) as total_tests,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') as passed,
    COUNT(*) FILTER (WHERE status LIKE 'FAIL%') as failed
FROM validation_test_results
GROUP BY test_category
ORDER BY test_category;

\echo ''
\echo 'Overall Summary:'
SELECT
    COUNT(*) as total_tests,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') as passed,
    COUNT(*) FILTER (WHERE status LIKE 'FAIL%') as failed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE status LIKE 'PASS%') / COUNT(*), 1) as pass_percentage
FROM validation_test_results;

\echo ''
\echo 'Detailed Results:'
SELECT
    test_number,
    test_category,
    test_name,
    status
FROM validation_test_results
ORDER BY test_number;

-- Check if all tests passed
DO $$
DECLARE
    failed_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count
    FROM validation_test_results
    WHERE status LIKE 'FAIL%';

    IF failed_count > 0 THEN
        RAISE EXCEPTION 'VALIDATION TEST SUITE FAILED: % test(s) failed', failed_count;
    ELSE
        RAISE NOTICE 'VALIDATION TEST SUITE PASSED: All % tests passed successfully!',
            (SELECT COUNT(*) FROM validation_test_results);
    END IF;
END $$;

ROLLBACK;
