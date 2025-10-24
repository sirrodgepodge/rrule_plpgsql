# Including Sub-Day Operations Guide

## Overview

This guide explains how to safely enable and use sub-day frequencies (HOURLY, MINUTELY, SECONDLY) in rrule_plpgsql.

**⚠️ Security Warning**: Sub-day frequencies are **disabled by default** because they can generate millions of occurrences, posing denial-of-service risks in multi-tenant environments.

---

## What Are Sub-Day Frequencies?

Sub-day frequencies allow recurrence rules at intervals shorter than one day:

- **HOURLY**: Events recurring every N hours
  - Example: "Every 3 hours" generates 8 occurrences per day
  - Max potential: 8,760 occurrences per year

- **MINUTELY**: Events recurring every N minutes
  - Example: "Every 15 minutes" generates 96 occurrences per day
  - Max potential: 525,600 occurrences per year

- **SECONDLY**: Events recurring every N seconds
  - Example: "Every 30 seconds" generates 2,880 occurrences per day
  - Max potential: 31,536,000 occurrences per year

---

## Security Risks

### Denial of Service (DoS)
Malicious or misconfigured RRULEs can exhaust system resources:

```sql
-- This would attempt to generate 31,536,000 occurrences!
SELECT * FROM rrule.all('FREQ=SECONDLY;COUNT=31536000', '2025-01-01');
```

### Resource Exhaustion
- **CPU**: Computing millions of date increments
- **Memory**: Building large TIMESTAMP[] arrays
- **Connection Pool**: Blocking connections in multi-tenant systems
- **Query Timeouts**: Long-running queries affecting other users

### Attack Vectors
In multi-tenant environments, one user could intentionally create expensive RRULEs that impact all tenants.

---

## When to Enable Sub-Day Frequencies

✅ **SAFE scenarios**:
- Single-tenant deployments where you control all RRULE input
- Internal tools with trusted users only
- Application has strict validation before RRULE reaches database
- Statement timeouts configured
- Monitoring and alerting in place

❌ **UNSAFE scenarios**:
- Multi-tenant SaaS applications
- User-generated RRULE strings without validation
- Public APIs accepting arbitrary RRULEs
- Systems without query monitoring
- Environments without statement timeouts

---

## Installation

### Standard Installation (Sub-Day Disabled)
```bash
cd rrule_plpgsql
psql -d your_database -f src/install.sql
```

### With Sub-Day Frequencies Enabled
```bash
cd rrule_plpgsql
psql -d your_database -f src/install_with_subday.sql
```

**Note**: `install_with_subday.sql` includes both standard frequencies AND sub-day frequencies.

---

## Required Safeguards

Before enabling sub-day frequencies, you **MUST** implement these safeguards:

### 1. Application-Level Validation

Validate RRULEs before they reach the database:

**TypeScript Example**:
```typescript
function validateRRule(rrule: string): void {
  const count = parseInt(rrule.match(/COUNT=(\d+)/)?.[1] || '0');
  const until = rrule.match(/UNTIL=([^;]+)/)?.[1];

  // HOURLY validation
  if (rrule.includes('FREQ=HOURLY')) {
    if (count > 1000) {
      throw new Error('HOURLY frequency limited to COUNT=1000');
    }
    if (until) {
      const duration = new Date(until).getTime() - new Date().getTime();
      const maxDuration = 7 * 24 * 60 * 60 * 1000; // 7 days
      if (duration > maxDuration) {
        throw new Error('HOURLY frequency limited to 7 days duration');
      }
    }
  }

  // MINUTELY validation (stricter)
  if (rrule.includes('FREQ=MINUTELY')) {
    if (count > 1000) {
      throw new Error('MINUTELY frequency limited to COUNT=1000');
    }
    if (until) {
      const duration = new Date(until).getTime() - new Date().getTime();
      const maxDuration = 24 * 60 * 60 * 1000; // 24 hours
      if (duration > maxDuration) {
        throw new Error('MINUTELY frequency limited to 24 hours');
      }
    }
  }

  // SECONDLY validation (very strict)
  if (rrule.includes('FREQ=SECONDLY')) {
    if (count > 1000) {
      throw new Error('SECONDLY frequency limited to COUNT=1000');
    }
    if (until) {
      const duration = new Date(until).getTime() - new Date().getTime();
      const maxDuration = 60 * 60 * 1000; // 1 hour
      if (duration > maxDuration) {
        throw new Error('SECONDLY frequency limited to 1 hour');
      }
    }
  }
}

// Usage
try {
  validateRRule(userInput);
  const occurrences = await db.query(
    'SELECT * FROM rrule.all($1, $2)',
    [userInput, dtstart]
  );
} catch (error) {
  return { error: error.message };
}
```

