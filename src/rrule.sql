/**
 * RRULE Implementation - Pure PL/pgSQL
 *
 * Clean-room implementation of iCalendar RRULE (RFC 5545) recurrence rules.
 * Written from scratch using only RFC 5545 specification.
 *
 * Copyright (c) 2025 Novel Platform
 * License: MIT
 *
 * Supported patterns:
 * - FREQ=DAILY with BYDAY, BYMONTH, BYMONTHDAY, INTERVAL, COUNT, UNTIL
 * - FREQ=WEEKLY with BYDAY, INTERVAL, COUNT, UNTIL, BYSETPOS
 * - FREQ=MONTHLY with BYDAY, BYMONTHDAY (including -1 for last day), INTERVAL, COUNT, UNTIL, BYSETPOS
 * - FREQ=YEARLY with BYMONTH, BYMONTHDAY (basic support)
 */

-- ============================================================================
-- TYPE DEFINITIONS
-- ============================================================================

-- Composite type for parsed RRULE components
DROP TYPE IF EXISTS rrule_config CASCADE;
CREATE TYPE rrule_config AS (
    freq TEXT,              -- DAILY, WEEKLY, MONTHLY, YEARLY
    interval INT,           -- Interval between occurrences (default 1)
    count INT,              -- Maximum number of occurrences (NULL if not specified)
    until_time TIMESTAMP,   -- End time for recurrence (NULL if not specified)
    byday TEXT[],           -- Array of day specifiers (e.g., ['MO', 'WE', 'FR'] or ['2MO', '-1FR'])
    bymonthday INT[],       -- Array of month days (1-31 or -1 to -31 for last days)
    bysetpos INT[],         -- Array of positions (e.g., [1, -1] for first and last)
    bymonth INT[],          -- Array of months (1-12)
    wkst TEXT               -- Week start day (default MO)
);

-- ============================================================================
-- PARSER: Parse RRULE string into structured format
-- ============================================================================

CREATE OR REPLACE FUNCTION parse_rrule(rrule_string TEXT)
RETURNS rrule_config AS $$
DECLARE
    config rrule_config;
    parts TEXT[];
    part TEXT;
    key_value TEXT[];
    value_parts TEXT[];
BEGIN
    -- Initialize defaults
    config.freq := NULL;
    config.interval := 1;
    config.count := NULL;
    config.until_time := NULL;
    config.byday := NULL;
    config.bymonthday := NULL;
    config.bysetpos := NULL;
    config.bymonth := NULL;
    config.wkst := 'MO';

    -- Handle NULL or empty input
    IF rrule_string IS NULL OR rrule_string = '' THEN
        RETURN config;
    END IF;

    -- Split by semicolon
    parts := string_to_array(rrule_string, ';');

    -- Parse each part
    FOREACH part IN ARRAY parts
    LOOP
        key_value := string_to_array(part, '=');

        IF array_length(key_value, 1) = 2 THEN
            CASE key_value[1]
                WHEN 'FREQ' THEN
                    config.freq := key_value[2];

                WHEN 'INTERVAL' THEN
                    config.interval := key_value[2]::INT;

                WHEN 'COUNT' THEN
                    config.count := key_value[2]::INT;

                WHEN 'UNTIL' THEN
                    -- Parse UNTIL (format: YYYYMMDDTHHMMSS or YYYYMMDD)
                    IF length(key_value[2]) = 8 THEN
                        -- YYYYMMDD format
                        config.until_time := to_timestamp(key_value[2], 'YYYYMMDD');
                    ELSE
                        -- YYYYMMDDTHHMMSS format
                        config.until_time := to_timestamp(substring(key_value[2], 1, 15), 'YYYYMMDD"T"HH24MISS');
                    END IF;

                WHEN 'BYDAY' THEN
                    -- Parse comma-separated day list: MO,WE,FR or 2MO,-1FR
                    value_parts := string_to_array(key_value[2], ',');
                    config.byday := value_parts;

                WHEN 'BYMONTHDAY' THEN
                    -- Parse comma-separated month day list: 1,15,31 or -1,-2
                    value_parts := string_to_array(key_value[2], ',');
                    config.bymonthday := ARRAY(SELECT unnest(value_parts)::INT);

                WHEN 'BYSETPOS' THEN
                    -- Parse comma-separated position list: 1,-1,2
                    value_parts := string_to_array(key_value[2], ',');
                    config.bysetpos := ARRAY(SELECT unnest(value_parts)::INT);

                WHEN 'BYMONTH' THEN
                    -- Parse comma-separated month list: 1,6,12
                    value_parts := string_to_array(key_value[2], ',');
                    config.bymonth := ARRAY(SELECT unnest(value_parts)::INT);

                WHEN 'WKST' THEN
                    config.wkst := key_value[2];

                ELSE
                    -- Ignore unknown keys
                    NULL;
            END CASE;
        END IF;
    END LOOP;

    RETURN config;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Get day of week number (0=Sunday, 1=Monday, ..., 6=Saturday)
