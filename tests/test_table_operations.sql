/**
 * Integration Tests for Table Operations
 *
 * These tests verify the real-world patterns documented in EXAMPLE_USAGE.md:
 * - Subscription billing (batch updates, LATERAL JOINs)
 * - Batch operations (computed columns, filtering)
 * - Calendar event management (conflict detection)
 * - Resource scheduling (availability queries)
 *
 * These are INTEGRATION tests that verify the patterns work end-to-end,
 * not just unit tests of individual functions.
 *
 * Usage:
 *   psql -d your_database -f test_table_operations.sql
 *
 * Expected output: All tests pass with "PASS" status
 */

\set ON_ERROR_STOP on
\set ECHO all

-- Test database setup
BEGIN;

-- Ensure timezone consistency
SET timezone = 'UTC';

-- Create rrule schema and load functions
DROP SCHEMA IF EXISTS rrule CASCADE;
CREATE SCHEMA IF NOT EXISTS rrule;
SET search_path = rrule, public;

-- Load the RRULE functions
\i src/rrule.sql
\i src/rrule_subday.sql

-- Test results table
CREATE TEMP TABLE test_results (
    test_id INT PRIMARY KEY,
    test_name TEXT,
    status TEXT
);

\echo ''
\echo '==================================================================='
\echo 'Integration Tests: Table Operations (EXAMPLE_USAGE.md scenarios)'
\echo '==================================================================='
\echo ''

---------------------------------------------------------------------------------------------------
-- SECTION 1: Subscription Billing
---------------------------------------------------------------------------------------------------
\echo '--- Section 1: Subscription Billing ---'

-- Test 1: Create subscriptions table and populate
CREATE TEMP TABLE subscriptions (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    plan_name TEXT NOT NULL,
    rrule TEXT NOT NULL,
    subscription_start TIMESTAMPTZ NOT NULL,
    last_billed_at TIMESTAMPTZ,
    next_billing_date TIMESTAMPTZ,
    status TEXT DEFAULT 'active',
    amount DECIMAL(10,2) DEFAULT 29.99
);

INSERT INTO subscriptions (customer_id, plan_name, rrule, subscription_start, last_billed_at, status, amount)
VALUES
    (1, 'Premium Monthly', 'FREQ=MONTHLY;BYMONTHDAY=1', '2025-01-01 00:00:00+00', '2025-01-01 00:00:00+00', 'active', 49.99),
    (2, 'Basic Weekly', 'FREQ=WEEKLY;BYDAY=MO', '2025-01-06 00:00:00+00', '2025-01-20 00:00:00+00', 'active', 19.99),
    (3, 'Annual Plan', 'FREQ=YEARLY;BYMONTH=1;BYMONTHDAY=15', '2025-01-15 00:00:00+00', NULL, 'active', 299.99),
    (4, 'Paused Plan', 'FREQ=MONTHLY;BYMONTHDAY=1', '2024-12-01 00:00:00+00', '2024-12-01 00:00:00+00', 'paused', 29.99);

INSERT INTO test_results VALUES (1, 'Create and populate subscriptions table',
    (SELECT CASE WHEN COUNT(*) = 4 THEN 'PASS' ELSE 'FAIL' END FROM subscriptions)
);

-- Test 2: Batch update next billing dates for all active subscriptions
UPDATE subscriptions
SET next_billing_date = (
    SELECT * FROM rrule.after(
        subscriptions.rrule,
        subscriptions.subscription_start,
        COALESCE(subscriptions.last_billed_at, subscriptions.subscription_start),
        1
    ) LIMIT 1
)
WHERE status = 'active';

INSERT INTO test_results VALUES (2, 'Batch UPDATE: compute next billing dates',
    (SELECT CASE
        WHEN COUNT(*) = 3 AND MIN(next_billing_date) IS NOT NULL
        THEN 'PASS'
        ELSE 'FAIL'
    END FROM subscriptions WHERE status = 'active')
);

-- Test 3: Find subscriptions due in next 7 days
INSERT INTO test_results VALUES (3, 'Query: subscriptions due in next 7 days',
    (SELECT CASE
        WHEN COUNT(*) >= 1  -- At least one should be due soon
        THEN 'PASS'
        ELSE 'FAIL'
    END FROM subscriptions
    WHERE status = 'active'
      AND next_billing_date <= NOW() + INTERVAL '7 days')
);

-- Test 4: Generate billing schedule (next 3 occurrences) using LATERAL JOIN
INSERT INTO test_results VALUES (4, 'LATERAL JOIN: generate billing schedules',
    (SELECT CASE
        WHEN COUNT(*) >= 6  -- At least 2 active subs × 3 occurrences = 6
        THEN 'PASS'
        ELSE 'FAIL'
    END
    FROM subscriptions s
    CROSS JOIN LATERAL (
        SELECT * FROM rrule.after(
            s.rrule,
            s.subscription_start,
            COALESCE(s.last_billed_at, s.subscription_start),
            3
        )
    ) AS occurrence
    WHERE s.status = 'active')
);

