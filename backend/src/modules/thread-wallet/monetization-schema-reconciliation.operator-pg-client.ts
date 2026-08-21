import { X509Certificate } from "node:crypto";
import { readFile } from "node:fs/promises";
import { Client } from "pg";
import { z } from "zod";

const operatorTlsEnvironmentSchema = z.object({
  PGSSLROOTCERT: z.string().trim().min(1)
});

export class OperatorTlsConfigurationError extends Error {
  readonly name = "OperatorTlsConfigurationError";

  constructor(options?: ErrorOptions) {
    super("operator TLS configuration is invalid", options);
  }
}

const readCertificateAuthority = async (path: string): Promise<string> => {
  let pem: string;
  try {
    pem = await readFile(path, "utf8");
  } catch (error: unknown) {
    throw new OperatorTlsConfigurationError({ cause: error });
  }
  let certificate: X509Certificate;
  try {
    certificate = new X509Certificate(pem);
  } catch (error: unknown) {
    throw new OperatorTlsConfigurationError({ cause: error });
  }
  if (!certificate.ca) {
    throw new OperatorTlsConfigurationError();
  }
  return pem;
};

export const createVerifiedOperatorPgClient = async (
  rawEnvironment: unknown
): Promise<Client> => {
  const environmentResult = operatorTlsEnvironmentSchema.safeParse(rawEnvironment);
  if (!environmentResult.success) {
    throw new OperatorTlsConfigurationError({ cause: environmentResult.error });
  }
  const environment = environmentResult.data;
  const certificateAuthority = await readCertificateAuthority(environment.PGSSLROOTCERT);
  return new Client({
    ssl: {
      ca: certificateAuthority,
      rejectUnauthorized: true
    }
  });
};
