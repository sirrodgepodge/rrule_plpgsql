/**
 * rrule-plpgsql - Pure PL/pgSQL RFC 5545 RRULE implementation
 *
 * This package exports SQL as strings, making it compatible with
 * any PostgreSQL client (pg, TypeORM, Prisma, Knex, Sequelize, etc.)
 *
 * Philosophy: Export SQL strings, not opinions.
 * Users call their client's method directly - no magic, no auto-detection.
 *
 * @license MIT
 */

const fs = require('fs');
const path = require('path');

/**
 * Raw SQL strings for all components
 *
 * Use these with your preferred PostgreSQL client's query method:
 * - pg: await client.query(SQL.install)
 * - TypeORM: await queryRunner.query(SQL.install)
 * - Prisma: await prisma.$executeRawUnsafe(SQL.install)
 * - Knex: await knex.raw(SQL.install)
 * - Sequelize: await sequelize.query(SQL.install)
 */
const SQL = {
  /** Complete installation SQL (includes all RRULE functions) */
  install: fs.readFileSync(path.join(__dirname, 'src/install.sql'), 'utf8'),

  /** Installation with sub-day frequency support (HOURLY, MINUTELY, SECONDLY) */
  installWithSubday: fs.readFileSync(path.join(__dirname, 'src/install_with_subday.sql'), 'utf8'),

  /** Core RRULE implementation with RFC 5545 & RFC 7529 compliance and public API */
  rrule: fs.readFileSync(path.join(__dirname, 'src/rrule.sql'), 'utf8'),
};

module.exports = { SQL };

// ES Module support
module.exports.default = { SQL };
