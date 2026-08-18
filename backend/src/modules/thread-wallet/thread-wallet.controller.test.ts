import assert from "node:assert/strict";
import type { Server } from "node:http";
import express from "express";
import { errorMiddleware } from "../../middleware/error.middleware";
import { createAppleIapPurchaseController } from "./thread-wallet.controller";

type TestServer = {
  readonly server: Server;
  readonly baseURL: string;
};

const startTestServer = async (submitAppleIapPurchase: (input: {
  readonly userId: string;
  readonly signedTransaction: string;
}) => Promise<{ readonly availableThreads: number; readonly status: "credited" | "already_credited" }>): Promise<TestServer> => {
  const app = express();
  app.use(express.json());
  app.use((request, _response, next) => {
    Object.assign(request, {
      user: { id: "845628bf-1362-4f64-937d-e947aa1d017f" }
    });
    next();
  });
  app.post(
    "/thread-wallet/iap/verify",
    createAppleIapPurchaseController({ submitAppleIapPurchase })
  );
  app.use(errorMiddleware);

  return new Promise<TestServer>((resolve, reject) => {
    const server = app.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        reject(new Error("Test server did not expose a TCP port"));
        return;
      }
      resolve({ server, baseURL: `http://127.0.0.1:${address.port}` });
    });
    server.once("error", reject);
  });
};

const closeServer = async (server: Server): Promise<void> => {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => error ? reject(error) : resolve());
  });
};

const tests: readonly { readonly name: string; readonly run: () => Promise<void> }[] = [
  {
    name: "accepts a signed StoreKit transaction and returns the server balance",
    run: async () => {
      let submittedInput: { readonly userId: string; readonly signedTransaction: string } | null = null;
      const testServer = await startTestServer(async (input) => {
        submittedInput = input;
        return { availableThreads: 46, status: "credited" };
      });

      try {
        const response = await fetch(`${testServer.baseURL}/thread-wallet/iap/verify`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ signedTransaction: " signed-storekit-jws " })
        });

        assert.equal(response.status, 201);
        assert.deepEqual(await response.json(), { availableThreads: 46, status: "credited" });
        assert.deepEqual(submittedInput, {
          userId: "845628bf-1362-4f64-937d-e947aa1d017f",
          signedTransaction: "signed-storekit-jws"
        });
      } finally {
        await closeServer(testServer.server);
      }
    }
  },
  {
    name: "rejects an empty transaction before calling the purchase service",
    run: async () => {
      let serviceCalls = 0;
      const testServer = await startTestServer(async () => {
        serviceCalls += 1;
        return { availableThreads: 46, status: "credited" };
      });

      try {
        const response = await fetch(`${testServer.baseURL}/thread-wallet/iap/verify`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ signedTransaction: " " })
        });

        assert.equal(response.status, 400);
        assert.deepEqual(await response.json(), { message: "signedTransaction is required" });
        assert.equal(serviceCalls, 0);
      } finally {
        await closeServer(testServer.server);
      }
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
