declare module "embedded-postgres" {
  import type { Client } from "pg";

  type EmbeddedPostgresOptions = {
    readonly databaseDir: string;
    readonly port: number;
    readonly user: string;
    readonly password: string;
    readonly authMethod: "scram-sha-256" | "password" | "md5";
    readonly persistent: boolean;
    readonly postgresFlags: readonly string[];
    readonly onLog: (message: string) => void;
    readonly onError: (error: unknown) => void;
  };

  export default class EmbeddedPostgres {
    constructor(options: Partial<EmbeddedPostgresOptions>);
    initialise(): Promise<void>;
    start(): Promise<void>;
    stop(): Promise<void>;
    getPgClient(database?: string, host?: string): Client;
  }
}
