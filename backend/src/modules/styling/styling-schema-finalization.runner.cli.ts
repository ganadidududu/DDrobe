import { z } from "zod";
import {
  createVerifiedOperatorPgClient,
  OperatorTlsConfigurationError
} from "../thread-wallet/monetization-schema-reconciliation.operator-pg-client";
import {
  applyStylingSchemaFinalization,
  stylingSchemaFinalizationApprovalToken
} from "./styling-schema-finalization.runner";

const operatorEnvironmentSchema = z.object({
  COORDIT_STYLING_SCHEMA_FINALIZATION_APPROVAL: z.literal(
    stylingSchemaFinalizationApprovalToken
  )
});

class OperatorApprovalRequiredError extends Error {
  readonly name = "OperatorApprovalRequiredError";

  constructor(options?: ErrorOptions) {
    super("styling schema finalization approval is required", options);
  }
}

const run = async (): Promise<void> => {
  const environmentResult = operatorEnvironmentSchema.safeParse(process.env);
  if (!environmentResult.success) {
    throw new OperatorApprovalRequiredError({ cause: environmentResult.error });
  }
  const environment = environmentResult.data;
  const client = await createVerifiedOperatorPgClient(process.env);
  await client.connect();
  try {
    const result = await applyStylingSchemaFinalization(
      client,
      environment.COORDIT_STYLING_SCHEMA_FINALIZATION_APPROVAL
    );
    process.stdout.write([
      "styling_schema_finalization_runner status=committed",
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
  const category = error instanceof OperatorApprovalRequiredError
    ? "approval_required"
    : error instanceof OperatorTlsConfigurationError
      ? "operator_tls_configuration"
      : "transaction_failed";
  process.stderr.write(
    `styling_schema_finalization_runner status=failed category=${category}\n`
  );
  process.exit(1);
});
