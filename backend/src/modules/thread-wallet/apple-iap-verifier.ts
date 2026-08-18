import { readFile } from "node:fs/promises";
import { Environment, SignedDataVerifier, Type, VerificationException } from "@apple/app-store-server-library";
import { z } from "zod";
import { env } from "../../config/env";
import { createHttpError } from "../../shared/utils/http-error";
import type { AppleIapVerifiedTransaction } from "./thread-wallet.service";

type AppleIapVerifierConfiguration = {
  readonly appAppleId: number;
  readonly bundleId: string;
  readonly rootCertificatePaths: readonly string[];
};

type AppleTransactionVerifier = {
  readonly verify: (signedTransaction: string) => Promise<AppleIapVerifiedTransaction>;
};

const appleTransactionSchema = z.object({
  transactionId: z.string().min(1),
  originalTransactionId: z.string().min(1),
  productId: z.string().min(1),
  appAccountToken: z.string().uuid(),
  purchaseDate: z.number().int().positive().max(8_640_000_000_000_000),
  environment: z.enum(["Sandbox", "Production"]),
  quantity: z.literal(1).optional(),
  revocationDate: z.never().optional(),
  type: z.literal(Type.CONSUMABLE)
});

const verifierConfiguration = (): AppleIapVerifierConfiguration => {
  if (!env.appleIapAppAppleId || env.appleIapRootCertificatePaths.length === 0) {
    throw createHttpError(503, "Apple 인앱결제 검증 설정이 아직 완료되지 않았어요.");
  }
  return {
    appAppleId: env.appleIapAppAppleId,
    bundleId: env.appleIapBundleId,
    rootCertificatePaths: env.appleIapRootCertificatePaths
  };
};

const parseVerifiedTransaction = (payload: unknown): AppleIapVerifiedTransaction => {
  const parsed = appleTransactionSchema.safeParse(payload);
  if (!parsed.success) {
    throw createHttpError(400, "Apple 구매 거래 정보를 확인할 수 없어요.");
  }
  return {
    transactionId: parsed.data.transactionId,
    originalTransactionId: parsed.data.originalTransactionId,
    productId: parsed.data.productId,
    appAccountToken: parsed.data.appAccountToken.toLowerCase(),
    purchasedAt: new Date(parsed.data.purchaseDate).toISOString(),
    environment: parsed.data.environment
  };
};

const createAppleTransactionVerifier = async (): Promise<AppleTransactionVerifier> => {
  const configuration = verifierConfiguration();
  const rootCertificates = await Promise.all(
    configuration.rootCertificatePaths.map((path) => readFile(path))
  );
  const productionVerifier = new SignedDataVerifier(
    rootCertificates,
    true,
    Environment.PRODUCTION,
    configuration.bundleId,
    configuration.appAppleId
  );
  const sandboxVerifier = new SignedDataVerifier(
    rootCertificates,
    true,
    Environment.SANDBOX,
    configuration.bundleId
  );

  return {
    verify: async (signedTransaction: string): Promise<AppleIapVerifiedTransaction> => {
      try {
        return parseVerifiedTransaction(
          await productionVerifier.verifyAndDecodeTransaction(signedTransaction)
        );
      } catch (error) {
        if (!(error instanceof VerificationException)) throw error;
      }

      try {
        return parseVerifiedTransaction(
          await sandboxVerifier.verifyAndDecodeTransaction(signedTransaction)
        );
      } catch (error) {
        if (error instanceof VerificationException) {
          throw createHttpError(400, "Apple 구매 거래를 검증할 수 없어요.");
        }
        throw error;
      }
    }
  };
};

let appleTransactionVerifier: Promise<AppleTransactionVerifier> | null = null;

const activeAppleTransactionVerifier = (): Promise<AppleTransactionVerifier> => {
  if (!appleTransactionVerifier) {
    appleTransactionVerifier = createAppleTransactionVerifier();
  }
  return appleTransactionVerifier;
};

export const verifyAppleTransaction = async (
  signedTransaction: string
): Promise<AppleIapVerifiedTransaction> => {
  return (await activeAppleTransactionVerifier()).verify(signedTransaction);
};
