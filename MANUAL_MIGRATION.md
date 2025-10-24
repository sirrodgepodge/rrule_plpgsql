# Manual Migration Guide for rrule_plpgsql

This guide explains how to update rrule_plpgsql when you have created database objects that depend on the `rrule` schema (views, functions, triggers, etc.).

## When Do I Need This?

You need manual migration if:

1. You get this error when running `install.sql`:
   ```
   ERROR: cannot drop schema rrule because other objects depend on it
   DETAIL: view public.my_schedule depends on function rrule.all(...)
   ```

2. You have created any of these:
   - Views using rrule functions
   - Functions that call rrule functions
   - Triggers that use rrule functions
   - Materialized views with rrule data

## Migration Strategy

The migration uses a "side-by-side" approach:

1. Install new version to `rrule_update` schema (alongside existing `rrule`)
2. Update your dependent objects to use `rrule_update`
3. Test thoroughly
4. Drop old `rrule` schema
5. Rename `rrule_update` to `rrule`

This ensures zero downtime and easy rollback if needed.

---

## Step-by-Step Migration

### Prerequisites

- Backup your database
- Identify all objects depending on `rrule` schema
- Schedule maintenance window (optional, but recommended)

### Step 1: Identify Dependencies

First, find all objects that depend on the rrule schema:

```sql
-- Find all dependent views
SELECT
    'VIEW' as object_type,
    n.nspname as schema_name,
    c.relname as object_name,
    pg_get_viewdef(c.oid) as definition
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
JOIN pg_depend d ON d.refobjid = c.oid
JOIN pg_proc p ON d.objid = p.oid
JOIN pg_namespace pn ON p.pronamespace = pn.oid
WHERE c.relkind = 'v'
  AND pn.nspname = 'rrule'
ORDER BY n.nspname, c.relname;

-- Find all dependent functions
SELECT
    'FUNCTION' as object_type,
    n.nspname as schema_name,
    p.proname as object_name,
    pg_get_functiondef(p.oid) as definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE pg_get_functiondef(p.oid) LIKE '%rrule.%'
  AND n.nspname != 'rrule'
ORDER BY n.nspname, p.proname;
```

**Save these results!** You'll need them to recreate your objects.

### Step 2: Install to rrule_update Schema

Run the manual installation script:

```bash
cd rrule_plpgsql
./src/installManual.sh your_database
```

Or if using git submodule/remote location:

```bash
./path/to/rrule_plpgsql/src/installManual.sh your_database
```

This creates the `rrule_update` schema with the new version.

### Step 3: Update Your Dependent Objects

For each dependent object, create an updated version using `rrule_update`:

**Example: Migrating a View**

```sql
-- Original view (using rrule)
CREATE VIEW my_daily_schedule AS
  SELECT * FROM rrule."all"(
    'FREQ=DAILY;COUNT=30',
    '2025-01-01 09:00:00'::TIMESTAMP
  );

-- Step 3a: Create updated version with temporary name
CREATE VIEW my_daily_schedule_new AS
  SELECT * FROM rrule_update."all"(
    'FREQ=DAILY;COUNT=30',
    '2025-01-01 09:00:00'::TIMESTAMP
  );

-- Step 3b: Test the new view
SELECT COUNT(*) FROM my_daily_schedule_new;  -- Should return 30

-- Step 3c: Drop old view and rename new one
DROP VIEW my_daily_schedule;
ALTER VIEW my_daily_schedule_new RENAME TO my_daily_schedule;
```

**Example: Migrating a Function**

