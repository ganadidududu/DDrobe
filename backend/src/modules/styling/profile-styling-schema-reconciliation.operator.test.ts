import assert from "node:assert/strict";
import { X509Certificate } from "node:crypto";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawn } from "node:child_process";
import { rootCertificates } from "node:tls";
import { profileStylingReconciliationApprovalToken } from "./profile-styling-schema-reconciliation.runner";

type RunnerProbeInput = {
  readonly approvalToken?: string;
  readonly caPath?: string;
};

type RunnerProbeResult = {
  readonly connectionCount: number;
  readonly exitCode: number | null;
  readonly stderr: string;
  readonly stdout: string;
};

const runRejectedRunner = async (
  input: RunnerProbeInput
): Promise<RunnerProbeResult> => {
  let connectionCount = 0;
  const server = createServer((socket) => {
    connectionCount += 1;
    socket.destroy();
  });
  await new Promise<void>((resolvePromise, rejectPromise) => {
    server.once("error", rejectPromise);
    server.listen(0, "127.0.0.1", resolvePromise);
  });

  try {
    const address = server.address();
    if (address === null || typeof address === "string") {
      throw new TypeError("Operator runner test did not receive a loopback port");
    }
    const environment: NodeJS.ProcessEnv = {
      ...process.env,
      PGHOST: "127.0.0.1",
      PGPORT: String(address.port),
      PGUSER: "operator-test",
      PGPASSWORD: "redacted-test-value",
      PGDATABASE: "operator-test",
      PGSSLMODE: "verify-full",
      PGCONNECT_TIMEOUT: "1"
    };
    if (input.caPath === undefined) {
      delete environment.PGSSLROOTCERT;
    } else {
      environment.PGSSLROOTCERT = input.caPath;
    }
    if (input.approvalToken === undefined) {
      delete environment.COORDIT_PROFILE_STYLING_SCHEMA_RECONCILIATION_APPROVAL;
    } else {
      environment.COORDIT_PROFILE_STYLING_SCHEMA_RECONCILIATION_APPROVAL =
        input.approvalToken;
    }

    const child = spawn(
      resolve(process.cwd(), "node_modules", ".bin", "tsx"),
      ["src/modules/styling/profile-styling-schema-reconciliation.runner.cli.ts"],
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
      connectionCount,
      exitCode,
      stderr: Buffer.concat(stderrChunks).toString("utf8").trim(),
      stdout: Buffer.concat(stdoutChunks).toString("utf8").trim()
    };
  } finally {
    await new Promise<void>((resolvePromise, rejectPromise) => {
      server.close((error) => error ? rejectPromise(error) : resolvePromise());
    });
  }
};

const run = async (): Promise<void> => {
  // Given: valid, malformed, missing, and unreadable operator CA inputs.
  const fixtureDirectory = await mkdtemp(join(tmpdir(), "coordit-profile-styling-ca-"));
  try {
    const malformedCaPath = join(fixtureDirectory, "malformed-ca.pem");
    await writeFile(malformedCaPath, "not a certificate\n", { mode: 0o600 });
    const unreadableCaPath = join(fixtureDirectory, "absent-ca.pem");
    const certificateAuthority = rootCertificates.find(
      (pem) => new X509Certificate(pem).ca
    );
    if (certificateAuthority === undefined) {
      throw new TypeError("Node did not provide a root CA test fixture");
    }
    const validCaPath = join(fixtureDirectory, "valid-ca.pem");
    await writeFile(validCaPath, certificateAuthority, { mode: 0o600 });

    // When: the real apply CLI receives each invalid approval/CA boundary input.
    const missingApproval = await runRejectedRunner({ caPath: validCaPath });
    const invalidApproval = await runRejectedRunner({
      approvalToken: "invalid-approval-token",
      caPath: validCaPath
    });
    const missingCa = await runRejectedRunner({
      approvalToken: profileStylingReconciliationApprovalToken
    });
    const malformedCa = await runRejectedRunner({
      approvalToken: profileStylingReconciliationApprovalToken,
      caPath: malformedCaPath
    });
    const unreadableCa = await runRejectedRunner({
      approvalToken: profileStylingReconciliationApprovalToken,
      caPath: unreadableCaPath
    });

    // Then: every invalid boundary fails before TCP and emits only allowlisted output.
    const results = [
      missingApproval,
      invalidApproval,
      missingCa,
      malformedCa,
      unreadableCa
    ];
    assert.deepEqual(results.map((result) => result.connectionCount), [0, 0, 0, 0, 0]);
    assert.deepEqual(results.map((result) => result.exitCode), [1, 1, 1, 1, 1]);
    assert.deepEqual(results.map((result) => result.stdout), ["", "", "", "", ""]);
    assert.deepEqual(results.map((result) => result.stderr), [
      "profile_styling_reconciliation_runner status=failed category=approval_required",
      "profile_styling_reconciliation_runner status=failed category=approval_required",
      "profile_styling_reconciliation_runner status=failed category=operator_tls_configuration",
      "profile_styling_reconciliation_runner status=failed category=operator_tls_configuration",
      "profile_styling_reconciliation_runner status=failed category=operator_tls_configuration"
    ]);
  } finally {
    await rm(fixtureDirectory, { recursive: true, force: true });
  }

  process.stdout.write([
    "profile_styling_operator_guard assertions=pass",
    "approval=missing-and-invalid-rejected-before-tcp",
    "ca=missing-malformed-unreadable-rejected-before-tcp",
    "connections=0",
    "outputs=allowlisted-and-redacted",
    "cleanup=temporary-ca-fixtures-removed"
  ].join("\n") + "\n");
};

void run().catch((error: unknown) => {
  if (error instanceof Error) {
    process.stderr.write(`${error.name}: ${error.message}\n`);
  } else {
    process.stderr.write("Unknown profile/styling operator guard test failure\n");
  }
  process.exit(1);
});
