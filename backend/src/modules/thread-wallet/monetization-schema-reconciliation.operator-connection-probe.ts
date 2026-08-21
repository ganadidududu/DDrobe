import {
  createVerifiedOperatorPgClient,
  OperatorTlsConfigurationError
} from "./monetization-schema-reconciliation.operator-pg-client";

type ConnectionOnlyClient = {
  readonly connect: () => Promise<unknown>;
  readonly end: () => Promise<void>;
};
type OperatorPgClientFactory = (rawEnvironment: unknown) => Promise<ConnectionOnlyClient>;

type OperatorConnectionProbeDependencies = {
  readonly createClient: OperatorPgClientFactory;
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

export const executeOperatorConnectionProbe = async (
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
      `monetization_connection_probe status=failed category=${category}\n`
    );
    return 1;
  }
  dependencies.writeStdout("monetization_connection_probe status=connected\n");
  return 0;
};
