import { Client } from "pg";
import { z } from "zod";
import {
  applyMonetizationSchemaReconciliation,
  monetizationReconciliationApprovalToken
} from "./monetization-schema-reconciliation.runner";

const operatorEnvironmentSchema = z.object({
  COORDIT_SCHEMA_RECONCILIATION_APPROVAL: z.literal(monetizationReconciliationApprovalToken)
});

const run = async (): Promise<void> => {
  const environment = operatorEnvironmentSchema.parse(process.env);
  const client = new Client();
  await client.connect();
  try {
    const result = await applyMonetizationSchemaReconciliation(
      client,
      environment.COORDIT_SCHEMA_RECONCILIATION_APPROVAL
    );
    process.stdout.write([
      "monetization_reconciliation_runner status=committed",
      `filename=${result.migration_filename}`,
      `sha256=${result.migration_sha256}`,
      `disposition=${result.disposition}`,
      "connection=redacted"
    ].join("\n") + "\n");
  } finally {
    await client.end();
  }
};

void run().catch((error: unknown) => {
  const category = error instanceof z.ZodError ? "approval_required" : "transaction_failed";
  process.stderr.write(`monetization_reconciliation_runner status=failed category=${category}\n`);
  process.exit(1);
});