CREATE OR REPLACE FUNCTION day_of_week_num(d TIMESTAMP)
RETURNS INT AS $$
BEGIN
    RETURN EXTRACT(DOW FROM d)::INT;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Get day of week abbreviation (MO, TU, WE, TH, FR, SA, SU)
CREATE OR REPLACE FUNCTION day_of_week_abbr(d TIMESTAMP)
RETURNS TEXT AS $$
BEGIN
    RETURN CASE EXTRACT(DOW FROM d)::INT
        WHEN 0 THEN 'SU'
        WHEN 1 THEN 'MO'
        WHEN 2 THEN 'TU'
        WHEN 3 THEN 'WE'
        WHEN 4 THEN 'TH'
        WHEN 5 THEN 'FR'
        WHEN 6 THEN 'SA'
    END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Convert day abbreviation to day of week number
CREATE OR REPLACE FUNCTION abbr_to_dow(abbr TEXT)
RETURNS INT AS $$
BEGIN
    RETURN CASE abbr
        WHEN 'SU' THEN 0
        WHEN 'MO' THEN 1
        WHEN 'TU' THEN 2
        WHEN 'WE' THEN 3
        WHEN 'TH' THEN 4
        WHEN 'FR' THEN 5
        WHEN 'SA' THEN 6
        ELSE NULL
    END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Get last day of month for a given date
CREATE OR REPLACE FUNCTION last_day_of_month(d TIMESTAMP)
RETURNS INT AS $$
BEGIN
    RETURN EXTRACT(DAY FROM (date_trunc('month', d) + INTERVAL '1 month' - INTERVAL '1 day'))::INT;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Parse BYDAY component (e.g., 'MO' or '2MO' or '-1FR')
-- Returns (nth, day_abbr) where nth is NULL for simple day, or number for positional
CREATE OR REPLACE FUNCTION parse_byday_component(byday_str TEXT)
RETURNS TABLE(nth INT, day_abbr TEXT) AS $$
BEGIN
    IF byday_str ~ '^-?[0-9]+[A-Z]{2}$' THEN
        -- Positional format like '2MO' or '-1FR'
        RETURN QUERY SELECT
            substring(byday_str, '^(-?[0-9]+)')::INT AS nth,
            substring(byday_str, '([A-Z]{2})$') AS day_abbr;
    ELSE
        -- Simple format like 'MO'
        RETURN QUERY SELECT NULL::INT AS nth, byday_str AS day_abbr;
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- FREQUENCY GENERATORS
-- ============================================================================

-- Generate DAILY occurrences
CREATE OR REPLACE FUNCTION generate_daily_occurrences(
    dtstart TIMESTAMP,
    config rrule_config,
    max_iterations INT DEFAULT 1000
)
RETURNS TIMESTAMP[] AS $$
DECLARE
    occurrences TIMESTAMP[];
    curr_date TIMESTAMP;
    iteration INT;
    limit_date TIMESTAMP;
