# Installation Guide

Complete installation instructions for all environments and PostgreSQL clients.

---

## Table of Contents

1. [Quick Start (psql/curl)](#quick-start-psqlcurl)
2. [TypeScript ORMs](#typescript-orms)
   - [node-postgres (pg)](#node-postgres-pg)
   - [TypeORM](#typeorm)
   - [Prisma](#prisma)
   - [Knex.js](#knexjs)
   - [Sequelize](#sequelize)
   - [Drizzle ORM](#drizzle-orm)
3. [Migration Management](#migration-management)
4. [Security Best Practices](#security-best-practices)
5. [Troubleshooting](#troubleshooting)

---

## Quick Start (psql/curl)

### Using psql

```bash
# Standard installation
psql -d your_database -f src/install.sql

# With sub-day frequencies (HOURLY/MINUTELY/SECONDLY)
psql -d your_database -f src/install_with_subday.sql
```

### Using curl (one-line install)

```bash
# Standard installation
curl -sL https://raw.githubusercontent.com/sirrodgepodge/rrule_plpgsql/main/src/install.sql | psql -d your_database

# With sub-day frequencies
curl -sL https://raw.githubusercontent.com/sirrodgepodge/rrule_plpgsql/main/src/install_with_subday.sql | psql -d your_database
```

---

## TypeScript ORMs

### node-postgres (pg)

The most direct way to install using the PostgreSQL client for Node.js.

#### Basic Installation

```typescript
import { Client } from 'pg';
import { SQL } from 'rrule-plpgsql';

const client = new Client({
  host: 'localhost',
  port: 5432,
  database: 'your_database',
  user: 'your_user',
  password: 'your_password',
});

await client.connect();

// Standard installation
await client.query(SQL.install);

// Or with sub-day frequencies
await client.query(SQL.installWithSubday);

await client.end();
```

#### Using Connection Pool (Recommended for Production)

```typescript
import { Pool } from 'pg';
import { SQL } from 'rrule-plpgsql';

const pool = new Pool({
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  max: 20, // Maximum pool size
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// Install on application startup
try {
  await pool.query(SQL.install);
  console.log('✅ RRULE functions installed');
} catch (error) {
  console.error('❌ Installation failed:', error);
  throw error;
}

// Your application code...

// Clean up on shutdown
await pool.end();
```

#### With node-pg-migrate

```typescript
// migrations/1234567890123_install_rrule.ts
import { MigrationBuilder } from 'node-pg-migrate';
import { SQL } from 'rrule-plpgsql';

export const up = async (pgm: MigrationBuilder) => {
  pgm.sql(SQL.install);
};

export const down = async (pgm: MigrationBuilder) => {
  pgm.sql('DROP SCHEMA IF EXISTS rrule CASCADE');
};
```

**Run migration:**
```bash
DATABASE_URL=postgres://user:pass@localhost:5432/dbname npm run migrate up
```

---

### TypeORM

TypeORM's migration system provides excellent integration with raw SQL queries.

#### TypeORM Migration (Recommended)

```typescript
// src/migrations/1234567890123-InstallRRule.ts
import { MigrationInterface, QueryRunner } from 'typeorm';
import { SQL } from 'rrule-plpgsql';

export class InstallRRule1234567890123 implements MigrationInterface {
  public async up(queryRunner: QueryRunner): Promise<void> {
    // Standard installation
    await queryRunner.query(SQL.install);

    // Or with sub-day frequencies:
    // await queryRunner.query(SQL.installWithSubday);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    // Clean uninstall
    await queryRunner.query('DROP SCHEMA IF EXISTS rrule CASCADE');
  }
}
```

**Generate migration:**
```bash
npm run typeorm migration:create src/migrations/InstallRRule
```

**Run migration:**
```bash
npm run typeorm migration:run
```

**Revert migration:**
```bash
npm run typeorm migration:revert
```

#### TypeORM Startup Script (Alternative)

```typescript
// src/database/setup.ts
import { DataSource } from 'typeorm';
import { SQL } from 'rrule-plpgsql';

export async function setupDatabase(dataSource: DataSource) {
  const queryRunner = dataSource.createQueryRunner();

  try {
    await queryRunner.connect();
    await queryRunner.query(SQL.install);
    console.log('✅ RRULE functions installed');
  } catch (error) {
    console.error('❌ Installation failed:', error);
    throw error;
  } finally {
    await queryRunner.release();
  }
}
```

**Best Practice:** Use migrations for production, startup scripts for development/testing.

---

### Prisma

Prisma handles migrations differently. **Important security considerations apply.**

#### ⚠️ Security Warning

Prisma's `$executeRawUnsafe()` bypasses SQL injection protection. While safe for trusted SQL files like `rrule-plpgsql`, be extremely careful with user input elsewhere in your application.

**Recommendation:** Use `$executeRaw` (with tagged templates) for any queries involving user data.

#### Prisma Migration (Recommended)

```typescript
// prisma/migrations/20240101000000_install_rrule/migration.sql
import fs from 'fs';
import path from 'path';

// Read the SQL file
const installSQL = fs.readFileSync(
  path.join(process.cwd(), 'node_modules/rrule-plpgsql/src/install.sql'),
  'utf8'
);

// Write to migration.sql
fs.writeFileSync(
  path.join(__dirname, 'migration.sql'),
  installSQL
);
```

Or manually copy the SQL:
```bash
# Copy install SQL to migration
cp node_modules/rrule-plpgsql/src/install.sql \
   prisma/migrations/20240101000000_install_rrule/migration.sql
```

**Apply migration:**
```bash
npx prisma migrate deploy
```

#### Prisma Startup Script (Alternative)

```typescript
// src/database/setup.ts
import { PrismaClient } from '@prisma/client';
import { SQL } from 'rrule-plpgsql';

export async function setupDatabase() {
  const prisma = new PrismaClient();

  try {
    // ⚠️ SECURITY: Only use $executeRawUnsafe for trusted SQL
    // Never use with user input - use $executeRaw instead
    await prisma.$executeRawUnsafe(SQL.install);
    console.log('✅ RRULE functions installed');
  } catch (error) {
    console.error('❌ Installation failed:', error);
    throw error;
  } finally {
    await prisma.$disconnect();
  }
}
```

#### Using $executeRaw (More Secure)

For queries with dynamic values (NOT for installation), use tagged templates:

```typescript
// ✅ SAFE: Proper parameterization
const rruleString = 'FREQ=DAILY;COUNT=5';
const dtstart = new Date('2025-01-01');

await prisma.$executeRaw`
  SELECT * FROM rrule.all(${rruleString}, ${dtstart}::TIMESTAMP)
`;

// ❌ UNSAFE: String interpolation (SQL injection risk)
await prisma.$executeRawUnsafe(
  `SELECT * FROM rrule.all('${rruleString}', '${dtstart}')`
);
```

---

### Knex.js

Knex provides excellent raw SQL support through `knex.raw()`.

#### Knex Migration (Recommended)

```typescript
// migrations/20240101000000_install_rrule.ts
import { Knex } from 'knex';
import { SQL } from 'rrule-plpgsql';

export async function up(knex: Knex): Promise<void> {
  await knex.raw(SQL.install);
}

export async function down(knex: Knex): Promise<void> {
  await knex.raw('DROP SCHEMA IF EXISTS rrule CASCADE');
}
```

**Run migration:**
```bash
npx knex migrate:latest
```

**Rollback:**
```bash
npx knex migrate:rollback
```

#### Knex Setup Script (Alternative)

```typescript
// src/database/setup.ts
import knex from 'knex';
import { SQL } from 'rrule-plpgsql';

const db = knex({
  client: 'pg',
  connection: {
    host: process.env.DB_HOST,
    port: parseInt(process.env.DB_PORT || '5432'),
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
  },
  pool: {
    min: 2,
    max: 10,
  },
});

export async function setupDatabase() {
  try {
    await db.raw(SQL.install);
    console.log('✅ RRULE functions installed');
  } catch (error) {
    console.error('❌ Installation failed:', error);
    throw error;
  }
}

// Remember to close the connection
export async function closeDatabase() {
  await db.destroy();
}
```

#### Loading SQL from Files

For better organization, you can store SQL in separate files:

```typescript
// migrations/20240101000000_install_rrule.ts
import { Knex } from 'knex';
import fs from 'fs';
import path from 'path';

export async function up(knex: Knex): Promise<void> {
  const sql = fs.readFileSync(
    path.join(__dirname, '../sql/install_rrule.sql'),
    'utf8'
  );
  await knex.raw(sql);
}

export async function down(knex: Knex): Promise<void> {
  const sql = fs.readFileSync(
    path.join(__dirname, '../sql/uninstall_rrule.sql'),
    'utf8'
  );
  await knex.raw(sql);
}
```

---

### Sequelize

Sequelize provides raw SQL execution through `queryInterface.sequelize.query()`.

#### Sequelize Migration (Recommended)

```typescript
// migrations/20240101000000-install-rrule.js
import { SQL } from 'rrule-plpgsql';

module.exports = {
  async up(queryInterface, Sequelize) {
    await queryInterface.sequelize.query(SQL.install);
  },

  async down(queryInterface, Sequelize) {
    await queryInterface.sequelize.query('DROP SCHEMA IF EXISTS rrule CASCADE');
  }
};
```

**Run migration:**
```bash
npx sequelize-cli db:migrate
```

**Rollback:**
```bash
npx sequelize-cli db:migrate:undo
```

#### Sequelize Setup Script (Alternative)

```typescript
// src/database/setup.ts
import { Sequelize } from 'sequelize';
import { SQL } from 'rrule-plpgsql';

const sequelize = new Sequelize({
  dialect: 'postgres',
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME,
  username: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  pool: {
    max: 20,
    min: 0,
    acquire: 30000,
    idle: 10000,
  },
});

export async function setupDatabase() {
  try {
    await sequelize.authenticate();
    await sequelize.query(SQL.install);
    console.log('✅ RRULE functions installed');
  } catch (error) {
    console.error('❌ Installation failed:', error);
    throw error;
  }
}

export async function closeDatabase() {
  await sequelize.close();
}
```

#### Running Multiple Queries in Order

```typescript
async function runSequentialQueries(sequelize, queries) {
  const results = [];
  for (const query of queries) {
    const result = await sequelize.query(query);
    results.push(result);
  }
  return results;
}

// Usage
await runSequentialQueries(sequelize, [
  'CREATE SCHEMA IF NOT EXISTS rrule',
  'SET search_path = rrule, public',
  SQL.core, // Core functions only
]);
```

---

### Drizzle ORM

Drizzle is a modern, type-safe ORM with excellent SQL support.

#### Drizzle Migration (Recommended)

```typescript
// drizzle/migrations/0000_install_rrule.sql
import { SQL } from 'rrule-plpgsql';
import fs from 'fs';

// Write SQL to migration file
fs.writeFileSync(
  './drizzle/migrations/0000_install_rrule.sql',
  SQL.install
);
```

**Apply migration:**
```bash
npx drizzle-kit push:pg
```

#### Drizzle Setup Script

```typescript
// src/database/setup.ts
import { drizzle } from 'drizzle-orm/node-postgres';
import { sql } from 'drizzle-orm';
import { Pool } from 'pg';
import { SQL as RRULE_SQL } from 'rrule-plpgsql';

const pool = new Pool({
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

const db = drizzle(pool);

export async function setupDatabase() {
  try {
    // Use sql.raw for unescaped SQL installation
    await db.execute(sql.raw(RRULE_SQL.install));
    console.log('✅ RRULE functions installed');
  } catch (error) {
    console.error('❌ Installation failed:', error);
    throw error;
  }
}

export async function closeDatabase() {
  await pool.end();
}
```

#### Using RRULE Functions with Drizzle

```typescript
import { sql } from 'drizzle-orm';

// Query with RRULE functions
const occurrences = await db.execute(
  sql`SELECT * FROM rrule.all(${rruleString}, ${dtstart}::TIMESTAMP)`
);

// Using prepared statements for better performance
const getOccurrences = db
  .execute(
    sql`SELECT * FROM rrule.all(
      ${sql.placeholder('rrule')},
      ${sql.placeholder('dtstart')}::TIMESTAMP
    )`
  )
  .prepare('getOccurrences');

// Execute with parameters
await getOccurrences.execute({
  rrule: 'FREQ=DAILY;COUNT=5',
  dtstart: '2025-01-01 10:00:00',
});
```

---

## Migration Management

### Best Practices

#### 1. **One-Time Execution**
Migrations must only run once, ever. Most migration tools handle this automatically by tracking which migrations have been applied.

#### 2. **All-or-Nothing (Transactions)**
Migrations should run within transactions to ensure atomicity:

```typescript
// TypeORM (automatic)
await queryRunner.query(SQL.install);

// node-postgres (manual)
await client.query('BEGIN');
try {
  await client.query(SQL.install);
  await client.query('COMMIT');
} catch (error) {
  await client.query('ROLLBACK');
  throw error;
}

// Knex (automatic with .transacting())
await knex.transaction(async (trx) => {
  await trx.raw(SQL.install);
});
```

#### 3. **Immutable Migrations**
Once applied to production, never modify a migration. Create a new migration instead.

#### 4. **Always Implement Rollback**
Every migration should have a corresponding `down()` function:

```typescript
export async function down(queryRunner: QueryRunner): Promise<void> {
  await queryRunner.query('DROP SCHEMA IF EXISTS rrule CASCADE');
}
```

#### 5. **Test Migrations Locally First**
Always test migrations in development before applying to production:

```bash
# Test up migration
npm run migrate:up

# Verify it worked
psql -d your_database -c "SELECT rrule.all('FREQ=DAILY;COUNT=1', NOW())"

# Test down migration
npm run migrate:down

# Verify clean uninstall
psql -d your_database -c "\dn rrule"  # Should show "No matching schemas found"
```

---

## Security Best Practices

### SQL Injection Prevention

**Critical:** While `rrule-plpgsql` SQL files are safe, your application queries MUST use parameterized queries:

#### ✅ SAFE: Parameterized Queries

```typescript
// node-postgres
await client.query(
  'SELECT * FROM rrule.all($1, $2)',
  [userRRule, dtstart]
);

// TypeORM
await dataSource.query(
  'SELECT * FROM rrule.all($1, $2)',
  [userRRule, dtstart]
);

// Prisma (tagged template)
await prisma.$executeRaw`
  SELECT * FROM rrule.all(${userRRule}, ${dtstart}::TIMESTAMP)
`;

// Knex
await knex.raw(
  'SELECT * FROM rrule.all(?, ?)',
  [userRRule, dtstart]
);

// Drizzle
await db.execute(
  sql`SELECT * FROM rrule.all(${userRRule}, ${dtstart}::TIMESTAMP)`
);
```

#### ❌ UNSAFE: String Interpolation

```typescript
// ❌ DANGEROUS - SQL INJECTION RISK
await client.query(
  `SELECT * FROM rrule.all('${userRRule}', '${dtstart}')`
);

// ❌ DANGEROUS - Template literals are NOT safe
await client.query(`
  SELECT * FROM rrule.all('${req.body.rrule}', '${req.body.date}')
`);
```

### Input Validation

Always validate RRULE strings before passing to database:

```typescript
function validateRRule(rrule: string): void {
  // 1. Length check
  if (rrule.length > 500) {
    throw new Error('RRULE too long');
  }

  // 2. Format check
  if (!rrule.match(/^[A-Z0-9=;:,+-]+$/)) {
    throw new Error('Invalid RRULE format');
  }

  // 3. Required parameter check
  if (!rrule.includes('FREQ=')) {
    throw new Error('RRULE must include FREQ parameter');
  }

  // 4. Database validation (PostgreSQL will validate RFC 5545 compliance)
  await client.query(
    'SELECT rrule.parse_rrule_parts($1::TIMESTAMPTZ, $2)',
    [new Date(), rrule]
  );
}
```

See [SECURITY.md](SECURITY.md) for comprehensive security guidelines.

---

## Troubleshooting

### Installation Failed

**Error:** `schema "rrule" already exists`

```typescript
// Solution: Drop existing schema first
await client.query('DROP SCHEMA IF EXISTS rrule CASCADE');
await client.query(SQL.install);
```

**Error:** `permission denied to create extension`

```typescript
// Solution: Connect as superuser or use pre-created extensions
// Option 1: Connect as postgres superuser
const client = new Client({ user: 'postgres', ... });

// Option 2: Pre-create extensions (if your DB role doesn't have CREATE EXTENSION)
// Run as superuser once:
// CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

### Query Errors

**Error:** `function rrule.all does not exist`

```typescript
// Solution: Ensure schema is in search_path
await client.query('SET search_path = rrule, public');
// Or use fully qualified names:
await client.query('SELECT * FROM rrule.all($1, $2)', [rrule, date]);
```

**Error:** `column "occurrence" does not exist`

```typescript
// Solution: Add column alias
// ❌ Wrong:
SELECT * FROM rrule.all(rrule, dtstart)

// ✅ Correct:
SELECT * FROM rrule.all(rrule, dtstart) AS occurrence
```

### Performance Issues

**Slow queries with large result sets:**

```typescript
// Solution: Use COUNT limits and date ranges
SELECT * FROM rrule.all('FREQ=DAILY;COUNT=365', dtstart)  -- Limit results

SELECT * FROM rrule.between(
  rrule,
  dtstart,
  '2025-01-01'::TIMESTAMPTZ,
  '2025-12-31'::TIMESTAMPTZ
)  -- Date range
```

See [PERFORMANCE.md](PERFORMANCE.md) for optimization strategies.

---

## Advanced: Custom Schema Management

For advanced users who want full control over schema setup:

```typescript
import { SQL } from 'rrule-plpgsql';

// Create your own schema
await client.query('CREATE SCHEMA IF NOT EXISTS my_rrule');
await client.query('SET search_path = my_rrule, public');

// Install core functions only (no schema creation)
await client.query(SQL.core);

// Your custom setup...
await client.query('GRANT USAGE ON SCHEMA my_rrule TO app_user');
```

**Use `SQL.core`** when:
- You manage schemas manually
- You need custom permissions/ownership
- You're integrating with existing schema management
- You want to inspect/modify SQL before execution

**Use `SQL.install`** for standard setup (recommended for 95% of users).

---

## Next Steps

- 📖 [Example Usage](EXAMPLE_USAGE.md) - Real-world patterns and recipes
- 📚 [API Reference](API_REFERENCE.md) - Complete function reference
- 🔒 [Security Guide](SECURITY.md) - SQL injection prevention
- ⚡ [Performance Guide](PERFORMANCE.md) - Optimization strategies

---

**Questions?** See [DEVELOPMENT.md](DEVELOPMENT.md) for contribution guidelines or open an issue on GitHub.
