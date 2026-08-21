import assert from "node:assert/strict";
import {
  VerificationException,
  VerificationStatus
} from "@apple/app-store-server-library";
import {
  createAppleIapVerifier,
  type AppleSignedDataDecoder
} from "./apple-iap-verifier";

const accountToken = "845628bf-1362-4f64-937d-e947aa1d017f";
const notificationUUID = "07d46496-352a-4f53-b333-9511ba8f449b";
const configuration = {
  appAppleId: 123456789,
  bundleId: "com.inseong.coordit"
} as const;

const productionTransaction = {
  transactionId: "production-transaction",
  originalTransactionId: "production-original-transaction",
  bundleId: configuration.bundleId,
  productId: "com.inseong.coordit.thread.10",
  appAccountToken: accountToken,
  purchaseDate: Date.parse("2026-08-21T00:00:00.000Z"),
  environment: "Production",
  quantity: 1,
  type: "Consumable"
} as const;

const rejectingDecoder = (): AppleSignedDataDecoder => ({
  verifyAndDecodeNotification: async () => {
    throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE);
  },
  verifyAndDecodeTransaction: async () => {
    throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE);
  }
});

const decoderWith = (
  notificationPayload: unknown,
  transactionPayload: unknown
): AppleSignedDataDecoder => ({
  verifyAndDecodeNotification: async () => notificationPayload,
  verifyAndDecodeTransaction: async () => transactionPayload
});

const expectHttpStatus = async (
  operation: () => Promise<unknown>,
  statusCode: number
): Promise<void> => {
  await assert.rejects(operation, (error: unknown) => {
    return error instanceof Error && "statusCode" in error && error.statusCode === statusCode;
  });
};