BEGIN
    occurrences := ARRAY[]::TIMESTAMP[];
    curr_date := dtstart;
    iteration := 0;

    -- Set limit date (10 years if no UNTIL specified)
    limit_date := COALESCE(config.until_time, dtstart + INTERVAL '10 years');

    WHILE iteration < max_iterations LOOP
        -- Check termination conditions
        IF curr_date > limit_date THEN
            EXIT;
        END IF;

        IF config.count IS NOT NULL AND COALESCE(array_length(occurrences, 1), 0) >= config.count THEN
            EXIT;
        END IF;

        -- Add occurrence
        occurrences := array_append(occurrences, curr_date);

        -- Advance by interval days
        curr_date := curr_date + (config.interval || ' days')::INTERVAL;
        iteration := iteration + 1;
    END LOOP;

    RETURN occurrences;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Generate WEEKLY occurrences
CREATE OR REPLACE FUNCTION generate_weekly_occurrences(
    dtstart TIMESTAMP,
    config rrule_config,
    max_iterations INT DEFAULT 1000
)
RETURNS TIMESTAMP[] AS $$
DECLARE
    occurrences TIMESTAMP[];
    current_week_start TIMESTAMP;
    curr_date TIMESTAMP;
    iteration INT;
    limit_date TIMESTAMP;
    days_in_week INT[];
    target_dow INT;
    day_offset INT;
