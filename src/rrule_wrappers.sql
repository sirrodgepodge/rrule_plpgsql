/**
 * RRULE Wrapper Functions for rrule_plpgsql
 *
 * This file provides wrapper functions around the DAVical RRULE base functions
 * to create a simple, clean API for RRULE processing using pure PL/pgSQL.
 *
 * API Functions:
 * - get_occurrences(rrule, dtstart) -> TIMESTAMP[]
 * - get_occurrences(rrule, dtstart, until) -> TIMESTAMP[]
 * - get_next_occurrence(rrule, dtstart, after) -> TIMESTAMP
 * - adjust_rrule_for_month_end(rrule_string) -> VARCHAR
 *
 * Uses naive TIMESTAMP (not TIMESTAMPTZ) for timezone-naive wall-clock times.
 *
 * @package rrule_plpgsql
 * @license MIT
 */

-- Create 'rrule' type as a domain over VARCHAR
DO $$
BEGIN
    -- Check if rrule type exists
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'rrule') THEN
        -- Create domain if type doesn't exist
        EXECUTE 'CREATE DOMAIN rrule AS VARCHAR';
    END IF;
END $$;

-- Helper function: Adjust RRULE for month-end handling
-- Converts BYMONTHDAY=29,30,31 to BYMONTHDAY=-1 (last day of month)
CREATE OR REPLACE FUNCTION adjust_rrule_for_month_end(rrule_string VARCHAR)
RETURNS VARCHAR AS $$
BEGIN
    -- Adjust BYMONTHDAY=29,30,31 to BYMONTHDAY=-1 (last day of month)
    -- This ensures monthly recurrences work consistently across all months
    IF rrule_string ~ 'BYMONTHDAY=31' THEN
        RETURN regexp_replace(rrule_string, 'BYMONTHDAY=31', 'BYMONTHDAY=-1');
    ELSIF rrule_string ~ 'BYMONTHDAY=30' THEN
        RETURN regexp_replace(rrule_string, 'BYMONTHDAY=30', 'BYMONTHDAY=-1');
    ELSIF rrule_string ~ 'BYMONTHDAY=29' THEN
        RETURN regexp_replace(rrule_string, 'BYMONTHDAY=29', 'BYMONTHDAY=-1');
    ELSE
        RETURN rrule_string;
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Main function: get_occurrences()
--
-- API: get_occurrences(rrule, dtstart) -> TIMESTAMP[]
--
-- Parameters:
--   rrule_string: RRULE string (e.g., 'FREQ=DAILY;COUNT=10')
--   dtstart: Start date as naive TIMESTAMP (timezone-naive wall-clock time)
--
-- Returns: Array of naive TIMESTAMPs (TIMESTAMP[])
--
-- Implementation notes:
-- - Generates occurrences up to 10 years from dtstart
-- - Returns up to 1000 occurrences by default
-- - Uses naive TIMESTAMP throughout (no timezone conversion)
CREATE OR REPLACE FUNCTION get_occurrences(
    rrule_string VARCHAR,
    dtstart TIMESTAMP
)
RETURNS TIMESTAMP[] AS $$
DECLARE
    maxdate TIMESTAMP;
    max_count INT;
    occurrences TIMESTAMP[];
    current_occurrence TIMESTAMP;
BEGIN
    -- Set search range: 10 years from dtstart (matching pg_rrule default)
    maxdate := dtstart + INTERVAL '10 years';
    max_count := 1000;

    -- Initialize array
    occurrences := ARRAY[]::TIMESTAMP[];

    -- Generate occurrences using DAVical's rrule_event_instances_range
    -- Note: DAVical functions use TIMESTAMPTZ, so we cast naive TIMESTAMP
    FOR current_occurrence IN
        SELECT d::TIMESTAMP
        FROM rrule_event_instances_range(
            dtstart::TIMESTAMPTZ,  -- Cast naive TIMESTAMP to TIMESTAMPTZ (interprets as UTC)
            rrule_string,
            dtstart::TIMESTAMPTZ,  -- mindate
            maxdate::TIMESTAMPTZ,  -- maxdate
            max_count
        ) d
    LOOP
        occurrences := array_append(occurrences, current_occurrence);
    END LOOP;

    RETURN occurrences;

EXCEPTION
    WHEN OTHERS THEN
        -- If RRULE parsing fails, return empty array
        RETURN ARRAY[]::TIMESTAMP[];
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Overload: get_occurrences with explicit until parameter
-- Allows limiting the range of occurrences
CREATE OR REPLACE FUNCTION get_occurrences(
    rrule_string VARCHAR,
    dtstart TIMESTAMP,
    until_date TIMESTAMP
)
RETURNS TIMESTAMP[] AS $$
DECLARE
    occurrences TIMESTAMP[];
    current_occurrence TIMESTAMP;
    max_count INT;
BEGIN
    max_count := 1000;

    -- Initialize array
    occurrences := ARRAY[]::TIMESTAMP[];

    -- Generate occurrences using DAVical's rrule_event_instances_range
    FOR current_occurrence IN
        SELECT d::TIMESTAMP
        FROM rrule_event_instances_range(
            dtstart::TIMESTAMPTZ,
            rrule_string,
            dtstart::TIMESTAMPTZ,
            until_date::TIMESTAMPTZ,
            max_count
        ) d
    LOOP
        occurrences := array_append(occurrences, current_occurrence);
    END LOOP;

    RETURN occurrences;

EXCEPTION
    WHEN OTHERS THEN
        -- If RRULE parsing fails, return empty array
        RETURN ARRAY[]::TIMESTAMP[];
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Helper function: get_next_occurrence
-- Convenience function to get just the next occurrence after a given date
CREATE OR REPLACE FUNCTION get_next_occurrence(
    rrule_string VARCHAR,
    dtstart TIMESTAMP,
    after_time TIMESTAMP
)
RETURNS TIMESTAMP AS $$
DECLARE
    next_occurrence TIMESTAMP;
BEGIN
    -- Get next occurrence using get_occurrences and filter
    SELECT occurrence INTO next_occurrence
    FROM unnest(get_occurrences(rrule_string, dtstart)) AS occurrence
    WHERE occurrence > after_time
    ORDER BY occurrence ASC
    LIMIT 1;

    RETURN next_occurrence;

EXCEPTION
    WHEN OTHERS THEN
        -- If RRULE parsing fails, return NULL
        RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE;
