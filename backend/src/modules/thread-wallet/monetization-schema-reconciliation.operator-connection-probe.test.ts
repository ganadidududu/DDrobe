import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { executeOperatorConnectionProbe } from "./monetization-schema-reconciliation.operator-connection-probe";

type CliResult = {
  readonly exitCode: number | null;
  readonly stderr: string;
  readonly stdout: string;
};

class SensitiveProbeFailure extends Error {
  readonly name = "SensitiveProbeFailure";

  constructor() {
    super("postgres://operator:credential@private-host/database");
  }
}

const runExactPackageCommand = async (): Promise<CliResult> => {
  const environment: NodeJS.ProcessEnv = { ...process.env };
  delete environment.COORDIT_SCHEMA_RECONCILIATION_APPROVAL;
  delete environment.PGSSLROOTCERT;

  const child = spawn(
    "npm",
    ["run", "--silent", "probe:monetization-schema-reconciliation:connection"],
    { cwd: process.cwd(), env: environment, stdio: ["ignore", "pipe", "pipe"] }
  );
  const stderrChunks: Buffer[] = [];
  const stdoutChunks: Buffer[] = [];
  child.stderr.on("data", (chunk: Buffer) => stderrChunks.push(chunk));
  child.stdout.on("data", (chunk: Buffer) => stdoutChunks.push(chunk));
  const exitCode = await new Promise<number | null>((resolvePromise, rejectPromise) => {
    child.once("error", rejectPromise);
    child.once("close", resolvePromise);
  });
  return {
    exitCode,
    stderr: Buffer.concat(stderrChunks).toString("utf8").trim(),
    stdout: Buffer.concat(stdoutChunks).toString("utf8").trim()
  };
};

const assertExactCliFailure = async (): Promise<void> => {
  const result = await runExactPackageCommand();
  assert.equal(result.exitCode, 1);
  assert.equal(result.stdout, "");
  assert.equal(
    result.stderr,
    "monetization_connection_probe status=failed category=operator_tls_configuration"
  );
};

const assertConnectionOnlySuccess = async (): Promise<void> => {
  const operatorEnvironment = { PGSSLROOTCERT: "unused-by-test-factory" };
  const events: string[] = [];
  const stderrLines: string[] = [];
  const stdoutLines: string[] = [];
  let queryCalls = 0;
  const client = {
    connect: async (): Promise<void> => {
      events.push("connect");
    },
    end: async (): Promise<void> => {
      events.push("end");
    },
    query: async (): Promise<void> => {
      queryCalls += 1;
    }
  };

  const exitCode = await executeOperatorConnectionProbe(operatorEnvironment, {
    createClient: async (rawEnvironment: unknown) => {
      assert.equal(rawEnvironment, operatorEnvironment);
      events.push("factory");
      return client;
    },
    writeStderr: (line: string) => {
      stderrLines.push(line);
    },
    writeStdout: (line: string) => {
      stdoutLines.push(line);
    }
  });

  assert.equal(exitCode, 0);
  assert.deepEqual(events, ["factory", "connect", "end"]);
  assert.equal(queryCalls, 0);
  assert.deepEqual(stdoutLines, ["monetization_connection_probe status=connected\n"]);
  assert.deepEqual(stderrLines, []);
};

const assertConnectionFailureIsRedacted = async (): Promise<void> => {
  const stderrLines: string[] = [];
  const stdoutLines: string[] = [];
  const exitCode = await executeOperatorConnectionProbe({}, {
    createClient: async () => {
      throw new SensitiveProbeFailure();
    },
    writeStderr: (line: string) => {
      stderrLines.push(line);
    },
    writeStdout: (line: string) => {
      stdoutLines.push(line);
    }
  });

  assert.equal(exitCode, 1);
  assert.deepEqual(stdoutLines, []);
  assert.deepEqual(stderrLines, [
    "monetization_connection_probe status=failed category=connection_failed\n"
  ]);
};

const run = async (): Promise<void> => {
  await assertConnectionOnlySuccess();
  await assertConnectionFailureIsRedacted();
  await assertExactCliFailure();
  process.stdout.write(
    "operator_connection_probe events=factory/connect/end query_calls=0 outputs=allowlisted\n"
  );
};

void run().catch((error: unknown) => {
  if (error instanceof Error) {
    process.stderr.write(`${error.name}: ${error.message}\n`);
  } else {
    process.stderr.write("Unknown connection probe test error\n");
  }
  process.exit(1);
});
