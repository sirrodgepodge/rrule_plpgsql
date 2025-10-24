# Development Guide

Testing, architecture, and contribution guidelines for rrule_plpgsql.

---

## Testing

### Running the Test Suite

Run the comprehensive test suite with 151 tests across 6 test suites:

```bash
# Core RRULE functionality tests (18 tests)
psql -d test_database -f tests/test_rrule_functions.sql

# TZID/Timezone support tests (20 tests)
psql -d test_database -f tests/test_tzid_support.sql

# WKST/Week Start support tests (22 tests)
psql -d test_database -f tests/test_wkst_support.sql

# SKIP/Month-end handling tests (15 tests)
psql -d test_database -f tests/test_skip_support.sql

# RFC 5545 & RFC 7529 compliance tests (15 tests)
psql -d test_database -f tests/test_rfc_compliance.sql

# RFC 5545 validation tests (61 tests)
psql -d test_database -f tests/test_validation.sql
```

**Total Test Coverage:** 151 tests across 6 comprehensive test suites

---

## Test Coverage Details

### Core Tests (test_rrule_functions.sql)
- Basic frequency patterns (DAILY, WEEKLY, MONTHLY, YEARLY)
- INTERVAL support (every N days/weeks/months)
- COUNT and UNTIL limits
- BYDAY rules (weekdays, positioned weekdays)
- BYMONTHDAY rules (including negative indices)
- BYMONTH rules
- Complex combinations (2nd Monday, last Friday, etc.)
- Edge cases (leap years, month boundaries, month-end)

### TZID/Timezone Tests (test_tzid_support.sql)
- Basic TZID functionality (America/New_York, Europe/London, Asia/Tokyo)
- DST transitions - Spring forward (lose an hour)
- DST transitions - Fall back (gain an hour)
- Multiple timezones (America, Europe, Asia, Australia)
- Half-hour offset timezones (Asia/Kolkata)
- Edge cases (invalid TZID, missing TZID)
- TZID with all frequency types (DAILY, WEEKLY, MONTHLY, YEARLY)
- TZID with complex RRULE patterns (BYDAY, BYMONTH, INTERVAL)

### WKST/Week Start Tests (test_wkst_support.sql)
- Basic WEEKLY frequency with all 7 WKST values (SU-SA)
- WEEKLY with BYDAY and different WKST values
- MONTHLY frequency with WKST
- YEARLY+BYWEEKNO+BYDAY with WKST (week expansion algorithm)
- Year boundary edge cases
- WKST default behavior (defaults to MO)
- Complex patterns across DST boundaries

### SKIP/Month-End Tests (test_skip_support.sql)
- SKIP=OMIT (default): Skip invalid dates entirely
- SKIP=BACKWARD: Use last valid day of month
- SKIP=FORWARD: Use first of next month
- Multiple BYMONTHDAY values with deduplication
- SKIP with BYDAY intersection
- SKIP with negative BYMONTHDAY (always valid)
- SKIP with YEARLY frequency
- Time preservation with SKIP

### RFC Compliance Tests (test_rfc_compliance.sql)
- RFC 7529 SKIP without RSCALE (auto-addition verification)
- Explicit RSCALE=GREGORIAN with SKIP parameters
- RSCALE validation (unsupported calendars rejected)
- RSCALE case-insensitivity (gregorian → GREGORIAN)
- Backward compatibility (legacy RRULEs without SKIP/RSCALE)
- RSCALE parsing edge cases (position independence)
- RSCALE + SKIP + other parameter integration
- RFC 7529 compliance verification (NOTICE messages)

### Validation Tests (test_validation.sql)
- **Group 1: Critical MUST/MUST NOT constraints (24 tests)**
  - FREQ required validation
  - COUNT+UNTIL mutual exclusion
  - BYWEEKNO only with YEARLY
  - BYYEARDAY not with DAILY/WEEKLY/MONTHLY
  - BYMONTHDAY not with WEEKLY
  - BYDAY ordinals only with MONTHLY/YEARLY
  - BYDAY ordinals not with YEARLY+BYWEEKNO
  - BYSETPOS requires other BYxxx parameters
- **Group 2: Parameter range validations (16 tests)**
  - BYSECOND, BYMINUTE, BYHOUR valid ranges
  - BYMONTH valid range (1-12)
