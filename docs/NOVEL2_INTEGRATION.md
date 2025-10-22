# Novel-2 Integration Guide for rrule_plpgsql

## Overview

This document provides step-by-step instructions for integrating rrule_plpgsql into the novel-2 project. **This will be the single RRULE implementation for all environments** (local dev, testing, staging, production).

## Strategy: Consistency Everywhere

**Key Decision**: Use rrule_plpgsql in ALL environments for consistency.

### Why Not pg_rrule C Extension?

While the pg_rrule C extension is faster (~100x vs ~50-75x for PL/pgSQL), using different implementations across environments creates risk:
- ✅ **Consistency**: Same code path in development, staging, and production
- ✅ **Simplicity**: No Docker image compilation for C extensions
- ✅ **Portability**: Works on AlloyDB (production requirement)
- ✅ **Performance**: 50-75x faster than Node.js is excellent
- ✅ **No surprises**: Test what you deploy

## Architecture

```
┌─────────────────┬──────────────────────┬────────────────────────┐
│ Environment     │ PostgreSQL Service   │ RRULE Implementation   │
├─────────────────┼──────────────────────┼────────────────────────┤
│ Local Dev       │ Self-hosted Postgres │ rrule_plpgsql ★        │
│ Testing         │ Self-hosted Postgres │ rrule_plpgsql ★        │
│ Staging         │ Cloud SQL            │ rrule_plpgsql ★        │
│ Production      │ AlloyDB              │ rrule_plpgsql ★        │
└─────────────────┴──────────────────────┴────────────────────────┘

★ = Same implementation everywhere
```

## Step 1: Push to GitHub

Create a new public GitHub repository:

```bash
# On GitHub UI:
# Repository: https://github.com/sirrodgepodge/rrule_plpgsql
# Visibility: Public
# Description: "Pure PL/pgSQL RRULE implementation for PostgreSQL - works everywhere"
# License: MIT + GPL (hybrid license for DAVical components)

# Push from local
cd /tmp/rrule_plpgsql
git remote add origin git@github.com:sirrodgepodge/rrule_plpgsql.git
git push -u origin master

# Create release tag
git tag v1.0.0 -m "Initial release: Pure PL/pgSQL RRULE implementation"
git push origin v1.0.0
```

## Step 2: Add as Git Submodule to novel-2

```bash
cd /Users/rbeaman/projects/novel-2

# Add submodule (public GitHub repo)
git submodule add https://github.com/sirrodgepodge/rrule_plpgsql.git rrule_plpgsql

# Initialize and update
git submodule update --init --recursive

# Commit submodule reference
git add .gitmodules rrule_plpgsql
git commit -m "Add rrule_plpgsql submodule for all environments

Pure PL/pgSQL RRULE implementation provides consistent behavior across
all environments (local, testing, staging, production). Replaces pg_rrule
C extension with simpler, more portable solution.

Repository: https://github.com/sirrodgepodge/rrule_plpgsql"
```

## Step 3: Remove pg_rrule C Extension

### 3.1 Remove from Docker

Edit `docker/Dockerfile.postgres-rrule`:

**Before:**
```dockerfile
FROM postgis/postgis:16-3.4

# Build from quantivly fork with SIGSEGV fix
RUN git clone --depth 1 --branch benoit/qua-1941-fix-pg_rrule-error-leading-to-segmentation-fault \
    https://github.com/quantivly/pg_rrule.git

WORKDIR /tmp/pg_rrule
RUN make USE_PGXS=1 && \
    cp pg_rrule.so `pg_config --pkglibdir`/ && \
    cp pg_rrule.control `pg_config --sharedir`/extension/ && \
    cp sql/pg_rrule--0.3.0.sql `pg_config --sharedir`/extension/
```

**After:**
```dockerfile
FROM postgis/postgis:16-3.4

# No pg_rrule C extension needed!
# We use rrule_plpgsql (pure PL/pgSQL) for all environments
```

### 3.2 Update docker-compose.yml

No changes needed - standard postgres image works fine.

### 3.3 Remove pg_rrule Extension Creation

Find and remove any `CREATE EXTENSION pg_rrule` statements in migrations.

## Step 4: Create TypeORM Migration

Create migration file: `backend/src/db/migrations/1755800000000-InstallRRulePlpgsql.ts`

