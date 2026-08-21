import assert from "node:assert/strict";
import { X509Certificate } from "node:crypto";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawn } from "node:child_process";
import { rootCertificates } from "node:tls";
import { Client } from "pg";
import { z } from "zod";
import { createVerifiedOperatorPgClient } from "./monetization-schema-reconciliation.operator-pg-client";

const validApprovalToken = "coordit-monetization-schema-reconciliation-20260822" as const;
const nonCaCertificate = `-----BEGIN CERTIFICATE-----
MIICxjCCAa4CCQCAsWF19lh/jzANBgkqhkiG9w0BAQsFADAlMSMwIQYDVQQDDBpj
b29yZGl0LWxvY2FsLWxlYWYtZml4dHVyZTAeFw0yNjA4MjExMjEwMzlaFw0zNjA4
MTgxMjEwMzlaMCUxIzAhBgNVBAMMGmNvb3JkaXQtbG9jYWwtbGVhZi1maXh0dXJl
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA36Qqa+Y2lVRAAbGaoAUP
669mSNAt1Gezt1JQq52+SpO1hHkP9h8jGXtfCfDL0bn/FkHw/PCzYpG/filh8cCx
gCNexdCgUiO2pfHt8Ap9qnX+39y7VNzp5qRFJynkTlnvoiHsWjxOLkZQTYPphFwj
2oGKAeIDfUbkBvHn5A+HmUx8ckU6ClGDnVGlolxOwc6IiJiue/FzdMAp6HJLcpJO
PsCZFlTiP9BOqXhzajCRQrCeTOzzmcJ4QrMiT2N9ZBq+AIrfwKxd7ei/kieLupsd
g7u52UQpkMc0jNoI3F66BlmNf+5vAYPhPMKeKK+q9ffgye/8ea+polbUpFSX1sAT
swIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQDe/f3RaqkSysxUXoPrVz21XPyKBaA6
iKuVxW8QkMT305mTjJrsPhiGDq1A+zSO++n4b41zfB6X3qFhpzssdTPVMPDFR3mO
Qq6ZzexRQAFbx83iOC7DBMj+RV+HwBeHgek3STAq1boylMCU8yvzIzHcLQn5AH+/
oVM8hNmhMVulyx4qHfGx+Wz8FN4gTo/mMI6/aZaiQ9h2BzQhwFlGeJwr91ebe54r
XC6IdHvDhsGyhtNlvMAjDw52w6FRqEXtmXQfHeqpq5uy5rZHgvbRogPXZQSmz0XZ
dwInoB4wlI9+ZCAIQaDo79sN4yRvNE3YeNffL4/gTaeoN9LfuSdAjTON
-----END CERTIFICATE-----
`;

type CliProbeResult = {
  readonly connectionCount: number;
  readonly exitCode: number | null;
  readonly stderr: string;
};

type CliProbeInput = {
  readonly approvalToken?: string;
  readonly caPath?: string;
};

const runRejectedCaProbe = async (input: CliProbeInput): Promise<CliProbeResult> => {
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
      throw new TypeError("TLS probe did not receive a loopback port");
    }
    const environment: NodeJS.ProcessEnv = {
      ...process.env,
      PGHOST: "127.0.0.1",
      PGPORT: String(address.port),
      PGUSER: "operator-probe",
      PGPASSWORD: "redacted-probe-value",
      PGDATABASE: "operator-probe",
      PGSSLMODE: "require",
      PGCONNECT_TIMEOUT: "1"
    };
    if (input.caPath === undefined) {
      delete environment.PGSSLROOTCERT;
    } else {
      environment.PGSSLROOTCERT = input.caPath;
    }
    if (input.approvalToken === undefined) {
      delete environment.COORDIT_SCHEMA_RECONCILIATION_APPROVAL;
    } else {
      environment.COORDIT_SCHEMA_RECONCILIATION_APPROVAL = input.approvalToken;
    }

    const child = spawn(
      resolve(process.cwd(), "node_modules", ".bin", "tsx"),
      ["src/modules/thread-wallet/monetization-schema-reconciliation.runner.cli.ts"],
      { cwd: process.cwd(), env: environment, stdio: ["ignore", "ignore", "pipe"] }
    );
    const stderrChunks: Buffer[] = [];
    child.stderr.on("data", (chunk: Buffer) => stderrChunks.push(chunk));
    const exitCode = await new Promise<number | null>((resolvePromise, rejectPromise) => {
      child.once("error", rejectPromise);
      child.once("close", resolvePromise);
    });
    return {
      connectionCount,
      exitCode,
      stderr: Buffer.concat(stderrChunks).toString("utf8").trim()
    };
  } finally {
    await new Promise<void>((resolvePromise, rejectPromise) => {
      server.close((error) => error ? rejectPromise(error) : resolvePromise());
    });
  }
};

