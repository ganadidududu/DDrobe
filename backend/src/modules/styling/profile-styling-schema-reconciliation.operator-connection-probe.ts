import {
  createVerifiedOperatorPgClient,
  OperatorTlsConfigurationError
} from "../thread-wallet/monetization-schema-reconciliation.operator-pg-client";

type ConnectionOnlyClient = {
  readonly connect: () => Promise<unknown>;
  readonly end: () => Promise<void>;
};

type OperatorConnectionProbeDependencies = {
  readonly createClient: (rawEnvironment: unknown) => Promise<ConnectionOnlyClient>;
  readonly writeStderr: (line: string) => void;
  readonly writeStdout: (line: string) => void;
};

const productionDependencies: OperatorConnectionProbeDependencies = {
  createClient: createVerifiedOperatorPgClient,
  writeStderr: (line: string) => {
    process.stderr.write(line);
  },
  writeStdout: (line: string) => {
    process.stdout.write(line);
  }
};

export const executeProfileStylingOperatorConnectionProbe = async (
  rawEnvironment: unknown,
  dependencies: OperatorConnectionProbeDependencies = productionDependencies
): Promise<0 | 1> => {
  try {
    const client = await dependencies.createClient(rawEnvironment);
    await client.connect();
    await client.end();
  } catch (error: unknown) {
    const category = error instanceof OperatorTlsConfigurationError
      ? "operator_tls_configuration"
      : "connection_failed";
    dependencies.writeStderr(
      `profile_styling_connection_probe status=failed category=${category}\n`
    );
    return 1;
  }
  dependencies.writeStdout("profile_styling_connection_probe status=connected\n");
  return 0;
};