const tests: readonly { readonly name: string; readonly run: () => Promise<void> }[] = [
  {
    name: "accepts an Apple-verified production consumable with the configured policy",
    run: async () => {
      // Given: the production Apple decoder verified a complete consumable transaction.
      const verifier = createAppleIapVerifier({
        configuration,
        decoders: {
          production: decoderWith({}, productionTransaction),
          sandbox: rejectingDecoder()
        }
      });

      // When: the backend verifies and parses the opaque client input.
      const transaction = await verifier.verifyTransaction("opaque-client-input");

      // Then: the trusted domain transaction preserves the exact product and environment.
      assert.deepEqual(transaction, {
        transactionId: productionTransaction.transactionId,
        originalTransactionId: productionTransaction.originalTransactionId,
        productId: productionTransaction.productId,
        appAccountToken: accountToken,
        purchasedAt: "2026-08-21T00:00:00.000Z",
        environment: "Production"
      });
    }
  },
  {
    name: "accepts Apple-verified Sandbox data after production verification rejects its environment",
    run: async () => {
      // Given: production verification rejects and Apple Sandbox verification succeeds.
      const sandboxTransaction = { ...productionTransaction, environment: "Sandbox" };
      const verifier = createAppleIapVerifier({
        configuration,
        decoders: {
          production: rejectingDecoder(),
          sandbox: decoderWith({}, sandboxTransaction)
        }
      });

      // When: the backend verifies the transaction for TestFlight or App Review.
      const transaction = await verifier.verifyTransaction("opaque-client-input");

      // Then: the Apple-signed Sandbox environment is retained for the ledger.
      assert.equal(transaction.environment, "Sandbox");
    }
  },
  ...[
    {
      name: "rejects an unknown product",
      payload: { ...productionTransaction, productId: "com.inseong.coordit.unknown" }
    },
    {
      name: "rejects a non-unit consumable quantity",
      payload: { ...productionTransaction, quantity: 2 }
    },
    {
      name: "rejects a revoked transaction",
      payload: { ...productionTransaction, revocationDate: Date.parse("2026-08-21T01:00:00.000Z") }
    },
    {
      name: "rejects a malformed app account token",
      payload: { ...productionTransaction, appAccountToken: "not-a-uuid" }
    },
    {
      name: "rejects a transaction for another bundle",
      payload: { ...productionTransaction, bundleId: "com.example.other" }
    }
  ].map(({ name, payload }) => ({
    name,
    run: async (): Promise<void> => {
      // Given: Apple decoding completed but a required Coordit transaction policy field is invalid.
      const verifier = createAppleIapVerifier({
        configuration,
        decoders: {
          production: decoderWith({}, payload),
          sandbox: rejectingDecoder()
        }
      });

      // When/Then: policy parsing rejects it before any settlement adapter receives the result.
      await expectHttpStatus(() => verifier.verifyTransaction("opaque-client-input"), 400);
    }
  })),
  {
    name: "verifies both the production V2 envelope and its nested transaction",
    run: async () => {
      // Given: Apple verified a production one-time-charge envelope for the configured app.
      let notificationCalls = 0;
      let transactionCalls = 0;
      const decoder: AppleSignedDataDecoder = {
        verifyAndDecodeNotification: async () => {
          notificationCalls += 1;
          return {
            notificationType: "ONE_TIME_CHARGE",
            notificationUUID,
            version: "2.0",
            data: {
              environment: "Production",
              appAppleId: configuration.appAppleId,
              bundleId: configuration.bundleId,
              signedTransactionInfo: "opaque-nested-input"
            }
          };
        },
        verifyAndDecodeTransaction: async () => {
          transactionCalls += 1;
          return productionTransaction;
        }
      };
      const verifier = createAppleIapVerifier({
        configuration,
        decoders: { production: decoder, sandbox: rejectingDecoder() }
      });

      // When: the V2 input is processed.
      const notification = await verifier.verifyNotification("opaque-notification-input");

      // Then: outer and nested signatures are each checked once before reconciliation.
      assert.equal(notificationCalls, 1);
      assert.equal(transactionCalls, 1);
      assert.equal(notification.kind, "reconcile");
      if (notification.kind === "reconcile") {
        assert.equal(notification.transaction.productId, productionTransaction.productId);
      }
    }
  },
  {
    name: "rejects a production notification with the wrong numeric Apple app ID",
    run: async () => {
      // Given: decoded notification claims identify another App Store app.
      const verifier = createAppleIapVerifier({
        configuration,
        decoders: {
          production: decoderWith({
            notificationType: "TEST",
            notificationUUID,
            version: "2.0",
            data: {
              environment: "Production",
              appAppleId: 987654321,
              bundleId: configuration.bundleId
            }
          }, productionTransaction),
          sandbox: rejectingDecoder()
        }
      });

      // When/Then: backend policy rejects the mismatched app before receipt persistence.
      await expectHttpStatus(() => verifier.verifyNotification("opaque-notification-input"), 400);
    }
  },
  {
    name: "rejects an invalid nested transaction signature as a bad provider request",
    run: async () => {
      // Given: Apple envelope verification succeeds but nested transaction verification fails.
      const decoder: AppleSignedDataDecoder = {
        verifyAndDecodeNotification: async () => ({
          notificationType: "ONE_TIME_CHARGE",
          notificationUUID,
          version: "2.0",
          data: {
            environment: "Production",
            appAppleId: configuration.appAppleId,
            bundleId: configuration.bundleId,
            signedTransactionInfo: "opaque-invalid-nested-input"
          }
        }),
        verifyAndDecodeTransaction: async () => {
          throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE);
        }
      };
      const verifier = createAppleIapVerifier({
        configuration,
        decoders: { production: decoder, sandbox: rejectingDecoder() }
      });

      // When/Then: the invalid nested signature becomes HTTP 400, never a verified transaction.
      await expectHttpStatus(() => verifier.verifyNotification("opaque-notification-input"), 400);
    }
  }
];

const runTests = async (): Promise<void> => {
  for (const test of tests) {
    await test.run();
    process.stdout.write(`PASS ${test.name}\n`);
  }
};

void runTests().catch((error: unknown) => {
  if (error instanceof Error) {
    process.stderr.write(`${error.name}: ${error.message}\n`);
  } else {
    process.stderr.write("Unknown Apple verifier test failure\n");
  }
  process.exit(1);
});
