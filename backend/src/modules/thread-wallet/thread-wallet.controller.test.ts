import assert from "node:assert/strict";
import type { Server } from "node:http";
import express from "express";
import { errorMiddleware } from "../../middleware/error.middleware";
import {
  createAppleIapPurchaseController,
  getThreadBalanceController
} from "./thread-wallet.controller";

type TestServer = {
  readonly server: Server;
  readonly baseURL: string;
};

let applicationRouteStack: readonly unknown[] = [];

const isGetRoute = (layer: unknown, path: string): boolean => {
  if (!layer || typeof layer !== "object" || !("route" in layer)) return false;
  const route = layer.route;
  if (!route || typeof route !== "object" || !("path" in route) || route.path !== path) {
    return false;
  }
  if (!("methods" in route) || !route.methods || typeof route.methods !== "object") return false;
  return "get" in route.methods && route.methods.get === true;
};

const isPostRoute = (layer: unknown, path: string): boolean => {
  if (!layer || typeof layer !== "object" || !("route" in layer)) return false;
  const route = layer.route;
  if (!route || typeof route !== "object" || !("path" in route) || route.path !== path) {
    return false;
  }
  if (!("methods" in route) || !route.methods || typeof route.methods !== "object") return false;
  return "post" in route.methods && route.methods.post === true;
};

const isNamedMiddleware = (layer: unknown, name: string): boolean => {
  return Boolean(layer && typeof layer === "object" && "name" in layer && layer.name === name);
};

const startTestServer = async (submitAppleIapPurchase: (input: {
  readonly userId: string;
  readonly signedTransaction: string;
}) => Promise<{ readonly availableThreads: number; readonly status: "credited" | "already_credited" }>): Promise<TestServer> => {
  const controllerModule = await import("./thread-wallet.controller");
  const readinessEntry: readonly [string, unknown] | undefined = Object
    .entries(controllerModule)
    .find(([name]) => name === "getMonetizationReadinessController");
  const readinessController = readinessEntry?.[1];
  if (typeof readinessController !== "function") {
    throw new Error("Missing wallet monetization-readiness controller contract");
  }

  const app = express();
  app.use(express.json());
  app.get("/thread-wallet/balance", getThreadBalanceController);
  app.use((request, _response, next) => {
    Object.assign(request, {
      user: { id: "845628bf-1362-4f64-937d-e947aa1d017f" }
    });
    next();
  });
  app.get("/thread-wallet/monetization-readiness", (request, response, next) => {
    readinessController(request, response, next);
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
    name: "rejects a balance request when the controller has no authenticated user",
    run: async () => {
      // Given: the existing balance controller is mounted without an authenticated user.
      const testServer = await startTestServer(async () => ({
        availableThreads: 46,
        status: "credited"
      }));

      try {
        // When: a client requests the balance endpoint.
        const response = await fetch(`${testServer.baseURL}/thread-wallet/balance`);

        // Then: the controller preserves its existing unauthenticated HTTP response.
        assert.equal(response.status, 401);
        assert.deepEqual(await response.json(), { message: "Authentication is required" });
      } finally {
        await closeServer(testServer.server);
      }
    }
  },
  {
    name: "returns the fail-closed wallet monetization-readiness contract",
    run: async () => {
      // Given: the readiness controller is mounted for an authenticated user with absent flags.
      const testServer = await startTestServer(async () => ({
        availableThreads: 46,
        status: "credited"
      }));

      try {
        // When: the authenticated client requests wallet monetization readiness.
        const response = await fetch(
          `${testServer.baseURL}/thread-wallet/monetization-readiness`
        );

        // Then: the response exposes exactly the two fail-closed booleans.
        assert.equal(response.status, 200);
        assert.deepEqual(await response.json(), {
          rewardedAdsEnabled: false,
          iapEnabled: false
        });
      } finally {
        await closeServer(testServer.server);
      }
    }
  },
  {
    name: "mounts wallet monetization readiness behind the same onboarding gate as balance",
    run: async () => {
      // Given: the production router stack includes the shared authentication and onboarding gates.
      // When: the wallet route positions are inspected.
      const authIndex = applicationRouteStack.findIndex((layer) => {
        return isNamedMiddleware(layer, "authMiddleware");
      });
      const onboardingIndex = applicationRouteStack.findIndex((layer) => {
        return isNamedMiddleware(layer, "onboardingMiddleware");
      });
      const balanceIndex = applicationRouteStack.findIndex((layer) => {
        return isGetRoute(layer, "/thread-wallet/balance");
      });
      const readinessIndex = applicationRouteStack.findIndex((layer) => {
        return isGetRoute(layer, "/thread-wallet/monetization-readiness");
      });

      // Then: both wallet reads are mounted after onboarding and readiness is present exactly once.
      assert.ok(authIndex >= 0);
      assert.ok(onboardingIndex > authIndex);
      assert.ok(balanceIndex > onboardingIndex);
      assert.ok(readinessIndex > onboardingIndex);
      assert.equal(applicationRouteStack.filter((layer) => {
        return isGetRoute(layer, "/thread-wallet/monetization-readiness");
      }).length, 1);
    }
  },
  {
    name: "mounts the Apple notification webhook before authentication",
    run: async () => {
      // Given: the production router contains its public provider webhooks and auth gate.
      // When: the Apple Notifications V2 endpoint position is inspected.
      const authIndex = applicationRouteStack.findIndex((layer) => {
        return isNamedMiddleware(layer, "authMiddleware");
      });
      const notificationIndex = applicationRouteStack.findIndex((layer) => {
        return isPostRoute(layer, "/webhooks/apple/app-store-notifications");
      });

      // Then: Apple can deliver without a user bearer token, before auth rejects the request.
      assert.ok(authIndex >= 0);
      assert.ok(notificationIndex >= 0);
      assert.ok(notificationIndex < authIndex);
      assert.equal(applicationRouteStack.filter((layer) => {
        return isPostRoute(layer, "/webhooks/apple/app-store-notifications");
      }).length, 1);
    }
  },
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
    name: "returns 200 without a second credit for a replayed StoreKit transaction",
    run: async () => {
      // Given: the authoritative settlement service recognizes an existing Apple transaction.
      let serviceCalls = 0;
      const testServer = await startTestServer(async () => {
        serviceCalls += 1;
        return { availableThreads: 46, status: "already_credited" };
      });

      try {
        // When: the client retries its unchanged opaque transaction input.
        const response = await fetch(`${testServer.baseURL}/thread-wallet/iap/verify`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ signedTransaction: "opaque-storekit-retry" })
        });

        // Then: retry is explicitly idempotent and invokes settlement only once for this request.
        assert.equal(response.status, 200);
        assert.deepEqual(await response.json(), {
          availableThreads: 46,
          status: "already_credited"
        });
        assert.equal(serviceCalls, 1);
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
  const { routes } = await import("../../routes");
  applicationRouteStack = routes.stack;
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