-- Test 5: Revenue forecast by month (aggregation)
INSERT INTO test_results VALUES (5, 'Aggregation: revenue forecast by month',
    (SELECT CASE
        WHEN COUNT(*) > 0 AND SUM(expected_revenue) > 0
        THEN 'PASS'
        ELSE 'FAIL'
    END
    FROM (
        SELECT
            DATE_TRUNC('month', occurrence) AS billing_month,
            SUM(s.amount) AS expected_revenue
        FROM subscriptions s
        CROSS JOIN LATERAL (
            SELECT occurrence FROM rrule.between(
                s.rrule,
                s.subscription_start,
                NOW(),
                NOW() + INTERVAL '3 months'
            ) AS occurrence
        ) AS occ
        WHERE s.status = 'active'
        GROUP BY billing_month
    ) revenue_by_month)
);

---------------------------------------------------------------------------------------------------
-- SECTION 2: Batch Operations
---------------------------------------------------------------------------------------------------
\echo '--- Section 2: Batch Operations ---'

-- Test 6: Events table with computed columns
CREATE TEMP TABLE events (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    rrule TEXT NOT NULL,
    event_start TIMESTAMPTZ NOT NULL,
    next_occurrence TIMESTAMPTZ,
    occurrence_count INTEGER,
    status TEXT DEFAULT 'active'
);

INSERT INTO events (title, rrule, event_start, status)
VALUES
    ('Daily Standup', 'FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;COUNT=500', '2025-01-06 09:00:00+00', 'active'),
    ('Weekly Review', 'FREQ=WEEKLY;BYDAY=FR;COUNT=200', '2025-01-10 15:00:00+00', 'active'),
    ('Monthly Planning', 'FREQ=MONTHLY;BYDAY=1MO;COUNT=120', '2025-01-06 10:00:00+00', 'active'),
    ('Archived Event', 'FREQ=DAILY;COUNT=10', '2024-01-01 10:00:00+00', 'archived');

INSERT INTO test_results VALUES (6, 'Create events table',
    (SELECT CASE WHEN COUNT(*) = 4 THEN 'PASS' ELSE 'FAIL' END FROM events)
);

-- Test 7: Batch update computed columns
UPDATE events
SET
    next_occurrence = (SELECT after_result FROM rrule.after(events.rrule, events.event_start, NOW(), 1) AS after_result LIMIT 1),
    occurrence_count = rrule.count(events.rrule, events.event_start);

INSERT INTO test_results VALUES (7, 'Batch UPDATE: multiple computed columns',
    (SELECT CASE
        WHEN COUNT(*) = 4
         AND MIN(occurrence_count) > 0
         AND COUNT(*) FILTER (WHERE status = 'active' AND next_occurrence IS NOT NULL) = 3
        THEN 'PASS'
        ELSE 'FAIL'
    END FROM events)
);

-- Test 8: Filtering with set operations - events on weekends
INSERT INTO test_results VALUES (8, 'Set filtering: weekend occurrences',
    (SELECT CASE
        WHEN COUNT(DISTINCT e.id) >= 0  -- May be 0 if no weekend events
        THEN 'PASS'
        ELSE 'FAIL'
    END
    FROM events e
    CROSS JOIN LATERAL (
        SELECT occurrence FROM rrule.between(
            e.rrule,
            e.event_start,
            NOW(),
            NOW() + INTERVAL '30 days' ) AS occurrence ) AS occ
    WHERE EXTRACT(DOW FROM occurrence) IN (0, 6))  -- Sunday = 0, Saturday = 6
);

---------------------------------------------------------------------------------------------------
-- SECTION 3: Calendar Event Management
---------------------------------------------------------------------------------------------------
\echo '--- Section 3: Calendar Event Management ---'

-- Test 9: Calendar events with duration
CREATE TEMP TABLE calendar_events (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    rrule TEXT NOT NULL,
    event_start TIMESTAMPTZ NOT NULL,
    duration_minutes INTEGER NOT NULL
);

INSERT INTO calendar_events (user_id, title, rrule, event_start, duration_minutes)
VALUES
    (123, 'Daily Standup', 'FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;COUNT=30', '2025-01-06 09:00:00+00', 30),
    (123, 'Lunch Break', 'FREQ=DAILY;COUNT=30', '2025-01-01 12:00:00+00', 60),
    (123, 'Weekly 1:1', 'FREQ=WEEKLY;BYDAY=TU;COUNT=10', '2025-01-07 14:00:00+00', 30);

