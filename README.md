# rrule_plpgsql

Pure PL/pgSQL implementation of iCalendar RRULE (RFC 5545) for PostgreSQL. No C extensions, no compilation, works everywhere.

---

## Overview

This library provides complete RRULE recurrence calculation functionality using pure PL/pgSQL. **Use this implementation for all environments** (local, development, staging, production) to ensure consistency.

**Key Features:**
- ✅ **No C extensions required** - Pure PL/pgSQL, works on any PostgreSQL
- ✅ **Full timezone support with DST handling** - Wall-clock time preserved ("10 AM stays 10 AM" across DST transitions)
- ✅ **Consistent everywhere** - Same implementation across all environments
- ✅ **Production-ready** - Comprehensive test suite with 187 tests (including table operation integration tests)
- ✅ **RFC 5545 & RFC 7529 compliant** - Supports standard RRULE patterns plus SKIP/RSCALE
- ✅ **50-75x faster than Node.js** - Excellent performance without compilation
- ✅ **Works on managed services** - AlloyDB, RDS, Azure Database for PostgreSQL

---

## Why This Approach?

### Query Engine Integration

**Computation where your data lives** delivers performance impossible with external processing:
- **Set-based operations**: JOIN recurrence rules against events, bookings, or any table without data transfer
- **Native WHERE/aggregation**: Filter by occurrence dates, COUNT occurrences, GROUP BY - all in SQL
- **Batch processing**: Process 100+ schedules in a single query without round trips
- **Memory-efficient streaming**: SETOF returns results incrementally, not all at once
- **50-75x faster than Node.js** for single-schedule operations, infinitely faster for multi-schedule batch queries

**See [Example Usage](EXAMPLE_USAGE.md) for practical patterns including subscription billing, batch updates, and conflict detection.**

### Zero Compilation

Pure PL/pgSQL means:
- ✅ No C compiler or build tools required
- ✅ Install with a single SQL file - no configuration
- ✅ Consistent behavior across all environments (dev, staging, production)

**Universal compatibility:**
- ✅ **Google AlloyDB** - High-performance PostgreSQL with AI integration
- ✅ **Google Cloud SQL** - Fully managed PostgreSQL service
- ✅ **Amazon Aurora PostgreSQL** - Serverless PostgreSQL with automatic scaling
- ✅ **Amazon RDS PostgreSQL** - Managed PostgreSQL without custom extensions
- ✅ **Azure Database for PostgreSQL** - Fully supported managed service
- ✅ **Self-hosted PostgreSQL** - No special configuration required
- ✅ **Docker PostgreSQL** - Standard postgres image compatibility

---

## Quick Start

```bash
# Install via psql
psql -d your_database -f src/install.sql

# Or use curl for one-line install
curl -sL https://raw.githubusercontent.com/sirrodgepodge/rrule_plpgsql/main/src/install.sql | psql -d your_database
```

**Next Steps:** See [Installation Guide](INSTALLATION.md) for TypeScript/ORM setup or [Example Usage](EXAMPLE_USAGE.md) for practical patterns.

---

## Documentation

### 📖 Core Documentation

- **[Installation Guide](INSTALLATION.md)** - TypeScript ORMs (node-postgres, TypeORM, Prisma, Knex, Sequelize, Drizzle)
- **[Example Usage](EXAMPLE_USAGE.md)** - Real-world patterns: subscription billing, batch operations, conflict detection
- **[API Reference](API_REFERENCE.md)** - Complete function reference with parameters and examples
- **[RFC Spec Compliance](SPEC_COMPLIANCE.md)** - Supported RFC 5545/7529 features and limitations
- **[Validation Rules](VALIDATION.md)** - RRULE constraint validation and error messages
- **[Development Guide](DEVELOPMENT.md)** - Testing, architecture, and contribution guidelines

### 🔒 Security & Advanced Features

- **[Security Guide](SECURITY.md)** - Best practices and vulnerability reporting
- **[Performance Optimization](PERFORMANCE.md)** - Indexes, query patterns, and scaling recommendations
- **[Sub-Day Operations](INCLUDING_SUBDAY_OPERATIONS.md)** - HOURLY/MINUTELY/SECONDLY guide (disabled by default)
- **[Migration Guide](MANUAL_MIGRATION.md)** - Upgrading with dependent database objects

---

## Key Features

### Supported Frequencies

