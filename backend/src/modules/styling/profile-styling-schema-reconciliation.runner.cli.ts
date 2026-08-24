import { z } from "zod";
import {
  createVerifiedOperatorPgClient,
  OperatorTlsConfigurationError
} from "../thread-wallet/monetization-schema-reconciliation.operator-pg-client";
import {
  applyProfileStylingSchemaReconciliation,
  profileStylingReconciliationApprovalToken
} from "./profile-styling-schema-reconciliation.runner";

const operatorEnvironmentSchema = z.object({
  COORDIT_PROFILE_STYLING_SCHEMA_RECONCILIATION_APPROVAL: z.literal(
    profileStylingReconciliationApprovalToken
  )
});

class OperatorApprovalRequiredError extends Error {
  readonly name = "OperatorApprovalRequiredError";

  constructor(options?: ErrorOptions) {
    super("profile/styling schema operator approval is required", options);
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
    const result = await applyProfileStylingSchemaReconciliation(
      client,
      environment.COORDIT_PROFILE_STYLING_SCHEMA_RECONCILIATION_APPROVAL
    );
    process.stdout.write([
      "profile_styling_reconciliation_runner status=committed",
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
    `profile_styling_reconciliation_runner status=failed category=${category}\n`
  );
  process.exit(1);
});
