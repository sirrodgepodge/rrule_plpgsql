# Performance Optimization Guide

## Overview

This guide provides recommendations for optimizing performance when using rrule_plpgsql in production environments.

---

## Database Indexes

### Recommended Indexes for Tables with RRULE Columns

When you have tables that store RRULE strings and datetimes, these indexes can significantly improve query performance:

#### Basic Indexes

```sql
-- For tables with RRULE data
CREATE TABLE events (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  dtstart TIMESTAMPTZ NOT NULL,
  dtend TIMESTAMPTZ,
  rrule TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index 1: BRIN index for datetime columns (excellent for chronological data)
-- BRIN (Block Range Index) is extremely space-efficient for time-series data
CREATE INDEX idx_events_dtstart_brin
  ON events USING brin(dtstart)
  WITH (pages_per_range = 128);

-- Index 2: Partial index for events with recurrence rules
-- Only indexes rows that have RRULE (saves space)
CREATE INDEX idx_events_with_rrule
  ON events (dtstart)
  WHERE rrule IS NOT NULL;

-- Index 3: Hash index for exact RRULE lookups (if needed)
CREATE INDEX idx_events_rrule_hash
  ON events USING hash(rrule)
  WHERE rrule IS NOT NULL;
```

#### Advanced Indexes for Complex Queries

```sql
-- Index 4: Composite index for range queries with RRULE
-- Useful for "find all recurring events in date range" queries
CREATE INDEX idx_events_dtstart_rrule
  ON events (dtstart, rrule)
  WHERE rrule IS NOT NULL;

-- Index 5: B-tree index for sorting by start date
-- When you need ORDER BY dtstart frequently
CREATE INDEX idx_events_dtstart_btree
  ON events (dtstart DESC);

-- Index 6: Partial index for non-recurring events
-- Separates one-time events for faster queries
CREATE INDEX idx_events_single_occurrence
  ON events (dtstart)
  WHERE rrule IS NULL;
```

#### Expression Indexes for TZID Support

```sql
-- Index 7: Expression index for timezone-aware queries
-- Useful when querying events in a specific timezone
CREATE INDEX idx_events_dtstart_utc
  ON events ((dtstart AT TIME ZONE 'UTC'));

CREATE INDEX idx_events_dtstart_ny
  ON events ((dtstart AT TIME ZONE 'America/New_York'));
```

### Index Selection Guide

| Query Pattern | Recommended Index | Reason |
|---------------|-------------------|--------|
| `WHERE dtstart >= ? AND dtstart <= ?` | BRIN or B-tree on dtstart | Range scans |
| `WHERE rrule = ?` | Hash on rrule | Exact match |
| `WHERE rrule IS NOT NULL` | Partial index with rrule filter | Includes only relevant rows |
| `WHERE dtstart > ? AND rrule LIKE 'FREQ=DAILY%'` | Composite (dtstart, rrule) | Multi-column filter |
| `ORDER BY dtstart DESC LIMIT 10` | B-tree DESC on dtstart | Sorted results |

---

## Query Optimization Patterns

### Pattern 1: Filtering Recurring Events in Range

#### ❌ Inefficient (N+1 queries)
```sql
-- DON'T: Query each event separately
SELECT id, title FROM events WHERE rrule IS NOT NULL;
-- Then for each row: SELECT * FROM rrule.between(...)
```

#### ✅ Efficient (Set-based)
```sql
-- DO: Use LATERAL JOIN for set-based processing
SELECT
  e.id,
  e.title,
  occurrence
FROM events e
CROSS JOIN LATERAL (
  SELECT * FROM rrule.between(
    e.rrule,
    e.dtstart,
    '2025-01-01'::TIMESTAMP,
    '2025-12-31'::TIMESTAMP
  )
) AS occurrence
WHERE e.rrule IS NOT NULL
  AND e.dtstart <= '2025-12-31'::TIMESTAMPTZ;
```

### Pattern 2: Finding Next Occurrence Across All Events