**✅ Production-Ready (Always Enabled):**
- `FREQ=DAILY` - Daily recurrence with date/time filters
- `FREQ=WEEKLY` - Weekly recurrence with day-of-week selection
- `FREQ=MONTHLY` - Monthly recurrence with day/week-of-month selection
- `FREQ=YEARLY` - Yearly recurrence with month/day/week selection

**⚠️ Advanced (Optional, Disabled by Default):**
- `FREQ=HOURLY` - Hourly recurrence (8,760/year max)
- `FREQ=MINUTELY` - Minutely recurrence (525,600/year max)
- `FREQ=SECONDLY` - Secondly recurrence (31M/year max)

See **[Sub-Day Operations Guide](INCLUDING_SUBDAY_OPERATIONS.md)** for enabling these safely.

### Supported Modifiers

- `COUNT` - Limit number of occurrences
- `UNTIL` - End date for recurrence
- `INTERVAL` - Frequency multiplier (every N days/weeks/months)
- `BYDAY` - Filter by day of week (MO, TU, WE, TH, FR, SA, SU)
- `BYDAY` with ordinals - Positioned weekdays (2MO = 2nd Monday, -1FR = last Friday)
- `BYMONTHDAY` - Filter by day of month (1-31, -1 = last day)
- `BYMONTH` - Filter by month (1-12)
- `BYYEARDAY` - Filter by day of year (1-366, negative supported)
- `BYWEEKNO` - Filter by ISO week number (1-53, YEARLY only)
- `BYSETPOS` - Select specific positions from generated set
- `WKST` - Week start day (SU, MO, TU, WE, TH, FR, SA)
- `SKIP` - Invalid date handling (OMIT, BACKWARD, FORWARD)
- `TZID` - Timezone specification with automatic DST handling
- `RSCALE` - Calendar system (GREGORIAN supported)

**See [RFC Spec Compliance](SPEC_COMPLIANCE.md) for complete feature support matrix and examples.**

### Timezone Support

**Full RFC 5545 timezone support with automatic DST handling:**

```sql
-- Meeting stays at 10 AM wall-clock time across DST boundary
SELECT * FROM rrule.all(
    'FREQ=DAILY;COUNT=3;TZID=America/New_York',
    '2025-03-08 10:00:00'::TIMESTAMP
);
-- Returns: March 8 (EST), March 9 (EDT), March 10 (EDT)
-- All at 10:00 AM wall-clock time
```

**See [API Reference](API_REFERENCE.md) for TIMESTAMPTZ API details.**

---

## Installation Options

### Standard Installation (Recommended)

```bash
psql -d your_database -f src/install.sql
```

**Includes:**
- DAILY, WEEKLY, MONTHLY, YEARLY frequencies
- All standard modifiers and filters
- Timezone support with DST handling
- Secure by default (no DoS vectors)

### With Sub-Day Frequencies (Advanced)

```bash
psql -d your_database -f src/install_with_subday.sql
```

**Includes standard PLUS:**
- HOURLY, MINUTELY, SECONDLY frequencies
- ⚠️ Security warnings during installation
- Requires application-level validation

**See [Sub-Day Operations Guide](INCLUDING_SUBDAY_OPERATIONS.md) before using this installation.**

---

## Troubleshooting

### Common Issues

**Error: "Invalid RRULE: FREQ parameter is required"**
- Every RRULE must start with FREQ
- Fix: Add `FREQ=DAILY` (or WEEKLY/MONTHLY/YEARLY)

**Error: "COUNT and UNTIL are mutually exclusive"**
- Cannot use both COUNT and UNTIL in same RRULE
- Fix: Use either `COUNT=10` OR `UNTIL=20251231T235959`

**Error: "BYWEEKNO can only be used with FREQ=YEARLY"**
- BYWEEKNO requires YEARLY frequency
- Fix: Change to `FREQ=YEARLY;BYWEEKNO=10`

**See [Validation Rules](VALIDATION.md) for complete error reference.**

---

## API Overview

**Both APIs are fully timezone-aware with automatic DST handling.**

### Public API Functions

All functions support both `TIMESTAMP` and `TIMESTAMPTZ` types with flexible timezone handling:

**Timezone Resolution Priority:**
1. **Explicit timezone parameter** (if provided)
2. **TZID in RRULE string** (e.g., `TZID=America/New_York`)
3. **UTC** (fallback when neither is specified)

