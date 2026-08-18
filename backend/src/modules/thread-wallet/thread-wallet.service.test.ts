import assert from "node:assert/strict";
import { settleAppleIapPurchase } from "./thread-wallet.service";

const verifiedTransaction = {
  transactionId: "2000000123456789",
  originalTransactionId: "2000000123456789",
  productId: "com.inseong.coordit.thread.10",
  appAccountToken: "845628bf-1362-4f64-937d-e947aa1d017f",
  purchasedAt: "2026-08-09T12:00:00.000Z",
  environment: "Sandbox"
} as const;

type AppleCreditInput = {
  readonly userId: string;
  readonly transactionId: string;
  readonly originalTransactionId: string;
  readonly productId: string;
  readonly appAccountToken: string;
  readonly purchasedAt: string;
  readonly environment: "Sandbox" | "Production";
  readonly threads: number;
};

const expectHttpError = async (promise: Promise<unknown>, statusCode: number): Promise<void> => {
  await assert.rejects(promise, (error: unknown) => {
    return error instanceof Error && "statusCode" in error && error.statusCode === statusCode;
  });
};

const tests: readonly { readonly name: string; readonly run: () => Promise<void> }[] = [
  {
    name: "credits the configured package exactly once after Apple verifies a transaction",
    run: async () => {
      let receivedSignedTransaction = "";
      let creditCalls = 0;
      let creditedInput: AppleCreditInput | null = null;

      const result = await settleAppleIapPurchase(
        {
          userId: verifiedTransaction.appAccountToken,
          signedTransaction: "signed-apple-transaction"
        },
        {
          verifyAppleTransaction: async (signedTransaction: string) => {
            receivedSignedTransaction = signedTransaction;
            return verifiedTransaction;
          },
          creditAppleTransaction: async (input: AppleCreditInput) => {
            creditCalls += 1;
            creditedInput = input;
            return { availableThreads: 46, status: "credited" as const };
          }
        }
      );

      assert.equal(receivedSignedTransaction, "signed-apple-transaction");
      assert.deepEqual(creditedInput, {
        userId: verifiedTransaction.appAccountToken,
        ...verifiedTransaction,
        threads: 10
      });
      assert.equal(creditCalls, 1);
      assert.deepEqual(result, { availableThreads: 46, status: "credited" });
    }
  },
  {
    name: "rejects a transaction assigned to another Coordit account without crediting it",
    run: async () => {
      let creditCalls = 0;

      await expectHttpError(
        settleAppleIapPurchase(
          {
            userId: "0c1d8e73-93a1-4c8d-92c8-4e4bf7877cbb",
            signedTransaction: "signed-apple-transaction"
          },
          {
            verifyAppleTransaction: async () => verifiedTransaction,
            creditAppleTransaction: async () => {
              creditCalls += 1;
              return { availableThreads: 46, status: "credited" as const };
            }
          }
        ),
        403
      );

      assert.equal(creditCalls, 0);
    }
  },
  {
    name: "rejects a verified Apple product that is not a thread package",
    run: async () => {
      let creditCalls = 0;

      await expectHttpError(
        settleAppleIapPurchase(
          {
            userId: verifiedTransaction.appAccountToken,
            signedTransaction: "signed-apple-transaction"
          },
          {
            verifyAppleTransaction: async () => ({
              ...verifiedTransaction,
              productId: "com.inseong.coordit.subscription.monthly"
            }),
            creditAppleTransaction: async () => {
              creditCalls += 1;
              return { availableThreads: 46, status: "credited" as const };
            }
          }
        ),
        400
      );

      assert.equal(creditCalls, 0);
    }
  }
];

const runTests = async (): Promise<void> => {
  for (const test of tests) {
    await test.run();
    console.log(`PASS ${test.name}`);
  }
};

runTests().catch((error: unknown) => {
  if (error instanceof Error) {
    console.error(error);
  } else {
    console.error("Unknown test failure");
  }
  process.exit(1);
});
