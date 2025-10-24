/**
 * RRULE Sub-Day Frequencies Extension
 *
 * ⚠️  WARNING: SECURITY-SENSITIVE CODE ⚠️
 *
 * This file extends the rrule_plpgsql implementation with HOURLY, MINUTELY,
 * and SECONDLY frequency support. These frequencies are DISABLED by default
 * due to security and performance concerns.
 *
 * DENIAL OF SERVICE RISKS:
 * - HOURLY: 8,760 occurrences per year
 * - MINUTELY: 525,600 occurrences per year
 * - SECONDLY: 31,536,000 occurrences per year
 *
 * RESOURCE EXHAUSTION RISKS:
 * - CPU: Computing millions of date increments
 * - Memory: Building large TIMESTAMP[] arrays
 * - Connections: Blocking connection pool in multi-tenant systems
 *
 * WHEN TO USE:
 * ✅ Single-tenant deployments where you control all RRULEs
 * ✅ With strict application-level validation (see below)
 * ✅ With query timeouts configured (statement_timeout)
 * ✅ With monitoring and alerting on long-running queries
 * ✅ Never in multi-tenant environments without strict limits
 *
 * REQUIRED VALIDATION:
 * Before installing this extension, implement application-level validation:
 * - HOURLY: COUNT <= 1000, UNTIL <= 7 days from dtstart
 * - MINUTELY: COUNT <= 1000, UNTIL <= 24 hours from dtstart
 * - SECONDLY: COUNT <= 1000, UNTIL <= 1 hour from dtstart
 *
 * EXAMPLE VALIDATION (TypeScript):
 * ```typescript
 * function validateSubDayRRule(rrule: string): void {
 *   const count = parseInt(rrule.match(/COUNT=(\d+)/)?.[1] || '0');
 *
 *   if (rrule.includes('FREQ=HOURLY') && count > 1000) {
 *     throw new Error('HOURLY limited to COUNT=1000');
 *   }
 *   if (rrule.includes('FREQ=MINUTELY') && count > 1000) {
 *     throw new Error('MINUTELY limited to COUNT=1000');
 *   }
 *   if (rrule.includes('FREQ=SECONDLY') && count > 1000) {
 *     throw new Error('SECONDLY limited to COUNT=1000');
 *   }
 * }
 * ```
 *
 * DATABASE CONFIGURATION:
 * Set statement timeout to prevent runaway queries:
 * ```sql
 * ALTER DATABASE your_db SET statement_timeout = '30s';
 * -- OR per-session:
 * SET statement_timeout = '30s';
 * ```
 *
 * INSTALLATION:
 * Use install_with_subday.sql instead of install.sql
 *
 * @package rrule_plpgsql
 * @license MIT
 * @security CRITICAL - Review security implications before use
 */

SET search_path = rrule, public;

------------------------------------------------------------------------------------------------------
-- HOURLY frequency handler
-- ⚠️  WARNING: This frequency can generate thousands of occurrences quickly
-- ⚠️  Recommended limits: COUNT <= 1000, UNTIL <= 7 days from dtstart
-- ⚠️  Use case: "Every 3 hours" (FREQ=HOURLY;INTERVAL=3;COUNT=8)
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hourly_set( TIMESTAMP WITH TIME ZONE, rrule.rrule_parts ) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  after ALIAS FOR $1;
  rrule ALIAS FOR $2;
BEGIN

  -- Apply day-level filters first
  IF rrule.bymonth IS NOT NULL AND NOT date_part('month',after) = ANY ( rrule.bymonth ) THEN
    RETURN;
  END IF;

  IF rrule.bymonthday IS NOT NULL AND NOT date_part('day',after) = ANY ( rrule.bymonthday ) THEN
    RETURN;
  END IF;

  IF rrule.byday IS NOT NULL AND NOT rrule.number_to_weekday(date_part('dow', after)::INT) = ANY ( rrule.byday ) THEN
    RETURN;
  END IF;

  -- Apply hour filter
  IF rrule.byhour IS NOT NULL AND NOT date_part('hour',after) = ANY ( rrule.byhour ) THEN
    RETURN;
  END IF;

  -- Apply minute/second filters if specified
  IF rrule.byminute IS NOT NULL AND NOT date_part('minute',after) = ANY ( rrule.byminute ) THEN
    RETURN;
  END IF;

  IF rrule.bysecond IS NOT NULL AND NOT date_part('second',after)::INT = ANY ( rrule.bysecond ) THEN
    RETURN;
  END IF;

  RETURN NEXT after;

END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;