**Python Example**:
```python
import re
from datetime import datetime, timedelta

def validate_rrule(rrule: str) -> None:
    count_match = re.search(r'COUNT=(\d+)', rrule)
    count = int(count_match.group(1)) if count_match else 0

    until_match = re.search(r'UNTIL=([^;]+)', rrule)

    if 'FREQ=HOURLY' in rrule:
        if count > 1000:
            raise ValueError('HOURLY frequency limited to COUNT=1000')
        if until_match:
            # Parse and validate duration
            pass  # Add duration check

    if 'FREQ=MINUTELY' in rrule:
        if count > 1000:
            raise ValueError('MINUTELY frequency limited to COUNT=1000')

    if 'FREQ=SECONDLY' in rrule:
        if count > 1000:
            raise ValueError('SECONDLY frequency limited to COUNT=1000')
```

### 2. Database Statement Timeout

Configure PostgreSQL to kill long-running queries:

```sql
-- Database-level (recommended)
ALTER DATABASE your_database SET statement_timeout = '30s';

-- Or per-session
SET statement_timeout = '30s';

-- Or per-transaction
BEGIN;
SET LOCAL statement_timeout = '30s';
SELECT * FROM rrule.all(...);
COMMIT;
```

### 3. Query Monitoring

Set up monitoring to detect long-running RRULE queries:

```sql
-- Find queries running longer than 10 seconds
SELECT
  pid,
  now() - pg_stat_activity.query_start AS duration,
  state,
  query
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '10 seconds'
  AND state = 'active'
  AND query LIKE '%rrule.%'
ORDER BY duration DESC;
```

**Set up alerts** when queries exceed thresholds.

### 4. Recommended Limits

| Frequency | COUNT Limit | UNTIL Limit | Use Case Example |
|-----------|-------------|-------------|------------------|
| HOURLY | ≤ 1,000 | ≤ 7 days | "Every 3 hours for a week" |
| MINUTELY | ≤ 1,000 | ≤ 24 hours | "Every 15 minutes today" |
| SECONDLY | ≤ 1,000 | ≤ 1 hour | "Every 30 seconds for 5 minutes" |

---

## Usage Examples

Once enabled with proper safeguards:

### HOURLY Examples

```sql
-- Every 3 hours, 8 times
SELECT * FROM rrule.all(
  'FREQ=HOURLY;INTERVAL=3;COUNT=8',
  '2025-01-01 09:00:00'::TIMESTAMP
);
-- Returns: 09:00, 12:00, 15:00, 18:00, 21:00, 00:00, 03:00, 06:00

-- Every hour during business hours
SELECT * FROM rrule.all(
  'FREQ=HOURLY;BYHOUR=9,10,11,12,13,14,15,16,17;COUNT=45',
  '2025-01-01 09:00:00'::TIMESTAMP
);
-- Returns: 9 hours/day × 5 days = 45 occurrences
```

### MINUTELY Examples

```sql
-- Every 15 minutes for 2 hours
SELECT * FROM rrule.all(
  'FREQ=MINUTELY;INTERVAL=15;COUNT=8',
  '2025-01-01 09:00:00'::TIMESTAMP
);
-- Returns: 09:00, 09:15, 09:30, 09:45, 10:00, 10:15, 10:30, 10:45

-- Every minute during specific hours
SELECT * FROM rrule.all(
  'FREQ=MINUTELY;BYHOUR=10,11;COUNT=120',
  '2025-01-01 10:00:00'::TIMESTAMP
);
-- Returns: 60 minutes × 2 hours = 120 occurrences
```

### SECONDLY Examples

```sql
-- Every 30 seconds for 5 minutes
SELECT * FROM rrule.all(
  'FREQ=SECONDLY;INTERVAL=30;COUNT=10',
  '2025-01-01 09:00:00'::TIMESTAMP
);
-- Returns: 10 occurrences at 30-second intervals

-- Real-time monitoring every 10 seconds
SELECT * FROM rrule.all(
  'FREQ=SECONDLY;INTERVAL=10;COUNT=60',
  '2025-01-01 09:00:00'::TIMESTAMP
);
-- Returns: 60 occurrences = 10 minutes of monitoring
```

---

## Testing After Installation

Verify sub-day frequencies are working:

