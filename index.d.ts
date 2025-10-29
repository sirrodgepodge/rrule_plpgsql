/**
 * Raw SQL strings for all RRULE components
 *
 * Philosophy: Export SQL strings, not opinions.
 * Users call their client's method directly - no magic, no auto-detection.
 *
 * @example
 * ```typescript
 * // node-postgres (pg)
 * import { Client } from 'pg';
 * import { SQL } from 'rrule-plpgsql';
 *
 * const client = new Client();
 * await client.connect();
 * await client.query(SQL.install);
 * ```
 *
 * @example
 * ```typescript
 * // TypeORM
 * import { MigrationInterface, QueryRunner } from 'typeorm';
 * import { SQL } from 'rrule-plpgsql';
 *
 * export class InstallRRule implements MigrationInterface {
 *   async up(queryRunner: QueryRunner) {
 *     await queryRunner.query(SQL.install);
 *   }
 * }
 * ```
 *
 * @example
 * ```typescript
 * // Prisma
 * import { PrismaClient } from '@prisma/client';
 * import { SQL } from 'rrule-plpgsql';
 *
 * const prisma = new PrismaClient();
 * await prisma.$executeRawUnsafe(SQL.install);
 * ```
 *
 * @example
 * ```typescript
 * // Knex
 * import knex from 'knex';
 * import { SQL } from 'rrule-plpgsql';
 *
 * await knex.raw(SQL.install);
 * ```
 *
 * @example
 * ```typescript
 * // Sequelize
 * import { Sequelize } from 'sequelize';
 * import { SQL } from 'rrule-plpgsql';
 *
 * const sequelize = new Sequelize(/* config */);
 * await sequelize.query(SQL.install);
 * ```
 */
export const SQL: {
  /** Complete installation SQL (includes all RRULE functions) */
  install: string;
  /** Installation with sub-day frequency support (HOURLY, MINUTELY, SECONDLY) */
  installWithSubday: string;
  /** Core RRULE functions only (no schema setup - for advanced use cases) */
  core: string;
};

/**
 * Default export (same as named export)
 */
declare const defaultExport: { SQL: typeof SQL };
export default defaultExport;