------------------------------------------------------------------------------------------------------
-- MINUTELY frequency handler
-- ⚠️  WARNING: This frequency can generate 525,600 occurrences per year
-- ⚠️  SECURITY RISK: Can exhaust database resources in multi-tenant environments
-- ⚠️  Recommended limits: COUNT <= 1000, UNTIL <= 24 hours from dtstart
-- ⚠️  Use case: "Every 15 minutes" (FREQ=MINUTELY;INTERVAL=15;COUNT=96)
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION minutely_set( TIMESTAMP WITH TIME ZONE, rrule.rrule_parts ) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  after ALIAS FOR $1;
  rrule ALIAS FOR $2;
BEGIN

  -- Apply all filters
  IF rrule.bymonth IS NOT NULL AND NOT date_part('month',after) = ANY ( rrule.bymonth ) THEN
    RETURN;
  END IF;

  IF rrule.bymonthday IS NOT NULL AND NOT date_part('day',after) = ANY ( rrule.bymonthday ) THEN
    RETURN;
  END IF;

  IF rrule.byday IS NOT NULL AND NOT rrule.number_to_weekday(date_part('dow', after)::INT) = ANY ( rrule.byday ) THEN
    RETURN;
  END IF;

  IF rrule.byhour IS NOT NULL AND NOT date_part('hour',after) = ANY ( rrule.byhour ) THEN
    RETURN;
  END IF;

  IF rrule.byminute IS NOT NULL AND NOT date_part('minute',after) = ANY ( rrule.byminute ) THEN
    RETURN;
  END IF;

  IF rrule.bysecond IS NOT NULL AND NOT date_part('second',after)::INT = ANY ( rrule.bysecond ) THEN
    RETURN;
  END IF;

  RETURN NEXT after;

END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;


------------------------------------------------------------------------------------------------------
-- SECONDLY frequency handler
-- ⚠️  CRITICAL SECURITY WARNING: This frequency can generate 31,536,000 occurrences per year
-- ⚠️  DENIAL OF SERVICE RISK: Can exhaust CPU, memory, and connection pools
-- ⚠️  DO NOT USE in production multi-tenant environments without strict limits
-- ⚠️  Recommended limits: COUNT <= 1000, UNTIL <= 1 hour from dtstart
-- ⚠️  Use case: "Every 30 seconds for 5 minutes" (FREQ=SECONDLY;INTERVAL=30;COUNT=10)
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION secondly_set( TIMESTAMP WITH TIME ZONE, rrule.rrule_parts ) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  after ALIAS FOR $1;
  rrule ALIAS FOR $2;
BEGIN

  -- Apply all filters
  IF rrule.bymonth IS NOT NULL AND NOT date_part('month',after) = ANY ( rrule.bymonth ) THEN
    RETURN;
  END IF;

  IF rrule.bymonthday IS NOT NULL AND NOT date_part('day',after) = ANY ( rrule.bymonthday ) THEN
    RETURN;
  END IF;

  IF rrule.byday IS NOT NULL AND NOT rrule.number_to_weekday(date_part('dow', after)::INT) = ANY ( rrule.byday ) THEN
    RETURN;
  END IF;

  IF rrule.byhour IS NOT NULL AND NOT date_part('hour',after) = ANY ( rrule.byhour ) THEN
    RETURN;
  END IF;

  IF rrule.byminute IS NOT NULL AND NOT date_part('minute',after) = ANY ( rrule.byminute ) THEN
    RETURN;
  END IF;

  IF rrule.bysecond IS NOT NULL AND NOT date_part('second',after)::INT = ANY ( rrule.bysecond ) THEN
    RETURN;
  END IF;

  RETURN NEXT after;

END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;


------------------------------------------------------------------------------------------------------
-- Override rrule_event_instances_range to enable sub-day frequencies
-- This replaces the version from rrule.sql that has sub-day frequencies commented out
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rrule_event_instances_range( TIMESTAMP WITH TIME ZONE, TEXT, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, INT )
                                         RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  basedate ALIAS FOR $1;
  repeatrule ALIAS FOR $2;
  mindate ALIAS FOR $3;
  maxdate ALIAS FOR $4;
  max_count ALIAS FOR $5;
  loopmax INT;
  loopcount INT;
  base_day TIMESTAMP WITH TIME ZONE;
  current_base TIMESTAMP WITH TIME ZONE;
  current TIMESTAMP WITH TIME ZONE;
  rrule rrule.rrule_parts;