```sql
-- Original function (using rrule)
CREATE FUNCTION get_next_meetings()
RETURNS SETOF TIMESTAMP AS $$
  SELECT * FROM rrule."all"(
    'FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=10',
    '2025-01-01 10:00:00'::TIMESTAMP
  )
$$ LANGUAGE sql STABLE;

-- Step 3a: Create updated version
CREATE OR REPLACE FUNCTION get_next_meetings()
RETURNS SETOF TIMESTAMP AS $$
  SELECT * FROM rrule_update."all"(
    'FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=10',
    '2025-01-01 10:00:00'::TIMESTAMP
  )
$$ LANGUAGE sql STABLE;

-- Step 3b: Test
SELECT COUNT(*) FROM get_next_meetings();  -- Should return 10
```

### Step 4: Test Thoroughly

```sql
-- Verify rrule_update works
SELECT * FROM rrule_update."all"('FREQ=DAILY;COUNT=3', NOW()::TIMESTAMP);

-- Test your application with updated objects
-- Check all views, functions, queries still work correctly

-- Compare old vs new (should be identical except for newer version features)
SELECT COUNT(*) FROM rrule."all"('FREQ=DAILY;COUNT=10', '2025-01-01'::TIMESTAMP);
SELECT COUNT(*) FROM rrule_update."all"('FREQ=DAILY;COUNT=10', '2025-01-01'::TIMESTAMP);
```

### Step 5: Drop Old Schema and Rename

Once you've verified everything works:

```sql
BEGIN;

-- Drop the old rrule schema
-- No CASCADE needed - all dependencies have been moved to rrule_update
DROP SCHEMA rrule;

-- Rename rrule_update to rrule
ALTER SCHEMA rrule_update RENAME TO rrule;

COMMIT;
```

### Step 6: Update Objects Back to 'rrule' Schema

Now update your objects to use `rrule` instead of `rrule_update`:

```sql
-- Update view back to use 'rrule' schema
CREATE OR REPLACE VIEW my_daily_schedule AS
  SELECT * FROM rrule."all"(
    'FREQ=DAILY;COUNT=30',
    '2025-01-01 09:00:00'::TIMESTAMP
  );

-- Update function back to use 'rrule' schema
CREATE OR REPLACE FUNCTION get_next_meetings()
RETURNS SETOF TIMESTAMP AS $$
  SELECT * FROM rrule."all"(
    'FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=10',
    '2025-01-01 10:00:00'::TIMESTAMP
  )
$$ LANGUAGE sql STABLE;
```

### Step 7: Final Verification

```sql
-- Verify schema rename worked
\df rrule.*        -- Should show all rrule functions
\dv rrule_update.* -- Should show nothing (schema renamed)

-- Test your application end-to-end
SELECT * FROM my_daily_schedule LIMIT 5;
SELECT * FROM get_next_meetings();
```

---

## Complete Migration Script Example

Here's a complete example you can adapt:

```sql
-- migration_example.sql
-- Adapt this to your specific objects

BEGIN;

-- 1. Check dependencies before starting
\echo 'Dependent views:'
SELECT n.nspname || '.' || c.relname
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
JOIN pg_depend d ON d.refobjid = c.oid
JOIN pg_proc p ON d.objid = p.oid
JOIN pg_namespace pn ON p.pronamespace = pn.oid
WHERE c.relkind = 'v' AND pn.nspname = 'rrule';

-- 2. Backup existing view definitions (for rollback)
CREATE TEMP TABLE view_backups AS
SELECT
    n.nspname as schema_name,
    c.relname as view_name,
    pg_get_viewdef(c.oid) as definition
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
JOIN pg_depend d ON d.refobjid = c.oid
JOIN pg_proc p ON d.objid = p.oid
JOIN pg_namespace pn ON p.pronamespace = pn.oid
WHERE c.relkind = 'v' AND pn.nspname = 'rrule';

\echo 'View backups created in temp table'

-- 3. Update each view to use rrule_update
-- EXAMPLE - CUSTOMIZE FOR YOUR VIEWS:
CREATE OR REPLACE VIEW my_daily_schedule AS
  SELECT * FROM rrule_update."all"(
    'FREQ=DAILY;COUNT=30',
    '2025-01-01 09:00:00'::TIMESTAMP
  );

-- 4. Test views
SELECT 'Testing my_daily_schedule:' as test;
SELECT COUNT(*) as event_count FROM my_daily_schedule;

-- 5. If tests pass, drop old schema and rename
\echo 'Tests passed, proceeding with migration...'
DROP SCHEMA rrule;  -- No CASCADE needed - dependencies moved to rrule_update
ALTER SCHEMA rrule_update RENAME TO rrule;

-- 6. Update views back to 'rrule' schema reference
CREATE OR REPLACE VIEW my_daily_schedule AS
  SELECT * FROM rrule."all"(
    'FREQ=DAILY;COUNT=30',
    '2025-01-01 09:00:00'::TIMESTAMP
  );

-- 7. Final verification
SELECT 'Migration complete. Final verification:' as status;
SELECT COUNT(*) as event_count FROM my_daily_schedule;

COMMIT;

\echo 'Migration successful!'
```

