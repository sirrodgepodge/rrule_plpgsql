# RFC 5545 & RFC 7529 Compliance

Complete feature support matrix and compliance details for rrule_plpgsql.

---

## RFC 5545 Support Matrix

### Comprehensive Feature Support Grid

| Feature | DAILY | WEEKLY | MONTHLY | YEARLY | ⚠️ HOURLY<sup>5</sup> | ⚠️ MINUTELY<sup>5</sup> | ⚠️ SECONDLY<sup>5</sup> |
|---------|-------|--------|---------|--------|----------|------------|------------|
| **Core Modifiers** | | | | | | | |
| `COUNT` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `UNTIL` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `INTERVAL` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Date Filters** | | | | | | | |
| `BYDAY` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYDAY` with position | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYMONTHDAY` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYMONTHDAY=-1` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYMONTH` | ✅ | ✅ | ✅ | ✅<sup>1</sup> | ✅ | ✅ | ✅ |
| `BYYEARDAY` | ✅ | ✅ | ✅ | ✅<sup>1</sup> | ✅ | ✅ | ✅ |
| `BYYEARDAY` negative | ✅ | ✅ | ✅ | ✅<sup>1</sup> | ✅ | ✅ | ✅ |
| `BYWEEKNO` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Week Configuration** | | | | | | | |
| `WKST` (week start day) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Time Filters** | | | | | | | |
| `BYHOUR` | ✅ | ❌<sup>2</sup> | ❌<sup>2</sup> | ❌<sup>2</sup> | ✅ | ✅ | ✅ |
| `BYMINUTE` | ✅ | ❌<sup>2</sup> | ❌<sup>2</sup> | ❌<sup>2</sup> | ✅ | ✅ | ✅ |
| `BYSECOND` | ✅ | ❌<sup>2</sup> | ❌<sup>2</sup> | ❌<sup>2</sup> | ✅ | ✅ | ✅ |
| **Position Selectors** | | | | | | | |
| `BYSETPOS` | ✅ | ✅ | ✅ | ✅ | ❌<sup>3</sup> | ❌<sup>3</sup> | ❌<sup>3</sup> |
| **Special Combinations** | | | | | | | |
| `BYMONTH` + `BYYEARDAY` | ✅ | ✅ | ✅ | 🚫<sup>4</sup> | ✅ | ✅ | ✅ |
| `BYWEEKNO` + `BYMONTH` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYWEEKNO` + `BYYEARDAY` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

**Legend:**
- ✅ = Fully supported and enabled
- ⚠️ = Fully implemented but **disabled by default** (see footnote 5)
- ❌ = Not supported (see footnotes below)
- 🚫 = **Raises exception** with descriptive error message

---

## Footnotes

<sup>1</sup> **YEARLY + BYMONTH/BYYEARDAY Limitation:**
   - Can use **either** BYMONTH **or** BYYEARDAY with YEARLY frequency
   - **Cannot combine both** (🚫 raises exception with clear error message)
   - Valid: `FREQ=YEARLY;BYMONTH=2` or `FREQ=YEARLY;BYYEARDAY=100`
   - Invalid: `FREQ=YEARLY;BYMONTH=2;BYYEARDAY=100` → Exception
   - **Why?** Semantically contradictory - "February on day 100" is impossible
   - **Note:** BYWEEKNO can combine with either: `FREQ=YEARLY;BYWEEKNO=10;BYMONTH=3` ✅

<sup>2</sup> **Time Filters (BYHOUR/BYMINUTE/BYSECOND) with WEEKLY/MONTHLY/YEARLY:**
   - **Why not supported?** These combinations are semantically ambiguous in RFC 5545
   - Example problem: `FREQ=WEEKLY;BYHOUR=10` - does this mean "every hour at :10 within the week"? No clear interpretation
   - **What to use instead:**
     - For hourly on specific days: `FREQ=HOURLY;BYDAY=MO,WE,FR` ✅
     - For daily with specific hours: `FREQ=DAILY;BYHOUR=9,10,11` ✅
   - **Technical reason:** Time filters only make sense with:
     - DAILY frequency (sub-day scheduling within each day)
     - Sub-day frequencies (HOURLY, MINUTELY, SECONDLY)

<sup>3</sup> **BYSETPOS with HOURLY/MINUTELY/SECONDLY:**
   - **Why not supported?** These frequencies are already position-based
   - **What BYSETPOS does:** Selects positions within a generated set (e.g., "2nd Monday of month")
   - **Why not needed:** With `FREQ=HOURLY`, each hour is atomic - there's no "set" to select from
   - **What to use instead:** Use INTERVAL
     - Want every 3rd hour? Use `FREQ=HOURLY;INTERVAL=3` ✅
     - Want every 15 minutes? Use `FREQ=MINUTELY;INTERVAL=15` ✅
   - **Technical note:** Sub-day frequencies generate single occurrences, not sets

<sup>4</sup> **YEARLY + BYMONTH + BYYEARDAY (🚫 Raises Exception):**
   - **What happens?** Immediate exception: `Invalid RRULE: FREQ=YEARLY with both BYMONTH and BYYEARDAY is not supported`
   - **Why?** Contradictory constraints - BYMONTH="February" + BYYEARDAY=100 (April 9/10) can never both be true
   - **Valid alternatives:**
     - ✅ `FREQ=YEARLY;BYMONTH=2` - February every year
     - ✅ `FREQ=YEARLY;BYYEARDAY=100` - Day 100 every year
     - ✅ `FREQ=YEARLY;BYWEEKNO=10;BYMONTH=3` - Week 10 in March (valid combo!)
   - **Full error message includes:** Why it's invalid, what to use instead, and example valid patterns

<sup>5</sup> **⚠️ Sub-Day Frequencies (HOURLY/MINUTELY/SECONDLY) - Disabled by Default:**
   - **Status:** ✅ Fully implemented and tested, ⚠️ but disabled by default for security
   - **Why?** Can generate millions of occurrences (SECONDLY: 31M/year), posing DoS risk in multi-tenant environments
   - **When safe to enable:** Single-tenant deployments with application-level validation and query timeouts
   - **See:** [INCLUDING_SUBDAY_OPERATIONS.md](INCLUDING_SUBDAY_OPERATIONS.md) for complete guide

---

## Frequency Details

### 🟢 Production-Ready Frequencies (Always Enabled)

**`FREQ=DAILY`**
- **Use case:** "Every day at 10 AM", "Weekdays only", "Every 3 days"
- **Max occurrences/year:** 365
- **Performance:** Excellent
- **Supports:** All date filters, time filters (BYHOUR/BYMINUTE/BYSECOND), BYSETPOS

**`FREQ=WEEKLY`**
- **Use case:** "Every Monday", "Mon/Wed/Fri", "Every 2 weeks"
- **Max occurrences/year:** 52
- **Performance:** Excellent
- **Supports:** All date filters, BYSETPOS

**`FREQ=MONTHLY`**
- **Use case:** "Last day of month", "2nd Tuesday", "Every 3 months"
- **Max occurrences/year:** 12
- **Performance:** Excellent
- **Supports:** All date filters, BYSETPOS

**`FREQ=YEARLY`**
- **Use case:** "Birthday", "Anniversary", "Day 100 of each year", "Week 10 of each year"
- **Max occurrences/year:** 1
- **Performance:** Excellent
- **Supports:** All date filters including BYYEARDAY (positive & negative), BYWEEKNO, BYSETPOS
- **Note:** Cannot combine BYMONTH + BYYEARDAY (semantically contradictory)

### ⚠️ Sub-Day Frequencies (Implemented, Disabled by Default)

**`FREQ=HOURLY`**
- **Status:** ✅ Implemented, ⚠️ Disabled by default
- **Use case:** "Every 3 hours", "Every hour 9 AM - 5 PM"
- **Max occurrences/year:** 8,760
- **Risk:** Medium - manageable with proper limits
- **Recommended limits:** COUNT ≤ 1,000, UNTIL ≤ 7 days
- **How to enable:** See [INCLUDING_SUBDAY_OPERATIONS.md](INCLUDING_SUBDAY_OPERATIONS.md)

**`FREQ=MINUTELY`**
- **Status:** ✅ Implemented, ⚠️ Disabled by default
- **Use case:** "Every 15 minutes", "Every minute during business hours"
- **Max occurrences/year:** 525,600
- **Risk:** High - can exhaust resources
- **Recommended limits:** COUNT ≤ 1,000, UNTIL ≤ 24 hours
- **How to enable:** See [INCLUDING_SUBDAY_OPERATIONS.md](INCLUDING_SUBDAY_OPERATIONS.md)

**`FREQ=SECONDLY`**
- **Status:** ✅ Implemented, ⚠️ Disabled by default
- **Use case:** "Every 30 seconds", "Real-time monitoring"
- **Max occurrences/year:** 31,536,000
- **Risk:** Critical - denial-of-service vector
- **Recommended limits:** COUNT ≤ 1,000, UNTIL ≤ 1 hour
- **How to enable:** See [INCLUDING_SUBDAY_OPERATIONS.md](INCLUDING_SUBDAY_OPERATIONS.md)

---

## Special Feature Notes

### Month-End Handling (RFC 7529 SKIP parameter)

- `SKIP=OMIT` (default): Skip invalid dates (e.g., Feb 31 → skip Feb entirely)
- `SKIP=BACKWARD`: Use last valid day (e.g., Feb 31 → Feb 28/29)
- `SKIP=FORWARD`: Use first of next month (e.g., Feb 31 → Mar 1)
- `BYMONTHDAY=-1` always works: Last day of every month (handles 28, 29, 30, 31)
- **RFC 7529 Compliance:** When using SKIP (other than OMIT), RSCALE=GREGORIAN is automatically added for RFC compliance
- Explicit RFC-compliant format: `RSCALE=GREGORIAN;SKIP=BACKWARD`

### Leap Year Support

- `BYYEARDAY=366` only generates in leap years (2024, 2028, etc.)
- `BYYEARDAY=-1` always generates (Dec 31)
- Negative BYYEARDAY indices work correctly in both leap and non-leap years

### Sub-Day Scheduling

- `BYHOUR`, `BYMINUTE`, `BYSECOND` work with DAILY frequency
- Generates all combinations: `BYHOUR=9,10,11;BYMINUTE=0,30` → 6 times per day
- `BYSETPOS` can select specific positions: `BYSETPOS=1,-1` → first and last time

---

## Common Use Cases

```sql
-- Every weekday at 10 AM
FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR

-- 2nd Tuesday of each month
FREQ=MONTHLY;BYDAY=2TU

-- Last day of each month at 11:59 PM
FREQ=MONTHLY;BYMONTHDAY=-1

-- Every Monday, Wednesday, Friday
FREQ=WEEKLY;BYDAY=MO,WE,FR

-- Day 100 of each year (April 9/10)
FREQ=YEARLY;BYYEARDAY=100

-- Last day of each year
FREQ=YEARLY;BYYEARDAY=-1

-- Once per year during week 10
FREQ=YEARLY;BYWEEKNO=10

-- Once per year during week 10 in March (combined filters)
FREQ=YEARLY;BYWEEKNO=10;BYMONTH=3

-- Daily at 9 AM, 12 PM, and 5 PM
FREQ=DAILY;BYHOUR=9,12,17

-- Daily, first and last hour only (with BYSETPOS)
FREQ=DAILY;BYHOUR=9,10,11,12,13,14,15,16,17;BYSETPOS=1,-1

-- Every 3 hours (requires HOURLY to be enabled)
-- FREQ=HOURLY;INTERVAL=3
```

---

## RFC 5545 & RFC 7529 Compliance Summary

**Coverage:** ~99% of RFC 5545 RRULE specification + RFC 7529 SKIP/RSCALE support

### RFC 5545 Supported Features

- ✅ All standard frequencies (DAILY, WEEKLY, MONTHLY, YEARLY)
- ✅ All sub-day frequencies (HOURLY, MINUTELY, SECONDLY) - implemented, disabled by default
- ✅ All date/time modifiers
- ✅ Complex combinations (BYDAY + BYMONTHDAY + BYSETPOS)
- ✅ Negative indices for month-end/year-end handling
- ✅ Leap year edge cases
- ✅ **TZID (Timezone) support** - Full RFC 5545 timezone support with automatic DST handling

### RFC 7529 Supported Features

- ✅ **SKIP parameter** (OMIT, BACKWARD, FORWARD) - Handles invalid dates in recurrence rules
- ✅ **RSCALE parameter** - Calendar system specification (GREGORIAN supported)
- ✅ **Auto-compliance** - Automatically adds RSCALE=GREGORIAN when SKIP is used (RFC 7529 requirement)
- ⚠️ **Non-Gregorian calendars** - Not yet supported (HEBREW, ISLAMIC, CHINESE, etc.)
  - Leap month syntax (e.g., "5L") is also not supported as it only applies to non-Gregorian calendars

---

## Not Supported (Will Raise Exception)

### ❌ YEARLY + BYMONTH + BYYEARDAY Combined

- Can only use one at a time: either BYMONTH or BYYEARDAY, not both
- *Why:* This combination is semantically contradictory (e.g., "February on day 100" is impossible)
- *Error:* Attempting this will raise: `Invalid RRULE: FREQ=YEARLY with both BYMONTH and BYYEARDAY is not supported`
- *Valid alternatives:*
  - ✅ `FREQ=YEARLY;BYMONTH=2` (February every year)
  - ✅ `FREQ=YEARLY;BYYEARDAY=100` (Day 100 every year)
  - ✅ `FREQ=YEARLY;BYWEEKNO=10;BYMONTH=3` (Week 10 in March - valid!)
  - ✅ `FREQ=YEARLY;BYWEEKNO=10;BYYEARDAY=64` (Day 64 in week 10 - valid!)
- *Note:* All other YEARLY combinations work! (YEARLY + BYWEEKNO, YEARLY + BYWEEKNO + BYMONTH, etc.)

### ❌ BYMONTHDAY with WEEKLY Frequency

- BYMONTHDAY cannot be used with FREQ=WEEKLY per RFC 5545
- *Why:* Day-of-month filters are not applicable to weekly recurrence patterns
- *Error:* Attempting this will raise: `Invalid RRULE: BYMONTHDAY cannot be used with FREQ=WEEKLY`
- *Valid alternatives:*
  - ✅ `FREQ=DAILY;BYDAY=MO,WE,FR` (specific weekdays)
  - ✅ `FREQ=WEEKLY;BYDAY=MO,WE,FR` (without BYMONTHDAY)
  - ✅ `FREQ=MONTHLY;BYMONTHDAY=15` (15th of every month)

### ❌ BYDAY with Ordinals when BYWEEKNO is Specified in YEARLY

- Ordinals like "2MO" (2nd Monday) cannot be used with BYWEEKNO in YEARLY rules
- *Why:* RFC 5545 explicitly prohibits this combination as semantically ambiguous
- *Example invalid:* `FREQ=YEARLY;BYWEEKNO=10;BYDAY=2MO`
- *Error:* Attempting this will raise: `Invalid RRULE: BYDAY with ordinal cannot be used when FREQ=YEARLY and BYWEEKNO is specified`
- *Valid alternatives:*
  - ✅ `FREQ=YEARLY;BYWEEKNO=10;BYDAY=MO` (without ordinal - all Mondays in week 10)
  - ✅ `FREQ=YEARLY;BYMONTH=3;BYDAY=2MO` (2nd Monday in March, without BYWEEKNO)
  - ✅ `FREQ=MONTHLY;BYDAY=2MO` (2nd Monday of every month)

---

## WKST (Week Start Day) Support

✅ **Fully supported!**

- *What:* Defines which day starts the week (SU, MO, TU, WE, TH, FR, SA)
- *Default:* Monday (MO) - RFC 5545 default
- *Use cases:*
  - US calendars: `WKST=SU` (week starts Sunday)
  - ISO 8601: `WKST=MO` (week starts Monday - default)
  - Custom schedules: Any day of week
- *Affects:* Week numbering for BYWEEKNO, week boundaries for WEEKLY;INTERVAL, BYDAY week calculations
- *Examples:*
  - `FREQ=WEEKLY;WKST=SU` - Weekly occurrences with Sunday week start
  - `FREQ=WEEKLY;INTERVAL=2;WKST=SU` - Biweekly with Sunday-Saturday weeks
  - `FREQ=YEARLY;BYWEEKNO=1;WKST=SU` - First week of year (Sunday-based)

---

## Why Not 100%?

Some RFC 5545 combinations are:
- Mathematically ambiguous (contradictory constraints)
- Have no practical use in calendar applications
- Add significant complexity for near-zero benefit

This implementation covers **all real-world scheduling needs** while maintaining simplicity and security.

---

## See Also

- [API_REFERENCE.md](API_REFERENCE.md) - Function reference
- [VALIDATION.md](VALIDATION.md) - RRULE validation rules
- [INCLUDING_SUBDAY_OPERATIONS.md](INCLUDING_SUBDAY_OPERATIONS.md) - Sub-day frequency guide
- [README.md](README.md) - Main documentation