```typescript
import { MigrationInterface, QueryRunner } from "typeorm";
import * as fs from "fs";
import * as path from "path";

/**
 * Install rrule_plpgsql - Pure PL/pgSQL RRULE Implementation
 *
 * This migration installs rrule_plpgsql functions for all environments
 * (local, testing, staging, production). This replaces any previous
 * pg_rrule C extension usage.
 *
 * The implementation provides:
 * - get_occurrences(rrule VARCHAR, dtstart TIMESTAMP) -> TIMESTAMP[]
 * - get_occurrences(rrule VARCHAR, dtstart TIMESTAMP, until TIMESTAMP) -> TIMESTAMP[]
 * - get_next_occurrence(rrule VARCHAR, dtstart TIMESTAMP, after TIMESTAMP) -> TIMESTAMP
 * - adjust_rrule_for_month_end(rrule VARCHAR) -> VARCHAR
 */
export class InstallRRulePlpgsql1755800000000 implements MigrationInterface {
    public async up(queryRunner: QueryRunner): Promise<void> {
        console.log('Installing rrule_plpgsql (Pure PL/pgSQL RRULE implementation)...');

        // Remove pg_rrule C extension if it exists
        try {
            await queryRunner.query(`DROP EXTENSION IF EXISTS pg_rrule CASCADE;`);
            console.log('  → Removed pg_rrule C extension (if it existed)');
        } catch (error) {
            // Ignore error if extension didn't exist
            console.log('  → No pg_rrule extension to remove');
        }

        // Load DAVical RRULE base functions
        const baseSqlPath = path.join(__dirname, "../../../rrule_plpgsql/src/davical_rrule_base.sql");
        const baseSql = fs.readFileSync(baseSqlPath, "utf8");

        console.log('  → Installing DAVical RRULE base functions...');
        await queryRunner.query(baseSql);

        // Load RRULE wrappers
        const wrappersSqlPath = path.join(__dirname, "../../../rrule_plpgsql/src/rrule_wrappers.sql");
        const wrappersSql = fs.readFileSync(wrappersSqlPath, "utf8");

        console.log('  → Installing RRULE wrapper functions...');
        await queryRunner.query(wrappersSql);

        console.log('✅ rrule_plpgsql installed successfully');
    }

    public async down(queryRunner: QueryRunner): Promise<void> {
        console.log('Uninstalling rrule_plpgsql...');

        // Drop wrapper functions
        await queryRunner.query(`DROP FUNCTION IF EXISTS get_next_occurrence(VARCHAR, TIMESTAMP, TIMESTAMP) CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS get_occurrences(VARCHAR, TIMESTAMP, TIMESTAMP) CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS get_occurrences(VARCHAR, TIMESTAMP) CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS adjust_rrule_for_month_end(VARCHAR) CASCADE;`);

        // Drop rrule domain
        await queryRunner.query(`DROP DOMAIN IF EXISTS rrule CASCADE;`);

        // Drop DAVical functions
        await queryRunner.query(`DROP FUNCTION IF EXISTS rrule_event_instances(TIMESTAMP WITH TIME ZONE, TEXT) CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS rrule_event_instances_range(TIMESTAMP WITH TIME ZONE, TEXT, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, INT) CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS event_instances(TIMESTAMP WITH TIME ZONE, TEXT) CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS rrule_event_overlaps CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS yearly_set CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS rrule_yearly_bymonth_set CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS monthly_set CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS weekly_set CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS daily_set CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS rrule_bysetpos_filter CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS test_byyearday_rule CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS test_bymonthday_rule CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS test_bymonth_rule CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS test_byday_rule CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS event_has_exceptions CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS rrule_week_byday_set CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS rrule_month_bymonthday_set CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS rrule_month_byday_set CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS parse_rrule_parts CASCADE;`);
        await queryRunner.query(`DROP FUNCTION IF EXISTS icalendar_interval_to_SQL CASCADE;`);

        await queryRunner.query(`DROP TYPE IF EXISTS rrule_instance CASCADE;`);
        await queryRunner.query(`DROP TYPE IF EXISTS rrule_parts CASCADE;`);

        console.log('✅ rrule_plpgsql uninstalled');
    }
}
```

## Step 5: Test Locally

```bash
cd backend
yarn db:migrate

# Verify
psql postgres://postgres:postgres@127.0.0.1:5432/novel_development -c \
  "SELECT unnest(get_occurrences('FREQ=DAILY;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP));"

# Run tests
yarn test:backend src/utils/__tests__/RRuleProcessor.spec.ts
```

## No Code Changes Required

✅ Zero application code changes needed! Same API as before.

---

**Status**: Ready for deployment to all environments
**Repository**: https://github.com/sirrodgepodge/rrule_plpgsql