const run = async (): Promise<void> => {
  const fixtureDirectory = await mkdtemp(join(tmpdir(), "coordit-operator-ca-test-"));
  try {
    const malformedCaPath = join(fixtureDirectory, "malformed-ca.pem");
    await writeFile(malformedCaPath, "not a certificate\n", { mode: 0o600 });
    const nonCaPath = join(fixtureDirectory, "non-ca.pem");
    await writeFile(nonCaPath, nonCaCertificate, { mode: 0o600 });
    const unreadableCaPath = join(fixtureDirectory, "does-not-exist.pem");
    const certificateAuthority = rootCertificates.find(
      (pem) => new X509Certificate(pem).ca
    );
    if (certificateAuthority === undefined) {
      throw new TypeError("Node did not provide a root CA test fixture");
    }
    const validCaPath = join(fixtureDirectory, "valid-ca.pem");
    await writeFile(validCaPath, certificateAuthority, { mode: 0o600 });

    const missing = await runRejectedCaProbe({ approvalToken: validApprovalToken });
    const malformed = await runRejectedCaProbe({
      approvalToken: validApprovalToken,
      caPath: malformedCaPath
    });
    const unreadable = await runRejectedCaProbe({
      approvalToken: validApprovalToken,
      caPath: unreadableCaPath
    });
    const nonCa = await runRejectedCaProbe({
      approvalToken: validApprovalToken,
      caPath: nonCaPath
    });
    const missingApproval = await runRejectedCaProbe({ caPath: validCaPath });
    const invalidApproval = await runRejectedCaProbe({
      approvalToken: "invalid-approval-token",
      caPath: validCaPath
    });
    process.stdout.write(
      [
        `operator_tls_rejection missing=${missing.connectionCount}`,
        `malformed=${malformed.connectionCount}`,
        `unreadable=${unreadable.connectionCount}`,
        `non_ca=${nonCa.connectionCount}`,
        `missing_approval=${missingApproval.connectionCount}`,
        `invalid_approval=${invalidApproval.connectionCount}`
      ].join(" ") + "\n"
    );
    assert.deepEqual(
      [
        missing.connectionCount,
        malformed.connectionCount,
        unreadable.connectionCount,
        nonCa.connectionCount,
        missingApproval.connectionCount,
        invalidApproval.connectionCount
      ],
      [0, 0, 0, 0, 0, 0],
      "operator configuration must be rejected before a TCP connection"
    );
    assert.deepEqual(
      [missing.exitCode, malformed.exitCode, unreadable.exitCode, nonCa.exitCode],
      [1, 1, 1, 1]
    );
    assert.deepEqual(
      [missing.stderr, malformed.stderr, unreadable.stderr, nonCa.stderr],
      [
        "monetization_reconciliation_runner status=failed category=operator_tls_configuration",
        "monetization_reconciliation_runner status=failed category=operator_tls_configuration",
        "monetization_reconciliation_runner status=failed category=operator_tls_configuration",
        "monetization_reconciliation_runner status=failed category=operator_tls_configuration"
      ]
    );
    assert.deepEqual(
      [missingApproval.exitCode, invalidApproval.exitCode],
      [1, 1]
    );
    assert.deepEqual(
      [missingApproval.stderr, invalidApproval.stderr],
      [
        "monetization_reconciliation_runner status=failed category=approval_required",
        "monetization_reconciliation_runner status=failed category=approval_required"
      ]
    );

    const client = await createVerifiedOperatorPgClient({ PGSSLROOTCERT: validCaPath });
    assert.ok(client instanceof Client);
    z.object({
      connectionParameters: z.object({
        ssl: z.object({
          ca: z.literal(certificateAuthority),
          rejectUnauthorized: z.literal(true)
        })
      }),
      _connected: z.literal(false),
      _connecting: z.literal(false)
    }).parse(client);
    process.stdout.write("operator_tls_client verified=true connected=false\n");
  } finally {
    await rm(fixtureDirectory, { recursive: true, force: true });
  }
};

void run().catch((error: unknown) => {
  if (error instanceof Error) {
    process.stderr.write(`${error.name}: ${error.message}\n`);
  } else {
    process.stderr.write("Unknown operator TLS test error\n");
  }
  process.exit(1);
});