```sql
-- Get all occurrences
rrule.all(rrule, dtstart) → SETOF TIMESTAMP
rrule.all(rrule, dtstart_tz, timezone DEFAULT NULL) → SETOF TIMESTAMPTZ

-- Get occurrences in date range
rrule.between(rrule, dtstart, start_date, end_date) → SETOF TIMESTAMP
rrule.between(rrule, dtstart_tz, start_tz, end_tz, timezone DEFAULT NULL) → SETOF TIMESTAMPTZ

-- Get first occurrence after date
rrule.after(rrule, dtstart, after_date) → TIMESTAMP
rrule.after(rrule, dtstart_tz, after_tz, count, timezone DEFAULT NULL) → SETOF TIMESTAMPTZ

-- Get last occurrence before date
rrule.before(rrule, dtstart, before_date) → TIMESTAMP
rrule.before(rrule, dtstart_tz, before_tz, count, timezone DEFAULT NULL) → SETOF TIMESTAMPTZ

-- Count total occurrences
rrule.count(rrule, dtstart) → INTEGER
rrule.count(rrule, dtstart_tz, timezone DEFAULT NULL) → INTEGER

-- Next occurrence from NOW
rrule.next(rrule, dtstart) → TIMESTAMP
rrule.next(rrule, dtstart_tz, timezone DEFAULT NULL) → TIMESTAMPTZ

-- Most recent occurrence before NOW
rrule.most_recent(rrule, dtstart) → TIMESTAMP
rrule.most_recent(rrule, dtstart_tz, timezone DEFAULT NULL) → TIMESTAMPTZ

-- Check if event overlaps date range
rrule.overlaps(dtstart_tz, dtend_tz, rrule, mindate_tz, maxdate_tz, timezone DEFAULT NULL) → BOOLEAN
```

**Examples:**

```sql
-- Using TZID in RRULE string (TIMESTAMP API)
SELECT * FROM rrule.all(
    'FREQ=DAILY;COUNT=5;TZID=America/New_York',
    '2025-03-08 10:00:00'::TIMESTAMP
);

-- Using explicit timezone parameter (TIMESTAMPTZ API)
SELECT * FROM rrule.all(
    'FREQ=DAILY;COUNT=5',
    '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
    'America/New_York'
);

-- Timezone parameter overrides TZID in RRULE
SELECT * FROM rrule.all(
    'FREQ=DAILY;COUNT=5;TZID=Europe/London',  -- TZID ignored
    '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
    'America/New_York'  -- This timezone is used
);

-- Defaults to UTC when no timezone specified
SELECT * FROM rrule.all(
    'FREQ=DAILY;COUNT=5',  -- No TZID
    '2025-03-08 10:00:00+00'::TIMESTAMPTZ,
    NULL  -- Defaults to UTC
);
```

**DST Handling:** All functions preserve wall-clock time across DST transitions. A meeting at 10:00 AM stays at 10:00 AM even when DST changes the UTC offset.

**See [API Reference](API_REFERENCE.md) for complete function documentation and advanced examples.**

---

## Contributing

Contributions welcome! Please:

1. Run all tests (168/168 must pass - includes integration tests)
2. Add test coverage for new features
3. Update documentation
4. Follow RFC 5545/7529 specifications
5. Submit pull request

**See [Development Guide](DEVELOPMENT.md) for contribution guidelines.**

---

## Performance

**Single schedule:** 50-75x faster than Node.js rrule.js
**Multi-schedule queries:** Eliminates application-database round trips entirely

**Scalability advantages:**
- Set-based batch operations: Query 100+ schedules in parallel without loops
- Streaming results: SETOF returns incrementally, not all at once (constant memory)
- Query planner optimization: PostgreSQL optimizes JOINs and filters with occurrence expansion
- Early-exit optimizations: Stops computation when COUNT/UNTIL limits reached

**See [Development Guide](DEVELOPMENT.md) for architecture and benchmarking details.**

---

## Requirements

- PostgreSQL 12 or higher
- No C extensions required
- No external dependencies
- Works on all PostgreSQL-compatible platforms

**See [Development Guide](DEVELOPMENT.md) for development setup instructions.**

---

## References

- [RFC 5545 (iCalendar)](https://tools.ietf.org/html/rfc5545) - RRULE specification
- [RFC 7529 (Non-Gregorian Recurrence Rules)](https://datatracker.ietf.org/doc/html/rfc7529) - SKIP and RSCALE parameters

---

## Support

- **Issues**: https://github.com/sirrodgepodge/rrule_plpgsql/issues
- **Security**: See [SECURITY.md](SECURITY.md)
- **Documentation**: See [API Reference](API_REFERENCE.md)
- **License**: MIT (see [LICENSE](LICENSE))