- **Group 3: Zero values and extended ranges (16 tests)**
  - BYMONTHDAY, BYYEARDAY, BYWEEKNO, BYSETPOS zero rejection
  - Negative index support and validation
  - Extended range validation (±366, ±53, etc.)
- **Group 4: Complex validation scenarios (5 tests)**
  - Multiple constraint violations
  - Complex valid RRULEs
  - Edge cases (BYMONTHDAY=31, BYYEARDAY=366)

**Expected output:** All tests pass with ✓ markers.

---

## Architecture

### Components

1. **rrule.sql**
   - Core RRULE parsing and generation logic
   - Comprehensive RFC 5545 & RFC 7529 implementation with full validation
   - Public API layer (rrule.js/python-dateutil compatible)
   - Standard methods: `all()`, `after()`, `before()`, `between()`, `count()`
   - Convenience methods: `next()`, `most_recent()`
   - Advanced: `overlaps()`
   - TZID validation and timezone handling
   - Enforces 16 RFC 5545 constraint validations
   - All functions created in `rrule` schema

2. **install.sql**
   - Master installation script
   - Creates `rrule` schema for namespace isolation
   - Loads core functions and API
   - Safe reinstall with dependency checking (see [MANUAL_MIGRATION.md](MANUAL_MIGRATION.md) if needed)

3. **install_with_subday.sql**
   - Optional installation with sub-day frequencies
   - Includes HOURLY, MINUTELY, SECONDLY support
   - Displays security warnings during installation
   - See [INCLUDING_SUBDAY_OPERATIONS.md](INCLUDING_SUBDAY_OPERATIONS.md)

4. **test_*.sql** (6 test suites, 151 tests)
   - Comprehensive test coverage
   - Core RRULE functionality tests
   - RFC 5545 & RFC 7529 compliance tests
   - TZID/timezone support tests with DST handling
   - SKIP parameter tests
   - WKST support tests
   - Validation tests

---

## Design Decisions

### Schema-Based Namespacing

**All functions live in `rrule` PostgreSQL schema**

**Benefits:**
- Prevents naming conflicts with user functions
- Safe reinstall with dependency checking
- Professional PostgreSQL convention (like `pg_catalog`, `information_schema`)
- Standard names inside schema match rrule.js/python-dateutil

**Usage:**
```sql
-- Schema-qualified (recommended)
SELECT * FROM rrule.all('FREQ=DAILY;COUNT=5', '2025-01-01'::TIMESTAMP);

-- With search_path
SET search_path = rrule, public;
SELECT * FROM "all"('FREQ=DAILY;COUNT=5', '2025-01-01'::TIMESTAMP);
```

---

### Timezone Handling

**Two APIs for different use cases (both DST-aware):**

1. **TIMESTAMP API**
   - Uses `TIMESTAMP` type (naive timestamp representation)
   - Timezone specified via `TZID=` in RRULE string
   - Automatic DST handling when TZID is provided
   - Wall-clock time semantics preserved across DST boundaries
   - Compatible with rrule.js/python-dateutil

2. **TIMESTAMPTZ API**
   - Uses `TIMESTAMPTZ` type (timestamp with timezone)
   - Timezone specified via explicit function parameter
   - Automatic DST handling
   - Preserves wall-clock time across DST boundaries
   - Timezone parameter can override TZID in RRULE string

**DST Handling Example:**
```sql
-- Meeting stays at 10 AM wall-clock time even across DST spring-forward
SELECT * FROM rrule.all(
    'FREQ=DAILY;COUNT=3',
    '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
    'America/New_York'
);
-- Results: 10 AM EST, 10 AM EDT, 10 AM EDT (wall-clock time preserved)
```

---

### SETOF vs Arrays

**Core API returns `SETOF TIMESTAMP` for memory efficiency**

**Benefits:**
- Streaming results (memory-efficient for large sets)
- Works with PostgreSQL's row processing
- No array size limits
- Efficient for large result sets

**Converting to Arrays:**
```sql
-- Use array_agg() when you need materialized arrays
SELECT array_agg(occurrence) FROM rrule.all(
    'FREQ=DAILY;COUNT=5',
    '2025-01-01'::TIMESTAMP
) AS occurrence;
```

**When to use each:**
- **SETOF (default):** For iteration, streaming, large result sets
- **Arrays:** When you need to store results, pass to other functions, or work with array operations

