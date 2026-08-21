import { randomBytes } from "node:crypto";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import EmbeddedPostgres from "embedded-postgres";
import type { Client } from "pg";

export const admobDatabaseMigrations = [
  "20260730_add_thread_wallet.sql",
  "20260806_add_fit_report_thread_charge.sql",
  "20260809_add_apple_iap_thread_credit.sql",
  "20260811_add_admob_rewarded_ssv.sql",
  "20260814_harden_admob_reward_atomicity.sql"
] as const;

export type DatabaseRole = "anon" | "authenticated" | "service_role";

export type DisposableAdmobDatabase = {
  readonly client: Client;
  readonly appliedMigrations: readonly string[];
  readonly databaseKind: "embedded-postgres";
  readonly openClient: () => Promise<Client>;
  readonly stop: () => Promise<void>;
};

const bootstrapSql = `
  create extension if not exists pgcrypto;
  create role anon nologin;
  create role authenticated nologin;
  create role service_role nologin bypassrls;

  create table public.users (
    id uuid primary key
  );

  create table public.fit_analysis_results (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.users(id) on delete cascade
  );

  create table public.recommendation_logs (
    id uuid primary key default gen_random_uuid()
  );
`;

const reserveLoopbackPort = async (): Promise<number> => {
  const server = createServer();
  await new Promise<void>((resolvePromise, rejectPromise) => {
    server.once("error", rejectPromise);
    server.listen(0, "127.0.0.1", resolvePromise);
  });

  const address = server.address();
  if (address === null || typeof address === "string") {
    server.close();
    throw new TypeError("Embedded Postgres did not receive a TCP port");
  }

  await new Promise<void>((resolvePromise, rejectPromise) => {
    server.close((error) => {
      if (error) {
        rejectPromise(error);
        return;
      }
      resolvePromise();
    });
  });
  return address.port;
};

const applyMigrations = async (client: Client): Promise<readonly string[]> => {
  const migrationDirectory = resolve(process.cwd(), "..", "supabase", "migrations");
  const appliedMigrations: string[] = [];

  for (const migrationName of admobDatabaseMigrations) {
    const sql = await readFile(join(migrationDirectory, migrationName), "utf8");
    await client.query(sql);
    appliedMigrations.push(migrationName);
  }

  return appliedMigrations;
};

export const withDatabaseRole = async <T>(
  client: Client,
  role: DatabaseRole,
  operation: (roleClient: Client) => Promise<T>
): Promise<T> => {
  await client.query("begin");
  try {
    await client.query(`set local role ${role}`);
    const result = await operation(client);
    await client.query("commit");
    return result;
  } catch (error) {
    await client.query("rollback");
    throw error;
  }
};

export const startDisposableAdmobDatabase = async (): Promise<DisposableAdmobDatabase> => {
  const databaseDirectory = await mkdtemp(join(tmpdir(), "coordit-admob-reward-db-"));
  const port = await reserveLoopbackPort();
  const postgres = new EmbeddedPostgres({
    databaseDir: databaseDirectory,
    port,
    user: "postgres",
    password: randomBytes(32).toString("base64url"),
    authMethod: "scram-sha-256",
    persistent: false,
    postgresFlags: ["-h", "127.0.0.1"],
    onLog: () => undefined,
    onError: () => undefined
  });

  let client: Client | undefined;
  let started = false;
  try {
    await postgres.initialise();
    await postgres.start();
    started = true;
    const connectedClient = postgres.getPgClient();
    client = connectedClient;
    await connectedClient.connect();
    await connectedClient.query(bootstrapSql);
    const appliedMigrations = await applyMigrations(connectedClient);
    /** Additional clients exist only to exercise real concurrent transactions. */
    const additionalClients: Client[] = [];

    return {
      client: connectedClient,
      appliedMigrations,
      databaseKind: "embedded-postgres",
      openClient: async () => {
        const additionalClient = postgres.getPgClient();
        await additionalClient.connect();
        additionalClients.push(additionalClient);
        return additionalClient;
      },
      stop: async () => {
        await Promise.all(additionalClients.map(async (additionalClient) => additionalClient.end()));
        await connectedClient.end();
        await postgres.stop();
        await rm(databaseDirectory, { recursive: true, force: true });
      }
    };
  } catch (error) {
    await client?.end();
    if (started) {
      await postgres.stop();
    }
    await rm(databaseDirectory, { recursive: true, force: true });
    throw error;
  }
};