#### ❌ Inefficient
```sql
-- DON'T: Generate all occurrences then filter
SELECT e.id, e.title, occ.occurrence
FROM events e,
LATERAL rrule.all(e.rrule, e.dtstart) AS occ(occurrence)
WHERE occ.occurrence > NOW()
ORDER BY occ.occurrence
LIMIT 1;
```

#### ✅ Efficient
```sql
-- DO: Use rrule.after() with index on dtstart
WITH next_occurrences AS (
  SELECT
    e.id,
    e.title,
    rrule.after(e.rrule, e.dtstart, NOW()::TIMESTAMP) AS next_occ
  FROM events e
  WHERE e.rrule IS NOT NULL
    AND e.dtstart <= NOW()  -- Index scan
)
SELECT id, title, next_occ
FROM next_occurrences
WHERE next_occ IS NOT NULL
ORDER BY next_occ
LIMIT 1;
```

### Pattern 3: Checking Event Conflicts

#### ❌ Inefficient
```sql
-- DON'T: Expand all occurrences for conflict detection
SELECT DISTINCT e1.id, e2.id
FROM events e1, events e2,
LATERAL rrule.all(e1.rrule, e1.dtstart) AS occ1(t),
LATERAL rrule.all(e2.rrule, e2.dtstart) AS occ2(t)
WHERE e1.id != e2.id
  AND occ1.t = occ2.t;
```

#### ✅ Efficient
```sql
-- DO: Use rrule.overlaps() function
SELECT e1.id, e2.id
FROM events e1, events e2
WHERE e1.id < e2.id
  AND rrule.overlaps(
    e1.dtstart,
    e1.dtend,
    e1.rrule,
    e2.dtstart,
    e2.dtend
  );
```

---

## Performance Configuration

### PostgreSQL Settings for RRULE Workloads

```sql
-- 1. Set reasonable statement timeout to prevent runaway queries
ALTER DATABASE your_db SET statement_timeout = '30s';

-- 2. Increase work_mem for complex RRULE calculations
-- (per-connection setting, adjust based on available RAM)
ALTER DATABASE your_db SET work_mem = '64MB';

-- 3. Enable parallel query execution for large datasets
ALTER DATABASE your_db SET max_parallel_workers_per_gather = 4;

-- 4. Optimize for IMMUTABLE function caching
ALTER DATABASE your_db SET enable_seqscan = on;
```

### Application-Level Settings

```typescript
// Connection pool sizing for RRULE-heavy applications
const pool = new Pool({
  max: 20,                    // Max connections
  idleTimeoutMillis: 30000,   // Close idle connections
  connectionTimeoutMillis: 2000,

  // Important: Set statement timeout at connection level
  statement_timeout: 30000,   // 30 second timeout
});
```

---

## Performance Monitoring

### Slow Query Detection

```sql
-- Find slow RRULE queries
SELECT
  query,
  mean_exec_time,
  calls,
  total_exec_time
FROM pg_stat_statements
WHERE query LIKE '%rrule.%'
ORDER BY mean_exec_time DESC
LIMIT 10;
```

### Index Usage Analysis

```sql
-- Check if RRULE-related indexes are being used
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan,
  idx_tup_read,
  idx_tup_fetch
FROM pg_stat_user_indexes
WHERE tablename IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public')
ORDER BY idx_scan DESC;
```

### Cache Hit Ratio

```sql
-- Monitor function call performance
SELECT
  funcname,
  calls,
  total_time,
  self_time,
  total_time / calls AS avg_time
FROM pg_stat_user_functions
WHERE schemaname = 'rrule'
ORDER BY total_time DESC;
```

---

## Benchmarking

### Example Performance Tests