---

### Performance

**Benchmarks:**
- **PL/pgSQL is ~50-75x faster than Node.js rrule.js**
- Handles batches of 100+ schedules efficiently
- Uses PostgreSQL's native date/time handling
- Early-exit optimizations for COUNT limits
- Array-based BYSETPOS filtering

**Optimization highlights:**
- FOREACH loops for sparse arrays (2-3x faster validation)
- O(1) weekday conversion helpers
- make_interval() usage (type-safe, efficient)
- Early-exit parameter propagation (30-80% reduction in date generation)
- Array-based BYSETPOS filtering (5x faster for multiple positions)
- date_part() instead of to_char() (20-30% faster weekday checks)

---

## Code Quality

### Validation First

All RRULEs are validated **before** processing:
- 16 RFC 5545 constraint validations
- Descriptive error messages with RFC citations
- Suggested fixes for common mistakes

### Type Safety

- Explicit parameter types
- Proper NULL handling
- IMMUTABLE functions where appropriate
- No SQL injection vectors

### Maintainability

- Clear function naming
- Comprehensive inline documentation
- Separated concerns (parsing, validation, generation)
- Well-organized test suites

---

## Contributing Code

### Before Submitting

1. **Run all tests** - Ensure 151/151 tests pass
2. **Add test coverage** - Include tests for new features
3. **Document changes** - Update relevant .md files
4. **Follow conventions** - Match existing code style

### Pull Request Checklist

- [ ] All tests pass (151/151)
- [ ] New features have test coverage
- [ ] Documentation updated (README.md, API_REFERENCE.md, etc.)
- [ ] No breaking changes (or clearly documented if necessary)
- [ ] RFC 5545/7529 compliance maintained
- [ ] Performance regressions addressed

### Adding New Features

1. **Study RFC 5545/7529** - Ensure feature is spec-compliant
2. **Write tests first** - TDD approach recommended
3. **Implement feature** - Follow existing patterns
4. **Validate against spec** - Cross-reference RFC sections
5. **Document thoroughly** - Update all relevant docs

---

## Development Setup

### Prerequisites

- PostgreSQL 12+ (tested on 12, 13, 14, 15, 16)
- psql command-line client
- Git (for version control)

### Local Development

```bash
# Clone repository
git clone https://github.com/sirrodgepodge/rrule_plpgsql.git
cd rrule_plpgsql

# Create test database
createdb rrule_test

# Install
psql -d rrule_test -f src/install.sql

# Run tests
psql -d rrule_test -f tests/test_rrule_functions.sql
psql -d rrule_test -f tests/test_validation.sql
# ... run all test files
```

### Making Changes

```bash
# 1. Make changes to src/rrule.sql

# 2. Reinstall
psql -d rrule_test -c "DROP SCHEMA IF EXISTS rrule CASCADE;"
psql -d rrule_test -f src/install.sql

# 3. Run tests
psql -d rrule_test -f tests/test_rrule_functions.sql

# 4. Iterate until tests pass
```

---

## Debugging Tips

### Enable Debug Output

```sql
-- See validation notices
\set VERBOSITY verbose

-- See function execution
SET client_min_messages TO DEBUG;
```

### Common Issues

**Tests failing?**
- Ensure fresh install (`DROP SCHEMA rrule CASCADE`)
- Check PostgreSQL version (12+ required)
- Verify timezone data is up to date

**Performance issues?**
- Check for missing early-exit optimization
- Profile with `EXPLAIN ANALYZE`
- Consider COUNT limits

**Timezone issues?**
- Verify timezone names: `SELECT * FROM pg_timezone_names;`
- Check DST handling with test_tzid_support.sql
- Ensure dtstart has correct timezone offset

---

## Release Process

1. **Version bump** - Update version in documentation
2. **Run all tests** - Ensure 151/151 pass
3. **Update CHANGELOG** - Document changes
4. **Tag release** - Git tag with version
5. **Publish** - Push to GitHub

---

## See Also

- [API_REFERENCE.md](API_REFERENCE.md) - Function reference
- [SPEC_COMPLIANCE.md](SPEC_COMPLIANCE.md) - RFC 5545/7529 feature support
- [VALIDATION.md](VALIDATION.md) - RRULE validation rules
- [README.md](README.md) - Main documentation
- [SECURITY.md](SECURITY.md) - Security practices
