# RRULE Validation

Comprehensive RFC 5545 constraint validation for RRULE strings.

---

## Overview

All RRULE strings are validated against RFC 5545 Section 3.3.10 requirements **before processing**. Invalid RRULEs are rejected with descriptive error messages that explain the problem and suggest fixes.

---

## 16 Validation Rules Enforced

### Core Requirements

1. **FREQ is REQUIRED**
   - Every RRULE must specify a frequency
   - Valid values: SECONDLY, MINUTELY, HOURLY, DAILY, WEEKLY, MONTHLY, YEARLY

2. **COUNT and UNTIL are mutually exclusive**
   - Cannot use both in same RRULE
   - Specify either COUNT (number of occurrences) OR UNTIL (end date), not both

### Frequency-Specific Constraints

3. **BYWEEKNO only with YEARLY**
   - Week numbers only valid with FREQ=YEARLY
   - RFC 5545: "BYWEEKNO MUST NOT be used when FREQ is not YEARLY"

4. **BYYEARDAY not with DAILY/WEEKLY/MONTHLY**
   - Year days only for YEARLY frequency
   - Use BYMONTHDAY or BYDAY for other frequencies

5. **BYMONTHDAY not with WEEKLY**
   - Month days cannot be used with FREQ=WEEKLY
   - RFC 5545: Day-of-month filters not applicable to weekly patterns

### BYDAY Ordinal Constraints

6. **BYDAY ordinals only with MONTHLY/YEARLY**
   - Positional weekdays (2MO, -1FR) restricted to monthly/yearly
   - Example: `2MO` means "2nd Monday"
   - Cannot use with DAILY or WEEKLY

7. **BYDAY ordinals not with YEARLY+BYWEEKNO**
   - Cannot use ordinals when BYWEEKNO is specified in YEARLY
   - RFC 5545: This combination is semantically ambiguous
   - Example invalid: `FREQ=YEARLY;BYWEEKNO=10;BYDAY=2MO`

### Position Selector Constraints

8. **BYSETPOS requires other BYxxx**
   - Position selector needs a set to select from
   - Must be used with BYDAY, BYMONTHDAY, or other filters
   - Example: `BYSETPOS=1` with `BYDAY=MO,WE,FR`

### Parameter Range Validations

9. **BYSECOND range 0-60**
   - Valid values 0-60 (60 for leap seconds)
   - RFC 5545: "Valid values are 0 to 60"

10. **BYMINUTE range 0-59**
    - Valid values 0-59
    - RFC 5545: "Valid values are 0 to 59"

11. **BYHOUR range 0-23**
    - Valid values 0-23 (0 = midnight, 23 = 11 PM)
    - RFC 5545: "Valid values are 0 to 23"

12. **BYMONTH range 1-12**
    - Valid values 1-12 (January-December)
    - RFC 5545: "Valid values are 1 to 12"

### Index Validations (Zero Not Allowed)

13. **BYMONTHDAY validation**
    - Cannot be 0
    - Range: -31 to 31 (excluding 0)
    - Negative values count from end of month
    - Example: -1 = last day of month

14. **BYYEARDAY validation**
    - Cannot be 0
    - Range: -366 to 366 (excluding 0)
    - Negative values count from end of year
    - Example: -1 = December 31

15. **BYWEEKNO validation**
    - Cannot be 0
    - Range: -53 to 53 (excluding 0)
    - Negative values count from end of year
    - Example: -1 = last week of year

16. **BYSETPOS validation**
    - Cannot be 0
    - Range: -366 to 366 (excluding 0)
    - Negative values count from end of set
    - Example: -1 = last occurrence in set

---

## Descriptive Error Messages

All validation errors provide:
- Clear description of what's wrong
- RFC 5545 section citation for reference
- Current values that caused the error
- Suggested fixes or alternatives

---

## Error Examples

### Missing FREQ (required)

```sql
SELECT array_agg(occurrence) FROM rrule.all('COUNT=10;BYMONTHDAY=15', '2025-01-01'::TIMESTAMP) AS occurrence;
```

**Error:**
```
ERROR: Invalid RRULE: FREQ parameter is required.
       Specify one of: SECONDLY, MINUTELY, HOURLY, DAILY, WEEKLY, MONTHLY, or YEARLY.
       RFC 5545 Section 3.3.10: "FREQ rule part is REQUIRED"
```

---

### COUNT and UNTIL together (mutually exclusive)

```sql
SELECT array_agg(occurrence) FROM rrule.all('FREQ=DAILY;COUNT=10;UNTIL=20251231T235959', '2025-01-01'::TIMESTAMP) AS occurrence;
```

**Error:**
```
ERROR: Invalid RRULE: COUNT and UNTIL are mutually exclusive.
       Specify either COUNT (number of occurrences) OR UNTIL (end date), not both.
       Current RRULE has COUNT=10 and UNTIL=20251231T235959.
       RFC 5545 Section 3.3.10: "they MUST NOT occur in the same recur"
```

---

### BYWEEKNO with wrong frequency

```sql
SELECT array_agg(occurrence) FROM rrule.all('FREQ=MONTHLY;BYWEEKNO=10;COUNT=3', '2025-01-01'::TIMESTAMP) AS occurrence;
```

