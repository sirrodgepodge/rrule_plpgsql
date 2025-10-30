# Security Guide

## Overview

This package exports raw SQL strings for PostgreSQL. While this approach is transparent and auditable, it's important to understand the security considerations.

---

## Security Model

### What This Package Does
- Exports static SQL strings (function definitions)
- No user input processing
- No network calls
- No dynamic SQL generation
- Pure DDL (Data Definition Language)

### What This Package Does NOT Do
- No data access (doesn't SELECT/UPDATE/DELETE your data)
- No credential handling
- No external dependencies
- No runtime SQL injection risk (static SQL only)

---

## Supply Chain Security

### Threat: Compromised NPM Package

**Risk:** Attacker publishes malicious version with backdoor SQL

**Mitigations We Provide:**

1. **Checksums**
   ```bash
   # Verify file integrity
   cd node_modules/rrule-plpgsql
   shasum -a 256 -c CHECKSUMS.txt
   ```

2. **Small, Auditable Codebase**
   - `index.js`: 40 lines (just file reading)
   - Total SQL: ~2,600 lines (pure PL/pgSQL, no obfuscation)
   - Easy to review in 30 minutes

3. **Git Commit Signing** (recommended for maintainers)
   ```bash
   git log --show-signature
   ```

**Best Practices for Users:**

1. **Pin Exact Versions**
   ```json
   {
     "dependencies": {
       "rrule-plpgsql": "1.1.0"  // Not "^1.1.0"
     }
   }
   ```

2. **Use Lock Files**
   - Commit `package-lock.json` or `yarn.lock`
   - Ensures reproducible builds

3. **Review Before Installing**
   ```bash
   # Check what's in the package before installing
   npm view rrule-plpgsql

   # Or review on GitHub first
   # https://github.com/sirrodgepodge/rrule_plpgsql
   ```

4. **Inspect SQL Before Running**
   ```javascript
   const { SQL } = require('rrule-plpgsql');

   // Review the SQL first
   console.log(SQL.install);

   // Verify it looks correct, then run
   await client.query(SQL.install);
   ```

5. **Verify Checksums**
   ```bash
   # After npm install
   cd node_modules/rrule-plpgsql
   shasum -a 256 src/install.sql
   # Compare to CHECKSUMS.txt in repo
   ```

---

## Application Security: Preventing SQL Injection

### CRITICAL: Always Use Parameterized Queries

While the RRULE functions themselves are safe (they use parameterized queries internally), **your application code MUST also use parameterized queries** when calling these functions with user input.

#### ✅ SAFE: Parameterized Queries

```typescript
// ✅ node-postgres (pg)
await client.query(
  'SELECT * FROM rrule.all($1, $2)',
  [userRRule, dtstart]
);

// ✅ TypeORM
await connection.query(
  'SELECT * FROM rrule.all($1, $2)',
  [userRRule, dtstart]
);

// ✅ Prisma
await prisma.$queryRawUnsafe(
  'SELECT * FROM rrule.all($1, $2)',
  userRRule,
  dtstart
);

// ✅ Knex
await knex.raw(
  'SELECT * FROM rrule.all(?, ?)',
  [userRRule, dtstart]
);
```

#### ❌ UNSAFE: String Interpolation (SQL Injection Risk)

```typescript
// ❌ DANGEROUS - DO NOT DO THIS
await client.query(
  `SELECT * FROM rrule.all('${userRRule}', '${dtstart}')`
);

// ❌ DANGEROUS - Template literals are NOT safe
await client.query(`
  SELECT * FROM rrule.all('${req.body.rrule}', '${req.body.date}')
`);

// ❌ DANGEROUS - String concatenation
await client.query(
  "SELECT * FROM rrule.all('" + userRRule + "', '" + dtstart + "')"
);
```

### Why This Matters

**Attack Scenario:**
```typescript
// Attacker sends malicious RRULE:
const userRRule = "FREQ=DAILY'); DROP TABLE users; --";

// With string interpolation (UNSAFE):
await client.query(
  `SELECT * FROM rrule.all('${userRRule}', '2025-01-01')`
);
// Becomes: SELECT * FROM rrule.all('FREQ=DAILY'); DROP TABLE users; --', '2025-01-01')
// ^ This executes DROP TABLE!

// With parameterized query (SAFE):
await client.query(
  'SELECT * FROM rrule.all($1, $2)',
  [userRRule, '2025-01-01']
);
// The RRULE string is properly escaped - attack prevented!
```

### Input Validation Best Practices

In addition to using parameterized queries, validate RRULE strings:

```typescript
// Example validation function
function validateRRule(rrule: string): void {
  // 1. Check length
  if (rrule.length > 500) {
    throw new Error('RRULE too long');
  }

  // 2. Validate format (basic check)
  if (!rrule.match(/^[A-Z0-9=;:,+-]+$/)) {
    throw new Error('Invalid RRULE format');
  }

  // 3. Check for required FREQ parameter
  if (!rrule.includes('FREQ=')) {
    throw new Error('RRULE must include FREQ parameter');
  }

  // 4. Validate against PostgreSQL (will throw if invalid)
  await client.query(
    'SELECT rrule.parse_rrule_parts($1::TIMESTAMPTZ, $2)',
    [new Date(), rrule]
  );
}
```

### Security Checklist for Applications

- [ ] Use parameterized queries (bind parameters) for ALL user input
- [ ] Never use string interpolation or concatenation with user input
- [ ] Validate RRULE strings before passing to database
- [ ] Limit RRULE string length (recommend max 500 characters)
- [ ] Use Content Security Policy (CSP) headers
- [ ] Log failed validation attempts for monitoring
- [ ] Apply rate limiting to prevent DoS via complex RRULEs

---

## Database Security

### Principle of Least Privilege

**Don't install as superuser if you can avoid it:**

```sql
-- Create a dedicated schema (recommended)
CREATE SCHEMA rrule;

-- Run installation as regular user
\c mydb regular_user
-- Then run SQL.install

-- Grant usage to application user
GRANT USAGE ON SCHEMA rrule TO app_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA rrule TO app_user;
```

### What Functions Can Do

The installed functions:
- ✅ **CAN:** Generate date sequences (read-only computation)
- ✅ **CAN:** Parse RRULE strings (string processing)
- ❌ **CANNOT:** Access your tables (no SELECT/INSERT/UPDATE/DELETE)
- ❌ **CANNOT:** Make network calls (no external connections)
- ❌ **CANNOT:** Execute arbitrary SQL (no `EXECUTE` statements)

All functions are marked `IMMUTABLE` or `STABLE` - they're pure computation.

---

## Security Checklist

### For Users

- [ ] Review the SQL before running (it's transparent!)
- [ ] Pin exact version in package.json
- [ ] Use package-lock.json
- [ ] Verify checksums (optional but recommended)
- [ ] Install in non-superuser schema if possible
- [ ] Review git commit history before updates
- [ ] Subscribe to security advisories (GitHub watch)

### For Maintainers

- [ ] Sign git commits with GPG
- [ ] Enable 2FA on NPM account
- [ ] Use `npm publish --provenance` when publishing
- [ ] Update CHECKSUMS.txt for each release
- [ ] Tag releases with signed git tags
- [ ] Never commit secrets or credentials
- [ ] Keep dependencies at zero (minimize attack surface)

---

## Vulnerability Reporting

If you discover a security vulnerability:

1. **DO NOT** open a public issue
2. Open a GitHub Security Advisory at https://github.com/sirrodgepodge/rrule_plpgsql/security/advisories
3. Include:
   - Description of vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We will respond within 48 hours and provide a fix within 7 days for critical issues.

---

## Security Features of Raw SQL Approach

### Why Raw SQL is More Secure Than "Magic" Helpers

**Transparency:**
```javascript
// You see EXACTLY what runs
const { SQL } = require('rrule-plpgsql');
console.log(SQL.install);  // Inspect before running
await client.query(SQL.install);
```

**vs. Hidden Abstraction:**
```javascript
// What does this do? You don't know!
await magicInstaller.install(client);
```

**No Auto-Detection Bugs:**
- No conditional logic based on client type
- No "guessing" which method to call
- No runtime surprises

**Explicit Control:**
- You control which SQL runs
- You control when it runs
- You control how it runs
- You can add your own validation

---

## NPM Security Features

When we publish with `npm publish --provenance`:

- **Provenance:** Proves package was built from this GitHub repo
- **Signature:** NPM cryptographically signs the package
- **Audit:** `npm audit` will catch known vulnerabilities (we have zero dependencies)

---

## Comparison to Alternatives

| Approach | Security Risk | Transparency | Auditability |
|----------|---------------|--------------|--------------|
| **Raw SQL (ours)** | Low - inspectable, static | Full | Easy |
| C Extension | High - binary, complex | None | Hard |
| Magic Helpers | Medium - hidden logic | Partial | Medium |
| Copy-paste SQL | Low - but versioning issues | Full | Easy |

---

## Additional Resources

- [NPM Security Best Practices](https://docs.npmjs.com/packages-and-modules/securing-your-code)
- [OWASP SQL Injection Prevention](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html)
- [PostgreSQL Security](https://www.postgresql.org/docs/current/sql-security.html)

---

## Summary

**Is this package secure?**

✅ Yes, because:
- Transparent (you can inspect all SQL)
- Static (no dynamic SQL generation)
- Zero dependencies (minimal attack surface)
- Auditable (small, readable codebase)
- No network calls or data access
- Pure computation (IMMUTABLE functions)

**Best practices:**
1. Review the SQL before running (seriously, it's readable!)
2. Pin exact versions
3. Verify checksums if paranoid (recommended for prod)
4. Use least privilege principle

**The raw SQL approach is actually MORE secure than magic helpers** because you maintain full control and visibility.