```sql
-- Benchmark 1: Simple daily recurrence (1000 occurrences)
EXPLAIN ANALYZE
SELECT * FROM rrule.all('FREQ=DAILY;COUNT=1000', '2025-01-01'::TIMESTAMP);
-- Expected: < 50ms

-- Benchmark 2: Complex BYSETPOS filter
EXPLAIN ANALYZE
SELECT * FROM rrule.all(
  'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=12',
  '2025-01-01'::TIMESTAMP
);
-- Expected: < 100ms

-- Benchmark 3: Set-based batch processing (100 events)
EXPLAIN ANALYZE
SELECT e.id, COUNT(*) AS occurrence_count
FROM events e
CROSS JOIN LATERAL rrule.between(
  e.rrule,
  e.dtstart,
  '2025-01-01'::TIMESTAMP,
  '2025-12-31'::TIMESTAMP
) AS occ
WHERE e.rrule IS NOT NULL
GROUP BY e.id;
-- Expected: Proportional to event count, < 1s for 100 events
```

---

## Common Performance Pitfalls

### ❌ Pitfall 1: Missing WHERE rrule IS NOT NULL

```sql
-- BAD: Scans all rows including non-recurring events
SELECT * FROM events;

-- GOOD: Use partial index
SELECT * FROM events WHERE rrule IS NOT NULL;
```

### ❌ Pitfall 2: Generating Unnecessary Occurrences

```sql
-- BAD: Generates all occurrences then filters
SELECT * FROM rrule.all('FREQ=DAILY', '2020-01-01'::TIMESTAMP)
WHERE occurrence >= '2025-01-01';

-- GOOD: Use rrule.after() or rrule.between()
SELECT * FROM rrule.after('FREQ=DAILY', '2020-01-01'::TIMESTAMP, '2025-01-01'::TIMESTAMP, 1);
```

### ❌ Pitfall 3: Not Using LIMIT

```sql
-- BAD: Unbounded result set
SELECT * FROM rrule.all('FREQ=SECONDLY', '2025-01-01'::TIMESTAMP);
-- ^ Will fail: SECONDLY not available in standard install

-- GOOD: Always use COUNT in RRULE or LIMIT in query
SELECT * FROM rrule.all('FREQ=DAILY;COUNT=365', '2025-01-01'::TIMESTAMP);
```

---

## Scaling Recommendations

### For < 1,000 Events
- Basic BRIN index on dtstart
- Use simple queries with LATERAL JOIN

### For 1,000 - 10,000 Events
- Add composite indexes (dtstart, rrule)
- Use partial indexes for recurring vs non-recurring
- Enable connection pooling
- Monitor slow queries

### For 10,000+ Events
- Partition tables by date range
- Use materialized views for common queries
- Implement caching layer (Redis) for hot queries
- Consider denormalizing next_occurrence column
- Use read replicas for reporting

---

## Caching Strategy

### Application-Level Caching

```typescript
// Example: Cache next occurrence for each event
import { createClient } from 'redis';

const redis = createClient();

async function getNextOccurrence(eventId: string): Promise<Date | null> {
  // Check cache first
  const cached = await redis.get(`event:${eventId}:next`);
  if (cached) return new Date(cached);

  // Query database
  const result = await db.query(
    'SELECT rrule.next($1, $2) AS next_occ FROM events WHERE id = $3',
    [rrule, dtstart, eventId]
  );

  // Cache for 1 hour
  if (result.rows[0].next_occ) {
    await redis.setEx(
      `event:${eventId}:next`,
      3600,
      result.rows[0].next_occ.toISOString()
    );
  }

  return result.rows[0].next_occ;
}
```

---

## Summary

**Key Performance Principles:**

1. ✅ Use BRIN indexes for chronological data
2. ✅ Use partial indexes to filter recurring events
3. ✅ Use LATERAL JOIN for set-based processing
4. ✅ Always specify COUNT or UNTIL in RRULEs
5. ✅ Use rrule.between() instead of rrule.all() with WHERE
6. ✅ Monitor query performance with pg_stat_statements
7. ✅ Set statement_timeout to prevent runaway queries
8. ✅ Cache hot queries at application level

**Expected Performance:**
- Single RRULE expansion: < 100ms for 1000 occurrences
- Batch processing: < 1s for 100 events with yearly recurrence
- Index scans: < 10ms for date range queries

For specific performance issues, please open a GitHub issue with:
- EXPLAIN ANALYZE output
- Table sizes
- Index definitions
- PostgreSQL version