**Error:**
```
ERROR: Invalid RRULE: BYWEEKNO can only be used with FREQ=YEARLY.
       Current FREQ=MONTHLY. BYWEEKNO specifies ISO 8601 week numbers within a year.
       Use FREQ=YEARLY or remove BYWEEKNO.
       RFC 5545 Section 3.3.10: "BYWEEKNO MUST NOT be used when FREQ is not YEARLY"
```

---

### Parameter out of range

```sql
SELECT array_agg(occurrence) FROM rrule.all('FREQ=DAILY;BYHOUR=24;COUNT=1', '2025-01-01'::TIMESTAMP) AS occurrence;
```

**Error:**
```
ERROR: Invalid RRULE: BYHOUR=24 is out of valid range.
       Valid values are 0-23 (0 = midnight, 23 = 11 PM).
       RFC 5545 Section 3.3.10: "Valid values are 0 to 23"
```

---

## Validation Test Coverage

The validation implementation includes a comprehensive test suite with 61 test cases covering:

### Group 1: Critical MUST/MUST NOT Constraints (24 tests)
- FREQ required validation
- COUNT+UNTIL mutual exclusion
- BYWEEKNO only with YEARLY
- BYYEARDAY not with DAILY/WEEKLY/MONTHLY
- BYMONTHDAY not with WEEKLY
- BYDAY ordinals only with MONTHLY/YEARLY
- BYDAY ordinals not with YEARLY+BYWEEKNO
- BYSETPOS requires other BYxxx parameters

### Group 2: Parameter Range Validations (16 tests)
- BYSECOND, BYMINUTE, BYHOUR valid ranges
- BYMONTH valid range (1-12)
- All parameter ranges thoroughly tested

### Group 3: Zero Values and Extended Ranges (16 tests)
- BYMONTHDAY, BYYEARDAY, BYWEEKNO, BYSETPOS zero rejection
- Negative index support and validation
- Extended range validation (±366, ±53, etc.)

### Group 4: Complex Validation Scenarios (5 tests)
- Multiple constraint violations
- Complex valid RRULEs
- Edge cases (BYMONTHDAY=31, BYYEARDAY=366)

---

## Running Validation Tests

```bash
# Run validation test suite
psql -d test_database -f tests/test_validation.sql
```

**Expected output:** All 61 tests pass with 100% success rate.

---

## Valid RRULE Examples

### Simple Patterns (Always Valid)

```sql
-- Every day
FREQ=DAILY;COUNT=10

-- Every Monday
FREQ=WEEKLY;BYDAY=MO

-- Last day of every month
FREQ=MONTHLY;BYMONTHDAY=-1

-- February every year
FREQ=YEARLY;BYMONTH=2
```

### Complex Valid Patterns

```sql
-- 2nd Tuesday of each month
FREQ=MONTHLY;BYDAY=2TU;COUNT=12

-- Every weekday at 9 AM and 5 PM
FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=9,17

-- First and last Monday of each month
FREQ=MONTHLY;BYDAY=MO;BYSETPOS=1,-1

-- Week 10 in March every year
FREQ=YEARLY;BYWEEKNO=10;BYMONTH=3
```

---

## Common Validation Mistakes

### ❌ Forgetting FREQ

```sql
-- INVALID
COUNT=10;BYMONTHDAY=15
```

✅ **Fix:** Add FREQ parameter
```sql
-- VALID
FREQ=MONTHLY;COUNT=10;BYMONTHDAY=15
```

---

### ❌ Using COUNT and UNTIL together

```sql
-- INVALID
FREQ=DAILY;COUNT=10;UNTIL=20251231T235959
```

✅ **Fix:** Choose one or the other
```sql
-- VALID (with COUNT)
FREQ=DAILY;COUNT=10

-- VALID (with UNTIL)
FREQ=DAILY;UNTIL=20251231T235959
```

---

### ❌ BYWEEKNO with wrong frequency

```sql
-- INVALID
FREQ=MONTHLY;BYWEEKNO=10
```

✅ **Fix:** Use YEARLY frequency
```sql
-- VALID
FREQ=YEARLY;BYWEEKNO=10
```

---

### ❌ BYMONTHDAY with WEEKLY

```sql
-- INVALID
FREQ=WEEKLY;BYMONTHDAY=15
```

✅ **Fix:** Use MONTHLY or DAILY
```sql
-- VALID (monthly)
FREQ=MONTHLY;BYMONTHDAY=15

-- VALID (daily with weekday filter)
FREQ=DAILY;BYDAY=MO,WE,FR
```

---

### ❌ Zero in index parameters

```sql
-- INVALID
FREQ=MONTHLY;BYMONTHDAY=0
FREQ=YEARLY;BYSETPOS=0
```

✅ **Fix:** Use positive or negative indices (not zero)
```sql
-- VALID
FREQ=MONTHLY;BYMONTHDAY=1      # First day
FREQ=MONTHLY;BYMONTHDAY=-1     # Last day
FREQ=YEARLY;BYSETPOS=1         # First occurrence
FREQ=YEARLY;BYSETPOS=-1        # Last occurrence
```

---

## See Also

- [SPEC_COMPLIANCE.md](SPEC_COMPLIANCE.md) - RFC 5545/7529 feature support
- [API_REFERENCE.md](API_REFERENCE.md) - Function reference
- [README.md](README.md) - Main documentation