---

## Rollback Procedure

If something goes wrong during migration:

### If You Haven't Dropped rrule Schema Yet:

```sql
-- Simply drop rrule_update and keep using rrule
DROP SCHEMA rrule_update;

-- Revert your objects back to using rrule (if you changed them)
CREATE OR REPLACE VIEW my_daily_schedule AS
  SELECT * FROM rrule."all"(...);  -- Original definition
```

### If You Already Dropped rrule Schema:

```sql
-- Rename rrule_update back to rrule
ALTER SCHEMA rrule_update RENAME TO rrule;

-- Reinstall old version from backup
-- (Restore from your database backup to get old rrule schema)
```

---

## Tips and Best Practices

### 1. Use a Transaction for Small Migrations

```sql
BEGIN;
-- All migration steps here
COMMIT;  -- Or ROLLBACK if something fails
```

### 2. Test in Staging First

Always test the migration in a non-production environment first.

### 3. Document Your Dependencies

Keep a list of all objects that depend on rrule:

```bash
# Save to file for reference
psql -d mydb -c "\
SELECT n.nspname || '.' || c.relname as full_name \
FROM pg_class c \
JOIN pg_namespace n ON c.relnamespace = n.oid \
JOIN pg_depend d ON d.refobjid = c.oid \
JOIN pg_proc p ON d.objid = p.oid \
JOIN pg_namespace pn ON p.pronamespace = pn.oid \
WHERE c.relkind = 'v' AND pn.nspname = 'rrule'" \
> rrule_dependencies.txt
```

### 4. Monitor Application During Migration

If doing a live migration:
- Monitor application logs
- Have rollback plan ready
- Consider read-only mode during critical steps

### 5. Avoid Dependencies in the Future

After migration, consider **not** creating new dependent objects. Instead:

```sql
-- ❌ Don't create views with rrule functions
CREATE VIEW my_schedule AS
  SELECT * FROM rrule."all"(...);

-- ✅ Do call rrule functions directly in queries
SELECT * FROM rrule."all"(...);  -- In application code
```

This makes future updates much simpler!

---

## Troubleshooting

### "schema rrule_update does not exist"

The installManual.sh script didn't run successfully. Check:
- Database connection is correct
- You have CREATE SCHEMA permission
- Path to rrule.sql is correct

### "function rrule_update.all does not exist"

The sed replacement didn't work. Manually verify:

```bash
sed 's/SET search_path = rrule,/SET search_path = rrule_update,/g' src/rrule.sql | grep search_path
```

Should show `SET search_path = rrule_update, public;`

### Migration is Too Complex

If you have many dependencies, consider:
1. Creating a migration script that programmatically updates all objects
2. Using a blue-green deployment approach with separate databases
3. Scheduling downtime for a clean migration

---

## Need Help?

- Open an issue: https://github.com/sirrodgepodge/rrule_plpgsql/issues
- Include your dependency count and types (views, functions, etc.)
- We can help create a custom migration script for complex scenarios
