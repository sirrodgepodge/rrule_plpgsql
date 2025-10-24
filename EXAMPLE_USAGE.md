# Example Usage: Real-World Patterns

This guide demonstrates practical table-based operations with rrule_plpgsql - the key advantage of having recurrence computation integrated with your query engine.

---

## Table of Contents

1. [Getting Started](#getting-started) - Basic syntax and simple queries
2. [Subscription Billing](#subscription-billing) - Computing next billing dates for all subscriptions
3. [Batch Operations](#batch-operations) - Updating computed columns efficiently
4. [Calendar Event Management](#calendar-event-management) - Conflict detection and availability
5. [Resource Scheduling](#resource-scheduling) - Room booking and equipment maintenance
6. [Performance Tips](#performance-tips) - Optimization patterns

---

## Getting Started

### Basic Syntax

The core function is `rrule.all()` which generates occurrences from an RRULE string:

```sql
-- Every day for 5 days
SELECT * FROM rrule.all(
    'FREQ=DAILY;COUNT=5',
    '2025-01-01 10:00:00'::TIMESTAMP
);
```

**Result:**
```
        occurrence
---------------------
 2025-01-01 10:00:00
 2025-01-02 10:00:00
 2025-01-03 10:00:00
 2025-01-04 10:00:00
 2025-01-05 10:00:00
```

### Common Recurrence Patterns

**Daily:**
```sql
-- Weekdays only (Mon-Fri)
SELECT * FROM rrule.all(
    'FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;COUNT=10',
    '2025-01-01 09:00:00'::TIMESTAMP
);

-- Every 3 days
SELECT * FROM rrule.all(
    'FREQ=DAILY;INTERVAL=3;COUNT=10',
    '2025-01-01 10:00:00'::TIMESTAMP
);
```

**Weekly:**
```sql
-- Every Monday
SELECT * FROM rrule.all(
    'FREQ=WEEKLY;BYDAY=MO;COUNT=12',
    '2025-01-06 10:00:00'::TIMESTAMP
);

-- Mon/Wed/Fri
SELECT * FROM rrule.all(
    'FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=12',
    '2025-01-06 14:00:00'::TIMESTAMP
);
```

**Monthly:**
```sql
-- Last day of each month
SELECT * FROM rrule.all(
    'FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=12',
    '2025-01-31 23:59:00'::TIMESTAMP
);

-- First Monday of each month
SELECT * FROM rrule.all(
    'FREQ=MONTHLY;BYDAY=1MO;COUNT=12',
    '2025-01-06 10:00:00'::TIMESTAMP
);

-- 15th of every month
SELECT * FROM rrule.all(
    'FREQ=MONTHLY;BYMONTHDAY=15;COUNT=12',
    '2025-01-15 12:00:00'::TIMESTAMP
);
```

**Yearly:**
```sql
-- Annual event (birthday, anniversary)
SELECT * FROM rrule.all(
    'FREQ=YEARLY;BYMONTH=3;BYMONTHDAY=15;COUNT=10',
    '2025-03-15 00:00:00'::TIMESTAMP
);
```

### Timezone Support

```sql
-- With timezone (DST handled automatically)
SELECT * FROM rrule.all(
    'FREQ=DAILY;COUNT=5;TZID=America/New_York',
    '2025-03-08 10:00:00'::TIMESTAMP
);
-- Result: 10 AM stays 10 AM, even across DST transition on March 9
```

**Now let's see the real power: operating on entire tables...**

---

## Subscription Billing

**The classic use case:** Compute next billing dates for all active subscriptions in a single query.

### Schema

```sql
CREATE TABLE subscriptions (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    plan_name TEXT NOT NULL,
    rrule TEXT NOT NULL,              -- e.g., 'FREQ=MONTHLY;BYMONTHDAY=1'
    subscription_start TIMESTAMPTZ NOT NULL,
    last_billed_at TIMESTAMPTZ,
    next_billing_date TIMESTAMPTZ,
    status TEXT DEFAULT 'active'
);
```

### Computing Next Billing Date (Single Subscription)

```sql
-- Update next billing date for subscription #123
UPDATE subscriptions
SET next_billing_date = (
    SELECT rrule.after(
        rrule,
        subscription_start,
        COALESCE(last_billed_at, subscription_start),
        1,
        'America/New_York'
    )
)
WHERE id = 123;
```

### Batch Update: All Active Subscriptions

**This is the power of in-database computation** - no application loops, no round trips:

```sql
-- Update next billing dates for ALL active subscriptions in one query
UPDATE subscriptions
SET next_billing_date = rrule.after(
    rrule,
    subscription_start,
    COALESCE(last_billed_at, subscription_start),
    1,
    'America/New_York'
)
WHERE status = 'active';
```

**Why this works:** The function is called once per row that matches the WHERE clause. PostgreSQL evaluates the function using each row's columns directly - no JOIN needed.

### Find Subscriptions Due Today

```sql
-- Get all subscriptions with billing due today
SELECT
    id,
    customer_id,
    plan_name,
    next_billing_date
FROM subscriptions
WHERE status = 'active'
  AND DATE(next_billing_date) = CURRENT_DATE
ORDER BY next_billing_date;
```

### Generate Billing Schedule Report

```sql
-- Show next 3 billing dates for all active subscriptions
SELECT
    s.id,
    s.customer_id,
    s.plan_name,
    occurrence AS billing_date
FROM subscriptions s
CROSS JOIN LATERAL (
    SELECT * FROM rrule.after(
        s.rrule,
        s.subscription_start,
        COALESCE(s.last_billed_at, s.subscription_start),
        3,  -- Next 3 occurrences
        'America/New_York'
    )
) AS occurrence
WHERE s.status = 'active'
ORDER BY s.id, occurrence;
```

**Result:**
```
 id | customer_id |    plan_name    |     billing_date
----+-------------+-----------------+---------------------
  1 |         101 | Premium Monthly | 2025-02-01 00:00:00-05
  1 |         101 | Premium Monthly | 2025-03-01 00:00:00-05
  1 |         101 | Premium Monthly | 2025-04-01 00:00:00-04
  2 |         102 | Basic Weekly    | 2025-01-27 00:00:00-05
  2 |         102 | Basic Weekly    | 2025-02-03 00:00:00-05
  2 |         102 | Basic Weekly    | 2025-02-10 00:00:00-05
```

### Revenue Forecast by Month

```sql
-- Aggregate expected revenue by month
SELECT
    DATE_TRUNC('month', occurrence) AS billing_month,
    COUNT(*) AS billing_count,
    SUM(s.amount) AS expected_revenue
FROM subscriptions s
CROSS JOIN LATERAL (
    SELECT * FROM rrule.between(
        s.rrule,
        s.subscription_start,
        NOW(),
        NOW() + INTERVAL '6 months',
        'America/New_York'
    )
) AS occurrence
WHERE s.status = 'active'
GROUP BY billing_month
ORDER BY billing_month;
```

---

## Batch Operations

### Pattern: Update Computed Columns

**Problem:** You have a table with RRULE data and want to maintain a computed column.

```sql
CREATE TABLE events (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    rrule TEXT NOT NULL,
    event_start TIMESTAMPTZ NOT NULL,
    next_occurrence TIMESTAMPTZ,    -- Computed column
    occurrence_count INTEGER         -- Total occurrences
);

-- Populate next occurrence for all events (no loops!)
UPDATE events
SET
    next_occurrence = rrule.after(rrule, event_start, NOW(), 1),
    occurrence_count = rrule.count(rrule, event_start);
```

### Pattern: Filtering with Set Operations

```sql
-- Find events that occur on weekends in the next 30 days
SELECT DISTINCT
    e.id,
    e.title,
    occurrence
FROM events e
CROSS JOIN LATERAL (
    SELECT * FROM rrule.between(
        e.rrule,
        e.event_start,
        NOW(),
        NOW() + INTERVAL '30 days'
    )
) AS occurrence
WHERE EXTRACT(DOW FROM occurrence) IN (0, 6)  -- Sunday = 0, Saturday = 6
ORDER BY occurrence;
```

---

## Calendar Event Management

### Event Conflict Detection

**Find scheduling conflicts** - events that overlap in time:

```sql
CREATE TABLE calendar_events (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    rrule TEXT NOT NULL,
    event_start TIMESTAMPTZ NOT NULL,
    duration_minutes INTEGER NOT NULL
);

-- Find all events for user that conflict with a proposed meeting
-- Proposed: 2025-02-15 14:00 for 60 minutes
WITH proposed_meeting AS (
    SELECT
        '2025-02-15 14:00:00-05'::TIMESTAMPTZ AS start_time,
        '2025-02-15 15:00:00-05'::TIMESTAMPTZ AS end_time
),
user_occurrences AS (
    SELECT
        e.id,
        e.title,
        occurrence AS event_start,
        occurrence + (e.duration_minutes || ' minutes')::INTERVAL AS event_end
    FROM calendar_events e
    CROSS JOIN LATERAL (
        SELECT * FROM rrule.between(
            e.rrule,
            e.event_start,
            (SELECT start_time FROM proposed_meeting) - INTERVAL '1 day',
            (SELECT end_time FROM proposed_meeting) + INTERVAL '1 day'
        )
    ) AS occurrence
    WHERE e.user_id = 123  -- Target user
)
SELECT
    uo.id,
    uo.title,
    uo.event_start,
    uo.event_end
FROM user_occurrences uo
CROSS JOIN proposed_meeting pm
WHERE uo.event_start < pm.end_time
  AND uo.event_end > pm.start_time;  -- Overlap condition
```

### Availability Windows

```sql
-- Find all free time slots (inverse of scheduled events)
-- Uses generate_series to create time grid, then filters out occupied slots
WITH
    time_grid AS (
        SELECT
            slot_start,
            slot_start + INTERVAL '30 minutes' AS slot_end
        FROM generate_series(
            '2025-02-15 09:00:00-05'::TIMESTAMPTZ,
            '2025-02-15 17:00:00-05'::TIMESTAMPTZ,
            INTERVAL '30 minutes'
        ) AS slot_start
    ),
    busy_times AS (
        SELECT
            occurrence AS event_start,
            occurrence + (e.duration_minutes || ' minutes')::INTERVAL AS event_end
        FROM calendar_events e
        CROSS JOIN LATERAL (
            SELECT * FROM rrule.between(
                e.rrule,
                e.event_start,
                '2025-02-15 00:00:00-05'::TIMESTAMPTZ,
                '2025-02-15 23:59:59-05'::TIMESTAMPTZ
            )
        ) AS occurrence
        WHERE e.user_id = 123
    )
SELECT
    tg.slot_start,
    tg.slot_end
FROM time_grid tg
WHERE NOT EXISTS (
    SELECT 1 FROM busy_times bt
    WHERE tg.slot_start < bt.event_end
      AND tg.slot_end > bt.event_start
)
ORDER BY tg.slot_start;
```

---

## Resource Scheduling

### Room Booking System

```sql
CREATE TABLE room_bookings (
    id SERIAL PRIMARY KEY,
    room_id INTEGER NOT NULL,
    booking_name TEXT NOT NULL,
    rrule TEXT NOT NULL,
    booking_start TIMESTAMPTZ NOT NULL,
    duration_minutes INTEGER NOT NULL
);

-- Find available rooms for a specific time slot
-- Looking for: 2025-02-20 14:00-16:00
WITH target_time AS (
    SELECT
        '2025-02-20 14:00:00-05'::TIMESTAMPTZ AS start_time,
        '2025-02-20 16:00:00-05'::TIMESTAMPTZ AS end_time
),
booked_rooms AS (
    SELECT DISTINCT rb.room_id
    FROM room_bookings rb
    CROSS JOIN LATERAL (
        SELECT * FROM rrule.between(
            rb.rrule,
            rb.booking_start,
            (SELECT start_time FROM target_time) - INTERVAL '1 day',
            (SELECT end_time FROM target_time) + INTERVAL '1 day'
        )
    ) AS occurrence
    CROSS JOIN target_time tt
    WHERE occurrence < tt.end_time
      AND occurrence + (rb.duration_minutes || ' minutes')::INTERVAL > tt.start_time
)
SELECT room_id
FROM (SELECT DISTINCT room_id FROM room_bookings) all_rooms
WHERE room_id NOT IN (SELECT room_id FROM booked_rooms)
ORDER BY room_id;
```

### Equipment Maintenance Schedules

```sql
CREATE TABLE equipment (
    id SERIAL PRIMARY KEY,
    equipment_name TEXT NOT NULL,
    maintenance_rrule TEXT NOT NULL,
    last_maintenance TIMESTAMPTZ,
    install_date TIMESTAMPTZ NOT NULL
);

-- Generate maintenance schedule for all equipment over next 90 days
SELECT
    e.id,
    e.equipment_name,
    occurrence AS scheduled_maintenance,
    -- Days until maintenance
    EXTRACT(DAY FROM occurrence - NOW()) AS days_until_maintenance
FROM equipment e
CROSS JOIN LATERAL (
    SELECT * FROM rrule.between(
        e.maintenance_rrule,
        COALESCE(e.last_maintenance, e.install_date),
        NOW(),
        NOW() + INTERVAL '90 days'
    )
) AS occurrence
WHERE occurrence > NOW()
ORDER BY occurrence;

-- Find equipment due for maintenance this week
SELECT
    e.id,
    e.equipment_name,
    next_maint.occurrence AS maintenance_date
FROM equipment e
CROSS JOIN LATERAL (
    SELECT * FROM rrule.after(
        e.maintenance_rrule,
        COALESCE(e.last_maintenance, e.install_date),
        NOW(),
        1
    )
) AS next_maint
WHERE next_maint.occurrence <= NOW() + INTERVAL '7 days'
ORDER BY next_maint.occurrence;
```

---

## Performance Tips

### Use LATERAL JOINs for Row-by-Row Expansion

**Good** - LATERAL processes each row efficiently:
```sql
SELECT e.id, occurrence
FROM events e
CROSS JOIN LATERAL (
    SELECT * FROM rrule.all(e.rrule, e.event_start)
) AS occurrence;
```

**Avoid** - Correlated subquery in SELECT (less efficient):
```sql
-- Don't do this
SELECT
    e.id,
    (SELECT * FROM rrule.all(e.rrule, e.event_start))  -- Wrong!
FROM events e;
```

### Filter Early, Expand Late

**Good** - Filter before expanding occurrences:
```sql
SELECT occurrence
FROM events e
CROSS JOIN LATERAL rrule.all(e.rrule, e.event_start) AS occurrence
WHERE e.status = 'active'      -- Filter first (indexed)
  AND e.user_id = 123          -- Filter first (indexed)
  AND occurrence > NOW();      -- Filter expanded results
```

### Use rrule.between() Instead of rrule.all()

When you know the date range, `between()` is more efficient:

```sql
-- Good - only generates occurrences in range
SELECT * FROM rrule.between(
    'FREQ=DAILY;COUNT=1000',
    '2025-01-01',
    '2025-02-01',  -- Only need February
    '2025-02-28'
);

-- Less efficient - generates all 1000, then filters
SELECT * FROM rrule.all(
    'FREQ=DAILY;COUNT=1000',
    '2025-01-01'
)
WHERE occurrence BETWEEN '2025-02-01' AND '2025-02-28';
```

### Batch Updates vs. Row-by-Row

**Best** - Direct function call in SET clause:
```sql
-- Simplest and most efficient
UPDATE subscriptions
SET next_billing_date = rrule.after(
    rrule,
    subscription_start,
    COALESCE(last_billed_at, subscription_start),
    1
)
WHERE status = 'active';
```

**Alternative** - FROM subquery (only needed for complex computed values):
```sql
-- Use this pattern when you need to reference aggregations or window functions
UPDATE subscriptions s
SET next_billing_date = computed.next_date
FROM (
    SELECT id, rrule.after(...) AS next_date
    FROM subscriptions
    WHERE status = 'active'
) computed
WHERE s.id = computed.id;
```

**Avoid** - Loop in application code:
```python
# Don't do this - requires N round trips to database
for subscription in active_subscriptions:
    next_date = compute_next_billing(subscription)
    update_subscription(subscription.id, next_date)
```

### Index Strategy

```sql
-- Index filtered columns for efficient WHERE clauses
CREATE INDEX idx_subscriptions_status ON subscriptions(status);
CREATE INDEX idx_subscriptions_next_billing ON subscriptions(next_billing_date);

-- Composite index for common query patterns
CREATE INDEX idx_subscriptions_status_next_billing
    ON subscriptions(status, next_billing_date);

-- Don't index rrule column (text, not useful for indexing)
```

---

## Summary

**Key Patterns:**
1. **LATERAL JOIN** - Expand occurrences row-by-row efficiently
2. **Batch UPDATE** - Use JOINs instead of loops
3. **Filter early** - Apply WHERE before occurrence expansion
4. **Use between()** - When you know the date range
5. **Set-based operations** - Leverage SQL's strength with JOINs, aggregations, etc.

**Performance Wins:**
- ✅ No application-database round trips for batch operations
- ✅ Query planner optimizes entire operation
- ✅ Memory-efficient SETOF streaming
- ✅ Native PostgreSQL date/time handling

For more examples, see:
- [API Reference](API_REFERENCE.md) - Complete function documentation
- [README](README.md) - Basic usage patterns
- [Development Guide](DEVELOPMENT.md) - Architecture and internals