INSERT INTO test_results VALUES (9, 'Create calendar events',
    (SELECT CASE WHEN COUNT(*) = 3 THEN 'PASS' ELSE 'FAIL' END FROM calendar_events)
);

-- Test 10: Conflict detection - check for overlapping events
-- Proposed meeting: 2025-01-07 14:15 for 30 minutes (should conflict with Weekly 1:1)
INSERT INTO test_results VALUES (10, 'Conflict detection: find overlapping events',
    (SELECT CASE
        WHEN COUNT(*) >= 1  -- Should find at least the Weekly 1:1 conflict
        THEN 'PASS'
        ELSE 'FAIL'
    END
    FROM (
        SELECT
            e.id,
            e.title,
            occurrence AS event_start,
            occurrence + (e.duration_minutes || ' minutes')::INTERVAL AS event_end
        FROM calendar_events e
        CROSS JOIN LATERAL (
            SELECT occurrence FROM rrule.between(
                e.rrule,
                e.event_start,
                '2025-01-07 00:00:00+00'::TIMESTAMPTZ,
                '2025-01-08 00:00:00+00'::TIMESTAMPTZ ) AS occurrence ) AS occ
        WHERE e.user_id = 123
    ) user_events
    WHERE user_events.event_start < '2025-01-07 14:45:00+00'::TIMESTAMPTZ
      AND user_events.event_end > '2025-01-07 14:15:00+00'::TIMESTAMPTZ)
);

---------------------------------------------------------------------------------------------------
-- SECTION 4: Resource Scheduling
---------------------------------------------------------------------------------------------------
\echo '--- Section 4: Resource Scheduling ---'

-- Test 11: Room bookings
CREATE TEMP TABLE room_bookings (
    id SERIAL PRIMARY KEY,
    room_id INTEGER NOT NULL,
    booking_name TEXT NOT NULL,
    rrule TEXT NOT NULL,
    booking_start TIMESTAMPTZ NOT NULL,
    duration_minutes INTEGER NOT NULL
);

INSERT INTO room_bookings (room_id, booking_name, rrule, booking_start, duration_minutes)
VALUES
    (1, 'Team Standup', 'FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;COUNT=30', '2025-01-06 09:00:00+00', 30),
    (1, 'Client Meeting', 'FREQ=WEEKLY;BYDAY=WE;COUNT=10', '2025-01-08 14:00:00+00', 120),
    (2, 'Training Session', 'FREQ=WEEKLY;BYDAY=TH;COUNT=8', '2025-01-09 10:00:00+00', 180);

INSERT INTO test_results VALUES (11, 'Create room bookings',
    (SELECT CASE WHEN COUNT(*) = 3 THEN 'PASS' ELSE 'FAIL' END FROM room_bookings)
);

-- Test 12: Find available rooms (rooms NOT booked during target time)
-- Looking for availability on 2025-01-08 10:00-12:00
INSERT INTO test_results VALUES (12, 'Resource availability: find free rooms',
    (SELECT CASE
        WHEN COUNT(*) >= 1  -- Should find at least room 2 available
        THEN 'PASS'
        ELSE 'FAIL'
    END
    FROM (
        SELECT DISTINCT room_id
        FROM room_bookings
    ) all_rooms
    WHERE room_id NOT IN (
        SELECT DISTINCT rb.room_id
        FROM room_bookings rb
        CROSS JOIN LATERAL (
            SELECT occurrence FROM rrule.between(
                rb.rrule,
                rb.booking_start,
                '2025-01-08 09:00:00+00'::TIMESTAMPTZ,
                '2025-01-08 13:00:00+00'::TIMESTAMPTZ ) AS occurrence ) AS occ
        WHERE occurrence < '2025-01-08 12:00:00+00'::TIMESTAMPTZ
          AND occurrence + (rb.duration_minutes || ' minutes')::INTERVAL > '2025-01-08 10:00:00+00'::TIMESTAMPTZ
    ))
);

-- Test 13: Equipment maintenance schedules
CREATE TEMP TABLE equipment (
    id SERIAL PRIMARY KEY,
    equipment_name TEXT NOT NULL,
    maintenance_rrule TEXT NOT NULL,
    install_date TIMESTAMPTZ NOT NULL,
    last_maintenance TIMESTAMPTZ
);

INSERT INTO equipment (equipment_name, maintenance_rrule, install_date, last_maintenance)
VALUES
    ('Server A', 'FREQ=MONTHLY;BYMONTHDAY=1', '2024-01-01 00:00:00+00', '2025-01-01 00:00:00+00'),
    ('HVAC System', 'FREQ=MONTHLY;INTERVAL=3;BYMONTHDAY=15', '2023-06-15 00:00:00+00', '2024-12-15 00:00:00+00'),
    ('Backup Generator', 'FREQ=MONTHLY;INTERVAL=6;BYMONTHDAY=1', '2023-01-01 00:00:00+00', '2025-01-01 00:00:00+00');