```sql
-- Test HOURLY
SELECT COUNT(*) FROM rrule.all(
  'FREQ=HOURLY;COUNT=5',
  '2025-01-01 10:00:00'::TIMESTAMP
);
-- Expected: 5

-- Test MINUTELY
SELECT COUNT(*) FROM rrule.all(
  'FREQ=MINUTELY;COUNT=5',
  '2025-01-01 10:00:00'::TIMESTAMP
);
-- Expected: 5

-- Test SECONDLY
SELECT COUNT(*) FROM rrule.all(
  'FREQ=SECONDLY;COUNT=5',
  '2025-01-01 10:00:00'::TIMESTAMP
);
-- Expected: 5
```

If these return 0 results, sub-day frequencies are not enabled. Use `install_with_subday.sql`.

---

## Troubleshooting

### Sub-Day Frequencies Return 0 Results

**Problem**: Installed with `install.sql` instead of `install_with_subday.sql`

**Solution**: Reinstall with sub-day support:
```bash
psql -d your_database -c "DROP SCHEMA IF EXISTS rrule CASCADE;"
psql -d your_database -f src/install_with_subday.sql
```

### Queries Timing Out

**Problem**: RRULEs generating too many occurrences

**Solution**:
1. Check validation is working (COUNT/UNTIL limits enforced)
2. Verify statement_timeout is configured
3. Review RRULE patterns for excessive generation

### Performance Issues

**Problem**: Sub-day queries slow

**Solution**:
- Ensure COUNT parameter is used (never rely on default limits)
- Use UNTIL for time-bounded queries
- Consider caching results in application layer for repeated queries
- Monitor with `EXPLAIN ANALYZE` to identify bottlenecks

---

## Migration Path

### From Standard to Sub-Day Installation

Already using standard installation? Upgrade with sub-day support:

```bash
cd rrule_plpgsql

# 1. Backup database
pg_dump your_database > backup.sql

# 2. Implement validation in application code (see above)

# 3. Configure statement timeout
psql -d your_database -c "ALTER DATABASE your_database SET statement_timeout = '30s';"

# 4. Reinstall with sub-day support
psql -d your_database -c "DROP SCHEMA IF EXISTS rrule CASCADE;"
psql -d your_database -f src/install_with_subday.sql

# 5. Test
psql -d your_database -c "
  SELECT 'HOURLY: ' || COUNT(*) || ' results'
  FROM rrule.all('FREQ=HOURLY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);
"
```

### From Sub-Day to Standard Installation

Need to disable sub-day frequencies?

```bash
# Reinstall standard version (sub-day disabled)
psql -d your_database -c "DROP SCHEMA IF EXISTS rrule CASCADE;"
psql -d your_database -f src/install.sql
```

**Note**: Existing RRULEs with sub-day frequencies will return 0 results and show a NOTICE message.

---

## Best Practices

1. **Always validate before database**: Never trust user input
2. **Use COUNT parameter**: Avoid open-ended recurrences
3. **Set reasonable limits**: Match limits to actual use cases
4. **Monitor queries**: Set up alerts for long-running RRULE queries
5. **Test in staging**: Verify performance with production-like data
6. **Document limits**: Make validation rules clear to API consumers
7. **Cache when possible**: Store computed occurrences for repeated queries
8. **Use INTERVAL wisely**: `INTERVAL=15` with MINUTELY is safer than `INTERVAL=1`

---

## Security Checklist

Before deploying sub-day frequencies to production:

- [ ] Application-level validation implemented
- [ ] Statement timeout configured (`30s` recommended)
- [ ] Query monitoring and alerts set up
- [ ] Tested with maximum expected COUNT values
- [ ] Documented validation rules for API consumers
- [ ] Single-tenant deployment OR strict user permissions
- [ ] Backup and rollback plan prepared
- [ ] Load tested with concurrent sub-day queries

---

## Support

For questions or issues:
- **GitHub Issues**: https://github.com/sirrodgepodge/rrule_plpgsql/issues
- **Security Issues**: See [SECURITY.md](SECURITY.md)
- **Documentation**: See main [README.md](README.md)

---

## References

- [RFC 5545 - RRULE Specification](https://datatracker.ietf.org/doc/html/rfc5545)
- [PostgreSQL Statement Timeout](https://www.postgresql.org/docs/current/runtime-config-client.html#GUC-STATEMENT-TIMEOUT)
- [Main Project Documentation](README.md)
- [Security Guide](SECURITY.md)