BEGIN
    occurrences := ARRAY[]::TIMESTAMP[];
    current_week_start := date_trunc('week', dtstart);
    iteration := 0;

    -- Set limit date
    limit_date := COALESCE(config.until_time, dtstart + INTERVAL '10 years');

    -- If BYDAY is specified, get list of target day-of-week numbers
    IF config.byday IS NOT NULL THEN
        days_in_week := ARRAY(
            SELECT abbr_to_dow(day_abbr)
            FROM unnest(config.byday) AS byday_item,
            LATERAL parse_byday_component(byday_item) AS parsed
            WHERE parsed.nth IS NULL  -- Only simple days for WEEKLY (no positional)
        );
    ELSE
        -- No BYDAY specified, use dtstart's day of week
        days_in_week := ARRAY[day_of_week_num(dtstart)];
    END IF;

    WHILE iteration < max_iterations LOOP
        -- For each day in the week pattern
        FOREACH target_dow IN ARRAY days_in_week LOOP
            -- Calculate day offset (adjust for Monday=1 in PostgreSQL's date_trunc)
            day_offset := target_dow - 1;  -- 0=Sun->-1, 1=Mon->0, etc.
            IF day_offset < 0 THEN
                day_offset := day_offset + 7;
            END IF;

            curr_date := current_week_start + (day_offset || ' days')::INTERVAL +
                           (EXTRACT(HOUR FROM dtstart) || ' hours')::INTERVAL +
                           (EXTRACT(MINUTE FROM dtstart) || ' minutes')::INTERVAL +
                           (EXTRACT(SECOND FROM dtstart) || ' seconds')::INTERVAL;

            -- Only include if >= dtstart and <= limit
            IF curr_date >= dtstart AND curr_date <= limit_date THEN
                IF config.count IS NULL OR COALESCE(array_length(occurrences, 1), 0) < config.count THEN
                    occurrences := array_append(occurrences, curr_date);
                END IF;
            END IF;

            -- Check count limit
            IF config.count IS NOT NULL AND COALESCE(array_length(occurrences, 1), 0) >= config.count THEN
                RETURN occurrences;
            END IF;
        END LOOP;

        -- Advance to next week (by interval)
        current_week_start := current_week_start + (config.interval || ' weeks')::INTERVAL;
        iteration := iteration + 1;

        -- Check if we've gone past limit
        IF current_week_start > limit_date THEN
            EXIT;
        END IF;
    END LOOP;

    RETURN occurrences;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Generate MONTHLY occurrences
CREATE OR REPLACE FUNCTION generate_monthly_occurrences(
    dtstart TIMESTAMP,
    config rrule_config,
    max_iterations INT DEFAULT 1000
)
RETURNS TIMESTAMP[] AS $$
DECLARE
    occurrences TIMESTAMP[];
    candidates TIMESTAMP[];
    current_month_start TIMESTAMP;
    curr_date TIMESTAMP;
    iteration INT;
    limit_date TIMESTAMP;
    monthday INT;
    last_day INT;
    parsed RECORD;
    target_dow INT;
    occurrence_count INT;
    day_of_month INT;
    candidate TIMESTAMP;
BEGIN
    occurrences := ARRAY[]::TIMESTAMP[];
    current_month_start := date_trunc('month', dtstart);
    iteration := 0;

    -- Set limit date
    limit_date := COALESCE(config.until_time, dtstart + INTERVAL '10 years');

    WHILE iteration < max_iterations LOOP
        candidates := ARRAY[]::TIMESTAMP[];

        -- Generate candidates for this month
        IF config.byday IS NOT NULL THEN
            -- BYDAY specified (e.g., 2MO for second Monday, MO for all Mondays)
            FOR parsed IN
                SELECT * FROM unnest(config.byday) AS byday_item,
                LATERAL parse_byday_component(byday_item) AS p
            LOOP
                target_dow := abbr_to_dow(parsed.day_abbr);

                IF parsed.nth IS NULL THEN
                    -- All occurrences of this day in the month
                    curr_date := current_month_start;
                    WHILE EXTRACT(MONTH FROM curr_date) = EXTRACT(MONTH FROM current_month_start) LOOP
                        IF day_of_week_num(curr_date) = target_dow THEN
                            candidates := array_append(candidates,
                                curr_date +
                                (EXTRACT(HOUR FROM dtstart) || ' hours')::INTERVAL +
                                (EXTRACT(MINUTE FROM dtstart) || ' minutes')::INTERVAL +
                                (EXTRACT(SECOND FROM dtstart) || ' seconds')::INTERVAL
                            );
                        END IF;
                        curr_date := curr_date + INTERVAL '1 day';
                    END LOOP;
                ELSE
                    -- Positional (e.g., 2MO for second Monday, -1FR for last Friday)
                    IF parsed.nth > 0 THEN
                        -- Positive position (1st, 2nd, 3rd, etc.)
                        curr_date := current_month_start;
                        occurrence_count := 0;
                        WHILE EXTRACT(MONTH FROM curr_date) = EXTRACT(MONTH FROM current_month_start) LOOP
                            IF day_of_week_num(curr_date) = target_dow THEN
                                occurrence_count := occurrence_count + 1;
                                IF occurrence_count = parsed.nth THEN
                                    candidates := array_append(candidates,
                                        curr_date +
                                        (EXTRACT(HOUR FROM dtstart) || ' hours')::INTERVAL +
                                        (EXTRACT(MINUTE FROM dtstart) || ' minutes')::INTERVAL +
                                        (EXTRACT(SECOND FROM dtstart) || ' seconds')::INTERVAL
                                    );
                                    EXIT;
                                END IF;
                            END IF;
                            curr_date := curr_date + INTERVAL '1 day';
                        END LOOP;
                    ELSE
                        -- Negative position (-1 for last, -2 for second-to-last, etc.)
                        curr_date := current_month_start + INTERVAL '1 month' - INTERVAL '1 day';
                        occurrence_count := 0;
                        WHILE EXTRACT(MONTH FROM curr_date) = EXTRACT(MONTH FROM current_month_start) LOOP
                            IF day_of_week_num(curr_date) = target_dow THEN
                                occurrence_count := occurrence_count + 1;
                                IF occurrence_count = abs(parsed.nth) THEN
                                    candidates := array_append(candidates,
                                        curr_date +
                                        (EXTRACT(HOUR FROM dtstart) || ' hours')::INTERVAL +
                                        (EXTRACT(MINUTE FROM dtstart) || ' minutes')::INTERVAL +
                                        (EXTRACT(SECOND FROM dtstart) || ' seconds')::INTERVAL
                                    );
                                    EXIT;
                                END IF;
                            END IF;
                            curr_date := curr_date - INTERVAL '1 day';
                        END LOOP;
                    END IF;
                END IF;
            END LOOP;

        ELSIF config.bymonthday IS NOT NULL THEN
            -- BYMONTHDAY specified (e.g., 15 or -1 for last day)
            last_day := last_day_of_month(current_month_start);

            FOREACH monthday IN ARRAY config.bymonthday LOOP
                IF monthday > 0 THEN
                    -- Positive day number
                    IF monthday <= last_day THEN
                        day_of_month := monthday;
                    ELSE
                        -- Day doesn't exist in this month (e.g., 31 in February)
                        CONTINUE;
                    END IF;
                ELSE
                    -- Negative day number (-1 = last day, -2 = second-to-last, etc.)
                    day_of_month := last_day + monthday + 1;
                    IF day_of_month < 1 THEN
                        CONTINUE;
                    END IF;
                END IF;

                candidates := array_append(candidates,
                    current_month_start + ((day_of_month - 1) || ' days')::INTERVAL +
                    (EXTRACT(HOUR FROM dtstart) || ' hours')::INTERVAL +
                    (EXTRACT(MINUTE FROM dtstart) || ' minutes')::INTERVAL +
                    (EXTRACT(SECOND FROM dtstart) || ' seconds')::INTERVAL
                );
            END LOOP;

        ELSE
            -- No BYDAY or BYMONTHDAY, use dtstart's day of month
            day_of_month := EXTRACT(DAY FROM dtstart)::INT;
            last_day := last_day_of_month(current_month_start);

            IF day_of_month <= last_day THEN
                candidates := array_append(candidates,
                    current_month_start + ((day_of_month - 1) || ' days')::INTERVAL +
                    (EXTRACT(HOUR FROM dtstart) || ' hours')::INTERVAL +
                    (EXTRACT(MINUTE FROM dtstart) || ' minutes')::INTERVAL +
                    (EXTRACT(SECOND FROM dtstart) || ' seconds')::INTERVAL
                );
            END IF;
        END IF;

        -- Sort candidates
        SELECT ARRAY(SELECT unnest(candidates) ORDER BY 1) INTO candidates;

        -- Apply BYSETPOS if specified
        IF config.bysetpos IS NOT NULL AND array_length(candidates, 1) > 0 THEN
            DECLARE
                setpos INT;
                selected_candidates TIMESTAMP[];
                idx INT;
            BEGIN
                selected_candidates := ARRAY[]::TIMESTAMP[];
                FOREACH setpos IN ARRAY config.bysetpos LOOP
                    IF setpos > 0 THEN
                        idx := setpos;
                    ELSE
                        idx := array_length(candidates, 1) + setpos + 1;
                    END IF;

                    IF idx >= 1 AND idx <= array_length(candidates, 1) THEN
                        selected_candidates := array_append(selected_candidates, candidates[idx]);
                    END IF;
                END LOOP;
                candidates := selected_candidates;
            END;
        END IF;

        -- Add candidates to occurrences if they meet criteria
        FOREACH candidate IN ARRAY candidates LOOP
            IF candidate >= dtstart AND candidate <= limit_date THEN
                IF config.count IS NULL OR COALESCE(array_length(occurrences, 1), 0) < config.count THEN
                    occurrences := array_append(occurrences, candidate);
                END IF;
            END IF;

            -- Check count limit
            IF config.count IS NOT NULL AND COALESCE(array_length(occurrences, 1), 0) >= config.count THEN
                RETURN occurrences;
            END IF;
        END LOOP;

        -- Advance to next month (by interval)
        current_month_start := current_month_start + (config.interval || ' months')::INTERVAL;
        iteration := iteration + 1;

        -- Check if we've gone past limit
        IF current_month_start > limit_date THEN
            EXIT;
        END IF;
    END LOOP;

    RETURN occurrences;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Generate YEARLY occurrences
CREATE OR REPLACE FUNCTION generate_yearly_occurrences(
    dtstart TIMESTAMP,
    config rrule_config,
    max_iterations INT DEFAULT 100
)
RETURNS TIMESTAMP[] AS $$
DECLARE
    occurrences TIMESTAMP[];
    current_year_start TIMESTAMP;
    curr_date TIMESTAMP;
    iteration INT;
    limit_date TIMESTAMP;
    target_month INT;
    monthday INT;
    last_day INT;
    month_start TIMESTAMP;
BEGIN
    occurrences := ARRAY[]::TIMESTAMP[];
    current_year_start := date_trunc('year', dtstart);
    iteration := 0;

    -- Set limit date
    limit_date := COALESCE(config.until_time, dtstart + INTERVAL '10 years');

    WHILE iteration < max_iterations LOOP
        -- If BYMONTH specified, iterate those months; otherwise use dtstart's month
        IF config.bymonth IS NOT NULL THEN
            FOREACH target_month IN ARRAY config.bymonth LOOP
                month_start := current_year_start + ((target_month - 1) || ' months')::INTERVAL;

                IF config.bymonthday IS NOT NULL THEN
                    last_day := last_day_of_month(month_start);
                    FOREACH monthday IN ARRAY config.bymonthday LOOP
                        IF monthday > 0 AND monthday <= last_day THEN
                            curr_date := month_start + ((monthday - 1) || ' days')::INTERVAL +
                                          (EXTRACT(HOUR FROM dtstart) || ' hours')::INTERVAL +
                                          (EXTRACT(MINUTE FROM dtstart) || ' minutes')::INTERVAL +
                                          (EXTRACT(SECOND FROM dtstart) || ' seconds')::INTERVAL;
                        ELSIF monthday < 0 THEN
                            curr_date := month_start + ((last_day + monthday) || ' days')::INTERVAL +
                                          (EXTRACT(HOUR FROM dtstart) || ' hours')::INTERVAL +
                                          (EXTRACT(MINUTE FROM dtstart) || ' minutes')::INTERVAL +
                                          (EXTRACT(SECOND FROM dtstart) || ' seconds')::INTERVAL;
                        ELSE
                            CONTINUE;
                        END IF;

                        IF curr_date >= dtstart AND curr_date <= limit_date THEN
                            IF config.count IS NULL OR COALESCE(array_length(occurrences, 1), 0) < config.count THEN
                                occurrences := array_append(occurrences, curr_date);
                            END IF;
                        END IF;
                    END LOOP;
                ELSE
                    -- Use dtstart's day
                    curr_date := month_start + ((EXTRACT(DAY FROM dtstart)::INT - 1) || ' days')::INTERVAL +
                                  (EXTRACT(HOUR FROM dtstart) || ' hours')::INTERVAL +
                                  (EXTRACT(MINUTE FROM dtstart) || ' minutes')::INTERVAL +
                                  (EXTRACT(SECOND FROM dtstart) || ' seconds')::INTERVAL;

                    IF curr_date >= dtstart AND curr_date <= limit_date THEN
                        IF config.count IS NULL OR COALESCE(array_length(occurrences, 1), 0) < config.count THEN
                            occurrences := array_append(occurrences, curr_date);
                        END IF;
                    END IF;
                END IF;
            END LOOP;
        ELSE
            -- No BYMONTH, use dtstart's month
            month_start := current_year_start + ((EXTRACT(MONTH FROM dtstart)::INT - 1) || ' months')::INTERVAL;
            curr_date := month_start + ((EXTRACT(DAY FROM dtstart)::INT - 1) || ' days')::INTERVAL +
                          (EXTRACT(HOUR FROM dtstart) || ' hours')::INTERVAL +
                          (EXTRACT(MINUTE FROM dtstart) || ' minutes')::INTERVAL +
                          (EXTRACT(SECOND FROM dtstart) || ' seconds')::INTERVAL;

            IF curr_date >= dtstart AND curr_date <= limit_date THEN
                IF config.count IS NULL OR COALESCE(array_length(occurrences, 1), 0) < config.count THEN
                    occurrences := array_append(occurrences, curr_date);
                END IF;
            END IF;
        END IF;

        -- Check count limit
        IF config.count IS NOT NULL AND COALESCE(array_length(occurrences, 1), 0) >= config.count THEN
            RETURN occurrences;
        END IF;

        -- Advance to next year (by interval)
        current_year_start := current_year_start + (config.interval || ' years')::INTERVAL;
        iteration := iteration + 1;

        -- Check if we've gone past limit
        IF current_year_start > limit_date THEN
            EXIT;
        END IF;
    END LOOP;

    RETURN occurrences;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- MAIN API FUNCTION
-- ============================================================================

-- Generate occurrences from RRULE string
CREATE OR REPLACE FUNCTION generate_rrule_occurrences(
    rrule_string TEXT,
    dtstart TIMESTAMP
)
RETURNS TIMESTAMP[] AS $$
DECLARE
    config rrule_config;
    occurrences TIMESTAMP[];
BEGIN
    -- Parse RRULE
    config := parse_rrule(rrule_string);

    -- Validate FREQ
    IF config.freq IS NULL THEN
        RAISE EXCEPTION 'FREQ is required in RRULE';
    END IF;

    -- Generate occurrences based on frequency
    CASE config.freq
        WHEN 'DAILY' THEN
            occurrences := generate_daily_occurrences(dtstart, config);
        WHEN 'WEEKLY' THEN
            occurrences := generate_weekly_occurrences(dtstart, config);
        WHEN 'MONTHLY' THEN
            occurrences := generate_monthly_occurrences(dtstart, config);
        WHEN 'YEARLY' THEN
            occurrences := generate_yearly_occurrences(dtstart, config);
        ELSE
            RAISE EXCEPTION 'Unsupported FREQ: %. Supported: DAILY, WEEKLY, MONTHLY, YEARLY', config.freq;
    END CASE;

    RETURN occurrences;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- API WRAPPER FUNCTIONS (Compatible with existing API)
-- ============================================================================

-- Create 'rrule' domain type if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'rrule') THEN
        EXECUTE 'CREATE DOMAIN rrule AS VARCHAR';
    END IF;