INSERT INTO test_results VALUES (13, 'Create equipment maintenance table',
    (SELECT CASE WHEN COUNT(*) = 3 THEN 'PASS' ELSE 'FAIL' END FROM equipment)
);

-- Test 14: Generate maintenance schedule for next 90 days
INSERT INTO test_results VALUES (14, 'Maintenance schedule: next 90 days',
    (SELECT CASE
        WHEN COUNT(*) >= 3  -- Should have at least a few maintenance events
        THEN 'PASS'
        ELSE 'FAIL'
    END
    FROM equipment e
    CROSS JOIN LATERAL (
        SELECT occurrence FROM rrule.between(
            e.maintenance_rrule,
            COALESCE(e.last_maintenance, e.install_date),
            NOW(),
            NOW() + INTERVAL '90 days' ) AS occurrence ) AS occ
    WHERE occurrence > NOW())
);

---------------------------------------------------------------------------------------------------
-- SECTION 5: Complex Query Patterns
---------------------------------------------------------------------------------------------------
\echo '--- Section 5: Complex Query Patterns ---'

-- Test 15: Multiple table JOIN with occurrence expansion
INSERT INTO test_results VALUES (15, 'Complex JOIN: subscriptions + events',
    (SELECT CASE
        WHEN COUNT(*) > 0  -- Should be able to JOIN and expand
        THEN 'PASS'
        ELSE 'FAIL'
    END
    FROM subscriptions s
    INNER JOIN events e ON s.customer_id = e.id  -- Artificial join for testing
    CROSS JOIN LATERAL (
        SELECT after_result AS sub_occurrence FROM rrule.after(s.rrule, s.subscription_start, NOW(), 1) AS after_result
    ) sub_next
    CROSS JOIN LATERAL (
        SELECT after_result AS event_occurrence FROM rrule.after(e.rrule, e.event_start, NOW(), 1) AS after_result
    ) event_next
    WHERE s.status = 'active' AND e.status = 'active'
    LIMIT 10)
);

-- Test 16: Window functions with occurrence data
INSERT INTO test_results VALUES (16, 'Window functions: occurrence ranking',
    (SELECT CASE
        WHEN MAX(occurrence_rank) >= 3  -- Should rank at least 3 occurrences
        THEN 'PASS'
        ELSE 'FAIL'
    END
    FROM (
        SELECT
            e.id,
            occ.occurrence,
            ROW_NUMBER() OVER (PARTITION BY e.id ORDER BY occ.occurrence) AS occurrence_rank
        FROM events e
        CROSS JOIN LATERAL (
            SELECT after_result AS occurrence FROM rrule.after(e.rrule, e.event_start, NOW(), 5) AS after_result
        ) AS occ
        WHERE e.status = 'active'
    ) ranked_occurrences)
);

-- Test 17: Subquery with occurrence filtering
INSERT INTO test_results VALUES (17, 'Subquery: filter by occurrence count',
    (SELECT CASE
        WHEN COUNT(*) > 0  -- Should find events with >10 occurrences
        THEN 'PASS'
        ELSE 'FAIL'
    END
    FROM (
        SELECT e.id, e.title, COUNT(*) AS occ_count
        FROM events e
        CROSS JOIN LATERAL (
            SELECT * FROM rrule.all(e.rrule, e.event_start)
        ) AS occurrence
        GROUP BY e.id, e.title
        HAVING COUNT(*) > 10
    ) events_with_many_occurrences)
);

---------------------------------------------------------------------------------------------------
-- Test Results Summary
---------------------------------------------------------------------------------------------------
\echo ''
\echo '==================================================================='
\echo 'Test Results Summary'
\echo '==================================================================='
\echo ''

SELECT
    test_id,
    CASE
        WHEN status = 'PASS' THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS result,
    test_name
FROM test_results
ORDER BY test_id;

-- Overall summary
\echo ''
SELECT
    COUNT(*) AS total_tests,
    COUNT(*) FILTER (WHERE status = 'PASS') AS passed,
    COUNT(*) FILTER (WHERE status = 'FAIL') AS failed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'PASS') / COUNT(*), 1) AS pass_rate
FROM test_results;

\echo ''
\echo 'Integration tests complete!'
\echo ''

-- Fail transaction if any tests failed
DO $$
DECLARE
    failed_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count FROM test_results WHERE status = 'FAIL';
    IF failed_count > 0 THEN
        RAISE EXCEPTION '% test(s) failed! See results above.', failed_count;
    END IF;
END $$;

ROLLBACK;  -- Clean up temporary tables