BEGIN

  rrule := rrule.parse_rrule_parts(basedate, repeatrule);

  -- Use the SMALLEST of max_count and rrule.count to respect COUNT parameter
  -- max_count comes from wrapper (e.g., all() uses 1000 as safety limit)
  -- rrule.count comes from the RRULE string itself (e.g., COUNT=5)
  IF rrule.count IS NOT NULL AND max_count IS NOT NULL THEN
    loopmax := LEAST(rrule.count, max_count);
  ELSE
    loopmax := COALESCE(rrule.count, max_count, 732);  -- Default: 2 years daily
  END IF;
  loopcount := 0;

  IF rrule.freq IS NULL THEN
    RAISE EXCEPTION 'Invalid RRULE: FREQ parameter is required';
  END IF;

  current_base := basedate;
  base_day := date_trunc('day',basedate);

  WHILE loopcount < loopmax AND current_base < maxdate LOOP
    IF rrule.freq = 'DAILY' THEN
      FOR current IN SELECT d FROM rrule.daily_set(current_base, rrule, loopmax - loopcount) d WHERE d >= base_day LOOP
        EXIT WHEN rrule.until IS NOT NULL AND current > rrule.until;
        IF current >= mindate THEN
          RETURN NEXT current;
        END IF;
        loopcount := loopcount + 1;
        EXIT WHEN loopcount >= loopmax;
      END LOOP;
      current_base := current_base + make_interval(days => rrule.interval);

    ELSIF rrule.freq = 'WEEKLY' THEN
      FOR current IN SELECT w FROM rrule.weekly_set(current_base, rrule, loopmax - loopcount) w WHERE w >= base_day LOOP
        IF rrule.test_byyearday_rule(current,rrule.byyearday)
               AND rrule.test_bymonthday_rule(current,rrule.bymonthday)
               AND rrule.test_bymonth_rule(current,rrule.bymonth)
        THEN
          EXIT WHEN rrule.until IS NOT NULL AND current > rrule.until;
          IF current >= mindate THEN
            RETURN NEXT current;
          END IF;
          loopcount := loopcount + 1;
          EXIT WHEN loopcount >= loopmax;
        END IF;
      END LOOP;
      current_base := current_base + make_interval(weeks => rrule.interval);

    ELSIF rrule.freq = 'MONTHLY' THEN
      FOR current IN SELECT m FROM rrule.monthly_set(current_base, rrule, loopmax - loopcount) m WHERE m >= base_day LOOP
        EXIT WHEN rrule.until IS NOT NULL AND current > rrule.until;
        IF current >= mindate THEN
          RETURN NEXT current;
        END IF;
        loopcount := loopcount + 1;
        EXIT WHEN loopcount >= loopmax;
      END LOOP;
      current_base := current_base + make_interval(months => rrule.interval);

    ELSIF rrule.freq = 'YEARLY' THEN
      FOR current IN SELECT y FROM rrule.yearly_set(current_base, rrule, loopmax - loopcount) y WHERE y >= base_day LOOP
        EXIT WHEN rrule.until IS NOT NULL AND current > rrule.until;
        IF current >= mindate THEN
          RETURN NEXT current;
        END IF;
        loopcount := loopcount + 1;
        EXIT WHEN loopcount >= loopmax;
      END LOOP;
      current_base := current_base + make_interval(years => rrule.interval);

    -- ⚠️  SUB-DAY FREQUENCIES ENABLED ⚠️
    -- These are active in this file. See header comments for security implications.

    ELSIF rrule.freq = 'HOURLY' THEN
      FOR current IN SELECT h FROM rrule.hourly_set(current_base,rrule) h WHERE h >= base_day LOOP
        EXIT WHEN rrule.until IS NOT NULL AND current > rrule.until;
        IF current >= mindate THEN
          RETURN NEXT current;
        END IF;
        loopcount := loopcount + 1;
        EXIT WHEN loopcount >= loopmax;
      END LOOP;
      current_base := current_base + make_interval(hours => rrule.interval);

    ELSIF rrule.freq = 'MINUTELY' THEN
      FOR current IN SELECT m FROM rrule.minutely_set(current_base,rrule) m WHERE m >= base_day LOOP
        EXIT WHEN rrule.until IS NOT NULL AND current > rrule.until;
        IF current >= mindate THEN
          RETURN NEXT current;
        END IF;
        loopcount := loopcount + 1;
        EXIT WHEN loopcount >= loopmax;
      END LOOP;
      current_base := current_base + make_interval(mins => rrule.interval);

    ELSIF rrule.freq = 'SECONDLY' THEN
      FOR current IN SELECT s FROM rrule.secondly_set(current_base,rrule) s WHERE s >= base_day LOOP
        EXIT WHEN rrule.until IS NOT NULL AND current > rrule.until;
        IF current >= mindate THEN
          RETURN NEXT current;
        END IF;
        loopcount := loopcount + 1;
        EXIT WHEN loopcount >= loopmax;
      END LOOP;
      current_base := current_base + make_interval(secs => rrule.interval);

    ELSE
      RAISE NOTICE 'A frequency of "%" is not handled', rrule.freq;
      RETURN;
    END IF;
    EXIT WHEN rrule.until IS NOT NULL AND current > rrule.until;
  END LOOP;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
