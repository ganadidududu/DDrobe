import assert from "node:assert/strict";
import type { Server } from "node:http";
import express from "express";
import { errorMiddleware } from "../../middleware/error.middleware";
import { createHttpError } from "../../shared/utils/http-error";
import { createAppleAppStoreNotificationController } from "./apple-app-store-notification.controller";
import {
  settleAppleAppStoreNotification,
  type AppleAppStoreNotificationResult
} from "./apple-app-store-notification.service";
import type { AppleIapVerifiedNotification } from "./apple-iap-policy";

type TestServer = {
  readonly baseURL: string;
  readonly server: Server;
};

const accountToken = "845628bf-1362-4f64-937d-e947aa1d017f";
const notificationUUID = "07d46496-352a-4f53-b333-9511ba8f449b";
const verifiedNotification: AppleIapVerifiedNotification = {
  kind: "reconcile",
  notificationUUID,
  notificationType: "ONE_TIME_CHARGE",
  subtype: null,
  environment: "Production",
  transaction: {
    transactionId: "production-transaction",
    originalTransactionId: "production-original-transaction",
    productId: "com.inseong.coordit.thread.10",
    appAccountToken: accountToken,
    purchasedAt: "2026-08-21T00:00:00.000Z",
    environment: "Production"
  }
};

const startServer = async (
  submitAppleAppStoreNotification: (
    request: { readonly signedPayload: string }
  ) => Promise<AppleAppStoreNotificationResult>
): Promise<TestServer> => {
  const app = express();
  app.use(express.json());
  app.post(
    "/webhooks/apple/app-store-notifications",
    createAppleAppStoreNotificationController({ submitAppleAppStoreNotification })
  );
  app.use(errorMiddleware);
  return new Promise<TestServer>((resolve, reject) => {
    const server = app.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        reject(new TypeError("Apple notification test server did not expose a TCP port"));
        return;
      }
      resolve({ baseURL: `http://127.0.0.1:${address.port}`, server });
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
    name: "returns 200 only after a verified one-time charge is reconciled once",
    run: async () => {
      // Given: verification yields a trusted production transaction and persistence can credit it.
      let verifiedInput = "";
      let processingCalls = 0;
      let processedNotification: AppleIapVerifiedNotification | null = null;
      const server = await startServer((request) => settleAppleAppStoreNotification(request, {
        verifyAppleNotification: async (input) => {
          verifiedInput = input;
          return verifiedNotification;
        },
        processVerifiedNotification: async (notification) => {
          processingCalls += 1;
          processedNotification = notification;
          return { kind: "reconcile", availableThreads: 46, status: "credited" };
        }
      }));
      try {
        // When: Apple posts the opaque V2 body through the real Express surface.
        const response = await fetch(`${server.baseURL}/webhooks/apple/app-store-notifications`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ signedPayload: " opaque-provider-input " })
        });

        // Then: success is emitted after one verified reconciliation with no payload echo.
        assert.equal(response.status, 200);
        assert.deepEqual(await response.json(), { availableThreads: 46, status: "credited" });
        assert.equal(verifiedInput, "opaque-provider-input");
        assert.equal(processingCalls, 1);
        assert.deepEqual(processedNotification, verifiedNotification);
      } finally {
        await closeServer(server.server);
      }
    }
  },
  {
    name: "returns 200 for a verified duplicate without requesting another credit",
    run: async () => {
      // Given: database reconciliation reports the notification UUID was already processed.
      const server = await startServer(async () => ({
        kind: "reconcile",
        availableThreads: 46,
        status: "already_processed"
      }));
      try {
        // When: the provider retries the same notification.
        const response = await fetch(`${server.baseURL}/webhooks/apple/app-store-notifications`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ signedPayload: "opaque-provider-retry" })
        });

        // Then: Apple receives success with an explicitly idempotent status.
        assert.equal(response.status, 200);
        assert.deepEqual(await response.json(), {
          availableThreads: 46,
          status: "already_processed"
        });
      } finally {
        await closeServer(server.server);
      }
    }
  },
  {
    name: "records a verified Apple test notification without granting threads",
    run: async () => {
      // Given: a verified record-only notification has no purchase transaction.
      const server = await startServer(async () => ({ kind: "record", status: "processed" }));
      try {
        // When: Apple sends the test event.
        const response = await fetch(`${server.baseURL}/webhooks/apple/app-store-notifications`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ signedPayload: "opaque-provider-test" })
        });

        // Then: it is acknowledged only as a processed receipt, with no balance field.
        assert.equal(response.status, 200);
        assert.deepEqual(await response.json(), { status: "processed" });
      } finally {
        await closeServer(server.server);
      }
    }
  },
  {
    name: "rejects malformed request bodies before verification or persistence",
    run: async () => {
      // Given: the public controller has observable service-call accounting.
      let serviceCalls = 0;
      const server = await startServer(async () => {
        serviceCalls += 1;
        return { kind: "record", status: "processed" };
      });
      try {
        // When: a callback-shaped body omits the required opaque JWS string.
        const response = await fetch(`${server.baseURL}/webhooks/apple/app-store-notifications`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ signedPayload: " " })
        });

        // Then: it is non-2xx and no processing adapter is called.
        assert.equal(response.status, 400);
        assert.equal(serviceCalls, 0);
      } finally {
        await closeServer(server.server);
      }
    }
  },
  {
    name: "rejects invalid nested Apple verification before database processing",
    run: async () => {
      // Given: outer or nested signature verification fails at the trust boundary.
      let processingCalls = 0;
      const server = await startServer((request) => settleAppleAppStoreNotification(request, {
        verifyAppleNotification: async () => {
          throw createHttpError(400, "Apple verification failed");
        },
        processVerifiedNotification: async () => {
          processingCalls += 1;
          return { kind: "record", status: "processed" };
        }
      }));
      try {
        // When: the invalid provider input reaches the public HTTP endpoint.
        const response = await fetch(`${server.baseURL}/webhooks/apple/app-store-notifications`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ signedPayload: "opaque-invalid-provider-input" })
        });

        // Then: Apple receives 400 and the database seam observes zero calls.
        assert.equal(response.status, 400);
        assert.equal(processingCalls, 0);
      } finally {
        await closeServer(server.server);
      }
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
    process.stderr.write("Unknown Apple notification HTTP test failure\n");
  }
  process.exit(1);
});