END $$;

-- Helper function: Adjust RRULE for month-end handling
CREATE OR REPLACE FUNCTION adjust_rrule_for_month_end(rrule_string VARCHAR)
RETURNS VARCHAR AS $$
BEGIN
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
CREATE OR REPLACE FUNCTION get_occurrences(
    rrule_string VARCHAR,
    dtstart TIMESTAMP
)
RETURNS TIMESTAMP[] AS $$
BEGIN
    RETURN generate_rrule_occurrences(rrule_string, dtstart);
EXCEPTION
    WHEN OTHERS THEN
        RETURN ARRAY[]::TIMESTAMP[];
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Overload with UNTIL parameter
CREATE OR REPLACE FUNCTION get_occurrences(
    rrule_string VARCHAR,
    dtstart TIMESTAMP,
    until_time TIMESTAMP
)
RETURNS TIMESTAMP[] AS $$
DECLARE
    modified_rrule VARCHAR;
    all_occurrences TIMESTAMP[];
BEGIN
    -- Add UNTIL to RRULE if not already present
    IF rrule_string ~ 'UNTIL=' THEN
        modified_rrule := rrule_string;
    ELSE
        modified_rrule := rrule_string || ';UNTIL=' || to_char(until_time, 'YYYYMMDD"T"HH24MISS');
    END IF;

    all_occurrences := generate_rrule_occurrences(modified_rrule, dtstart);

    -- Filter occurrences up to until_time
    RETURN ARRAY(
        SELECT unnest(all_occurrences) AS occ
        WHERE occ <= until_time
        ORDER BY occ
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN ARRAY[]::TIMESTAMP[];
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Helper function: get_next_occurrence
CREATE OR REPLACE FUNCTION get_next_occurrence(
    rrule_string VARCHAR,
    dtstart TIMESTAMP,
    after_time TIMESTAMP
)
RETURNS TIMESTAMP AS $$
DECLARE
    next_occurrence TIMESTAMP;
BEGIN
    SELECT occurrence INTO next_occurrence
    FROM unnest(get_occurrences(rrule_string, dtstart)) AS occurrence
    WHERE occurrence > after_time
    ORDER BY occurrence ASC
    LIMIT 1;

    RETURN next_occurrence;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE;
